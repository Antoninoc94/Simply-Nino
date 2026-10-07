-- The golf scorecard for charts that were played as golf holes: a par box and a stroke
-- total, both styled like this screen's difficulty block and gameplay's own par box, laid
-- out as a row running inboard from it.
--
-- The letter grade keeps its slot. There's no room to stack anything under it -- the grade
-- runs from _screen.cy-160 to _screen.cy-112 and StreamInfo's breakdown starts at
-- _screen.cy-117 -- so the golf numbers live in the 40px band the difficulty block sits in,
-- between StreamInfo above and StepArtist below.
--
-- Only loaded when there's a golf result for this player from the chart that was just
-- played. Modules/GolfScoring.lua writes it; see Scripts/SL-GolfHelpers.lua.

local player = ...
local pn = ToEnumShortString(player)

local golf = Golf.GetScoreForCurrentChart(player)
local under = Golf.IsUnderPar(golf.strokes, golf.par)

-- Everything here is positioned within this player's Upper ActorFrame, which Upper/default.lua
-- has already placed at _screen.cx-155 for P1 and _screen.cx+155 for P2. That means these
-- offsets only ever need to describe one side and mirror it, and a single player joined on
-- either side lands correctly without any extra handling.
local side = (player == PLAYER_1) and -1 or 1

-- Distances below are measured inboard from the frame origin, then mirrored by `side`, so
-- "outer" is the edge nearer the screen edge and "inner" the edge nearer screen centre.
--
-- Difficulty.lua centres its 40x40 block on 129.5, so its inner edge is at 109.5, and the
-- row grows inboard from there. It has to stop before the frame origin: the banner's left
-- edge sits only a few px past it, and going outboard instead isn't an option because
-- 129.5 is already near the left edge of a 4:3 screen.
local ROW_Y       = _screen.cy - 76
local BOX_H       = 40
local GAP         = 4
local INNER_LIMIT = 2

local par_outer     = 129.5 - (40/2) - GAP
local PAR_W         = 40
local par_inner     = par_outer - PAR_W

local strokes_outer = par_inner - GAP
local STROKES_W     = strokes_outer - INNER_LIMIT

-- One box of the row: a solid colored block with a value and a caption, the same shape
-- Difficulty.lua and gameplay's par display both use.
--
-- Both strings are measured and scaled to fit rather than clamped with maxwidth, so a
-- stroke total that runs to four or five digits ("12.34", "123.45", and up to "200.00" for
-- a chart missed end to end) shrinks evenly instead of being squashed horizontally.
local function Box(outer_edge, width, fill, value, caption)
	local function Fit(self, max_zoom, y)
		local w = self:GetWidth()
		self:diffuse(Color.Black)
		self:zoom(w > 0 and math.min(max_zoom, (width - 6) / w) or max_zoom)
		self:y(y)
	end

	return Def.ActorFrame{
		InitCommand=function(self) self:xy((outer_edge - width/2) * side, ROW_Y) end,

		Def.Quad{
			InitCommand=function(self)
				self:zoomto(width, BOX_H)
				self:diffuse(fill)
			end,
		},

		LoadFont(ThemePrefs.Get("ThemeFont") .. " Bold")..{
			Text=value,
			InitCommand=function(self) Fit(self, 0.55, -6) end,
		},

		LoadFont(ThemePrefs.Get("ThemeFont") .. " Normal")..{
			Text=caption,
			InitCommand=function(self) Fit(self, 0.5, 13) end,
		},
	}
end

return Def.ActorFrame{
	Name=pn.."_GolfScore",

	Box(par_outer, PAR_W, color("#33CC33"), Golf.FormatPar(golf.par), "Par"),

	-- green under par, red over: the one thing a player wants to read at a glance
	Box(strokes_outer, STROKES_W, under and color("#33CC33") or color("#E06666"),
		Golf.FormatScore(golf.strokes), "Strokes"),
}
