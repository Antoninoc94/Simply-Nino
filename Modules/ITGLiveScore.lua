-- Writes a live snapshot of the current song/scores to /Save/RealTimeResults.json while
-- ScreenGameplay is active, and appends a final snapshot to /Save/RealTimeResultsHistory.json
-- once a song ends, for the companion web overlay in Tools/ITGLiveScore.
-- See Tools/ITGLiveScore/README.md for the JSON schema and how to run the overlay server.

local WriteInterval = 0.5
local LivePath = "/Save/RealTimeResults.json"
local HistoryPath = "/Save/RealTimeResultsHistory.json"
local DetailDir = "/Save/RealTimeScoreDetails/"
local HistoryLimit = 50

local Windows = {
	{ Key = "Fantastic", TNS = "TapNoteScore_W1" },
	{ Key = "Excellent", TNS = "TapNoteScore_W2" },
	{ Key = "Great",     TNS = "TapNoteScore_W3" },
	{ Key = "Decent",    TNS = "TapNoteScore_W4" },
	{ Key = "WayOff",    TNS = "TapNoteScore_W5" },
	{ Key = "Miss",      TNS = "TapNoteScore_Miss" },
}

-- GetExJudgmentCounts() (Scripts/SL-Helpers.lua) splits FA+ (W0) out of the Fantastic (W1)
-- window; plain GetTapNoteScores can't tell them apart. Not available in Casual mode, so
-- fall back to the raw per-window counts there.
local BuildJudgmentCounts = function(player, pss)
	local ok, counts = pcall(GetExJudgmentCounts, player)
	if ok and counts then
		return {
			FAPlus     = counts.W0 or 0,
			Fantastic  = counts.W1 or 0,
			Excellent  = counts.W2 or 0,
			Great      = counts.W3 or 0,
			Decent     = counts.W4 or 0,
			WayOff     = counts.W5 or 0,
			Miss       = counts.Miss or 0,
			Holds      = counts.Holds,
			HoldsTotal = counts.totalHolds,
			Rolls      = counts.Rolls,
			RollsTotal = counts.totalRolls,
			Mines      = counts.Mines,
			MinesTotal = counts.totalMines,
		}
	end

	local judgments = { FAPlus = 0 }
	for _, window in ipairs(Windows) do
		judgments[window.Key] = pss:GetTapNoteScores(window.TNS)
	end
	return judgments
end

-- Same FA+ (W0) window formula as IsW0Judgment() in Scripts/SL-Helpers.lua, applied to an
-- already-recorded offset instead of a live JudgmentMessageCommand.
local ClassifyOffset = function(offsetSeconds)
	if offsetSeconds == "Miss" then return "Miss" end

	local window = DetermineTimingWindow(offsetSeconds)
	if window == 1 and (SL.Global.GameMode == "ITG" or SL.Global.GameMode == "FA+") then
		local prefs = SL.Preferences["FA+"]
		local scale = PREFSMAN:GetPreference("TimingWindowScale")
		local w0 = prefs["TimingWindowSecondsW1"] * scale + prefs["TimingWindowAdd"]
		if math.abs(offsetSeconds) <= w0 then return "FAPlus" end
	end

	local labels = { "Fantastic", "Excellent", "Great", "Decent", "WayOff" }
	return labels[window] or "WayOff"
end

-- Per-note offsets are already recorded during gameplay by
-- BGAnimations/ScreenGameplay overlay/JudgmentOffsetTracking.lua (used for the theme's own
-- scatter plot/histogram on ScreenEvaluation) -- reuse that instead of tracking it ourselves.
-- Each entry is { time_seconds, offset_seconds_or_"Miss", arrow, isStream, foot, hitEarly,
-- earlyOffset, heldMiss, is_autohit }; we only need the first two.
local BuildOffsetDetail = function(player)
	local pn = ToEnumShortString(player)
	local stage = SL[pn].Stages.Stats[SL.Global.Stages.PlayedThisGame + 1]
	local sequential = stage and stage.sequential_offsets
	if not sequential then return nil end

	local points = {}
	local sumOffset, sumAbsOffset, sumSquares, maxAbsOffset, n = 0, 0, 0, 0, 0

	for _, note in ipairs(sequential) do
		local t = note[1]
		local offset = note[2]
		local ms = nil

		if offset ~= "Miss" then
			ms = offset * 1000
			n = n + 1
			sumOffset = sumOffset + ms
			local absMs = math.abs(ms)
			sumAbsOffset = sumAbsOffset + absMs
			sumSquares = sumSquares + (ms * ms)
			if absMs > maxAbsOffset then maxAbsOffset = absMs end
		end

		points[#points + 1] = { t = t, ms = ms, tns = ClassifyOffset(offset) }
	end

	local stats = { MeanOffset = 0, MeanAbsError = 0, StdDev3 = 0, MaxError = 0 }
	if n > 0 then
		stats.MeanOffset = sumOffset / n
		stats.MeanAbsError = sumAbsOffset / n
		-- population variance via E[x^2] - E[x]^2; 99.7% of hits fall within 3 standard
		-- deviations of the mean (the "three-sigma rule"), matching ArrowCloud's stat.
		local variance = (sumSquares / n) - (stats.MeanOffset * stats.MeanOffset)
		stats.StdDev3 = math.sqrt(math.max(variance, 0)) * 3
		stats.MaxError = maxAbsOffset
	end

	return { Offsets = points, Stats = stats }
end

-- Mirrors getLifebarData() in Modules/ArrowCloud.lua: GetLifeRecord() is an engine API that
-- returns evenly-spaced life samples across the whole song, already tracked for us.
local BuildLifeCurve = function(player)
	local song = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps(player)
	if not song or not steps then return nil end

	local lastSecond = song:GetLastSecond()
	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)
	local ok, lifeRecord = pcall(function() return pss:GetLifeRecord(lastSecond, 100) end)
	if not ok or not lifeRecord or #lifeRecord == 0 then return nil end

	local firstSecond = math.min(steps:GetTimingData():GetElapsedTimeFromBeat(0), 0)
	local chartStartSecond = song:GetFirstSecond()
	local duration = lastSecond - firstSecond

	local points = {}
	for i, life in ipairs(lifeRecord) do
		points[i] = { t = chartStartSecond + (i - 1) * (duration / #lifeRecord), life = life }
	end
	return points
end

-- Song title/artist plus each joined player's score and judgment counts.
-- Shared by the live writer and the end-of-song history writer.
local BuildSongSnapshot = function()
	-- courses switch songs mid-stage; keep this simple and only cover single songs for now
	if GAMESTATE:IsCourseMode() then return nil end

	local song = GAMESTATE:GetCurrentSong()
	if not song then return nil end

	local snapshot = {
		SongTitle = song:GetDisplayFullTitle(),
		SongArtist = song:GetDisplayArtist(),
	}

	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local pn = ToEnumShortString(player)
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(player)

		local playerName = "[GUEST]"
		if PROFILEMAN:IsPersistentProfile(player) then
			playerName = PROFILEMAN:GetProfile(player):GetDisplayName()
		end

		local entry = {
			PlayerName = playerName,
			PunteggioITG = pss:GetPercentDancePoints() * 100,
		}
		for key, value in pairs(BuildJudgmentCounts(player, pss)) do
			entry[key] = value
		end

		snapshot[pn] = entry
	end

	return snapshot
end

local WriteSnapshot = function(life)
	local snapshot = BuildSongSnapshot()
	if not snapshot then return end

	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		snapshot[ToEnumShortString(player)].Life = life[player] or 1
	end

	local file = RageFileUtil:CreateRageFile()
	if file:Open(LivePath, 2) then
		file:Write(JsonEncode(snapshot))
		file:Close()
	end
	file:destroy()
end

local AppendHistory = function()
	local snapshot = BuildSongSnapshot()
	if not snapshot then return end

	snapshot.DateTime = ("%04d-%02d-%02d %02d:%02d:%02d"):format(
		Year(), MonthOfYear() + 1, DayOfMonth(), Hour(), Minute(), Second())
	snapshot.Id = (snapshot.DateTime):gsub("[ :]", "_")

	-- Detail payload (per-note offsets + life curve) for the "click a score" view.
	-- Kept in a separate file per song so the compact history list stays light to fetch.
	local detail = {}
	for player in ivalues(GAMESTATE:GetHumanPlayers()) do
		local offsetDetail = BuildOffsetDetail(player)
		if offsetDetail then
			offsetDetail.Life = BuildLifeCurve(player)
			detail[ToEnumShortString(player)] = offsetDetail
		end
	end

	if next(detail) then
		local detailFile = RageFileUtil:CreateRageFile()
		if detailFile:Open(DetailDir .. snapshot.Id .. ".json", 2) then
			detailFile:Write(JsonEncode(detail))
			detailFile:Close()
		end
		detailFile:destroy()
	end

	local history = {}
	if FILEMAN:DoesFileExist(HistoryPath) then
		local reader = RageFileUtil:CreateRageFile()
		if reader:Open(HistoryPath, 1) then
			local ok, decoded = pcall(JsonDecode, reader:Read())
			if ok and type(decoded) == "table" then history = decoded end
			reader:Close()
		end
		reader:destroy()
	end

	table.insert(history, snapshot)
	while #history > HistoryLimit do
		table.remove(history, 1)
	end

	local writer = RageFileUtil:CreateRageFile()
	if writer:Open(HistoryPath, 2) then
		writer:Write(JsonEncode(history))
		writer:Close()
	end
	writer:destroy()
end

local t = {}

t[Branch.GameplayScreen()] = Def.ActorFrame {
	Name = "ITGLiveScoreExport",

	InitCommand = function(self)
		self.life = { [PLAYER_1] = 1, [PLAYER_2] = 1 }
	end,

	LifeChangedMessageCommand = function(self, params)
		if params.Player and params.LifeMeter then
			self.life[params.Player] = params.LifeMeter:GetLife()
		end
	end,

	ModuleCommand = function(self)
		if not ThemePrefs.Get("EnableLiveScoreExport") then return end
		self.life = { [PLAYER_1] = 1, [PLAYER_2] = 1 }
		self:queuecommand("Tick")
	end,

	TickCommand = function(self)
		if SCREENMAN:GetTopScreen():GetName() ~= Branch.GameplayScreen() then return end
		WriteSnapshot(self.life)
		self:sleep(WriteInterval):queuecommand("Tick")
	end,
}

-- Appends the just-finished song's final result to the history file. Same screen ArrowCloud
-- (Modules/ArrowCloud.lua) uses for its own end-of-song hook.
t["ScreenEvaluationStage"] = Def.ActorFrame {
	Name = "ITGLiveScoreHistory",

	ModuleCommand = function(self)
		if not ThemePrefs.Get("EnableLiveScoreExport") then return end
		AppendHistory()
	end,
}

-- Status indicator on the title screen, stacked below ArrowCloud's (Modules/ArrowCloud.lua),
-- same top-right anchor. Just reflects the ThemePrefs toggle, no network involved.
t["ScreenTitleMenu"] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(_screen.w - 10, 33):zoom(0.8):halign(1)
	end,

	ModuleCommand = function(self)
		local bmt = self:GetChild("Status")
		if not bmt then return end
		bmt:settext(ThemePrefs.Get("EnableLiveScoreExport") and "✔ Live Score" or "❌ Live Score")
	end,

	LoadFont("Common Normal") .. {
		Name = "Status",
		InitCommand = function(self)
			self:halign(1)
			self:settext("Live Score")
		end
	}
}

return t
