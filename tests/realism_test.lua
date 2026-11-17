-- Run from the mod root: luajit tests/realism_test.lua
-- Realism scaling (gen3-hd-sprites only): each Pokemon's size from its real height on a
-- rubber-band curve, the enemy's front a little smaller for perspective, and every size change
-- made about the FEET, so a Pokemon stays standing on its pad.
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
}, timer = { getTime = function() return NOW or 0 end } }

local Atlas = dofile("src/atlas.lua")
local function near(a, b, e) return math.abs(a - b) < (e or 1e-6) end

-- the curve
local R = Atlas.realism
check(near(R(16.5), 1), "the neutral height (1.65 m) keeps its size")
check(near(R(200), 1.25), "the tallest (20 m) grows 25% (" .. R(200) .. ")")
check(near(R(1), 0.85), "the shortest (0.1 m) shrinks 15% (" .. R(1) .. ")")
check(near(R(2000), 1.25) and near(R(0.5), 0.85), "past the limits it holds the limit")
check(near(R(4), 0.946, 0.002), "Pikachu (0.4 m) about 95% (" .. R(4) .. ")")
check(near(R(145), 1.203, 0.002), "Wailord (14.5 m) about 120% (" .. R(145) .. ")")
local prev = 0
local mono = true
for dm = 1, 200 do
  local v = R(dm)
  if v < prev - 1e-12 then mono = false end
  prev = v
end
check(mono, "taller is never smaller")
check(R(nil) == 1 and R(0) == 1, "no height: no change")
check(R(200, { on = false }) == 1, "off: no change")
check(near(R(200, { grow = 0.1 }), 1.1), "the settings are read")
check(near(R(1, { shrink = 0.3 }), 0.7), "the shrink is read")

-- the HD tags: sizes and feet
local index = { species = {
  -- a 1.65 m Pokemon: realism 1, so only the front's perspective shows
  MID = { dex = 400, slot = 464, ht = 16.5,
    front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, ffr = 90 },
    back = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, cx0 = 20, cy0 = 10,
             cx1 = 70, cy1 = 80, ux0 = 18, uy0 = 4, ux1 = 74, uy1 = 82, bfr = 80, bfl = 67 } },
  -- a 20 m Pokemon: realism 1.25
  -- a 1.65 m Pokemon whose back art is drawn smaller than its front: bn 1.2
  NORM = { dex = 402, slot = 466, ht = 16.5,
    back = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, cx0 = 20, cy0 = 10,
             cx1 = 70, cy1 = 80, ux0 = 18, uy0 = 4, ux1 = 74, uy1 = 82, bfr = 80, bfl = 67, bn = 1.2 } },
  BIG = { dex = 401, slot = 465, ht = 200,
    front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, ffr = 90 },
    back = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, cx0 = 20, cy0 = 10,
             cx1 = 70, cy1 = 80, ux0 = 18, uy0 = 4, ux1 = 74, uy1 = 82, bfr = 80, bfl = 67 } },
} }
local function newAtlas(tuning)
  return Atlas.new({ path = "x", log = { warn = function() end } }, function(path)
    if path == "data/atlas_index.lua" then return index end
    if path == "data/sprite_scale.lua" then return tuning end
    return nil
  end)
end
local function fakeHd()
  local hd = { tags = {} }
  function hd.enabled() return true end
  function hd.tag(image, spec) hd.tags[image] = spec end
  return hd
end
-- where a spec puts a source point (pivot space) on screen, relative to the low pivot
local function feet(spec)
  return spec.lowPivot[1], spec.lowPivot[2]
end

do
  local atlas = newAtlas(nil)
  local hd = fakeHd(); atlas.hd = hd
  local mid = hd.tags[atlas.picFrame(464, "front", atlas.cell(464, "front"), 0, true)]
  check(mid and near(mid.scale, 0.9), "a 1.65 m front: only the perspective, 90% (" .. tostring(mid and mid.scale) .. ")")
  check(mid and mid.pivot[2] == 90, "the front scales about its feet row (ffr)")
  local big = hd.tags[atlas.picFrame(465, "front", atlas.cell(465, "front"), 0, true)]
  check(big and near(big.scale, 1.25 * 0.9), "a 20 m front: 125% x 90% (" .. tostring(big and big.scale) .. ")")
  local mx, my = feet(mid)
  local bx, by = feet(big)
  check(near(mx, bx) and near(my, by), "both stand on the same spot whatever their size")
  local mb = hd.tags[atlas.picFrame(464, "back", atlas.cell(464, "back"), 0, true)]
  check(mb and near(mb.scale, 1), "a 1.65 m back: its own size, no perspective")
  check(mb and mb.pivot[2] == 80 and near(mb.pivot[1], 45), "the back scales about its feet (bfr, body centre)")
  local bb = hd.tags[atlas.picFrame(465, "back", atlas.cell(465, "back"), 0, true)]
  check(bb and near(bb.scale, 1.25), "a 20 m back: 125% (" .. tostring(bb and bb.scale) .. ")")
  local x1, y1 = feet(mb)
  local x2, y2 = feet(bb)
  check(near(x1, x2) and near(y1, y2) and near(y1, 67), "backs keep their feet on the line (y " .. y1 .. ")")
  check(bb and bb.top == 4, "Battle Fit gets a back's first row of art too")
  local nb = hd.tags[atlas.picFrame(466, "back", atlas.cell(466, "back"), 0, true)]
  check(nb and near(nb.scale, 1.2), "a back is brought to its front's size (bn)")
  local x3, y3 = feet(nb)
  check(near(y3, 67), "...and still stands on the feet line")
end

do
  local atlas = newAtlas({ realism = { on = false } })
  local hd = fakeHd(); atlas.hd = hd
  local big = hd.tags[atlas.picFrame(465, "front", atlas.cell(465, "front"), 0, true)]
  check(big and near(big.scale, 1), "realism off: the front at its own size, no perspective")
  local bb = hd.tags[atlas.picFrame(465, "back", atlas.cell(465, "back"), 0, true)]
  check(bb and near(bb.scale, 1), "realism off: the back at its own size")
  local nb = hd.tags[atlas.picFrame(466, "back", atlas.cell(466, "back"), 0, true)]
  check(nb and near(nb.scale, 1), "realism off: no back matching either")
end

do
  local atlas = newAtlas({ BIG = { front = 0.5 } })
  local hd = fakeHd(); atlas.hd = hd
  local big = hd.tags[atlas.picFrame(465, "front", atlas.cell(465, "front"), 0, true)]
  check(big and near(big.scale, 0.5 * 1.25 * 0.9), "a hand-set size multiplies the realism")
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 realism)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
