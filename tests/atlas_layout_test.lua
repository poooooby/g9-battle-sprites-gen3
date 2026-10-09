-- Headless check of Atlas.backLayout (src/atlas.lua): where a back pic's frame goes
-- in the 64x64 pic box. No LOVE needed. Run from the mod root:
--   luajit tests/atlas_layout_test.lua
local Atlas = dofile("src/atlas.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
local RAISE = 4 -- BACK_RAISE in src/atlas.lua: every back pic sits this many px higher

-- Abomasnow: a 94x94 frame, the creature 83 wide x 70 tall inside it (x 7-90, y 15-85).
-- Wider and taller than the box: full size, cropped at the sides and the bottom.
do
  local s, ox, oy = Atlas.backLayout({ fs = 94, cx0 = 7, cy0 = 15, cx1 = 90, cy1 = 85 })
  check(s == 1, "a big creature is not shrunk (s = " .. s .. ")")
  check(near(ox, -16.5), "centred on the creature: cropped evenly at both sides (ox = " .. ox .. ")")
  check(near(oy, -15 - RAISE), "its top sits at the box top, the bottom is cut off (oy = " .. oy .. ")")
end

-- a small creature: whole, with its feet on the box bottom, not the frame's bottom
do
  local s, ox, oy = Atlas.backLayout({ fs = 60, cx0 = 10, cy0 = 12, cx1 = 50, cy1 = 48 })
  check(s == 1, "a small creature stays at full size")
  check(near(ox, 32 - 30), "...centred on the creature (ox = " .. ox .. ")")
  check(near(oy, 64 - 48 - RAISE), "...feet on the box bottom, empty rows below it ignored (oy = " .. oy .. ")")
end

-- a creature exactly as tall as the box counts as a close-up (top aligned, nothing to cut)
do
  local _, _, oy = Atlas.backLayout({ fs = 64, cx0 = 0, cy0 = 0, cx1 = 64, cy1 = 64 })
  check(near(oy, -RAISE), "a 64px creature fills the box, lifted")
end

-- a giant is reduced only as far as needed to keep a useful share in view
do
  local s = Atlas.backLayout({ fs = 182, cx0 = 0, cy0 = 0, cx1 = 182, cy1 = 182 })
  check(s < 1, "a giant is reduced (s = " .. s .. ")")
  check(64 / (182 * s) >= 0.7 - 1e-9, "...but still shows at least 70% of its width")
  local tall = Atlas.backLayout({ fs = 160, cx0 = 60, cy0 = 0, cx1 = 100, cy1 = 160 })
  check(near(tall, 64 / (0.5 * 160)), "a tall, narrow one is limited by its height share (s = " .. tall .. ")")
end

-- an older index without the creature's box falls back to the whole frame
do
  local s, ox, oy = Atlas.backLayout({ fs = 80 })
  check(s == 1 and near(ox, -8) and near(oy, -RAISE), "no box: the whole frame is the creature")
end

-- ------- wide mode: the canvas grows to hold the whole creature, never shrunk
do
  -- Noivern (160x107 box in a 182 frame): 160 px of wing, centred, spills past both sides
  local s, ox, oy, xmin, xmax = Atlas.backLayout({ fs = 182, cx0 = 11, cy0 = 38, cx1 = 171, cy1 = 145 }, true)
  check(s == 1, "wide: a giant is not shrunk at all")
  check(xmin < 0 and xmax > 64, "wide: the canvas extends past both sides of the box (" .. xmin .. " .. " .. xmax .. ")")
  check(near(ox + 11, xmin) or ox + 11 >= xmin, "wide: the creature's left edge is inside the canvas")
  check(ox + 171 <= xmax + 1e-9, "wide: ...and so is its right edge")
  check(near(oy, -38 - RAISE), "wide: the top is still at the box top, the bottom still cut off")
  -- Abomasnow (x 7-90): a little past the box
  local _, _, _, ax0, ax1 = Atlas.backLayout({ fs = 94, cx0 = 7, cy0 = 15, cx1 = 90, cy1 = 85 }, true)
  check(ax0 == -10 and ax1 == 74, "wide: Abomasnow gets the 10px it needs each side (" .. ax0 .. " .. " .. ax1 .. ")")
  -- a small creature keeps the plain box
  local _, _, _, sx0, sx1 = Atlas.backLayout({ fs = 60, cx0 = 10, cy0 = 12, cx1 = 50, cy1 = 48 }, true)
  check(sx0 == 0 and sx1 == 64, "wide: a creature that fits keeps the 64px canvas")
  -- the canvas never grows without limit
  local _, _, _, wx0, wx1 = Atlas.backLayout({ fs = 600, cx0 = 0, cy0 = 0, cx1 = 600, cy1 = 300 }, true)
  check(wx0 >= -96 and wx1 <= 160, "wide: capped at 96px past the box each side (" .. wx0 .. " .. " .. wx1 .. ")")
  -- not wide: always the plain box
  local _, _, _, nx0, nx1 = Atlas.backLayout({ fs = 182, cx0 = 11, cy0 = 38, cx1 = 171, cy1 = 145 }, false)
  check(nx0 == 0 and nx1 == 64, "not wide: the canvas stays 64px")
end

-- ------- wide mode: a head that swings above its typical pose is not cut off either
do
  -- Blacephalon: typical pose x 38-100, y 69-144; over the animation x 29-114, y 0-144
  local cell = { fs = 144, cx0 = 38, cy0 = 69, cx1 = 100, cy1 = 144, ux0 = 29, uy0 = 0, ux1 = 114, uy1 = 144 }
  local s, ox, oy, xmin, xmax, ymin, ymax = Atlas.backLayout(cell, true)
  check(s == 1, "tall: not shrunk")
  check(near(oy, -69 - RAISE), "tall: still anchored with the typical pose's top at the box top (oy = " .. oy .. ")")
  check(ymin == -69 - RAISE, "tall: the canvas reaches up to where the head swings (ymin = " .. ymin .. ")")
  check(ymax == 75 - RAISE, "tall: ...and down to the frame's bottom, past the box (ymax = " .. ymax .. ")")
  check(xmin <= ox + 29 and xmax >= ox + 114, "tall: and holds the animation's full width")
  -- the vertical extent is capped too
  local _, _, _, _, _, tmin, tmax = Atlas.backLayout({ fs = 600, cx0 = 0, cy0 = 300, cx1 = 64, cy1 = 600, ux0 = 0, uy0 = 0, ux1 = 64, uy1 = 600 }, true)
  check(tmin >= -96 and tmax <= 160, "tall: capped at 96px past the box (" .. tmin .. " .. " .. tmax .. ")")
  -- not wide: the box
  local _, _, _, _, _, nmin, nmax = Atlas.backLayout(cell, false)
  check(nmin == 0 and nmax == 64, "not wide: the canvas stays the box")
end

-- ------- front pics in battle: the whole frame at 1:1, bottom-centred, nothing shrunk or cut
do
  -- a 100px frame: same anchor as the fit layout (bottom on the box bottom, centred), no scaling
  local s, ox, oy, xmin, xmax, ymin, ymax = Atlas.frontLayout({ fs = 100 })
  check(s == 1, "front: not shrunk")
  check(near(ox, -18) and near(oy, -36), "front: bottom-centred on the box (ox = " .. ox .. ", oy = " .. oy .. ")")
  check(xmin == -18 and xmax == 82, "front: the canvas holds the frame's full width (" .. xmin .. " .. " .. xmax .. ")")
  check(ymin == -36 and ymax == 64, "front: ...and full height, ending at the box bottom (" .. ymin .. " .. " .. ymax .. ")")
  -- a frame that fits the box keeps the plain box
  local _, ox2, oy2, x0, x1, y0, y1 = Atlas.frontLayout({ fs = 48 })
  check(near(ox2, 8) and near(oy2, 16) and x0 == 0 and x1 == 64 and y0 == 0 and y1 == 64, "front: a small frame stays in the 64px box")
  -- capped, not unbounded
  local _, _, _, cx0, cx1, cy0 = Atlas.frontLayout({ fs = 600 })
  check(cx0 >= -96 and cx1 <= 160 and cy0 >= -96, "front: capped at 96px past the box")
end

-- ------- a front pic dropped below its frame's bottom edge (`fy`)
do
  local s, ox, oy, xmin, xmax, ymin, ymax = Atlas.frontLayout({ fs = 100, fy = 20 })
  check(s == 1 and near(oy, -36 + 20), "front drop: 20px lower than the plain layout (oy = " .. oy .. ")")
  check(ymin == -16 and ymax == 84, "front drop: the canvas holds the frame in its new place (" .. ymin .. " .. " .. ymax .. ")")
  local _, _, oy0, _, _, y0, y1 = Atlas.frontLayout({ fs = 100 })
  check(near(oy0, -36) and y0 == -36 and y1 == 64, "front drop: no `fy` is the plain layout")
end

-- ------- back pics framed like the cart: body top on the reference's row, at its scale
do
  -- Abomasnow-sized body (x 7-90, y 15-85), reference body top on row 4, drawn at 1x
  local cell = { fs = 94, cx0 = 7, cy0 = 15, cx1 = 90, cy1 = 85, bt = 4, bs = 1,
                 ux0 = 0, uy0 = 0, ux1 = 94, uy1 = 94 }
  local s, ox, oy, xmin, xmax, ymin, ymax = Atlas.backLayout(cell, true)
  check(s == 1, "framed: scale 1")
  check(near(oy, 4 - 15), "framed: the body's top sits on the reference's row, with no extra lift (oy = " .. oy .. ")")
  check(near(ox, 32 - 48.5), "framed: centred on the body (ox = " .. ox .. ")")
  check(ymin == math.floor(oy), "framed: the canvas still reaches the top of the animation (" .. ymin .. ")")
  -- upscaled: 1.5x grows the body down from the same row, and the canvas grows with it
  local up = { fs = 60, cx0 = 10, cy0 = 12, cx1 = 50, cy1 = 48, bt = 8, bs = 1.5,
               ux0 = 4, uy0 = 6, ux1 = 56, uy1 = 54 }
  local s2, ox2, oy2, x0, x1, y0, y1 = Atlas.backLayout(up, true)
  check(s2 == 1.5, "framed: 1.5x is kept")
  check(near(oy2, 8 - 1.5 * 12), "framed: the top is still on the reference's row (oy = " .. oy2 .. ")")
  check(near(ox2, 32 - 1.5 * 30), "framed: centred at the new size (ox = " .. ox2 .. ")")
  check(x1 - x0 >= 1.5 * (56 - 4) - 1, "framed: the canvas holds the scaled animation's width (" .. x0 .. " .. " .. x1 .. ")")
  -- a cell with no reference is laid out as before (this one fits whole, feet on the box bottom, lifted)
  local _, _, oy3 = Atlas.backLayout({ fs = 60, cx0 = 10, cy0 = 12, cx1 = 50, cy1 = 48 }, true)
  check(near(oy3, 64 - 48 - RAISE), "no reference: unchanged (oy = " .. oy3 .. ")")
end

-- ------- exact zoom and anchor (gen3-hd-sprites): the body matches the cart sprite's height and column
do
  -- Treecko-like: body 44 x 46 starting at (9, 12); the cart's body is 51 rows tall from row 7, centred on column 31
  local cell = { fs = 63, cx0 = 9, cy0 = 12, cx1 = 53, cy1 = 58, bt = 7, bs = 1, bv = 51, bx = 31,
                 ux0 = 9, uy0 = 0, ux1 = 55, uy1 = 63 }
  local s, ox, oy = Atlas.backLayout(cell, true, true)
  check(near(s, 51 / 46), "exact: zoomed to the cart's height, not a clean step (s = " .. s .. ")")
  check(near(oy, 7 - s * 12), "exact: the body's top is on the cart's row (oy = " .. oy .. ")")
  check(near(ox, 31 - s * 31), "exact: centred on the cart body's column (ox = " .. ox .. ")")
  local s1 = Atlas.backLayout(cell, true, false)
  check(s1 == 1, "not exact: the clean step is used")
  -- clamped
  local huge = { fs = 40, cx0 = 0, cy0 = 0, cx1 = 20, cy1 = 10, bt = 0, bs = 2, bv = 64, bx = 32 }
  check(Atlas.backLayout(huge, true, true) == 3, "exact: never more than 3x")
  local tiny = { fs = 200, cx0 = 0, cy0 = 0, cx1 = 100, cy1 = 200, bt = 0, bs = 1, bv = 40, bx = 32 }
  check(Atlas.backLayout(tiny, true, true) == 1, "exact: zooms in only, never below 1x")
  -- no reference height: the clean step
  local old = { fs = 63, cx0 = 9, cy0 = 12, cx1 = 53, cy1 = 58, bt = 7, bs = 1.5 }
  check(Atlas.backLayout(old, true, true) == 1.5, "exact: an index without `bv` keeps its step")
end

-- ------- the draw wrap swaps the engine's (32, 32) origin for a wide canvas's own pivot
do
  local calls = {}
  love = { graphics = { draw = function(...) calls[#calls + 1] = { ... } end } }
  check(Atlas._installDrawWrap() == true, "the wrap installs over love.graphics.draw")
  check(Atlas._installDrawWrap() == true, "...and a second call is a no-op (still installed once)")
  local wide, plain = {}, {}
  Atlas._pivots[wide] = { 80, 32 }

  love.graphics.draw(wide, 100, 90, 0, 1, 1, 32, 32)
  local c = calls[#calls]
  check(c[7] == 80 and c[8] == 32, "a wide canvas drawn with origin (32, 32) gets its own pivot (" .. tostring(c[7]) .. ", " .. tostring(c[8]) .. ")")
  check(c[2] == 100 and c[3] == 90 and c[6] == 1, "...and its position and scale are untouched")

  love.graphics.draw(wide, 100, 90, 0, 1, 1, 5, 6)
  c = calls[#calls]
  check(c[7] == 5 and c[8] == 6, "a wide canvas drawn with any other origin is left alone")

  love.graphics.draw(plain, 100, 90, 0, 1, 1, 32, 32)
  c = calls[#calls]
  check(c[7] == 32 and c[8] == 32, "any other image keeps its origin")

  love.graphics.draw(wide, "quad", 100, 90, 0, 1, 1, 32, 32)
  c = calls[#calls]
  check(c[8] == 32 and c[9] == 32, "the quad form is passed through unchanged")

  love.graphics.draw(plain, 10, 20)
  c = calls[#calls]
  check(c[1] == plain and c[2] == 10 and c[3] == 20, "a short call (image, x, y) still works")
  love = nil
end

print(string.format("%d/%d checks passed (atlas back layout)", passed, passed + failed))
if failed > 0 then os.exit(1) end
