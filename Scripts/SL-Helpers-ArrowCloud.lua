-- -----------------------------------------------------------------------
-- Sets the ArrowCloud API key for a player if it's found in their profile.
-- Reads the same ArrowCloud.ini file (and [ArrowCloud] section) that the
-- QR device-login flow in Modules/ArrowCloud.lua reads from and writes to,
-- so a key saved via QR login is immediately available here too.

ParseArrowCloudIni = function(player)
	if not player then return end

	local profile_slot = {
		[PLAYER_1] = "ProfileSlot_Player1",
		[PLAYER_2] = "ProfileSlot_Player2"
	}

	if not profile_slot[player] then return end

	local dir = PROFILEMAN:GetProfileDir(profile_slot[player])
	local pn = ToEnumShortString(player)
	if not dir or #dir == 0 then return end

	local path = dir .. "ArrowCloud.ini"

	if not FILEMAN:DoesFileExist(path) then
		IniFile.WriteFile(path, {
			["ArrowCloud"] = {
				["ApiKey"] = "",
				["AllowAutoplay"] = "0",
			}
		})
		SL[pn].ArrowCloudApiKey = ""
		return
	end

	local contents = IniFile.ReadFile(path)
	if contents["ArrowCloud"] and contents["ArrowCloud"]["ApiKey"] then
		SL[pn].ArrowCloudApiKey = contents["ArrowCloud"]["ApiKey"]
	else
		SL[pn].ArrowCloudApiKey = ""
	end
end
