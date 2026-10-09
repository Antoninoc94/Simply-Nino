-- -----------------------------------------------------------------------
-- Extra keyboard hotkeys (Simply Nino).
--
-- Some actions have no free GameButton to map them to in ITGmania's own key
-- config (e.g. a 3-button cabinet already uses MenuLeft/Start/MenuRight), so
-- they're bound to raw keyboard keys instead -- typically sent by a Stream
-- Deck. The bindings live in Save/SimplyNinoHotkeys.ini, [Hotkeys] section,
-- one Action=Key per line. Keys are ITGmania device button names without the
-- "DeviceButton_" prefix: a lowercase letter/digit ("y", "7") or a named key
-- ("F9", "space", "home"). Leave a value empty to disable that hotkey.
--
-- The file is created with the defaults below if missing, and any action
-- added here later is appended to an existing file automatically. Edits are
-- picked up on the next game start (or Reload Scripts).
--
-- Loaded after SL_Init.lua (alphabetical order), so SL already exists here.

local path = "Save/SimplyNinoHotkeys.ini"

-- Action name -> default key. Add new hotkeys here.
local defaults = {
	-- Reopens Arrow Cloud's result-image dialog on the Evaluation screen
	-- after it has been closed (Modules/ArrowCloud.lua).
	ArrowCloudResultDialog = "y",
}

SL.Hotkeys = {
	Keys = {},

	Load = function()
		local contents = FILEMAN:DoesFileExist(path) and IniFile.ReadFile(path) or {}
		local section = contents["Hotkeys"] or {}
		local missing = false

		SL.Hotkeys.Keys = {}
		for action, default in pairs(defaults) do
			local key = section[action]
			if key == nil then
				key = default
				section[action] = default
				missing = true
			end
			key = tostring(key)
			-- Single characters are lowercase device buttons ("Y" -> "y").
			if #key == 1 then key = key:lower() end
			SL.Hotkeys.Keys[action] = key
		end

		if missing then
			contents["Hotkeys"] = section
			IniFile.WriteFile(path, contents)
		end
	end,

	-- True if this input event is the key bound to `action`.
	Matches = function(event, action)
		local key = SL.Hotkeys.Keys[action]
		if not key or key == "" then return false end
		return event and event.DeviceInput and event.DeviceInput.button == "DeviceButton_" .. key
	end,
}

SL.Hotkeys.Load()
