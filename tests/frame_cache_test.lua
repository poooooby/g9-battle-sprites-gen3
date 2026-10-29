-- Run from the mod root: luajit tests/frame_cache_test.lua
-- The rendered pic frames are kept up to CANVAS_CAP, the least recently used dropped first. A
-- battle pic's dropped canvas is rendered into again for a frame of its shape: an animation
-- longer than the cap (four battlers' in a double battle or a raid) must not make a new canvas
-- for every frame it plays, which left hundreds for the garbage collector to destroy at once.
-- A frame still being asked for is never the one dropped; any other pic is dropped, not reused,
-- so whoever still holds it (the save editor) keeps its picture.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local made, target = 0, nil
local drawsInto = {}           -- canvas -> how many times something was drawn into it
local function image() return { getDimensions = function() return 4096, 4096 end, setFilter = function() end } end
love = { graphics = {
  newImage = function() return image() end,
  newQuad = function() return {} end,
  newCanvas = function(w, h)
    made = made + 1
    return { getDimensions = function() return w, h end, setFilter = function() end, release = function() end }
  end,
  getCanvas = function() return target end,
  setCanvas = function(c) target = c end,
  setScissor = function() end, origin = function() end,
  setShader = function() end, setBlendMode = function() end, setColor = function() end,
  clear = function() end, push = function() end, pop = function() end,
  draw = function() if target then drawsInto[target] = (drawsInto[target] or 0) + 1 end end,
}, timer = { getTime = function() return 0 end } }

local Atlas = dofile("src/atlas.lua")
local FRAMES = 200
local back = { sheet = 0, start = 0, fs = 40, cols = 100, frames = FRAMES, ox = 0, oy = 0,
  cx0 = 3, cy0 = 7, cx1 = 35, cy1 = 37, ux0 = 2, uy0 = 0, ux1 = 35, uy1 = 38, bfr = 37, bfl = 51, bn = 1 }
local front = { sheet = 0, start = 0, fs = 40, cols = 100, frames = FRAMES, ox = 0, oy = 0, uy0 = 0, ffr = 38 }
local index = { species = { THING = { dex = 387, slot = 451, back = back, front = front } } }
local atlas = Atlas.new({ path = "x", log = { warn = function() end } },
  function(path) return path == "data/atlas_index.lua" and index or nil end)
check(atlas ~= nil, "the atlas builds from the index")

-- a back animation of 200 frames played twice through, frame 0 asked for between every frame
-- (a second battler holding its resting frame)
local cell = atlas.cell(451, "back")
local held = atlas.picFrame(451, "back", cell, 0, true)
local heldDraws = drawsInto[held]
local first = {}
for pass = 1, 2 do
  for f = 1, FRAMES - 1 do
    local c = atlas.picFrame(451, "back", cell, f, true)
    check(c ~= nil, ("back frame %d rendered (pass %d)"):format(f, pass))
    if pass == 1 and f == 1 then first.c = c end
    check(atlas.picFrame(451, "back", cell, 0, true) == held, "the held frame stays cached")
  end
end
check(made <= 130, ("a back animation longer than the cap reuses its canvases (%d made for %d frames x 2)"):format(made, FRAMES))
check(drawsInto[held] == heldDraws, "the held frame was never drawn into again")
check((drawsInto[first.c] or 0) > 1, "a dropped back canvas was rendered into again")

-- a plain (summary / editor) front pic is dropped, never rendered into again
local fcell = atlas.cell(451, "front")
local plain = atlas.picFrame(451, "front", fcell, 0, false)
local plainDraws = drawsInto[plain]
local before = made
for f = 1, FRAMES - 1 do atlas.picFrame(451, "front", fcell, f, false) end
check(made - before >= FRAMES - 1, "plain pics are made new, not reused")
check(drawsInto[plain] == plainDraws, "a dropped plain pic is never drawn into again (its holder keeps it)")

print(("%d/%d checks passed (g9-battle-sprites-gen3 frame cache)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
