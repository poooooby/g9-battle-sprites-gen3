-- Run from the mod root: luajit tests/clean_state_test.lua
-- A pic is rendered into a canvas the first time it is asked for, possibly in the middle of
-- another screen's draw. The save editor draws its party rows inside a scissor and a
-- transform, and the sprite came out as a small clipped piece. The render must ignore the
-- caller's graphics state, and put it back afterwards.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a graphics fake that tracks the state a real draw would be affected by
local state = { scissor = nil, identity = true, canvas = "screen" }
local stack, draws = {}, {}
local function image() return { getDimensions = function() return 4096, 4096 end, setFilter = function() end } end
love = { graphics = {
  newImage = function() return image() end,
  newQuad = function() return {} end,
  newCanvas = function(w, h)
    return { getDimensions = function() return w, h end, setFilter = function() end, release = function() end }
  end,
  getCanvas = function() return state.canvas end,
  setCanvas = function(c) state.canvas = c or "screen" end,
  setScissor = function(x, y, w, h) state.scissor = x and { x, y, w, h } or nil end,
  getScissor = function() return state.scissor and unpack(state.scissor) end,
  origin = function() state.identity = true end,
  setShader = function() end, setBlendMode = function() end, setColor = function() end,
  clear = function() end,
  push = function(what)
    stack[#stack + 1] = { scissor = state.scissor, identity = state.identity, canvas = state.canvas }
  end,
  pop = function()
    local s = table.remove(stack)
    state.scissor, state.identity, state.canvas = s.scissor, s.identity, s.canvas
  end,
  draw = function()
    draws[#draws + 1] = { scissor = state.scissor, identity = state.identity, canvas = state.canvas }
  end,
}, timer = { getTime = function() return 0 end } }

local Atlas = dofile("src/atlas.lua")
local index = { species = { THING = { dex = 387, slot = 451,
  front = { sheet = 0, start = 0, fs = 100, cols = 10, frames = 1, ox = 0, oy = 0 } } } }
local atlas = Atlas.new({ path = "x", log = { warn = function() end } },
  function(path) return path == "data/atlas_index.lua" and index or nil end)
check(atlas ~= nil, "the atlas builds from the index")

-- the screen is mid-draw: a scissor on a row, a transform in effect
state.scissor, state.identity = { 10, 10, 5, 5 }, false
local canvas = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false)
check(canvas ~= nil, "a pic is rendered")
check(#draws > 0, "something was drawn into it")
for i, d in ipairs(draws) do
  check(d.scissor == nil, "draw " .. i .. " ran with no scissor")
  check(d.identity, "draw " .. i .. " ran with no transform")
  check(d.canvas ~= "screen", "draw " .. i .. " went to a canvas, not the screen")
end
check(state.scissor and state.scissor[1] == 10 and state.scissor[3] == 5, "the caller's scissor is back")
check(state.identity == false, "and its transform")
check(state.canvas == "screen", "and its render target")
check(#stack == 0, "the graphics stack is balanced")

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 clean state)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
