-- Run from the mod root: luajit tests/clean_state_test.lua
-- A pic is rendered into a canvas the first time it is asked for, possibly in the middle of
-- another screen's draw. The save editor draws its party rows inside a scissor and a
-- transform, and the sprite came out as a small clipped piece. The render must ignore the
-- caller's graphics state, and put it back afterwards.
--
-- The scissor must also come back at the caller's own scale. LOVE's pop() puts the scissor back
-- BEFORE the canvas, converting it to pixels at the DPI scale of the canvas still bound (ours, 4):
-- a pic rendered in the middle of Crystal's battle panel left the rest of the panel clipped to a
-- rectangle four times too far right, and the battle flashed to its scenery. The fake below
-- restores in LOVE's order and keeps the pixel rectangle the GPU would clip to.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a graphics fake that tracks the state a real draw would be affected by
local state = { scissor = nil, identity = true, canvas = "screen", pixels = nil }
local stack, draws = {}, {}
local function dpiOf(c) return type(c) == "table" and c.dpi or 1 end
-- (the pixel rectangle: the scissor in units times the bound target's DPI scale, as LOVE converts it)
local function setScissor(x, y, w, h)
  state.scissor = x and { x, y, w, h } or nil
  local k = dpiOf(state.canvas)
  state.pixels = x and { x * k, y * k, w * k, h * k } or nil
end
local function image() return { getDimensions = function() return 4096, 4096 end, setFilter = function() end } end
love = { graphics = {
  newImage = function() return image() end,
  newQuad = function() return {} end,
  newCanvas = function(w, h, opts)
    return { dpi = opts and opts.dpiscale or 1, getDimensions = function() return w, h end,
      setFilter = function() end, release = function() end }
  end,
  getCanvas = function() return state.canvas end,
  -- (setting a canvas does not convert the scissor again)
  setCanvas = function(c) state.canvas = c or "screen" end,
  setScissor = setScissor,
  getScissor = function() if state.scissor then return unpack(state.scissor) end end,
  origin = function() state.identity = true end,
  setShader = function() end, setBlendMode = function() end, setColor = function() end,
  clear = function() end,
  push = function(what)
    stack[#stack + 1] = { scissor = state.scissor, identity = state.identity, canvas = state.canvas }
  end,
  -- LOVE's order: the scissor first (with the canvas still bound), then the canvas
  pop = function()
    local s = table.remove(stack)
    state.identity = s.identity
    if s.scissor then setScissor(unpack(s.scissor)) else setScissor() end
    state.canvas = s.canvas
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
setScissor(10, 10, 5, 5)
state.identity = false
local canvas = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false)
check(canvas ~= nil, "a pic is rendered")
check(dpiOf(canvas) > 1, "into a canvas finer than the screen (the case LOVE's pop gets wrong)")
check(#draws > 0, "something was drawn into it")
for i, d in ipairs(draws) do
  check(d.scissor == nil, "draw " .. i .. " ran with no scissor")
  check(d.identity, "draw " .. i .. " ran with no transform")
  check(d.canvas ~= "screen", "draw " .. i .. " went to a canvas, not the screen")
end
check(state.scissor and state.scissor[1] == 10 and state.scissor[3] == 5, "the caller's scissor is back")
check(state.pixels and state.pixels[1] == 10 and state.pixels[3] == 5,
  "at the screen's own scale (" .. table.concat(state.pixels or {}, ",") .. ")")
check(state.identity == false, "and its transform")
check(state.canvas == "screen", "and its render target")
check(#stack == 0, "the graphics stack is balanced")

-- with no scissor in effect none is left behind
setScissor()
draws = {}
atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, true)
check(state.scissor == nil and state.pixels == nil, "no scissor before, none after")

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 clean state)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
