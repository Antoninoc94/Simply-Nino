-- Golf mode helpers.
--
-- Golf is an alternate scoring concept (see Modules/GolfScoring.lua) where every tap is
-- worth a number of "strokes" based on how far off it was, and a chart has a "par" the
-- player is trying to come in under.
--
-- Par isn't something the engine knows about, and it isn't something we can hide in the
-- simfile either: the .sm/.ssc loaders parse a fixed set of tags and throw away anything
-- they don't recognize, so a custom "#PAR:" would only be readable by re-reading the raw
-- file off disk ourselves (the way SL-ChartParser.lua does). That's far too expensive to
-- do from MusicWheelItem's SetCommand, which fires for every visible row on every scroll.
--
-- So par lives in a "Golf.ini" at the root of the pack, read once per pack and cached.
-- The presence of that file is the entire opt-in: any pack that ships one is a golf pack,
-- and any chart it names is a golf hole.
--
--     ; /Songs/<any pack>/Golf.ini
--     [Honey]
--     Par=3
--
--     ; per-chart override, for songs carrying more than one golf chart
--     [Honey:Challenge]
--     Par=4
--
-- Section names are the song's folder name, optionally suffixed with ":" and the short
-- Difficulty string ("Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit").

Golf = Golf or {}

-- [pack directory] -> parsed Golf.ini table, or false if the pack has no Golf.ini.
-- Doubles as the is-this-a-golf-pack answer, and as the cache that keeps the wheel from
-- stat()ing the same pack once per visible row per scroll tick.
local par_data = {}

-- -----------------------------------------------------------------------
-- "/Songs/Some Pack/Some Song/" -> "/Songs/Some Pack/"
local function PackDir(song)
	local dir = song:GetSongDir()
	if not dir or dir == "" then return nil end
	return (dir:gsub("[^/]+/$", ""))
end

-- IniFile.StrToKeyVal already converts numeric values with tonumber(), but a Golf.ini
-- written with CRLF line endings (likely, since these packs get authored on Windows)
-- leaves a trailing \r on anything it couldn't convert. Be forgiving.
local function ToPar(value)
	if type(value) == "number" then return value end
	if type(value) ~= "string" then return nil end
	return tonumber(value:match("^%s*(.-)%s*$"))
end

local function LoadParData(pack_dir)
	if par_data[pack_dir] ~= nil then return par_data[pack_dir] end

	local path = pack_dir .. "Golf.ini"
	if not FILEMAN:DoesFileExist(path) then
		par_data[pack_dir] = false
		return false
	end

	par_data[pack_dir] = IniFile.ReadFile(path) or false
	return par_data[pack_dir]
end

-- -----------------------------------------------------------------------
-- Is this song in a pack that defines golf pars?
Golf.IsGolfPack = function(song)
	if not song then return false end

	local pack_dir = PackDir(song)
	if not pack_dir then return false end

	return LoadParData(pack_dir) ~= false
end

-- Which chart's par should we show for a song we aren't currently sitting on?
-- Golf songs are expected to carry a single chart, so the common case is trivial. When
-- there is more than one, prefer whatever difficulty the master player is currently on so
-- the wheel stays consistent with the difficulty they're browsing at.
Golf.ChooseSteps = function(song)
	if not song then return nil end

	local steps = SongUtil.GetPlayableSteps(song)
	if not steps or #steps == 0 then return nil end
	if #steps == 1 then return steps[1] end

	local current = GAMESTATE:GetCurrentSteps(GAMESTATE:GetMasterPlayerNumber())
	if current then
		local difficulty = current:GetDifficulty()
		for chart in ivalues(steps) do
			if chart:GetDifficulty() == difficulty then return chart end
		end
	end

	return steps[#steps]
end

-- Returns the par for a chart as a number, or nil if the pack has no Golf.ini or that
-- particular song/chart has no par defined in it.
-- `steps` is optional; when omitted we only bother resolving a chart once we already know
-- the pack has par data at all.
Golf.GetPar = function(song, steps)
	if not song then return nil end

	local pack_dir = PackDir(song)
	if not pack_dir then return nil end

	local data = LoadParData(pack_dir)
	if not data then return nil end

	local song_key = Basename(song:GetSongDir())
	if not song_key or song_key == "" then return nil end

	steps = steps or Golf.ChooseSteps(song)

	-- a per-chart entry wins over the song-wide one
	if steps then
		local section = data[song_key .. ":" .. ToEnumShortString(steps:GetDifficulty())]
		if section then
			local par = ToPar(section.Par)
			if par then return par end
		end
	end

	local section = data[song_key]
	if section then return ToPar(section.Par) end

	return nil
end

-- Drop the cached Golf.ini contents so edits made while the game is running -- including
-- adding a Golf.ini to a pack that had none -- get picked up on the next visit to
-- ScreenSelectMusic rather than needing a restart.
Golf.ClearCache = function()
	par_data = {}
end

-- -----------------------------------------------------------------------
-- Score formatting and hand-off between gameplay and evaluation.

-- Raw strokes are a per-note quantity (up to 200 for a miss/dropped hold/hit mine), so a
-- full chart runs into the thousands. Par is authored in the displayed unit -- "Par=3"
-- means 3.00, i.e. 3000 raw strokes -- so divide by this to get from one to the other.
Golf.STROKES_PER_POINT = 1000

Golf.FormatScore = function(strokes)
	return ("%.2f"):format((strokes or 0) / Golf.STROKES_PER_POINT)
end

-- Pars are whole numbers in practice; don't print a pointless ".00" for them.
Golf.FormatPar = function(par)
	if not par then return "-" end
	if par == math.floor(par) then return ("%d"):format(par) end
	return ("%.2f"):format(par)
end

Golf.IsUnderPar = function(strokes, par)
	if not par then return false end
	return ((strokes or 0) / Golf.STROKES_PER_POINT) <= par
end

-- Per-player results for the stage currently being played, written by
-- Modules/GolfScoring.lua and read by ScreenEvaluation. Keyed "P1"/"P2"; a player with no
-- entry wasn't playing a golf hole, and should get the theme's normal scoring UI.
Golf.Scores = {}

Golf.ClearScores = function()
	Golf.Scores = {}
end

-- Returns this player's golf result only if it actually belongs to the chart currently
-- loaded in GAMESTATE. Gameplay clears the table on entry, but only on the gameplay screens
-- the module hooks -- a golf chart played somewhere it doesn't hook (routine's
-- ScreenGameplayShared, say) would otherwise leave the previous stage's result sitting
-- there for ScreenEvaluation to render as if it were this one's.
Golf.GetScoreForCurrentChart = function(player)
	local result = Golf.Scores[ToEnumShortString(player)]
	if not result then return nil end

	local song = GAMESTATE:GetCurrentSong()
	if not song or result.songDir ~= song:GetSongDir() then return nil end

	local steps = GAMESTATE:GetCurrentSteps(player)
	if result.difficulty ~= (steps and steps:GetDifficulty()) then return nil end

	return result
end
