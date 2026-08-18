local NumEntries = 13
local RowHeight = 24

local SetEntryText = function(rank, name, score, date, actor)
	if actor == nil then return end

	actor:GetChild("Rank"):settext(rank)
	actor:GetChild("Name"):settext(name)
	actor:GetChild("Score"):settext(score)
	actor:GetChild("Date"):settext(date)
end

local SetLeaderboardForPlayer = function(player_num, leaderboard, leaderboardData, isRanked)
	if leaderboard == nil or leaderboardData == nil then return end
	local playerStr = "player"..player_num
	local entryNum = 1
	local rivalNum = 1

	
	if leaderboardData["Disabled"] then
		if leaderboardData["Name"] then
			local name = leaderboardData["Name"]:gsub("ITL Online", "ITL")
			leaderboard:GetChild("Header"):settext(name)
		end
		for j=1, NumEntries do
			local entry = leaderboard:GetChild("LeaderboardEntry"..j)
			if j == 1 then
				SetEntryText("", "Disabled", "", "", entry)
			else
				-- Empty out the remaining rows.
				SetEntryText("", "", "", "", entry)
			end
		end
		return
	end

	-- Hide the rival and self highlights.
	-- They will be unhidden and repositioned as needed below.
	for i=1,3 do
		leaderboard:GetChild("Rival"..i):visible(false)
	end
	leaderboard:GetChild("Self"):visible(false)

	-- Hide/Unhide EX score display
	leaderboard:GetChild("EX"):visible(leaderboardData["IsEX"])

	if leaderboardData then
		if leaderboardData["Name"] then
			local name = leaderboardData["Name"]:gsub("ITL Online", "ITL")
			leaderboard:GetChild("Header"):settext(name)
		end

		if leaderboardData["Data"] then
			local added = {}
			for gsEntry in ivalues(leaderboardData["Data"]) do
				if not added[gsEntry["name"]] then
					added[gsEntry["name"]] = true
					local entry = leaderboard:GetChild("LeaderboardEntry"..entryNum)
					SetEntryText(
						gsEntry["rank"]..".",
						gsEntry["name"],
						string.format("%.2f%%", gsEntry["score"]/100),
						ParseGrooveStatsDate(gsEntry["date"]),
						entry
					)
					if gsEntry["isRival"] then
						if gsEntry["isFail"] then
							entry:GetChild("Rank"):diffuse(Color.Black)
							entry:GetChild("Name"):diffuse(Color.Black)
							entry:GetChild("Score"):diffuse(Color.Red)
							entry:GetChild("Date"):diffuse(Color.Black)
						else
							entry:diffuse(Color.Black)
						end
						leaderboard:GetChild("Rival"..rivalNum):y(entry:GetY()):visible(true)
						rivalNum = rivalNum + 1
					elseif gsEntry["isSelf"] then
						if gsEntry["isFail"] then
							entry:GetChild("Rank"):diffuse(Color.Black)
							entry:GetChild("Name"):diffuse(Color.Black)
							entry:GetChild("Score"):diffuse(Color.Red)
							entry:GetChild("Date"):diffuse(Color.Black)
						else
							entry:diffuse(Color.Black)
						end
						leaderboard:GetChild("Self"):y(entry:GetY()):visible(true)
					else
						entry:diffuse(Color.White)
					end

					-- Why does this work for normal entries but not for Rivals/Self where
					-- I have to explicitly set the colors for each child??
					if gsEntry["isFail"] then
						entry:GetChild("Score"):diffuse(Color.Red)
					end
					entryNum = entryNum + 1
				end
			end
		end
	end

	-- Empty out any remaining entries.
	-- This also handles the error case. If success is false, then the above if block will not run.
	-- and we will set the first entry to "Failed to Load 😞".
	for i=entryNum, NumEntries do
		local entry = leaderboard:GetChild("LeaderboardEntry"..i)
		-- We didn't get any scores if i is still == 1.
		if i == 1 then
			SetEntryText("", "No Scores", "", "", entry)
		else
			-- Empty out the remaining rows.
			SetEntryText("", "", "", "", entry)
		end
	end
end
local getLocalLeaderboard = function(pn)
	if not GAMESTATE:IsPlayerEnabled(pn) then return {} end
    local HighScores = PROFILEMAN:GetMachineProfile():GetHighScoreList(GAMESTATE:GetCurrentSong(),GAMESTATE:GetCurrentSteps(pn)):GetHighScores()
    local profileName = PROFILEMAN:GetProfile(pn):GetLastUsedHighScoreName()
    local localData = {}
    if HighScores then
        for i, highscore in ipairs(HighScores) do
            local name = highscore:GetName()
            local percentDP = highscore:GetPercentDP()
            local score = tonumber(("%.0f"):format(percentDP * 10000))
            local date = highscore:GetDate()
            local grade = highscore:GetGrade()
            local isRival = false
            local isSelf = name == profileName
            local isFail = false
            if grade == "Grade_Failed" then
                isFail = true
            end
            local entry = {
                name=name,
                score=score,
                date=date,
                isRival=isRival,
                isSelf=isSelf,
                isFail=isFail,
                rank=i
            }
            table.insert(localData, entry)
        end
    end
    return localData
end
-- Official GrooveStats and BoogieStats are now queried as two independent,
-- parallel requests (instead of BoogieStats silently replacing GrooveStats
-- whenever EnableBoogieStats is on), so both can appear as separate entries
-- to cycle through with left/right. pendingRequests tracks how many of the
-- two responses (per player) we're still waiting on; once it hits 0 we
-- assemble the final list from whichever succeeded.
local pendingRequests = {P1=0, P2=0}
local officialResponseData = {P1=nil, P2=nil}
local boogieResponseData = {P1=nil, P2=nil}

local FinalizeLeaderboardsForPlayer = function(i, master)
	local pn = "P"..i
	local leaderboard = master:GetChild(pn.."Leaderboard")
	local leaderboardList = master[pn]["Leaderboards"]

	local data = officialResponseData[pn]
	local bdata = boogieResponseData[pn]

	if data then
		master[pn].isRanked = data["isRanked"]

		if data["gsLeaderboard"] then
			leaderboardList[#leaderboardList + 1] = {
				Name="GrooveStats",
				Data=DeepCopy(data["gsLeaderboard"]),
				IsEX=false
			}
		end
		if data["exLeaderboard"] then
			leaderboardList[#leaderboardList + 1] = {
				Name="GrooveStats",
				Data=DeepCopy(data["exLeaderboard"]),
				IsEX=true
			}
		end
	end

	if bdata then
		if bdata["gsLeaderboard"] then
			leaderboardList[#leaderboardList + 1] = {
				Name="BoogieStats",
				Data=DeepCopy(bdata["gsLeaderboard"]),
				IsEX=false
			}
		end
		if bdata["exLeaderboard"] then
			leaderboardList[#leaderboardList + 1] = {
				Name="BoogieStats",
				Data=DeepCopy(bdata["exLeaderboard"]),
				IsEX=true
			}
		end
	end

	if data then
		local events = {"rpg", "itl"}
		for event in ivalues(events) do
			if data[event] and data[event][event.."Leaderboard"] then
				leaderboardList[#leaderboardList + 1] = {
					Name=data[event]["name"],
					Data=DeepCopy(data[event][event.."Leaderboard"]),
					IsEX=(event == "itl")
				}
			end
		end
	end

	-- Display the local leaderboard last
	local localData = getLocalLeaderboard(pn)
	leaderboardList[#leaderboardList + 1] = {
		Name="Machine's  Best",
		Data=DeepCopy(localData),
		IsEX=false
	}

	master[pn]["LeaderboardIndex"] = 1
	leaderboard:GetChild("PaneIcons"):visible(#leaderboardList > 1)

	-- We assume that at least one leaderboard has been added.
	SetLeaderboardForPlayer(i, leaderboard, leaderboardList[1], master[pn].isRanked)
end

-- Processes one response (from either server) and, once both the official
-- and BoogieStats responses for a player have arrived (or failed), finalizes
-- that player's leaderboard list.
local ProcessLeaderboardResponse = function(res, master, dataStore)
	if master == nil then return end

	local data = nil
	if not (res.error or res.statusCode ~= 200) then
		data = JsonDecode(res.body)
	end

	for i=1, 2 do
		local pn = "P"..i
		if pendingRequests[pn] > 0 then
			if data and data["player"..i] then
				dataStore[pn] = data["player"..i]
			end
			pendingRequests[pn] = pendingRequests[pn] - 1
			if pendingRequests[pn] == 0 then
				FinalizeLeaderboardsForPlayer(i, master)
			end
		end
	end
end

local OfficialLeaderboardProcessor = function(res, master)
	ProcessLeaderboardResponse(res, master, officialResponseData)
end

local BoogieLeaderboardProcessor = function(res, master)
	ProcessLeaderboardResponse(res, master, boogieResponseData)
end

local af = Def.ActorFrame{
	Name="LeaderboardMaster",
	InitCommand=function(self) self:visible(false) end,
	ShowLeaderboardCommand=function(self)
		self:visible(true)
		for i=1, 2 do
			local pn = "P"..i
			self[pn] = {}
			self[pn].isRanked = false
			self[pn].Leaderboards = {}
			self[pn].LeaderboardIndex = 0
			pendingRequests[pn] = 0
			officialResponseData[pn] = nil
			boogieResponseData[pn] = nil
		end
		MESSAGEMAN:Broadcast("ResetEntry")
		-- Only make the request when this actor gets actually displayed through the sort menu.
		self:queuecommand("SendLeaderboardRequest")
	end,
	HideLeaderboardCommand=function(self) self:visible(false) end,
	LeaderboardInputEventMessageCommand=function(self, event)
		local pn = ToEnumShortString(event.PlayerNumber)
		if #self[pn].Leaderboards == 0 then return end

		if event.type == "InputEventType_FirstPress" then
			-- We don't use modulus because #Leaderboards might be zero.
			if event.GameButton == "MenuLeft" then
				self[pn].LeaderboardIndex = self[pn].LeaderboardIndex - 1

				if self[pn].LeaderboardIndex == 0 then
					-- Wrap around if we decremented from 1 to 0.
					self[pn].LeaderboardIndex = #self[pn].Leaderboards
				end
			elseif event.GameButton == "MenuRight" then
				self[pn].LeaderboardIndex = self[pn].LeaderboardIndex + 1

				if self[pn].LeaderboardIndex > #self[pn].Leaderboards then
					-- Wrap around if we incremented past #Leaderboards
					self[pn].LeaderboardIndex = 1
				end
			end

			if event.GameButton == "MenuLeft" or event.GameButton == "MenuRight" then
				local leaderboard = self:GetChild(pn.."Leaderboard")
				local leaderboardList = self[pn]["Leaderboards"]
				local leaderboardData = leaderboardList[self[pn].LeaderboardIndex]
				SetLeaderboardForPlayer("P1" == pn and 1 or 2, leaderboard, leaderboardData, self[pn].isRanked)
			end
		end
	end,

	Def.Quad{ InitCommand=function(self) self:FullScreen():diffuse(0,0,0,0.875) end },
	LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
		Text=THEME:GetString("Common", "PopupDismissText"),
		InitCommand=function(self) self:xy(_screen.cx, _screen.h-50):zoom(1.1) end
	},
	RequestResponseActor(17, 50)..{
		SendLeaderboardRequestCommand=function(self)
			-- If a player does not have an API key or chart hash just show the local leaderboard.
			for i=1,2 do
				local pn = "P"..i
				if SL[pn].ApiKey == "" or SL[pn].Streams.Hash == "" or not IsServiceAllowed(SL.GrooveStats.Leaderboard) then
					local pn = "P"..i
					local leaderboard = self:GetParent():GetChild(pn.."Leaderboard")
					local leaderboardList = self:GetParent()[pn]["Leaderboards"]
					local localData = getLocalLeaderboard(pn)
					leaderboardList[#leaderboardList + 1] = {
						Name="Machine's  Best",
						Data=DeepCopy(localData),
						IsEX=false
					}
					self:GetParent()[pn]["LeaderboardIndex"] = 1
				end
			end
			if not IsServiceAllowed(SL.GrooveStats.Leaderboard) then
				if SL.GrooveStats.IsConnected then
					-- If we disable the service from a previous request, surface it to the user here.
					for i=1, 2 do
						local pn = "P"..i
						local leaderboard = self:GetParent():GetChild(pn.."Leaderboard")
						local leaderboardList = self:GetParent()[pn]["Leaderboards"]
						leaderboardList[#leaderboardList + 1] = {
							Name="GrooveStats",
							Disabled=true,
							IsEX=false
						}
						SetLeaderboardForPlayer(i, leaderboard, leaderboardList[1], false)
					end
				end
				return
			end

			local sendRequest = false
			local headers = {}
			local query = {
				maxLeaderboardResults=NumEntries,
			}

			for i=1,2 do
				local pn = "P"..i
				if SL[pn].ApiKey ~= "" and SL[pn].Streams.Hash ~= "" then
					query["chartHashP"..i] = SL[pn].Streams.Hash
					headers["x-api-key-player-"..i] = SL[pn].ApiKey
					pendingRequests[pn] = 2
					sendRequest = true
				end
			end
			-- Only send the request if it's applicable.
			-- Technically this should always be true since otherwise we wouldn't even get to this screen.
			if sendRequest then
				local endpoint = "?action=playerLeaderboards&"..NETWORK:EncodeQueryParameters(query)
				local master = SCREENMAN:GetTopScreen():GetChild("Overlay"):GetChild("LeaderboardMaster")
				-- Send both requests in parallel -- one to the official
				-- GrooveStats server, one to the BoogieStats proxy -- so both
				-- can be shown, regardless of the EnableBoogieStats setting.
				self:GetParent():GetChild("OfficialRequester"):playcommand("MakeGrooveStatsRequest", {
					endpoint=endpoint,
					method="GET",
					headers=headers,
					timeout=10,
					callback=OfficialLeaderboardProcessor,
					args=master,
				})
				self:GetParent():GetChild("BoogieRequester"):playcommand("MakeGrooveStatsRequest", {
					endpoint=endpoint,
					method="GET",
					headers=headers,
					timeout=10,
					callback=BoogieLeaderboardProcessor,
					args=master,
				})
			end
		end
	},

	-- Two independent requesters, each pinned to a specific server
	-- regardless of the EnableBoogieStats preference (see GrooveStatsURL()
	-- in SL-Helpers-GrooveStats.lua). The coordinator above triggers both.
	RequestResponseActor(17, 50, "official")..{
		Name="OfficialRequester",
	},
	RequestResponseActor(17, 50, "boogie")..{
		Name="BoogieRequester",
	},
}

local paneWidth1Player = 330
local paneWidth2Player = 230
local paneWidth = (GAMESTATE:GetNumSidesJoined() == 1) and paneWidth1Player or paneWidth2Player
local paneHeight = 360
local borderWidth = 2

for player in ivalues( PlayerNumber ) do
	af[#af+1] = Def.ActorFrame{
		Name=ToEnumShortString(player).."Leaderboard",
		InitCommand=function(self)
			self:y(_screen.cy - 15)
			self:queuecommand("Refresh")
		end,
		PlayerJoinedMessageCommand=function(self)
			self:queuecommand("Refresh")
		end,

		RefreshCommand=function(self)
			self:visible(GAMESTATE:IsSideJoined(player))

			if GAMESTATE:GetNumSidesJoined() == 1 then
				self:xy(_screen.cx, _screen.cy - 15)
			else
				self:xy(_screen.cx + 160 * (player==PLAYER_1 and -1 or 1), _screen.cy - 15)
			end
			self:SetWidth(paneWidth)
		end,

		-- White border
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.White)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width + borderWidth, paneHeight + borderWidth)
			end
		},

		-- Main black body
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.Black)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, paneHeight)
			end
		},

		-- Header border
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.White):y(-paneHeight/2 + RowHeight/2)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width + borderWidth, RowHeight + borderWidth)
			end
		},

		-- Blue Header
		Def.Quad {
			InitCommand=function(self)
				self:diffuse(Color.Blue):y(-paneHeight/2 + RowHeight/2)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		-- Header Text
		LoadFont("Wendy/_wendy small").. {
			Name="Header",
			Text="GrooveStats",
			InitCommand=function(self)
				self:zoom(0.5)
				self:y(-paneHeight/2 + 12)
			end
		},

		-- EX Text
		LoadFont("Wendy/_wendy small").. {
			Name="EX",
			Text="EX",
			InitCommand=function(self)
				self:zoom(0.5)
				self:y(-paneHeight/2 + 12)
				self:x(paneWidth/2 - 16)
				self:visible(false)
			end
		},

		-- Highlight backgrounds for the leaderboard. Initially hidden.
		Def.Quad {
			Name="Rival1",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Rival2",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Rival3",
			InitCommand=function(self)
				self:diffuse(color("#BD94FF")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		Def.Quad {
			Name="Self",
			InitCommand=function(self)
				self:diffuse(color("#A1FF94")):visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:zoomto(width, RowHeight)
			end
		},

		-- Marker for the additional panes. Hidden by default.
		Def.ActorFrame{
			Name="PaneIcons",
			InitCommand=function(self)
				self:y(paneHeight/2 - RowHeight/2)
				self:visible(false)
			end,
			ResetEntryMessageCommand=function(self)
				self:visible(false)
			end,

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="LeftIcon",
				Text="&MENULEFT;",
				InitCommand=function(self)
					self:x(-paneWidth/2 + 10)
				end,
				OnCommand=function(self) self:queuecommand("Bounce") end,
				BounceCommand=function(self)
					self:decelerate(0.5):addx(10):accelerate(0.5):addx(-10)
					self:queuecommand("Bounce")
				end,
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Text",
				Text=THEME:GetString("GrooveStats", "MoreLeaderboards"),
				InitCommand=function(self)
					self:diffuse(Color.White)
				end,
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="RightIcon",
				Text="&MENURiGHT;",
				InitCommand=function(self)
					self:x(paneWidth/2 - 10)
				end,
				OnCommand=function(self) self:queuecommand("Bounce") end,
				BounceCommand=function(self)
					self:decelerate(0.5):addx(-10):accelerate(0.5):addx(10)
					self:queuecommand("Bounce")
				end,
			},
		}
	}

	local af2 = af[#af]
	for i=1, NumEntries do
		--- Each entry has a Rank, Name, and Score subactor.
		af2[#af2+1] = Def.ActorFrame{
			Name="LeaderboardEntry"..i,
			InitCommand=function(self)
				if NumEntries % 2 == 1 then
					self:y(RowHeight*(i - (NumEntries+1)/2) )
				else
					self:y(RowHeight*(i - NumEntries/2))
				end
			end,
			RefreshCommand=function(self)
				local width = self:GetParent():GetWidth()
				self:x(-(width-paneWidth2Player)/2)
				self:GetChild("Date"):visible(GAMESTATE:GetNumSidesJoined() == 1)
			end,

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Rank",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:maxwidth(30)
					self:x(-paneWidth2Player/2 + 30 + borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Name",
				Text=(i==1 and THEME:GetString("GrooveStats", "Loading") or ""),
				InitCommand=function(self)
					self:horizalign(center)
					self:maxwidth(130)
					self:x(-paneWidth2Player/2 + 100)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext(i==1 and THEME:GetString("GrooveStats", "Loading") or "")
					self:diffuse(Color.White)
				end
			},

			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Score",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:x(paneWidth2Player/2-borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},
			LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal").. {
				Name="Date",
				Text="",
				InitCommand=function(self)
					self:horizalign(right)
					self:x(paneWidth2Player/2 + 100 - borderWidth)
					self:diffuse(Color.White)
				end,
				ResetEntryMessageCommand=function(self)
					self:settext("")
					self:diffuse(Color.White)
				end
			},
		}
	end
end

return af
