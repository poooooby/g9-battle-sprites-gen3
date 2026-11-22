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
  translate = function() state.identity = false end, scale = function() state.identity = false end,
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
  -- a 1 m Pokemon that leaps on its front only: its front's art reaches 90 px over the feet,
  -- resting 40; its back's 76, resting 70
  LEAP = { dex = 403, slot = 467, ht = 10,
    front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, ffr = 90,
              cx0 = 20, cy0 = 50, cx1 = 70, cy1 = 90, ux0 = 18, uy0 = 0, ux1 = 74, uy1 = 90 },
    back = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0, cx0 = 20, cy0 = 10,
             cx1 = 70, cy1 = 80, ux0 = 18, uy0 = 4, ux1 = 74, uy1 = 82, bfr = 80, bfl = 67 } },
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

-- a long Pokemon (its Pokedex height its length): `height` scales the height it is sized by,
-- the one WoobleView is told and the realism's
do
  local atlas = newAtlas({ BIG = { height = 0.5 } })
  local hd = fakeHd(); atlas.hd = hd
  check(near(atlas.heightOf(465), 10), "height 0.5: a 20 m Pokemon told as 10 m (" .. tostring(atlas.heightOf(465)) .. ")")
  check(near(atlas.heightOf(464), 1.65), "no height: the Pokedex's")
  local big = hd.tags[atlas.picFrame(465, "front", atlas.cell(465, "front"), 0, true)]
  check(big and near(big.height, 10), "the tag carries the halved height")
  check(big and near(big.scale, R(100) * 0.9), "realism by the halved height (" .. tostring(big and big.scale) .. ")")
end

-- the tag's height: measured on the front (its art from the feet to the top of its animation),
-- so a back whose art reaches less far over its resting body carries that much less
do
  local atlas = newAtlas({ LEAP = { height = 2.25 } })
  local hd = fakeHd(); atlas.hd = hd
  local f = hd.tags[atlas.picFrame(467, "front", atlas.cell(467, "front"), 0, true)]
  check(f and near(f.height, 2.25), "a front's tag: the measured height (" .. tostring(f and f.height) .. ")")
  local b = hd.tags[atlas.picFrame(467, "back", atlas.cell(467, "back"), 0, true)]
  local want = 2.25 * (76 / 70) / (90 / 40)
  check(b and near(b.height, want), "a back's: by its art's reach over its rest against the front's (" ..
    tostring(b and b.height) .. ", want " .. want .. ")")
  local mb = hd.tags[atlas.picFrame(464, "back", atlas.cell(464, "back"), 0, true)]
  check(mb and near(mb.height, 1.65), "a back whose front has no boxes: the height as it is")
  check(near(atlas.tagHeight(467, atlas.cell(467, "back"), true), want) and
    near(atlas.tagHeight(467, atlas.cell(467, "front"), false), 2.25), "tagHeight: the same, either side")
end

-- `size`: a share of the size it is drawn at, front and back (the realism by its own height,
-- untouched) and, for Battle Fit, the art box grown to match (fitArt); the feet stay where they are
do
  local plain = newAtlas(nil)
  local hp = fakeHd(); plain.hd = hp
  local p0 = hp.tags[plain.picFrame(465, "front", plain.cell(465, "front"), 0, true)]
  local pb = hp.tags[plain.picFrame(465, "back", plain.cell(465, "back"), 0, true)]
  local atlas = newAtlas({ BIG = { size = 0.25 } })
  local hd = fakeHd(); atlas.hd = hd
  check(near(atlas.sizeOf(465), 0.25) and near(atlas.sizeOf(464), 1), "sizeOf: the tuning's, else 1")
  check(near(atlas.heightOf(465), 20), "size leaves the height alone")
  local f = hd.tags[atlas.picFrame(465, "front", atlas.cell(465, "front"), 0, true)]
  check(f and near(f.scale, p0.scale * 0.25), "size 0.25: a quarter of the front (" .. tostring(f and f.scale) .. ")")
  local b = hd.tags[atlas.picFrame(465, "back", atlas.cell(465, "back"), 0, true)]
  check(b and near(b.scale, pb.scale * 0.25), "...and of the back")
  local x0, y0 = feet(p0)
  local x1, y1 = feet(f)
  check(near(x0, x1) and near(y0, y1) and f.pivot[2] == p0.pivot[2], "...standing on the same feet")
  -- Battle Fit: the art box (back: x 18-74, y 4-82, feet at 45, 80) grown 4x about the feet, so
  -- the art fills a quarter of the room; with no size, the art's own box
  local a = b and b.art
  check(a and near(a[1], 45 - 27 * 4) and near(a[2], 80 - 76 * 4) and near(a[3], 45 + 29 * 4)
    and near(a[4], 80 + 2 * 4), "Battle Fit's art box grown by 1 / size about the feet")
  local mb = hd.tags[atlas.picFrame(464, "back", atlas.cell(464, "back"), 0, true)]
  check(mb and mb.art and mb.art[1] == 18 and mb.art[2] == 4 and mb.art[3] == 74 and mb.art[4] == 82,
    "no size: the art's own box")
  local s1 = select(1, plain.battleSize(465, plain.cell(465, "front"), false))
  local s2 = select(1, atlas.battleSize(465, atlas.cell(465, "front"), false))
  check(near(s2, s1 * 0.25), "Gen 1 / 2's battleSize has it too")
end

-- 3DB FRONTAL (Gen 3): the player's pic as its front art, stood where its back stands (the
-- front's feet row on the back's feet line, body centred, sized as a back: realism, no
-- perspective), tagged as the player's at the front's own height; 3DB FLIP mirrors it
do
  local atlas = newAtlas(nil)
  local hd = fakeHd(); atlas.hd = hd
  local fc = atlas.cell(467, "front")
  local t = hd.tags[atlas.picFrame(467, "front", fc, 0, true, nil, "front")]
  check(t and t.side == "player", "frontal: tagged as the player's")
  check(t and near(t.lowPivot[2], 67) and near(t.lowPivot[1], 32), "frontal: its feet on the back's feet line, centred ("
    .. tostring(t and t.lowPivot[1]) .. ", " .. tostring(t and t.lowPivot[2]) .. ")")
  check(t and t.pivot[2] == 90 and near(t.pivot[1], 45), "frontal: about the front's feet row and body centre")
  check(t and near(t.scale, R(10)), "frontal: realism, no perspective (" .. tostring(t and t.scale) .. ")")
  check(t and near(t.height, atlas.heightOf(467)), "frontal: the front's own height")
  check(t and not t.flip, "frontal: not mirrored")
  local back = hd.tags[atlas.picFrame(467, "back", atlas.cell(467, "back"), 0, true)]
  check(back and near(back.lowPivot[2], t.lowPivot[2]), "frontal: the same feet line as the back")
  check(atlas.picFrame(467, "front", fc, 0, true) ~= atlas.picFrame(467, "front", fc, 0, true, nil, "front"),
    "frontal: a canvas of its own, not the enemy's front")
  -- FLIP: mirrored only where WoobleView mirrors a tag
  local plain = atlas.picFrame(467, "front", fc, 0, true, nil, "flip")
  check(hd.tags[plain] == nil, "flip without WoobleView's flip feature: the plain mirrored canvas, untagged")
  hd.features = { flip = true }
  local atlas2 = newAtlas(nil); atlas2.hd = hd
  local f = hd.tags[atlas2.picFrame(467, "front", atlas2.cell(467, "front"), 0, true, nil, "flip")]
  check(f and f.flip == true and near(f.lowPivot[1], 32) and near(f.lowPivot[2], 67), "flip: tagged mirrored, same feet")
  -- (a back variant ignores it)
  local b = hd.tags[atlas2.picFrame(467, "back", atlas2.cell(467, "back"), 0, true, nil, "flip")]
  check(b and not b.flip and b.side == "player", "a back is never frontal")
end

-- ANIMATE (Gen 3: atlas.option) off: every pic on its first frame
do
  local atlas = newAtlas(nil)
  local many = { frames = 40 }
  NOW = 3.7
  check(atlas.frameIndex(many) ~= 0, "animated by default")
  local on = true
  atlas.option = function(key) if key == "animate_sprites" then return on end end
  check(atlas.frameIndex(many) ~= 0, "ANIMATE on: animated")
  on = false
  check(atlas.frameIndex(many) == 0, "ANIMATE off: the first frame")
  atlas.option = function() error("broken") end
  check(atlas.frameIndex(many) ~= 0, "an option getter that errors: animated")
  NOW = nil
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 realism)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
