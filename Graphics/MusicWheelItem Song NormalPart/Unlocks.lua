local player = ...
local pn = ToEnumShortString(player)

local af = Def.ActorFrame {
	-- Resetting player state on a guest (re)join is handled once, centrally, by
	-- LoadGuest() in Scripts/SL-PlayerProfiles.lua (see ScreenSelectMusic overlay/default.lua),
	-- which preserves SL[pn].Stages across the reset. Duplicating that reset here (once per
	-- music wheel item!) without preserving Stages wiped out the session's score history/timer
	-- whenever a player left and rejoined mid-session.
	PlayerJoinedMessageCommand=function(self, params)
		if pn == nil then
			player = params.Player
			pn = ToEnumShortString(player)
		end
	end,
    Def.Sprite{
        InitCommand=function(self)
            self:animate(false):visible(false)
            if player == PLAYER_1 then
                self:diffuse(Color.Yellow)
            else
                self:diffuse(Color.Orange)
            end
            if #GAMESTATE:GetHumanPlayers() > 1 then
                self:x(-12)
            else
                self:x(-15)
            end
            self:Load( THEME:GetPathG("", "lock.png") )
        end,
        SetCommand=function(self, params)
            -- Don't display anything if the player isn't even enabled.
            if not GAMESTATE:IsPlayerEnabled(player) then
                self:visible(false)
                return
            end

            if params.Song then
                local song = params.Song
                local song_dir = song:GetSongDir()
                -- Only take the <song> parth of /Songs/<pack>/<song>/
                local song_folder = song_dir:gsub("[/\\]+$", ""):match("([^/\\]+)$") or song_dir

                local year = 2026
                if string.find(string.lower(song_dir), "itl online "..year.." unlocks") then
                    local unlockData = SL[pn].ITLData["unlockFolders"] or {}
                    local songUnlocked = (unlockData[song_folder]==true)
                    self:visible(not songUnlocked)
                else
                    self:visible(false)
                end

                if #GAMESTATE:GetHumanPlayers() > 1 then
                    self:zoomto(15,15)
                    self:y(pn == "P1" and -8 or 8)
                else
                    self:zoomto(20,20):y(0)
                end
            end
        end,
    }
}

return af
