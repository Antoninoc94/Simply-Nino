local Players = GAMESTATE:GetHumanPlayers()
local NumPanes = SL.Global.GameMode=="Casual" and 1 or 10

local InputHandler = nil
local EventOverlayInputHandler = nil
-- Whether Arrow Cloud's result-image dialog (Modules/ArrowCloud.lua) currently has input
-- priority. See DirectInputToACResultDialogCommand/DirectInputFromACResultDialogCommand and the
-- guard in DirectInputToEventOverlayHandlerCommand below. This hook is optional -- Arrow Cloud's
-- own dialog dismisses correctly without it (see the module-only fallback in
-- Modules/ArrowCloud.lua), but when present it also stops MenuLeft/MenuRight from silently
-- cycling this screen's panes behind the dialog while it's open.
local arrowCloudDialogOpen = false

SL.Global.IsGameplay = false
UnzipQueue()

if ThemePrefs.Get("WriteCustomScores") then
	WriteScores()
end

local t = Def.ActorFrame{Name="ScreenEval Common"}

if SL.Global.GameMode ~= "Casual" then
	-- add a lua-based InputCalllback to this screen so that we can navigate
	-- through multiple panes of information; pass a reference to this ActorFrame
	-- and the number of panes there are to InputHandler.lua
	t.OnCommand=function(self)
		InputHandler = LoadActor("./InputHandler.lua", {self, NumPanes})
		EventOverlayInputHandler = LoadActor("./Shared/EventInputHandler.lua")
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		PROFILEMAN:SaveMachineProfile()
	end
	t.DirectInputToEngineCommand=function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(EventOverlayInputHandler)
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)

		for player in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(player, false)
		end
	end
	t.DirectInputToEventOverlayHandlerCommand=function(self)
		-- Don't let GrooveStats/ITL/SRPG's event overlay steal the input slot while Arrow
		-- Cloud's result-image dialog has it -- see DirectInputToACResultDialogCommand below.
		-- Its own hardcoded Start/Back handling (Shared/EventInputHandler.lua) unconditionally
		-- hides EventOverlay and un-redirects both players regardless of what's actually open,
		-- which would let a press meant to dismiss Arrow Cloud's dialog also fall through and
		-- advance past this screen (Arrow Cloud's own module-only fallback guards against this
		-- too, but there's no reason to let it happen here when we can prevent it outright).
		if arrowCloudDialogOpen then return end

		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
		SCREENMAN:GetTopScreen():AddInputCallback(EventOverlayInputHandler)

		for player in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(player, true)
		end
	end
	-- Arrow Cloud's post-submission result-image dialog (Modules/ArrowCloud.lua) needs the same
	-- "stop the pane-cycling InputHandler from also reacting" treatment ITL/SRPG's EventOverlay
	-- gets above, but can't reuse DirectInputToEventOverlayHandler: EventOverlayInputHandler
	-- (Shared/EventInputHandler.lua) unconditionally hides EventOverlay and calls
	-- DirectInputToEngine on any Start/Back press, which would rip Arrow Cloud's own dialog
	-- state out from under it. InputHandler is local to this file, so it can only be removed
	-- from here -- Arrow Cloud calls these two commands opportunistically (if this actor
	-- exists) as a theme-specific enhancement on top of its own module-only input handling,
	-- not a requirement for it.
	t.DirectInputToACResultDialogCommand=function(self)
		arrowCloudDialogOpen = true
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
		-- In case GrooveStats/ITL/SRPG's event overlay got there first (it can activate any
		-- time up to ~10+ seconds after screen entry, well after Arrow Cloud's own near-instant
		-- dialog might already be up) -- see the guard above for the reverse ordering.
		SCREENMAN:GetTopScreen():RemoveInputCallback(EventOverlayInputHandler)
		for player in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(player, true)
		end
	end
	t.DirectInputFromACResultDialogCommand=function(self)
		arrowCloudDialogOpen = false
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		for player in ivalues(PlayerNumber) do
			SCREENMAN:set_input_redirected(player, false)
		end
	end
else
	t.OnCommand=function(self)
		PROFILEMAN:SaveMachineProfile()
	end
end

-- -----------------------------------------------------------------------
-- First, add actors that would be the same whether 1 or 2 players are joined.

-- code for triggering a screenshot and animating a "screenshot" texture
t[#t+1] = LoadActor("./Shared/ScreenshotHandler.lua")

-- code for non-normal exits, such as restarting the song or entering practice mode
t[#t+1] = LoadActor("./Shared/ExitHandler.lua")

-- the title of the song and its graphical banner, if there is one
t[#t+1] = LoadActor("./Shared/TitleAndBanner.lua")

-- text to display BPM range (and ratemod if ~= 1.0) and song length immediately
-- under the banner
t[#t+1] = LoadActor("./Shared/SongFeatures.lua")

-- store some attributes of this playthrough of this song in the global SL table
-- for later retrieval on ScreenEvaluationSummary
t[#t+1] = LoadActor("./Shared/GlobalStorage.lua")

-- help text that appears if we're in Casual gamemode
t[#t+1] = LoadActor("./Shared/CasualHelpText.lua")

-- -----------------------------------------------------------------------
-- Then, load player-specific actors.

for player in ivalues(Players) do

	-- store player stats for later retrieval on EvaluationSummary and NameEntryTraditional
	-- this doesn't draw anything to the screen, it just runs some code
	t[#t+1] = LoadActor("./PerPlayer/Storage.lua", player)

	-- the per-player upper half of ScreenEvaluation, including: letter grade, nice
	-- stepartist, difficulty text, difficulty meter, machine/personal HighScore text
	t[#t+1] = LoadActor("./PerPlayer/Upper/default.lua", player)

	-- the per-player lower half of ScreenEvaluation, including:
	-- judgment scatterplot, modifier list, disqualified text
	t[#t+1] = LoadActor("./PerPlayer/Lower/default.lua", player)

	-- Save Ghost Data if player has improved their score
	t[#t+1] = LoadActor("./PerPlayer/SaveGhostData.lua", player)

	-- Generate the .itl file for the player.
	-- When the event isn't active, this actor is nil.
	t[#t+1] = LoadActor("./PerPlayer/ItlFile.lua", player)

	-- Generate the .rpg file for the player to keep track of best rate mod on the songwheel
	-- When the event isn't active, this actor is nil.
	t[#t+1] = LoadActor("./PerPlayer/RpgRatemod.lua", player)
	
	
end

-- -----------------------------------------------------------------------
-- Then load the Panes.

t[#t+1] = LoadActor("./Panes/default.lua", NumPanes)

-- -----------------------------------------------------------------------

-- The actor that will automatically upload scores to GrooveStats.
-- This is only added in "dance" mode and if the service is available.
-- Since this actor also spawns the event overlay it must go on top of everything else
t[#t+1] = LoadActor("./Shared/AutoSubmitScore.lua")

return t
