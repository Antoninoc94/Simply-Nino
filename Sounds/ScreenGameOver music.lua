local audio_file = "fold.ogg"

local style = ThemePrefs.Get("VisualStyle")
if style == "SRPG9" then
	audio_file = "SRPG9-GameOver.ogg"
elseif style == "Transistor" then
	audio_file = "paper boats.ogg"
end

return THEME:GetPathS("", audio_file)
