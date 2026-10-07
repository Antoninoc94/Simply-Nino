-- per-player upper half of ScreenEvaluation

local player = ...

-- Charts played as golf holes get a par/strokes scorecard alongside everything else. Nil
-- for every other chart, including one in a golf pack that simply has no par defined.
local golf = Golf and Golf.GetScoreForCurrentChart and Golf.GetScoreForCurrentChart(player)

local t = Def.ActorFrame{
	Name=ToEnumShortString(player).."_AF_Upper",
	OnCommand=function(self)
		if player == PLAYER_1 then
			self:x(_screen.cx - 155)
		elseif player == PLAYER_2 then
			self:x(_screen.cx + 155)
		end
	end,
}

-- Several of these files return nothing under the right conditions (StreamInfo on a chart
-- without enough stream, ItlFile when the event is off), so append rather than listing them
-- in the constructor above, where a nil would sit in the middle of the child list.
local function add(actor)
	if actor then t[#t+1] = actor end
end

-- letter grade
add(LoadActor("./LetterGrade.lua", player))

-- nice
add(LoadActor("./nice.lua", player))

-- stream info
add(LoadActor("./StreamInfo.lua", player))

-- stepartist. Golf holes drop it: the credit/description is bottom-anchored at
-- _screen.cy-42 and grows upward into the band the par/strokes boxes occupy, so the two
-- can't share the space.
if not golf then
	add(LoadActor("./StepArtist.lua", player))
end

-- difficulty text and meter
add(LoadActor("./Difficulty.lua", player))

-- Record Texts (Machine and/or Personal)
add(LoadActor("./RecordTexts.lua", player))

-- Event Progress Box
add(LoadActor("./EventProgress.lua", player))

-- par and stroke total, for charts played as golf holes
if golf then
	add(LoadActor("./GolfScore.lua", player))
end

return t
