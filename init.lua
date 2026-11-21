-- autoplay: a toggle left of the play button. while it's on, the game's own judgement gives every note a perfect, with
-- its hit sounds, effects and combo, and the play counts for nothing: nothing is saved, recorded or sent

local UE = CS.UnityEngine
local ui = phigrospp.ui
local BOT = [[<path d="M12 8V4H8" /><rect width="16" height="12" x="4" y="8" rx="2" /><path d="M2 14h2" />
  <path d="M20 14h2" /><path d="M15 13v2" /><path d="M9 13v2" />]] -- lucide's bot

local armed = false -- the toggle, off again at each launch
local selector, button
local hooks, manager, pending, holding
local autoplayed, result -- the song ended autoplayed, and its result screen

-- on, the button's colours swap
local colours
local function paint()
  local shape = button:GetComponent(CS.Lean.Gui.LeanPolygon)
  local icon = phigrospp.find(button.transform, "phigrospp-icon"):GetComponent(UE.UI.Image)
  colours = colours or { shape.color, icon.color }
  shape.color, icon.color = colours[armed and 2 or 1], colours[armed and 1 or 2]
end

-- the notes on the field not touched yet: they're made a few seconds before their time
local FIELDS = { "clickControls", "dragControls", "holdControls", "flickControls" } -- by a note's type
local KINDS = { "click", "drag", "hold", "flick" }

local function keep(note, control)
  pending[#pending + 1] = { kind = KINDS[note.type], note = note, control = control, time = note.realTime }
end

-- the note just made is the last of its kind on NoteUpdateManager
local function made(line, index, above)
  local note = (above and line.notesAbove or line.notesBelow)._items[index]
  local list = manager[FIELDS[note.type]]
  keep(note, list._items[list._size - 1])
end

-- a note is touched in the frame closest to its time, before NoteUpdateManager judges it like a finger was there.
-- drags and flicks only need to be touched before their time, a hold's finger stays until the hold is over
local function touch()
  local now, lead = manager.progressControl.nowTime, UE.Time.deltaTime / 2
  for i = #pending, 1, -1 do
    local n = pending[i]
    if n.time - now <= lead then
      if n.kind == "drag" then n.control.isJudged = true
      elseif n.kind == "flick" then n.note.isJudgedForFlick = true
      else n.note.isJudged = true end
      if n.kind == "hold" then holding[n.control] = true end
      pending[i] = pending[#pending]
      pending[#pending] = nil
    end
  end
  for hold in pairs(holding) do
    if il2cpp.alive(hold) then hold._safeFrame = 3 else holding[hold] = nil end
  end
end

local function stop()
  for _, id in ipairs(hooks or {}) do unhook(id) end
  hooks = nil
end

local function skip() return true end

on("song", function()
  autoplayed = false
  local level = UE.Object.FindObjectOfType(CS.LevelControl)
  if not armed or level.progressControl._inChallengeMode or not phigrospp.counts() then return end
  phigrospp.counts(false)
  manager, pending, holding = level.judgeControl.noteUpdateManager, {}, {}
  for _, field in ipairs(FIELDS) do
    local list = manager[field]
    for i = 0, list._size - 1 do keep(list._items[i].noteInfor, list._items[i]) end
  end
  -- real touches judge nothing, JudgeControl still checks them for the pause button
  hooks = {
    hook(CS.JudgeLineControl, "CreateNote", { after = made }),
    hook(CS.NoteUpdateManager, "Update", { before = touch }),
    hook(CS.JudgeControl, "CheckNote", { skip = skip }),
    hook(CS.JudgeControl, "CheckFlick", { skip = skip }),
  }
  print(("autoplay: %s %s"):format(playing().id, playing().difficulty))
end)

on("finish", function() autoplayed = hooks ~= nil end)
on("leave", stop)

on("scene", function(name)
  selector, button, colours = nil, nil, nil
  if name == "SongSelector" then selector = UE.Object.FindObjectOfType(CS.SongSelector) end
  result = name == "LevelOver" and autoplayed and UE.Object.FindObjectOfType(CS.LevelOverControl) or nil
end)

on("update", function()
  if result then
    -- every frame, the result screen's animation sets the grade's rotation too
    local ratings = result.ratings
    for i = 0, #ratings - 1 do ratings[i].transform.localEulerAngles = { 0, 0, 180 } end
    return
  end
  if not selector or selector.SongItems._size == 0 then return end -- the list fills in after the scene starts
  if not button then
    button = ui.sideButton(selector.startButton, 2, ui.icon(BOT), function()
      armed = not armed
      paint()
    end)
    paint()
  end
  local playable = not selector.locked.activeSelf
  if button.activeSelf ~= playable then button:SetActive(playable) end
end)
