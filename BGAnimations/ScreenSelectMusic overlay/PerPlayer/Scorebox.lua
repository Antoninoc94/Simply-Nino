-- No need to get GS scores for courses
if GAMESTATE:IsCourseMode() then return end

-- Don't display if Music Wheel GS integration isn't set to Scorebox.
if ThemePrefs.Get("MusicWheelGS") ~= "Scorebox" then return end

local player = ...
local pn = ToEnumShortString(player)

-- Note: we intentionally don't bail out here when the player has no
-- GrooveStats API Key. The box still displays the machine's local high
-- scores in that case; only the GrooveStats network request itself is
-- skipped (see MakeRequestCommand below).

local n = player==PLAYER_1 and "1" or "2"
local IsNotWide = (GetScreenAspectRatio() < 16/9)
local NoteFieldIsCentered = (GetNotefieldX(player) == _screen.cx)
local NumEntries = 5

-- Overall size multiplier for the whole box (rank/name/score text, crown,
-- outline, background) relative to the original 162x80 design.
-- Tweak this single number to make the box bigger/smaller.
local scale = 0.7

local border = 5
local width = 162 * scale
local height = 80 * scale
local row_height = height / NumEntries

local cur_style = 0
-- 10 rotating styles: GS ITG, GS EX, Boogie ITG, Boogie EX, RPG, ITL,
-- ArrowCloud ITG, ArrowCloud EX, ArrowCloud HardEX, Local.
-- GrooveStats, BoogieStats, and ArrowCloud are each queried as independent,
-- parallel requests (see OfficialRequester/BoogieRequester below, and the
-- direct NETWORK:HttpRequest for ArrowCloud in MakeRequestCommand) so all
-- of them can be shown together, gated individually by their own
-- API key/EnableXStats preference rather than one replacing another.
local num_styles = 10

local GrooveStatsBlue = color("#007b85")
local RpgYellow = color("1,0.972,0.792,1")
local ItlPink = color("1,0.2,0.406,1")
local BoogieStatsPurple = color("#8000ff")
local ArrowCloudRed = color("#D32F2F")
local ArrowCloudCyan = color("#21CCE8")
local ArrowCloudBrightRed = color("#FF0000")
local LocalAqua = color("#00C2D4")

local currentHash = "nothing"
-- Tracks how many of the in-flight GrooveStats/BoogieStats/ArrowCloud
-- requests we're still waiting on, so we only refresh the display once
-- (via CheckScorebox) after ALL of them have responded.
local pendingRequests = 0
local MaybeCheckScorebox = function(master)
	pendingRequests = pendingRequests - 1
	if pendingRequests <= 0 then
		master:queuecommand("CheckScorebox")
	end
end

local style_color = {
	[0] = GrooveStatsBlue,      -- GrooveStats ITG
	[1] = GrooveStatsBlue,      -- GrooveStats EX
	[2] = BoogieStatsPurple,    -- BoogieStats ITG
	[3] = BoogieStatsPurple,    -- BoogieStats EX
	[4] = RpgYellow,
	[5] = ItlPink,
	[6] = ArrowCloudCyan,       -- ArrowCloud ITG (rarely/never populated -- ArrowCloud appears to be EX-only)
	[7] = ArrowCloudRed,        -- ArrowCloud EX (the one that actually shows up)
	[8] = ArrowCloudBrightRed,  -- ArrowCloud HardEX
	[9] = LocalAqua,            -- Machine's local high scores
}

local self_color = color("#a1ff94")
local rival_color = color("#c29cff")

local loop_seconds = 5
local transition_seconds = 1

local all_data = {}

local ResetAllData = function()
	all_data = {}
	SL[pn].Rival = {}
	SL[pn].Rival.Score = 0
	SL[pn].Rival.ExScore = 0
	SL[pn].Rival.WRScore = 0
	SL[pn].Rival.WRExScore = 0
	
	for i=1,num_styles do
		local data = {
			["has_data"]=false,
			["scores"]={}
		}
		local scores = data["scores"]
		for i=1,NumEntries do
			scores[#scores+1] = {
				["rank"]="",
				["name"]="",
				["score"]="",
				["isSelf"]=false,
				["isRival"]=false,
				["isFail"]=false,
				["isEx"]=false,
			}
		end
		all_data[i] = data
	end
end

-- Initialize the all_data object.
ResetAllData()

-- Checks to see if any data is available.
local HasData = function(idx)
	return all_data[idx+1] and all_data[idx+1].has_data
end

local SetScoreData = function(data_idx, score_idx, rank, name, score, isSelf, isRival, isFail, isEx)
	if score_idx > 5 then return end
	all_data[data_idx].has_data = true

	local score_data = all_data[data_idx]["scores"][score_idx]
	score_data.rank = rank..((#rank > 0) and "." or "")
	score_data.name = name
	score_data.score = score
	score_data.isSelf = isSelf
	score_data.isRival = isRival
	score_data.isFail = isFail
	score_data.isEx = isEx
	
	if not isFail and (isRival or isSelf) then
		if data_idx == 5 then
			if tonumber(score) > SL[pn].Rival.ExScore then
				SL[pn].Rival.ExScore = tonumber(score)
			end
		else
			if tonumber(score) > SL[pn].Rival.Score then
				SL[pn].Rival.Score = tonumber(score)
			end
		end
	end

	if score_data.rank == 1 then
		if data_idx == 5 then
			SL[pn].Rival.WRExScore = tonumber(score)
		else
			if tonumber(score) > SL[pn].Rival.WRScore then
				SL[pn].Rival.WRScore = tonumber(score)
			end
		end
	end
end

-- Populates data_idx 10 (the "Machine's Best" style) with the current
-- chart's local high scores from the machine profile. This doesn't require
-- any network access, so it works regardless of GrooveStats configuration.
local PopulateLocalScores = function()
	-- Always leave data_idx 10 with at least a "No Scores" fallback, even if
	-- one of the checks below bails out early or the profile lookup errors.
	-- Otherwise, when there's no GrooveStats API Key, this is the ONLY
	-- source of data for the scorebox, and if it never sets has_data,
	-- LoopScoreboxCommand's "if not has_data then return end" guard would
	-- leave the box permanently blank.
	if not GAMESTATE:IsHumanPlayer(player) then
		SetScoreData(10, 1, "", "No Scores", "", false, false, false, false)
		return
	end

	local SongOrCourse = GAMESTATE:GetCurrentSong()
	local StepsOrTrail = GAMESTATE:GetCurrentSteps(player)
	if not SongOrCourse or not StepsOrTrail then
		SetScoreData(10, 1, "", "No Scores", "", false, false, false, false)
		return
	end

	local ok, HighScores = pcall(function()
		return PROFILEMAN:GetMachineProfile():GetHighScoreList(SongOrCourse, StepsOrTrail):GetHighScores()
	end)
	if not ok then HighScores = nil end

	local profileName = nil
	if PROFILEMAN:IsPersistentProfile(player) then
		profileName = PROFILEMAN:GetProfile(player):GetLastUsedHighScoreName()
	end

	SetScoreData(10, 1, "", "No Scores", "", false, false, false, false)

	if HighScores then
		local numEntries = 0
		for i, highscore in ipairs(HighScores) do
			if i > NumEntries then break end
			numEntries = numEntries + 1
			local isSelf = profileName ~= nil and highscore:GetName() == profileName
			local isFail = highscore:GetGrade() == "Grade_Failed"
			SetScoreData(10, numEntries,
				tostring(i),
				highscore:GetName(),
				string.format("%.2f", highscore:GetPercentDP() * 100),
				isSelf,
				false,
				isFail,
				false
			)
		end
		numEntries = numEntries + 1
		for i=math.max(2,numEntries),NumEntries,1 do
			SetScoreData(10, i, "", "", "", false, false, false, false)
		end
	end
end

-- Processes the response from the official GrooveStats server.
-- Populates data_idx 1 (ITG), 2 (EX), 5 (RPG event), 6 (ITL event).
local OfficialLeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		SetScoreData(1, 1, "", text, "", false, false, false, false)
		MaybeCheckScorebox(master)
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	if data and data[playerStr] then
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end
		currentHash = SL[pn].Streams.Hash

		-- These will get overwritten if we have any entries in the leaderboard below.
		SetScoreData(1, 1, "", "No Scores", "", false, false, false, false)
		SetScoreData(2, 1, "", "No Scores", "", false, false, false, false)
		all_data[1].has_data = false
		all_data[2].has_data = false

		local showITG = SL["P"..n].ActiveModifiers.SBITGScore
		local showEX = SL["P"..n].ActiveModifiers.SBExScore
		local showEvents = SL["P"..n].ActiveModifiers.SBEvents

		if showITG and data[playerStr]["gsLeaderboard"] then
			local added = {}
			local numEntries = 0
			for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
				if not added[entry["name"]] then
					added[entry["name"]] = true
					numEntries = numEntries + 1
					SetScoreData(1, numEntries,
									tostring(entry["rank"]),
									entry["name"],
									string.format("%.2f", entry["score"]/100),
									entry["isSelf"],
									entry["isRival"],
									entry["isFail"],
									false
								)
				end
			end
			numEntries = numEntries + 1
			for i=math.max(2,numEntries),NumEntries,1 do
				SetScoreData(1, i, "", "", "", false, false, false, false)
			end
		end

		if showEX and data[playerStr]["exLeaderboard"] then
			local added = {}
			local numEntries = 0
			for entry in ivalues(data[playerStr]["exLeaderboard"]) do
				if not added[entry["name"]] then
					added[entry["name"]] = true
					numEntries = numEntries + 1
					SetScoreData(2, numEntries,
									tostring(entry["rank"]),
									entry["name"],
									string.format("%.2f", entry["score"]/100),
									entry["isSelf"],
									entry["isRival"],
									entry["isFail"],
									true
								)
				end
			end
			numEntries = numEntries + 1
			for i=math.max(2,numEntries),NumEntries,1 do
				SetScoreData(2, i, "", "", "", false, false, false, false)
			end
		end

		if showEvents then
			if data[playerStr]["rpg"] then
				cur_style = 4
				local added = {}
				local numEntries = 0
				SetScoreData(5, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["rpg"]["rpgLeaderboard"] then
					for entry in ivalues(data[playerStr]["rpg"]["rpgLeaderboard"]) do
						if not added[entry["name"]] then
							added[entry["name"]] = true
							numEntries = numEntries + 1
							SetScoreData(5, numEntries,
											tostring(entry["rank"]),
											entry["name"],
											string.format("%.2f", entry["score"]/100),
											entry["isSelf"],
											entry["isRival"],
											entry["isFail"],
											false
										)
						end
					end
					numEntries = numEntries + 1
					for i=numEntries,NumEntries,1 do
						SetScoreData(5, i, "", "", "", false, false, false)
					end
				end
			end

			if data[playerStr]["itl"] then
				cur_style = 5
				local added = {}
				local numEntries = 0
				SetScoreData(6, 1, "", "No Scores", "", false, false, false)

				if data[playerStr]["itl"]["itlLeaderboard"] then
					for entry in ivalues(data[playerStr]["itl"]["itlLeaderboard"]) do
						if not added[entry["name"]] then
							added[entry["name"]] = true
							if entry["isSelf"] then
								UpdateItlExScore(player, SL[pn].Streams.Hash, entry["score"])
								SL["P"..n].itlScore = entry["score"]
							end
							numEntries = numEntries + 1
							SetScoreData(6, numEntries,
											tostring(entry["rank"]),
											entry["name"],
											string.format("%.2f", entry["score"]/100),
											entry["isSelf"],
											entry["isRival"],
											entry["isFail"],
											true
										)
						end
					end
					numEntries = numEntries + 1
					for i=numEntries,NumEntries,1 do
						SetScoreData(6, i, "", "", "", false, false, false)
					end
				end
			end
		end
	end

	MaybeCheckScorebox(master)
end

-- Processes the response from the BoogieStats proxy server.
-- Populates data_idx 3 (ITG) and 4 (EX). Sent as a completely separate
-- request from the official GrooveStats one (see BoogieRequester below),
-- so both can be shown side by side in the rotation.
local BoogieLeaderboardRequestProcessor = function(res, master)
	if master == nil then return end

	if res.error or res.statusCode ~= 200 then
		local error = res.error and ToEnumShortString(res.error) or nil
		local text = ""
		if error == "Timeout" then
			text = "Timed Out"
		elseif error or (res.statusCode ~= nil and res.statusCode ~= 200) then
			text = "Failed to Load 😞"
		end
		SetScoreData(3, 1, "", text, "", false, false, false, false)
		MaybeCheckScorebox(master)
		return
	end

	local playerStr = "player"..n
	local data = JsonDecode(res.body)

	if data and data[playerStr] then
		if SL[pn].Streams.Hash ~= data[playerStr]["chartHash"] then return end

		SetScoreData(3, 1, "", "No Scores", "", false, false, false, false)
		SetScoreData(4, 1, "", "No Scores", "", false, false, false, false)
		all_data[3].has_data = false
		all_data[4].has_data = false

		local showITG = SL["P"..n].ActiveModifiers.SBITGScore
		local showEX = SL["P"..n].ActiveModifiers.SBExScore

		if showITG and data[playerStr]["gsLeaderboard"] then
			local added = {}
			local numEntries = 0
			for entry in ivalues(data[playerStr]["gsLeaderboard"]) do
				if not added[entry["name"]] then
					added[entry["name"]] = true
					numEntries = numEntries + 1
					SetScoreData(3, numEntries,
									tostring(entry["rank"]),
									entry["name"],
									string.format("%.2f", entry["score"]/100),
									entry["isSelf"],
									entry["isRival"],
									entry["isFail"],
									false
								)
				end
			end
			numEntries = numEntries + 1
			for i=math.max(2,numEntries),NumEntries,1 do
				SetScoreData(3, i, "", "", "", false, false, false, false)
			end
		end

		if showEX and data[playerStr]["exLeaderboard"] then
			local added = {}
			local numEntries = 0
			for entry in ivalues(data[playerStr]["exLeaderboard"]) do
				if not added[entry["name"]] then
					added[entry["name"]] = true
					numEntries = numEntries + 1
					SetScoreData(4, numEntries,
									tostring(entry["rank"]),
									entry["name"],
									string.format("%.2f", entry["score"]/100),
									entry["isSelf"],
									entry["isRival"],
									entry["isFail"],
									true
								)
				end
			end
			numEntries = numEntries + 1
			for i=math.max(2,numEntries),NumEntries,1 do
				SetScoreData(4, i, "", "", "", false, false, false, false)
			end
		end
	end

	MaybeCheckScorebox(master)
end

-- Processes the response from ArrowCloud's leaderboard endpoint
-- (GET /v1/chart/{hash}/leaderboards). Populates data_idx 7 (ITG),
-- 8 (EX), 9 (HardEX). Sent as its own direct NETWORK:HttpRequest (see
-- MakeRequestCommand) since ArrowCloud isn't a GrooveStats-compatible
-- endpoint and doesn't go through RequestResponseActor.
local ArrowCloudRequestProcessor = function(res, master)
	if master == nil then return end

	if not res or res.statusCode ~= 200 or not res.body then
		SetScoreData(7, 1, "", "Failed to Load 😞", "", false, false, false, false)
		MaybeCheckScorebox(master)
		return
	end

	local ok, parsed = pcall(JsonDecode, res.body)
	if not ok or type(parsed) ~= "table" or type(parsed.leaderboards) ~= "table" then
		SetScoreData(7, 1, "", "Failed to Load 😞", "", false, false, false, false)
		MaybeCheckScorebox(master)
		return
	end

	-- Map ArrowCloud's leaderboard "type" to our data_idx slots.
	local index_map = { ITG = 7, EX = 8, HardEX = 9 }
	for _, board in ipairs(parsed.leaderboards) do
		local data_idx = index_map[board.type]
		if data_idx then
			local isExType = (board.type == "EX" or board.type == "HardEX")
			local slot = 1
			if type(board.scores) == "table" then
				for _, entry in ipairs(board.scores) do
					if slot > NumEntries then break end
					SetScoreData(data_idx, slot,
						tostring(entry.rank or ""),
						tostring(entry.alias or "--"),
						tostring(entry.score or ""),
						not not entry.isSelf,
						not not entry.isRival,
						false,
						isExType
					)
					slot = slot + 1
				end
			end
			if slot == 1 then
				SetScoreData(data_idx, 1, "", "No Scores", "", false, false, false, isExType)
				slot = 2
			end
			for i=slot, NumEntries do
				SetScoreData(data_idx, i, "", "", "", false, false, false, isExType)
			end
		end
	end

	MaybeCheckScorebox(master)
end

local af = Def.ActorFrame{
	Name="ScoreBox"..pn,
	InitCommand=function(self)
		if #GAMESTATE:GetHumanPlayers() == 1 then
			self:x(_screen.cx - 60):y(_screen.cy + 178)
		else
			if pn == "P1" then
				self:zoom(0.95):x(_screen.cx - 65):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx - 48)
				end
			else
				self:zoom(0.95):x(_screen.cx + 371):y(_screen.cy + 178)
				if IsNotWide then
					self:x(_screen.cx + 279)
				end
			end
		end
		self.isFirst = true
	end,
	ResetCommand=function(self) self:stoptweening() end,
	OffCommand=function(self) self:stoptweening() end,
	PlayerJoinedMessageCommand=function(self, params)
		if pn == "P1" then
			self:zoom(0.95):x(_screen.cx - 65):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx - 48)
			end
		else
			self:zoom(0.95):x(_screen.cx + 371):y(_screen.cy + 178)
			if IsNotWide then
				self:x(_screen.cx + 279)
			end
		end
	end,
	PlayerUnjoinedMessageCommand=function(self, params)
		if params.Player == player then
			self:visible(false)
		end
		self:x(_screen.cx - 60):y(_screen.cy + 178):zoom(1)
	end,
	CurrentSongChangedMessageCommand=function(self)
		self:finishtweening():visible(false)
		self.isFirst = true
	end,
	CheckScoreboxCommand=function(self)
		if GAMESTATE:GetCurrentSong() and GAMESTATE:GetCurrentSteps(player) then
			self:queuecommand("LoopScorebox")
		end
	end,
	LoopScoreboxCommand=function(self)
		self:visible(true)

		local has_data = false
		if #all_data == 0 then return end
		for i=1,num_styles do
			if all_data[i].has_data then
				has_data = true
				break
			end
		end
		if not has_data then return end

		self:finishtweening()

		self:GetChild("Name1"):visible(true)
		self:GetChild("Name2"):visible(true)
		self:GetChild("Name3"):visible(true)
		self:GetChild("Name4"):visible(true)
		self:GetChild("Name5"):visible(true)
		self:GetChild("Score1"):visible(true)
		self:GetChild("Score2"):visible(true)
		self:GetChild("Score3"):visible(true)
		self:GetChild("Score4"):visible(true)
		self:GetChild("Score5"):visible(true)
		self:GetChild("Rank1"):visible(true)
		self:GetChild("Rank2"):visible(true)
		self:GetChild("Rank3"):visible(true)
		self:GetChild("Rank4"):visible(true)
		self:GetChild("Rank5"):visible(true)
		self:GetChild("GrooveStatsLogo"):stopeffect():visible(true)
		self:GetChild("BoogieStatsLogo"):stopeffect():visible(true)
		self:GetChild("BoogieStatsEXLogo"):stopeffect():visible(true)
		self:GetChild("ArrowCloudLogo"):stopeffect():visible(true)
		self:GetChild("SRPGLogo"):visible(true)
		self:GetChild("ITLLogo"):visible(true)
		self:GetChild("Outline"):visible(true)
		self:GetChild("Background"):linear(transition_seconds/2):diffusealpha(1):visible(true)

		if self.isFirst then
			self.isFirst = false
			-- On the very first pass, show cur_style itself if it already
			-- has data, instead of always skipping ahead to the next one.
			if not HasData(cur_style) then
				local start = cur_style
				repeat
					cur_style = (cur_style + 1) % num_styles
				until cur_style == start or HasData(cur_style)
			end
		else
			local start = cur_style
			repeat
				cur_style = (cur_style + 1) % num_styles
			until cur_style == start or HasData(cur_style)
		end

		-- Loop only if there's more than one style with data to cycle through.
		local styleCount = 0
		for i=0, num_styles-1 do
			if HasData(i) then styleCount = styleCount + 1 end
		end
		if styleCount > 1 then
			self:sleep(loop_seconds):queuecommand("LoopScorebox")
		end
	end,

	-- Coordinator: tracks chart parsing, clears/prepares the UI, and kicks
	-- off both network requesters below (or falls back to local-only).
	RequestResponseActor(0, 0)..{
		OnCommand=function(self)
			self:queuecommand("MakeRequest")
			-- Create variables for both players, even if they're not currently active.
			self.IsParsing = {false, false}
		end,
		-- Broadcasted from ./PerPlayer/DensityGraph.lua
		P1ChartParsingMessageCommand=function(self)	self.IsParsing[1] = true end,
		P2ChartParsingMessageCommand=function(self)	self.IsParsing[2] = true end,
		P1ChartParsedMessageCommand=function(self)
			self.IsParsing[1] = false
			if pn == "P1" then
				self:queuecommand("ChartParsed")
			end
		end,
		P2ChartParsedMessageCommand=function(self)
			self.IsParsing[2] = false
			if pn == "P2" then
				self:queuecommand("ChartParsed")
			end
		end,
		ChartParsedMessageCommand=function(self)
			if not self.leaving_screen then
				self:queuecommand("MakeRequest")
			end
		end,
		MakeRequestCommand=function(self)
			-- If this player isn't actually joined, leave their scorebox
			-- untouched (never made visible). Without this, the unjoined
			-- player's box would still get shown (to display local scores)
			-- but its animation loop never starts (no song/steps for a
			-- player who isn't playing), leaving it stuck at its default
			-- fully-opaque state -- which, since both players' boxes share
			-- the same screen position in solo play, ends up covering the
			-- joined player's real scorebox.
			if not GAMESTATE:IsHumanPlayer(player) then return end

			local canSendGS = IsServiceAllowed(SL.GrooveStats.GetScores) and SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= ""
			local canSendAC = ThemePrefs.Get("EnableArrowCloud") and SL[pn].ArrowCloudApiKey ~= "" and SL[pn].Streams.Hash ~= ""

			-- We technically will send requests in ultrawide versus mode since
			-- both players will have their own individual scoreboxes.
			-- Should be fine though.
			if canSendGS or canSendAC then
				if self.IsParsing[1] or self.IsParsing[2] then return end
				if currentHash == SL[pn].Streams.Hash then
					self:GetParent():visible(true)
					self:GetParent():queuecommand("CheckScorebox")
					return
				end

				RemoveStaleCachedRequests()
				ResetAllData()

				self:GetParent():visible(true)
				self:GetParent():GetChild("Name1"):settext(""):visible(false)
				self:GetParent():GetChild("Name2"):settext(""):visible(false)
				self:GetParent():GetChild("Name3"):settext(""):visible(false)
				self:GetParent():GetChild("Name4"):settext(""):visible(false)
				self:GetParent():GetChild("Name5"):settext(""):visible(false)
				self:GetParent():GetChild("Score1"):settext(""):visible(false)
				self:GetParent():GetChild("Score2"):settext(""):visible(false)
				self:GetParent():GetChild("Score3"):settext(""):visible(false)
				self:GetParent():GetChild("Score4"):settext(""):visible(false)
				self:GetParent():GetChild("Score5"):settext(""):visible(false)
				self:GetParent():GetChild("Rank1"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Rank2"):settext(""):visible(false)
				self:GetParent():GetChild("Rank3"):settext(""):visible(false)
				self:GetParent():GetChild("Rank4"):settext(""):visible(false)
				self:GetParent():GetChild("Rank5"):settext(""):visible(false)
				-- Only show ONE glowing "loading" logo at a time -- if both
				-- GrooveStats and ArrowCloud are being fetched, GrooveStats
				-- takes priority as the loading indicator so the two logos
				-- don't end up overlapping each other in the same spot.
				local acLoadingIndicator = canSendAC and not canSendGS
				self:GetParent():GetChild("GrooveStatsLogo"):visible(canSendGS):diffusealpha(canSendGS and 0.5 or 0):glowshift({color("#C8FFFF"), color("#6BF0FF")})
				self:GetParent():GetChild("BoogieStatsLogo"):visible(false)
				self:GetParent():GetChild("BoogieStatsEXLogo"):visible(false)
				self:GetParent():GetChild("ArrowCloudLogo"):visible(acLoadingIndicator):diffusealpha(acLoadingIndicator and 0.5 or 0):glowshift({color("#C8FFFF"), color("#6BF0FF")})
				self:GetParent():GetChild("SRPGLogo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("ITLLogo"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Outline"):diffusealpha(0):visible(false)
				self:GetParent():GetChild("Background"):diffusealpha(0):visible(false)

				if IsItlSong(player) then
					UpdatePathMap(player, SL[pn].Streams.Hash)
				end

				ResetAllData()
				PopulateLocalScores()

				pendingRequests = 0
				if canSendGS then pendingRequests = pendingRequests + 2 end -- official + boogie
				if canSendAC then pendingRequests = pendingRequests + 1 end

				-- Send GrooveStats and BoogieStats in parallel -- one to the
				-- official server, one to the BoogieStats proxy -- so both can
				-- be shown, regardless of the EnableBoogieStats setting.
				if canSendGS then
					local query = {
						maxLeaderboardResults=NumEntries,
					}
					query["chartHashP"..n] = SL[pn].Streams.Hash
					local headers = {}
					headers["x-api-key-player-"..n] = SL[pn].ApiKey
					local endpoint = "?action=playerLeaderboards&"..NETWORK:EncodeQueryParameters(query)

					self:GetParent():GetChild("OfficialRequester"):playcommand("MakeGrooveStatsRequest", {
						endpoint=endpoint,
						method="GET",
						headers=headers,
						timeout=10,
						callback=OfficialLeaderboardRequestProcessor,
						args=self:GetParent(),
					})
					self:GetParent():GetChild("BoogieRequester"):playcommand("MakeGrooveStatsRequest", {
						endpoint=endpoint,
						method="GET",
						headers=headers,
						timeout=10,
						callback=BoogieLeaderboardRequestProcessor,
						args=self:GetParent(),
					})
				end

				-- ArrowCloud is a different, non-GrooveStats-compatible API
				-- (Bearer auth, different base URL), so it's sent directly
				-- rather than through the OfficialRequester/BoogieRequester
				-- RequestResponseActors.
				if canSendAC then
					local acHeaders = {
						["Authorization"] = "Bearer " .. SL[pn].ArrowCloudApiKey,
					}
					local master = self:GetParent()
					NETWORK:HttpRequest{
						url = SL.ArrowCloud.BaseURL .. "/v1/chart/" .. SL[pn].Streams.Hash .. "/leaderboards",
						method = "GET",
						headers = acHeaders,
						connectTimeout = SL.ArrowCloud.RequestTimeout,
						transferTimeout = SL.ArrowCloud.RequestTimeout,
						onResponse = function(acres)
							ArrowCloudRequestProcessor(acres, master)
						end
					}
				end
			else
				-- Nothing available (no GrooveStats API Key, ArrowCloud
				-- disabled/no key, or the GrooveStats service is disabled):
				-- fall back to showing just the machine's local high scores.
				-- Explicitly clear the GrooveStats/Boogie/ArrowCloud/EX
				-- decorations so they can't get stuck visible from an earlier
				-- pass through the canSendGS/canSendAC branch (e.g. before a
				-- chart hash was available).
				ResetAllData()
				self:GetParent():GetChild("GrooveStatsLogo"):stopeffect():visible(false):diffusealpha(0)
				self:GetParent():GetChild("BoogieStatsLogo"):stopeffect():visible(false):diffusealpha(0)
				self:GetParent():GetChild("BoogieStatsEXLogo"):stopeffect():visible(false):diffusealpha(0)
				self:GetParent():GetChild("ArrowCloudLogo"):stopeffect():visible(false):diffusealpha(0)
				self:GetParent():GetChild("EXText"):finishtweening():diffusealpha(0)
				PopulateLocalScores()
				self:GetParent():visible(true)
				self:GetParent():queuecommand("CheckScorebox")
			end
		end
	},

	-- Two independent requesters, each pinned to a specific server
	-- regardless of the EnableBoogieStats preference (see GrooveStatsURL()
	-- in SL-Helpers-GrooveStats.lua). The coordinator above triggers both.
	RequestResponseActor(0, 0, "official")..{
		Name="OfficialRequester",
	},
	RequestResponseActor(0, 0, "boogie")..{
		Name="BoogieRequester",
	},

	-- Outline
	Def.Quad{
		Name="Outline",
		InitCommand=function(self)
			self:diffuse(GrooveStatsBlue):setsize(width + border, height + border)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width + border - 40, height + border)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width + border - 40, height + border)
			else
				self:setsize(width + border, height + border)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width + border, height + border)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds):diffuse(style_color[cur_style])
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- Main body
	Def.Quad{
		Name="Background",
		InitCommand=function(self)
			self:diffuse(color("#000000")):setsize(width, height)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:setsize(width - 40, height)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:setsize(width - 40, height)
			else
				self:setsize(width, height)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:setsize(width, height)
		end,
	},
	-- GrooveStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "GrooveStats.png"),
		Name="GrooveStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8 * scale):diffusealpha(0.5)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 0 or cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStats.png"),
		Name="BoogieStatsLogo",
		InitCommand=function(self)
			self:zoom(0.8 * scale):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 2 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- BoogieStats EX Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "BoogieStatsEX.png"),
		Name="BoogieStatsEXLogo",
		InitCommand=function(self)
			self:zoom(0.8 * scale):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 3 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- EX Text -- only for GrooveStats EX. BoogieStats EX uses its own
	-- "BoogieStatsEX.png" texture, which already has "EX" drawn into it,
	-- so adding this badge there would overlap/double up with it.
	Def.BitmapText{
		Name="EXText",
		Font=ThemePrefs.Get("ThemeFont") .. " Normal",
		Text="EX",
		InitCommand=function(self)
			self:diffusealpha(0):x(2 * scale):y(-5 * scale):zoom(scale)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 1 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.3)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- SRPG Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "_VisualStyles/SRPG10/logo_alt (doubleres).png"),
		Name="SRPGLogo",
		InitCommand=function(self)
			self:diffusealpha(0.4):zoom(0.07 * scale):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 4 then
				self:linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- ITL Logo
	Def.Sprite{
		Texture=THEME:GetPathG("", "ITL.png"),
		Name="ITLLogo",
		InitCommand=function(self)
			self:diffusealpha(0.2):zoom(0.45 * scale):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 5 then
				self:linear(transition_seconds/2):diffusealpha(0.2)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
	-- ArrowCloud Logo (shared by ITG/EX/HardEX; the outline color already
	-- distinguishes which sub-style is showing). "ac logo.png" is a huge
	-- 1196x1196 source image, unlike GrooveStats/BoogieStats.png at
	-- 128x128, so its zoom has to be scaled down by that same ratio
	-- (128/1196) to end up the same rendered size as those.
	Def.Sprite{
		Texture=THEME:GetPathG("", "Arrow Cloud/ac logo.png"),
		Name="ArrowCloudLogo",
		InitCommand=function(self)
			self:zoom((128/1196) * 0.8 * scale):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 6 or cur_style == 7 or cur_style == 8 then
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0.5)
			else
				self:linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening():stopeffect() end
	},
	-- Local/Machine scores background tint (no logo image yet; aqua blue fill)
	Def.Quad{
		Name="LocalScoresBackground",
		InitCommand=function(self)
			self:diffuse(LocalAqua):zoomto(width, height):diffusealpha(0)
		end,
		LoopScoreboxCommand=function(self)
			if cur_style == 9 then
				self:linear(transition_seconds/2):diffusealpha(0.25)
			else
				self:sleep(transition_seconds/2):linear(transition_seconds/2):diffusealpha(0)
			end
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	},
}

for i=1,NumEntries do
	local y = -height/2 + row_height * i - row_height/2
	local zoom = 0.87 * scale

	-- Rank 1 gets a crown.
	if i == 1 then
		af[#af+1] = Def.Sprite{
			Name="Rank"..i,
			Texture=THEME:GetPathG("", "crown.png"),
			InitCommand=function(self)
				self:zoom(0.09 * scale):xy(-width/2 + 14 * scale, y):diffusealpha(0)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 32 * scale)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 32 * scale)
				else
					self:x(-width/2 + 14 * scale)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 14)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				if score.rank ~= "" then
					self:linear(transition_seconds/2):diffusealpha(1)
				end
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	else
		af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Name="Rank"..i,
			Text="",
			InitCommand=function(self)
				self:diffuse(Color.White):xy(-width/2 + 27 * scale, y):maxwidth(30 * scale):horizalign(right):zoom(zoom)
				if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
					self:x(-width/2 + 42 * scale)
				end
			end,
			PlayerJoinedMessageCommand=function(self,params)
				if IsNotWide then
					self:x(-width/2 + 42 * scale)
				else
					self:x(-width/2 + 27 * scale)
				end
			end,
			PlayerUnjoinedMessageCommand=function(self,params)
				self:x(-width/2 + 27 * scale)
			end,
			LoopScoreboxCommand=function(self)
				self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
			end,
			SetScoreboxCommand=function(self)
				local score = all_data[cur_style+1]["scores"][i]
				local clr = Color.White
				if score.isSelf then
					clr = self_color
				elseif score.isRival then
					clr = rival_color
				end
				self:settext(score.rank)
				self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
			end,
			ResetCommand=function(self) self:stoptweening() end,
			OffCommand=function(self) self:stoptweening() end
		}
	end

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Name"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 30 * scale, y):maxwidth(100 * scale):horizalign(left):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 45 * scale):maxwidth(70 * scale)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 45 * scale):maxwidth(70 * scale)
			else
				self:x(-width/2 + 30 * scale):maxwidth(100 * scale)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 30 * scale):maxwidth(100 * scale)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = Color.White
			if score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.name)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}

	af[#af+1] = LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Name="Score"..i,
		Text="",
		InitCommand=function(self)
			self:diffuse(Color.White):xy(-width/2 + 160 * scale, y):horizalign(right):zoom(zoom)
			if IsNotWide and #GAMESTATE:GetHumanPlayers() > 1 then
				self:x(-width/2 + 140 * scale)
			end
		end,
		PlayerJoinedMessageCommand=function(self,params)
			if IsNotWide then
				self:x(-width/2 + 140 * scale)
			else
				self:x(-width/2 + 160 * scale)
			end
		end,
		PlayerUnjoinedMessageCommand=function(self,params)
			self:x(-width/2 + 160 * scale)
		end,
		LoopScoreboxCommand=function(self)
			self:linear(transition_seconds/2):diffusealpha(0):queuecommand("SetScorebox")
		end,
		SetScoreboxCommand=function(self)
			local score = all_data[cur_style+1]["scores"][i]
			local clr = Color.White
			if score.isFail then
				clr = Color.Red
			elseif score.isEx then
				clr = SL.JudgmentColors["FA+"][1]
			elseif score.isSelf then
				clr = self_color
			elseif score.isRival then
				clr = rival_color
			end
			self:settext(score.score)
			self:linear(transition_seconds/2):diffusealpha(1):diffuse(clr)
		end,
		ResetCommand=function(self) self:stoptweening() end,
		OffCommand=function(self) self:stoptweening() end
	}
end
return af
