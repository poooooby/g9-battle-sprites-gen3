-- Reads the packed sprite atlases (assets/atlas/, indexed by data/atlas_index.lua,
-- both written by tools/build_atlas.py) and hands out what the engine draws.
--
--   * battle pics: the engine's Pokemon.frontPic / backPic return one Image
--     per call, so the current animation frame is rendered into a 64x64
--     canvas (the vanilla pic box) and cached. The cache is bounded, least
--     recently used first, so a long session cannot grow it without limit.
--   * party icons: the engine's own icon entry shape (an image plus one quad
--     per frame), so no canvas is needed.
--
-- Nothing here reads a file that is not in the atlas set, and nothing touches
-- the network.

local Atlas = {}

local PIC_BOX = 64          -- the engine's battle / summary pic box, in its own units
local PIC_SCALE = 4         -- detail: canvases are PIC_BOX * PIC_SCALE pixels, dpiscale = PIC_SCALE
local PIC_SCALE_BIG = 2     -- ... for a canvas bigger than the box (a whole frame): bounds its memory
local PIC_FPS = 8           -- animation rate of the sheets, frames per second
local DEX_FRAME_TIME = 0.5  -- seconds each of the cart front pic's two frames shows on an RSE entry
local CANVAS_CAP = 128      -- most rendered pic frames kept at once

-- Back (player-side) pics are a close-up: the creature at full size, not shrunk to
-- fit, with whatever overflows the box cut off at the bottom (the battle GUI
-- covers it).
--
-- WIDE: the engine draws a battle pic with its centre (32, 32) at the battler's spot
-- and nothing limits how far the image extends to the right or down, but it cannot
-- extend left of x = 0 or above y = 0, so a wide or tall creature (wings, a head that
-- swings up) would be cropped at the box edges. So the pic is rendered into a canvas
-- big enough for the creature's whole animation, and the engine's draw call is told
-- where that canvas's centre is (see installDrawWrap): nothing is cut off by the
-- canvas, and what falls below the box is covered by the battle GUI as it is for the
-- built-in pics. Without the wrap (it could not be installed) a giant is reduced just
-- enough to keep BACK_MIN_W of its width in view and cropped to the box instead.
local BACK_WIDE = true
local BACK_WIDE_MAX = 96     -- most px the canvas grows past the box in any direction
local BACK_MIN_W = 0.7       -- (no WIDE) at least this share of the creature's width stays visible
local BACK_MIN_H = 0.5       -- ... and this share of its height
local BACK_ZOOM_MIN = 1      -- the exact zoom (gen3-hd-sprites) only zooms IN, never out: stays between these
local BACK_ZOOM_MAX = 3
local BACK_RAISE = 4         -- px a back pic WITHOUT a cart reference is lifted, to sit on the platform

-- Realism scaling (gen3-hd-sprites only): a Pokemon's size from its real height, pulled toward
-- the neutral height like a rubber band. L = ln(h / center); above the neutral height
-- s = 1 + grow * (L / ln(tallest / center))^curve, below it s = 1 - shrink * (|L| /
-- ln(center / shortest))^curve, so only the true extremes reach the limits. Heights in metres;
-- `htDm` is the index's `ht` (decimetres). Returns 1 when off, or with no height. Pure.
Atlas.REALISM = { on = true, center = 1.65, grow = 0.25, shrink = 0.15, curve = 1.5,
                  shortest = 0.1, tallest = 20, front = 0.85, match_backs = true }
function Atlas.realism(htDm, cfg)
  cfg = cfg or Atlas.REALISM
  local h = tonumber(htDm)
  if cfg.on == false or not h or h <= 0 then return 1 end
  h = h / 10
  local function n(key) return tonumber(cfg[key]) or Atlas.REALISM[key] end
  local center, p = n("center"), n("curve")
  local L = math.log(h / center)
  if L > 0 then
    local span = math.log(n("tallest") / center)
    if span <= 0 then return 1 end
    return 1 + n("grow") * math.min(1, L / span) ^ p
  elseif L < 0 then
    local span = math.log(center / n("shortest"))
    if span <= 0 then return 1 end
    return 1 - n("shrink") * math.min(1, -L / span) ^ p
  end
  return 1
end

-- px the player's back pic is lowered on top of its cell's feet line: 4 on Ruby / Sapphire,
-- which draw the player's pic 4 px higher than FireRed / LeafGreen / Emerald (set by main.lua)
Atlas.backShift = 0

-- px each slot's battle pic is lowered by on this game: tools/build_atlas.py places the feet
-- against FireRed / LeafGreen's per-species offsets (pret gMonFront/BackPicCoords and
-- gEnemyMonElevation), but Ruby / Sapphire / Emerald carry their own, Emerald's Pidgey hovering
-- 16 px for its flying-pose art. Empty on FireRed / LeafGreen (set by main.lua)
Atlas.coordShift = { front = {}, back = {} }

--- The per-slot shifts that cancel the difference between this game's pic offsets and
--- FireRed's: `frlg` and `active` are { front, back, elev } tables keyed by slot (the engine's
--- PicCoords). A slot missing from a table counts as 0. Pure.
function Atlas.gameCoordShift(frlg, active)
  local out = { front = {}, back = {} }
  if type(frlg) ~= "table" or type(active) ~= "table" or frlg == active then return out end
  local function get(t, k, sp) return tonumber(type(t[k]) == "table" and t[k][sp]) or 0 end
  local slots = {}
  for _, t in ipairs({ frlg, active }) do
    for _, k in ipairs({ "front", "back", "elev" }) do
      for sp in pairs(type(t[k]) == "table" and t[k] or {}) do slots[sp] = true end
    end
  end
  for sp in pairs(slots) do
    -- the engine centres a front on base + offset - elevation, a back on base + offset
    local df = (get(frlg, "front", sp) - get(frlg, "elev", sp)) - (get(active, "front", sp) - get(active, "elev", sp))
    local db = get(frlg, "back", sp) - get(active, "back", sp)
    if df ~= 0 then out.front[sp] = df end
    if db ~= 0 then out.back[sp] = db end
  end
  return out
end

--- Where a back pic's frame goes in the PIC_BOX x PIC_BOX box: scale `s` and the
--- frame's top-left (`ox`, `oy`), in box px, plus the canvas's extent `xmin`, `xmax`,
--- `ymin`, `ymax` in box px (0 .. PIC_BOX unless `wide`). `cell` carries the
--- creature's typical box in its frame (cx0, cy0, cx1, cy1, source px; what it is
--- anchored on) and its box over the whole animation (ux0, uy0, ux1, uy1; how much
--- room it needs), both written by tools/build_atlas.py; an older index without them
--- falls back to the whole frame. A cell framed from the cart's own sprite (tools/back_framing.py)
--- also has `bt`, the box row its body's top sits on, and `bs`, the scale (1, 1.5 or 2) that
--- brings its body to the cart's on-screen height: the body is then drawn at that scale with its
--- top on row `bt`, and whatever runs below the box is what the battle GUI covers. Pure.
function Atlas.backLayout(cell, wide, exact, force, dy)
  local fs = cell.fs or PIC_BOX
  local x0, y0 = cell.cx0 or 0, cell.cy0 or 0
  local x1, y1 = cell.cx1 or fs, cell.cy1 or fs
  local cw, ch = math.max(1, x1 - x0), math.max(1, y1 - y0)
  local s, oy, anchorX, zoomTop
  if cell.bfl and cell.bfr then
    -- stood on its feet, like the fronts: the resting pose's bottom row (`bfr`, source px) on
    -- the player's feet line (`bfl`, box rows; tools/build_atlas.py BACK_FEET_ROW), at the art's
    -- own size. A size set by hand (data/sprite_scale.lua, HD only) scales about the feet.
    if wide or exact then
      s = force or 1
    else
      s = math.min(1, PIC_BOX / (BACK_MIN_W * cw), PIC_BOX / (BACK_MIN_H * ch))
    end
    oy = cell.bfl + Atlas.backShift - s * cell.bfr
  elseif cell.bt then
    -- framed like the cart: the body's top on the reference's row, at the reference's size
    s = cell.bs or 1
    if exact and cell.bv then
      -- gen3-hd-sprites draws at window resolution, so any zoom keeps every pixel: the body
      -- is zoomed to exactly the cart sprite's on-screen height instead of a clean step
      s = math.max(BACK_ZOOM_MIN, math.min(BACK_ZOOM_MAX, cell.bv / ch))
      anchorX = cell.bx            -- ... and put where the cart sprite's body is, side to side too
    end
    if exact and cell.bz then
      -- fitted over the cart's static back sprite (tools/back_fit.py): its own zoom, any value
      s = math.max(0.5, math.min(BACK_ZOOM_MAX, cell.bz))
      anchorX = cell.bzx
      zoomTop = cell.bzt
    end
    if force then s = force end    -- a size set by hand (data/sprite_scale.lua)
    oy = (zoomTop or cell.bt) - s * y0
  else
    if wide then
      s = 1
    else
      s = math.min(1, PIC_BOX / (BACK_MIN_W * cw), PIC_BOX / (BACK_MIN_H * ch))
    end
    if ch * s >= PIC_BOX then
      oy = -s * y0               -- top at the box top: the overflow is cut at the bottom
    else
      oy = PIC_BOX - s * y1      -- fits whole: feet on the box bottom
    end
    oy = oy - BACK_RAISE
  end
  oy = oy + (dy or 0)            -- this game's offset against FireRed's (Atlas.coordShift)
  -- centred on the creature
  local ox = (anchorX or PIC_BOX / 2) - s * (x0 + x1) / 2
  local xmin, xmax, ymin, ymax = 0, PIC_BOX, 0, PIC_BOX
  if wide then
    local u0, v0 = cell.ux0 or x0, cell.uy0 or y0
    local u1, v1 = cell.ux1 or x1, cell.uy1 or y1
    local m = BACK_WIDE_MAX
    xmin = math.max(-m, math.min(0, math.floor(ox + s * u0)))
    xmax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(ox + s * u1)))
    ymin = math.max(-m, math.min(0, math.floor(oy + s * v0)))
    ymax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(oy + s * v1)))
  end
  return s, ox, oy, xmin, xmax, ymin, ymax
end

-- canvases that are wider than the box -> where the engine's pivot (32, 32) is in them
local pivots = setmetatable({}, { __mode = "k" })
local wrapState = nil        -- nil = not tried, true = installed, false = unavailable

--- The engine draws a battle pic with `love.graphics.draw(image, x, y, r, sx, sy,
--- 32, 32)`. For one of our wide canvases the pivot is somewhere else, so that
--- call's origin is swapped for the canvas's own; every other draw passes through.
--- Installed once, only when a wide canvas is first needed. Returns whether it is
--- in place.
local function installDrawWrap()
  if wrapState ~= nil then return wrapState end
  local g = love and love.graphics
  local real = g and g.draw
  if type(real) ~= "function" then
    wrapState = false
    return false
  end
  local half = PIC_BOX / 2
  local ok = pcall(function()
    g.draw = function(img, a, b, c, d, e, f, h, i, ...)
      local pivot = pivots[img]
      if pivot and type(a) == "number" and f == half and h == half then
        return real(img, a, b, c, d, e, pivot[1], pivot[2], i, ...)
      end
      return real(img, a, b, c, d, e, f, h, i, ...)
    end
  end)
  wrapState = ok
  return ok
end

Atlas._pivots, Atlas._installDrawWrap = pivots, installDrawWrap -- for the tests

--- Where a FRONT pic goes when it is drawn in battle at full size: the whole frame at
--- 1:1, bottom-centred on the pic box exactly as the fit-to-box layout anchors it, in
--- a canvas that extends past the box (no shrinking, nothing cut off). Returns the same
--- as backLayout: `s, ox, oy, xmin, xmax, ymin, ymax`. Pure.
function Atlas.frontLayout(cell, dy)
  local fs = cell.fs or PIC_BOX
  -- a species drawn lower than its frame's bottom edge puts it, plus this game's offset
  -- against FireRed's (Atlas.coordShift)
  local drop = (cell.fy or 0) + (dy or 0)
  local ox, oy = (PIC_BOX - fs) / 2, PIC_BOX - fs + drop
  local m = BACK_WIDE_MAX
  local xmin = math.max(-m, math.min(0, math.floor(ox)))
  local xmax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(ox + fs)))
  local ymin = math.max(-m, math.min(0, math.floor(oy)))
  local ymax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(oy + fs)))
  return 1, ox, oy, xmin, xmax, ymin, ymax
end

-- ------- colour numbers (tools/build_numbers.py) ------------------------------------------
-- The battle art ships as colour numbers: each species' animation (normal + shiny) once, as a
-- greyscale strip of numbers in a shard (assets/numbers/num_<n>.png, the number in red), its real
-- colours one row of assets/numbers/palette.png. A species' block is rebuilt when it is first
-- drawn, laid out as a grid of frames (a strip of 100+ frames would pass the texture limit), so
-- only what is on screen is in memory -- not whole 4032x4032 pages.
local BLOCK_CAP = 24        -- species blocks kept at once (least recently used dropped first)
local SHARD_CAP = 3         -- decoded number shards kept at once

--- The exact RGBA bytes of a `count`-pixel image from its decoded number pixels (`numbers`,
--- RGBA bytes, number in red) and its palette row (`row`, 4 bytes per colour). Pure.
function Atlas._expand(numbers, count, row)
  local byte, sub = string.byte, string.sub
  local colours = {}
  for i = 0, math.floor(#row / 4) - 1 do colours[i] = sub(row, i * 4 + 1, i * 4 + 4) end
  local out = {}
  local transparent = "\0\0\0\0"
  for i = 1, count do out[i] = colours[byte(numbers, i * 4 - 3)] or transparent end
  return table.concat(out)
end

--- Columns of the grid a block of `frames` frames, `fs` px square, is laid out in: about square,
--- so no side passes the texture limit (182 px x 172 frames -> 14 x 13). Pure.
function Atlas.blockCols(frames)
  return math.max(1, math.ceil(math.sqrt(math.max(1, frames or 1))))
end

--- The key of a cell in the numbers index (tools/build_numbers.py cell_key). Pure.
function Atlas.blockKey(variant, cell)
  return string.format("%s:%d:%d:%d:%d", variant, cell.sheet or 0, cell.start or 0, cell.ox or 0, cell.oy or 0)
end

-- the palette lookup done on the GPU: number (red) -> column of a one-row palette image
local DECODE_SHADER = [[
extern Image pal;
extern number palW;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  number n = floor(Texel(tex, tc).r * 255.0 + 0.5);
  return Texel(pal, vec2((n + 0.5) / palW, 0.5));
}
]]

local function loadIndex(load)
  local index = load("data/atlas_index.lua")
  if type(index) ~= "table" or type(index.species) ~= "table" then return nil end
  -- keyed by the engine's species SLOT: a base species (dex + 64) and an
  -- alternate form (a slot of its own, with its base's dex number) are both
  -- one entry, so a form never replaces its base. An index without `slot`
  -- (an older build) is read as dex + 64.
  -- A female sheet (MEOWSTIC_FEMALE) has `female_of` instead: the slot of the species
  -- it is the female look of. It is kept under the NEGATIVE of that slot, so it never
  -- replaces the species and the hooks can ask for it by gender.
  local bySlot = {}
  for id, rec in pairs(index.species) do
    if type(rec) == "table" and tonumber(rec.female_of) then
      bySlot[-tonumber(rec.female_of)] = { id = id, cells = rec }
    else
      local slot = type(rec) == "table" and (tonumber(rec.slot) or (tonumber(rec.dex) and tonumber(rec.dex) + 64))
      if slot then bySlot[slot] = { id = id, cells = rec } end
    end
  end
  return bySlot
end

-- A window mode change (love.window.setMode / updateMode / setFullscreen) may recreate the
-- graphics context, which empties every Canvas: the decoded colour-number blocks and every
-- rendered frame would draw as nothing from then on (an Image is reloaded by LOVE itself). Each
-- change is counted (`love.window.__woobleGfx.n`, shared by every copy of this module, so a
-- reload of the mod still sees it), and an atlas that sees a new count drops its canvases.
function Atlas.watchWindow()
  local W = type(love) == "table" and love.window or nil
  if type(W) ~= "table" then return nil end
  if type(W.__woobleGfx) == "table" then return W.__woobleGfx end
  local gfx = { n = 0 }
  W.__woobleGfx = gfx
  local function after(...)
    gfx.n = gfx.n + 1
    return ...
  end
  for _, name in ipairs({ "setMode", "updateMode", "setFullscreen" }) do
    local orig = W[name]
    if type(orig) == "function" then
      W[name] = function(...) return after(orig(...)) end
    end
  end
  return gfx
end

--- How many window mode changes there have been: a canvas made before the last one may be empty.
function Atlas.gfxEpoch()
  local W = type(love) == "table" and love.window or nil
  local gfx = type(W) == "table" and W.__woobleGfx or nil
  return type(gfx) == "table" and gfx.n or 0
end

-- mod: the mod table (for mod.path and mod.log); load: loadSibling-style reader
function Atlas.new(mod, load)
  local bySlot = loadIndex(load)
  if not bySlot then return nil end
  Atlas.watchWindow()

  local self = { pages = {}, icons = {}, frames = {} }

  -- Hand-tuned sizes (data/sprite_scale.lua), used with gen3-hd-sprites. A missing or broken
  -- file just means the defaults.
  local tuning = {}
  do
    local ok, t = pcall(load, "data/sprite_scale.lua")
    if ok and type(t) == "table" then tuning = t end
  end
  -- (where an enemy front pic's feet go is in the atlas itself: the cell's drop `fy`, which
  -- tools/build_atlas.py works out for every species, with or without gen3-hd-sprites)
  -- realism scaling's settings (data/sprite_scale.lua `realism`, over Atlas.REALISM)
  local realismCfg = {}
  for k, v in pairs(Atlas.REALISM) do realismCfg[k] = v end
  if type(tuning.realism) == "table" then
    for k, v in pairs(tuning.realism) do realismCfg[k] = v end
  end
  self.realismCfg = realismCfg
  -- -> the species' own tuning, the `all` row, and its realism scale (1 when off)
  local function tuned(slot)
    local rec = bySlot[tonumber(slot)]
    local own = rec and tuning[rec.id]
    local all = type(tuning.all) == "table" and tuning.all or {}
    local real = rec and Atlas.realism(rec.cells.ht, realismCfg) or 1
    return type(own) == "table" and own or {}, all, real
  end

  -- A page is loaded once and kept. A failed load is NOT kept: assets:path()
  -- answers nil until the mod service is ready, so the next draw retries. The
  -- first failure of each page is logged, once, with the reason.
  local failed = {}
  local function page(name)
    local hit = self.pages[name]
    if hit then return hit end
    -- the mod's own folder (mod.path, as the sibling loader uses), not
    -- mod.assets, which is the dataset helper for generated data
    local path = mod.path .. "/assets/atlas/" .. name .. ".png"
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      -- icons are drawn straight to the screen by the engine; an Image defaults to
      -- linear filtering, which smears pixel art whenever it lands off the pixel
      -- grid (the engine sets nearest on its own icons for this reason). Battle
      -- pages are sampled into canvases by picFrame, which sets its own filters.
      if (name:find("^party_icons") or name:find("^dex_fronts")) and img.setFilter then img:setFilter("nearest", "nearest") end
      self.pages[name] = img
      return img
    end
    if not failed[name] then
      failed[name] = true
      if mod.log then
        mod.log:warn("could not load atlas page %s (path %s): %s", name, tostring(path),
          tostring(img))
      end
    end
    return nil
  end

  -- Colour numbers (see the section above Atlas.new). Without the index (an older build, the
  -- tests) every battle pic is read from the pages as before.
  local numbers
  do
    local ok, t = pcall(load, "data/numbers_index.lua")
    if ok and type(t) == "table" and type(t.blocks) == "table" and type(t.shards) == "table"
      and type(t.palette) == "table" then
      numbers = t
    end
  end
  self.numbers = numbers ~= nil
  local blocks, blockOrder = {}, {}
  local shardData, shardOrder = {}, {}
  local paletteData             -- palette.png as ImageData (false: unusable)
  local decodeShader            -- nil = not tried, false = unavailable, else the Shader
  local gpuTrusted              -- nil = not checked yet, true / false after the self-check

  local function numbersPath(name) return mod.path .. "/assets/numbers/" .. name .. ".png" end

  local function shard(n)
    local hit = shardData[n]
    if hit then return hit end
    local meta = numbers.shards[n + 1]
    if type(meta) ~= "table" then return nil end
    local ok, data = pcall(love.image.newImageData, numbersPath(meta.file))
    if not ok or not data then return nil end
    shardData[n] = data
    shardOrder[#shardOrder + 1] = n
    if #shardOrder > SHARD_CAP then shardData[table.remove(shardOrder, 1)] = nil end
    return data
  end

  local function paletteRow(row)
    if paletteData == nil then
      local ok, data = pcall(love.image.newImageData, numbersPath(numbers.palette.file))
      paletteData = ok and data or false
    end
    if not paletteData then return nil end
    local w = numbers.palette.w
    local p = love.image.newImageData(w, 1)
    p:paste(paletteData, 0, 0, 0, row, w, 1)
    return p
  end

  -- the strip (frames stacked) laid out as a grid of `cols` columns
  local function grid(stripData, fs, frames, cols)
    local rows = math.ceil(frames / cols)
    local g = love.image.newImageData(cols * fs, rows * fs)
    for f = 0, frames - 1 do
      g:paste(stripData, (f % cols) * fs, math.floor(f / cols) * fs, 0, f * fs, fs, fs)
    end
    return g
  end

  -- CPU decode: the exact colours as ImageData
  local function decodeCpu(numberGrid, pal)
    local w, h = numberGrid:getDimensions()
    return love.image.newImageData(w, h, "rgba8", Atlas._expand(numberGrid:getString(), w * h, pal:getString()))
  end

  -- GPU decode: the numbers drawn through the palette shader into a canvas (no per-pixel Lua)
  local function decodeGpu(numberGrid, pal)
    if decodeShader == nil then
      local ok, sh = pcall(love.graphics.newShader, DECODE_SHADER)
      decodeShader = ok and sh or false
    end
    if not decodeShader then return nil end
    local ok, canvas = pcall(function()
      local nimg = love.graphics.newImage(numberGrid)
      nimg:setFilter("nearest", "nearest")
      local pimg = love.graphics.newImage(pal)
      pimg:setFilter("nearest", "nearest")
      local c = love.graphics.newCanvas(numberGrid:getWidth(), numberGrid:getHeight())
      local G = love.graphics
      G.push("all")
      local okDraw, err = pcall(function()
        G.origin()
        if G.setScissor then G.setScissor() end
        G.setCanvas(c)
        G.clear(0, 0, 0, 0)
        G.setColor(1, 1, 1, 1)
        G.setBlendMode("replace", "premultiplied")  -- write the palette's bytes as they are
        G.setShader(decodeShader)
        decodeShader:send("pal", pimg)
        decodeShader:send("palW", pal:getWidth())
        G.draw(nimg, 0, 0)
      end)
      G.pop()
      nimg:release()
      pimg:release()
      if not okDraw then error(err, 0) end
      return c
    end)
    return ok and canvas or nil
  end

  -- The texture holding every frame of the cell (a grid of `cols` columns) and `cols`, or nil.
  local function block(variant, cell)
    local key = Atlas.blockKey(variant, cell)
    local hit = blocks[key]
    if hit then return hit.tex, hit.cols end
    local b = numbers.blocks[key]
    if type(b) ~= "table" then return nil end
    local data = shard(b[1])
    if not data then return nil end
    local fs, frames = cell.fs, cell.frames or 1
    local ok, tex, cols = pcall(function()
      local stripData = love.image.newImageData(b[3], b[4])
      stripData:paste(data, 0, 0, 0, b[2], b[3], b[4])
      local c = Atlas.blockCols(frames)
      local numberGrid = grid(stripData, fs, frames, c)
      local pal = paletteRow(b[5])
      if not pal then return nil end
      local t
      if gpuTrusted ~= false then
        t = decodeGpu(numberGrid, pal)
        if t and gpuTrusted == nil then
          -- once per session: the GPU's result must be the exact colours, else the CPU does it
          local want = decodeCpu(numberGrid, pal)
          gpuTrusted = t:newImageData():getString() == want:getString()
          if not gpuTrusted then
            if mod.log then mod.log:warn("GPU colour decode is not exact on this device; decoding on the CPU") end
            t = love.graphics.newImage(want)
          end
        elseif not t then
          gpuTrusted = false
        end
      end
      if not t then t = love.graphics.newImage(decodeCpu(numberGrid, pal)) end
      return t, c
    end)
    if not ok or not tex then
      if mod.log and not ok then mod.log:warn("could not build the pic block %s: %s", key, tostring(tex)) end
      return nil
    end
    -- dropped, not released, when the cache is full: a pic canvas or an HD tag may still draw it
    blocks[key] = { tex = tex, cols = cols }
    blockOrder[#blockOrder + 1] = key
    if #blockOrder > BLOCK_CAP then blocks[table.remove(blockOrder, 1)] = nil end
    return tex, cols
  end

  --- Where frame `f` of the cell is drawn from: the texture and the frame's top-left in it.
  local function frameSource(variant, cell, f)
    local fs = cell.fs
    if numbers then
      local tex, cols = block(variant, cell)
      if tex then return tex, (f % cols) * fs, math.floor(f / cols) * fs end
    end
    local img = page(string.format("battle_%s_%s", variant, cell.sheet))
    if not img then return nil end
    -- frame n of a species is cell start + n; cells are fs x fs, cols per row,
    -- in a block whose corner is (ox, oy) on the page
    local idx = (cell.start or 0) + f
    local cols = cell.cols or 1
    return img, (cell.ox or 0) + (idx % cols) * fs, (cell.oy or 0) + math.floor(idx / cols) * fs
  end
  self._frameSource = frameSource -- for the tests and tools

  -- The rendered pic frames, the least recently used dropped past CANVAS_CAP. A battle pic's
  -- canvas (a back, or a front for the battle: asked for again every frame, which is how it
  -- animates) is set aside when dropped and rendered into again for a frame of its shape, rather
  -- than left to the garbage collector: four battlers' animations (a double battle, a mod's raid)
  -- run through more frames than the cap, and a new canvas for each - ~30 a second - left hundreds
  -- for the collector to destroy in one frame, a hitch every few seconds. Any other pic is
  -- dropped, not released: whoever else still holds it (the save editor keeps the ones it has
  -- drawn) keeps a valid image, and the collector frees it once nothing does.
  local SPARE_CAP = 8          -- dropped battle canvases kept per shape, to render into again
  local useTick, count = 0, 0
  local used = {}              -- key -> its last use
  local shapeOf = setmetatable({}, { __mode = "k" })   -- a battle pic's canvas -> its shape
  local spare = {}             -- shape -> canvases to render into again
  local function touch(key)
    useTick = useTick + 1
    used[key] = useTick
  end
  local function remember(key, canvas)
    if self.frames[key] == nil then count = count + 1 end
    self.frames[key] = canvas
    touch(key)
    if count <= CANVAS_CAP then return end
    local old, oldT
    for k, t in pairs(used) do
      if k ~= key and (oldT == nil or t < oldT) then old, oldT = k, t end
    end
    if not old then return end
    local c = self.frames[old]
    self.frames[old], used[old] = nil, nil
    count = count - 1
    local shape = c and shapeOf[c]
    if shape then
      local list = spare[shape]
      if not list then
        list = {}
        spare[shape] = list
      end
      if #list < SPARE_CAP then list[#list + 1] = c end
    end
  end
  local function spareFor(shape)
    local list = spare[shape]
    local n = list and #list or 0
    if n == 0 then return nil end
    local c = list[n]
    list[n] = nil
    return c
  end

  -- After a window mode change (Atlas.watchWindow) every canvas made before it may be empty:
  -- the decoded blocks and the cached frames are dropped and made again when next asked for
  -- (a spare is cleared before it is drawn into, so it is kept), and a live pic redraws its
  -- canvas. Checked where a pic is asked for.
  local seenEpoch = Atlas.gfxEpoch()
  local function fresh()
    local n = Atlas.gfxEpoch()
    if n == seenEpoch then return end
    seenEpoch = n
    blocks, blockOrder = {}, {}
    for k in pairs(self.frames) do self.frames[k] = nil end
    used, count = {}, 0
    if self.dexPics then self.dexPics = {} end
    if self.iconPics then self.iconPics = {} end
    for _, rec in pairs(self.live or {}) do rec.f = nil end
  end
  self.fresh = fresh
  self.epoch = Atlas.gfxEpoch

  -- The cell for one species slot and variant ("front", "front_shiny", "back",
  -- "back_shiny"), or nil when the atlas has none. (The first argument is just
  -- a key: picFrame and icon cache by it.)
  function self.cell(slot, variant)
    local rec = bySlot[tonumber(slot)]
    return rec and rec.cells[variant] or nil
  end

  function self.hasSlot(slot)
    return bySlot[tonumber(slot)] ~= nil
  end

  -- Species ids to atlas keys, for the games that name a species by its id (Gen 1 / 2). The
  -- index's ids are the National Dex mods' own (NIDORAN_F, MR_MIME, RATTATA_ALOLA ...); a dex
  -- number finds its base species, the lowest slot with that number (forms and Unown's letters
  -- sit above it).
  local byId, byDex = {}, {}
  for key, rec in pairs(bySlot) do
    if key > 0 then
      byId[rec.id] = key
      local dex = tonumber(rec.cells.dex)
      if dex and (byDex[dex] == nil or key < byDex[dex]) then byDex[dex] = key end
    end
  end

  --- The atlas key for a species `id`, else for `base` (a form the atlas has no art for, a
  --- Mega say, shows its base species), else for its dex number; nil when it has none.
  function self.keyFor(id, dex, base)
    return (id ~= nil and byId[id]) or (base ~= nil and byId[base])
      or (tonumber(dex) and byDex[tonumber(dex)]) or nil
  end

  --- The key of a species' female sheet (Meowstic, Oinkologne ...), or nil.
  function self.femaleKey(key)
    local k = tonumber(key)
    return k and k > 0 and bySlot[-k] and -k or nil
  end

  -- Which frame plays now. Each cell has `frames`; the clock is shared, so
  -- every battler of one species animates in step.
  function self.frameIndex(cell)
    local n = math.max(1, cell.frames or 1)
    return math.floor(love.timer.getTime() * PIC_FPS) % n
  end

  -- Canvas creation can fail on a platform/GPU this was never tried on (an
  -- unsupported size or the dpiscale option, say). Logged once; after that,
  -- every pic the atlas draws quietly falls back to the game's own sprite
  -- instead of erroring out of the draw loop.
  local canvasFailed = false
  local function warnCanvas(where, err)
    if canvasFailed then return end
    canvasFailed = true
    if mod.log then
      mod.log:warn("could not create a canvas for atlas pics (%s): %s -- species "
        .. "the species it draws will show the game's own sprites instead", where, tostring(err))
    end
  end

  -- Runs fn(), which draws into a canvas, with the graphics state cleaned and then restored.
  -- A pic is rendered the first time it is asked for, which can be in the middle of another
  -- screen's draw: that screen's scissor, transform, shader and colour would otherwise apply
  -- to the canvas too (the save editor draws its party rows inside a scissor, and the sprite
  -- came out as a small clipped piece). push("all") also puts the previous canvas back.
  local function drawClean(fn)
    local G = love.graphics
    if not (G.push and G.pop) then return fn() end
    G.push("all")
    local ok, err = pcall(function()
      G.origin()
      if G.setScissor then G.setScissor() end
      if G.setShader then G.setShader() end
      if G.setBlendMode then G.setBlendMode("alpha") end
      G.setColor(1, 1, 1, 1)
      fn()
    end)
    G.pop()
    if not ok then error(err, 0) end
  end

  -- Halves the source until it is within 2x of the detailed box, one 2x2
  -- average per halving, so every pixel of the source contributes. A single
  -- bilinear step from a much larger frame samples only 2x2 of each block and
  -- reads as nearest-neighbour. Returns the (image, quad, w, h) to draw from,
  -- or nil when canvas creation fails.
  local function reduce(img, quad, w, h)
    local tmp = {}
    local box = PIC_BOX * PIC_SCALE
    while w / 2 >= box and h / 2 >= box do
      local nw, nh = math.floor(w / 2), math.floor(h / 2)
      local ok, c = pcall(love.graphics.newCanvas, nw, nh)
      if not ok then
        warnCanvas("reduce", c)
        for _, t in ipairs(tmp) do t:release() end
        return nil
      end
      c:setFilter("linear", "linear")
      local from, fromQuad, fromW, fromH = img, quad, w, h
      drawClean(function()
        love.graphics.setCanvas(c)
        love.graphics.clear(0, 0, 0, 0)
        if fromQuad then
          love.graphics.draw(from, fromQuad, 0, 0, 0, nw / fromW, nh / fromH)
        else
          love.graphics.draw(from, 0, 0, 0, nw / fromW, nh / fromH)
        end
      end)
      tmp[#tmp + 1] = c
      img, quad, w, h = c, nil, nw, nh
    end
    return img, quad, w, h, tmp
  end

  -- A canvas holding frame `f` of the cell. Front pics are bottom-centred at 1:1 with
  -- the game's pixels (shrunk only when they would overflow the box); back pics are
  -- a full-size close-up cut off at the bottom (Atlas.backLayout). It is stored at
  -- PIC_SCALE times the pic box and declared with dpiscale, so it reports
  -- 64x64 to the engine (whose draw origin is 32,32) and draws at full detail.
  -- `battle` (front pics only): the caller is the battle screen, which draws a pic with
  -- its centre on the battler's spot, so the pic may be full size in a canvas bigger
  -- than the box. Every other screen (Pokedex, summary, PC ...) draws the pic as a
  -- plain 64x64 image, so it gets the fit-to-box one.
  -- `kind` (front pics only): what the screen is ("dex" for the Pokedex screens). Every front pic
  -- off the battle screen is tagged for WoobleView (gen3-hd-sprites), which draws the ones its
  -- Pokedex and summary screens draw at window resolution (fitted to the box, the size the plain
  -- pic has); on any other screen the tagged canvas is simply drawn, as the plain pic.
  function self.picFrame(dex, variant, cell, f, battle, kind)
    fresh()
    local isBack = variant == "back" or variant == "back_shiny"
    local big = isBack or battle == true
    -- gen3-hd-sprites (when installed and on): the pic is drawn from the atlas at the
    -- window's resolution, so the canvas only has to be the low-res stand-in
    local hd = big and self.hd and self.hd.enabled("battle") and self.hd or nil
    local dexHd = not big and self.hd and self.hd.enabled("dex") and self.hd or nil
    -- battle pics sit by this game's offsets against FireRed's (Atlas.coordShift)
    local gdy = big and Atlas.coordShift[isBack and "back" or "front"][dex] or nil
    local key = tostring(dex) .. ":" .. variant .. ":" .. f
      .. (hd and ":hd" or big and ":w" or dexHd and ":dex" or "") .. (gdy and ":" .. gdy or "")
    local hit = self.frames[key]
    if hit then
      touch(key)
      return hit
    end
    local img, qx, qy = frameSource(variant, cell, f)
    if not img then return nil end
    local fs = cell.fs
    local quad = love.graphics.newQuad(qx, qy, fs, fs, img:getDimensions())
    local fw, fh = fs, fs
    local src, sq, w, h, temps = reduce(img, quad, fw, fh)
    if not src then return nil end
    -- the canvas is PIC_SCALE times the box in pixels, but drawing on a dpiscale
    -- canvas uses the logical box, so layout below is in PIC_BOX units
    -- 1:1 with the game's pixel grid (the atlas already holds game pixels), so a
    -- small species stays small; only a sprite larger than the box is reduced
    local s, ox, oy, wide, ls
    local own, all, real = tuned(dex)
    local xmin, xmax, ymin, ymax = 0, PIC_BOX, 0, PIC_BOX
    if hd then
      -- the same layout as the wide canvas, but the canvas stays the 64x64 box: the
      -- full frame is drawn by gen3-hd-sprites, this is only what shows if it cannot
      if isBack then
        -- its size scales about the feet line: hand-set, times realism, times `bn` (the back art
        -- brought to its own front art's size, so a Pokemon is the same size from both sides)
        local bn = 1
        if realismCfg.on ~= false and realismCfg.match_backs ~= false then bn = tonumber(cell.bn) or 1 end
        ls, ox, oy = Atlas.backLayout(cell, true, true, (tonumber(own.back) or 1) * real * bn, gdy)
      else
        ls, ox, oy = Atlas.frontLayout(cell, gdy)
      end
      s = ls / (w / fw)
    elseif not isBack and battle and BACK_WIDE and installDrawWrap() then
      local ls
      ls, ox, oy, xmin, xmax, ymin, ymax = Atlas.frontLayout(cell, gdy)
      s = ls / (w / fw)
    elseif isBack then
      -- a close-up at full size, cropped at the bottom (Atlas.backLayout); the layout
      -- is in source px, and `src` may be a reduced copy of the frame
      local ls
      wide = BACK_WIDE and installDrawWrap()
      ls, ox, oy, xmin, xmax, ymin, ymax = Atlas.backLayout(cell, wide, nil, nil, gdy)
      s = ls / (w / fw)
    else
      s = math.min(1, PIC_BOX / w, PIC_BOX / h)
      ox, oy = (PIC_BOX - w * s) / 2, PIC_BOX - h * s
    end
    -- px; bigger than the box only for a back pic whose animation needs the room. newCanvas
    -- takes its size in DPI-scaled units (LOVE 11): the box's own size, `dpi` times the pixels,
    -- so a host that fits the pic by its size (Kanto Gear's party) sees the 64x64 box
    local dpi = (xmax - xmin > PIC_BOX or ymax - ymin > PIC_BOX) and PIC_SCALE_BIG or PIC_SCALE
    local cw, ch = xmax - xmin, ymax - ymin
    -- (a battle pic: a dropped canvas of its shape rendered into again, else a new one)
    local shape = big and string.format("%s:%s:%s:%s", hd and "hd" or "w", cw, ch, dpi) or nil
    local canvas = shape and spareFor(shape)
    if not canvas then
      local okC, made = pcall(love.graphics.newCanvas, cw, ch, { dpiscale = dpi })
      if not okC then
        warnCanvas("picFrame", made)
        for _, t in ipairs(temps) do t:release() end
        return nil
      end
      canvas = made
      if shape then shapeOf[canvas] = shape end
    end
    -- (what a reused canvas was set up with before)
    pivots[canvas] = nil
    -- nearest, as the game draws its own pics: linear here blurs the sprite
    canvas:setFilter("nearest", "nearest")
    drawClean(function()
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 0)
      if sq then
        love.graphics.draw(src, sq, ox - xmin, oy - ymin, 0, s, s)
      else
        love.graphics.draw(src, ox - xmin, oy - ymin, 0, s, s)
      end
    end)
    for _, t in ipairs(temps) do t:release() end
    if hd then
      -- the point the HD frame is anchored on: the FEET (the resting pose's bottom row, `ffr`
      -- / `bfr`), so a size change (hand-set, realism) keeps the Pokemon standing on its pad
      local lx, ly
      if isBack then
        local cx = ((cell.cx0 or 0) + (cell.cx1 or fs)) / 2
        lx, ly = ox + ls * cx, oy + ls * (tonumber(cell.bfr) or fs / 2)
      else
        lx, ly = ox + ls * fs / 2, oy + ls * (tonumber(cell.ffr) or fs)
      end
      -- hand-tuned size and nudge (data/sprite_scale.lua); a back's own size and its realism
      -- are already in `ls` (backLayout); a front's realism carries the perspective factor too
      local mul = tonumber(isBack and all.back or all.front) or 1
      local dx = tonumber(isBack and own.back_dx or own.front_dx) or 0
      local dy = tonumber(isBack and own.back_dy or own.front_dy) or 0
      local k = 1
      if not isBack then
        local persp = realismCfg.on == false and 1 or (tonumber(realismCfg.front) or 1)
        k = (tonumber(own.front) or 1) * real * persp
      end
      hd.tag(canvas, {
        texture = img, quad = quad,
        lowPivot = { lx + dx, ly + dy },
        pivot = { (lx - ox) / ls, (ly - oy) / ls },
        scale = ls * k * mul,
        -- the first row of art over the whole animation: gen3-hd-sprites' Battle Fit pulls the
        -- camera back to fit the art, not the frame's empty margin above it
        top = tonumber(cell.uy0),
        -- whose Pokemon this is; a back's resting body box (frame px), which Battle Fit keeps
        -- mostly out from under the HP boxes and the text box
        side = isBack and "player" or "enemy",
        body = isBack and cell.cx0 and { cell.cx0, cell.cy0, cell.cx1, cell.cy1 } or nil,
      })
    elseif dexHd then
      -- the Pokedex and the summary: the whole frame at window resolution, fitted to the box exactly as the
      -- plain pic above is (whose canvas stays the stand-in), standing on the box's bottom-centre
      local spec = {
        texture = img, quad = quad,
        lowPivot = { PIC_BOX / 2, PIC_BOX },
        pivot = { fs / 2, fs },
        scale = math.min(1, PIC_BOX / fs),
      }
      dexHd.tag(canvas, spec)
      self.dexSpecs[canvas] = spec
    elseif xmin ~= 0 or xmax ~= PIC_BOX or ymin ~= 0 or ymax ~= PIC_BOX then
      pivots[canvas] = { PIC_BOX / 2 - xmin, PIC_BOX / 2 - ymin }
    end
    remember(key, canvas)
    return canvas
  end

  --- A species' own record in the index (its dex, height, `fl` floats, `pm` pack metrics ...).
  function self.info(key)
    local rec = bySlot[tonumber(key)]
    return rec and rec.cells or nil
  end

  -- The pack's contact shadows (assets/shadow/1..3.png: small, medium, large), each with the
  -- box of its opaque pixels. Loaded once; false when one cannot be.
  local shadows = {}
  local function shadowArt(n)
    local hit = shadows[n]
    if hit ~= nil then return hit or nil end
    shadows[n] = false
    local ok, data = pcall(love.image.newImageData, mod.path .. "/assets/shadow/" .. n .. ".png")
    if not (ok and data) then return nil end
    local w, h = data:getDimensions()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < x0 then return nil end
    local okI, img = pcall(love.graphics.newImage, data)
    if not okI then return nil end
    img:setFilter("nearest", "nearest")
    shadows[n] = { image = img, quad = love.graphics.newQuad(x0, y0, x1 - x0 + 1, y1 - y0 + 1, w, h),
                   cw = x1 - x0 + 1, ch = y1 - y0 + 1 }
    return shadows[n]
  end

  local FLOAT_LIFT, FLOAT_LIFT_MIN = 0.35, 2        -- a floater's lift: share of its height, px
  local PACK_FRONT, PACK_BACK = 2, 3                -- the pack's own render scale (its metrics)
  local SHADOW_W = { base = 0.55, step = 0.10, neg = 0.05, min = 0.15, max = 1 }

  -- The Game Boy's four shades, by brightness: Gen 1's colour pass recolours a pic by its
  -- shade (the red channel: above 0.83, 0.5, 0.17), so full-colour art it does not keep as it
  -- is would come out in blotches. Drawn through this, the art is the cart's kind of pic, and
  -- the pass colours it with the species' palette as it does the game's own.
  local shadesShader = nil
  function self.shadesShader()
    if shadesShader == nil then
      shadesShader = false
      if love.graphics.newShader then
        local ok, sh = pcall(love.graphics.newShader, [[
          vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 p = Texel(tex, tc) * color;
            float y = dot(p.rgb, vec3(0.299, 0.587, 0.114));
            float q = y > 0.75 ? 1.0 : (y > 0.5 ? 0.6667 : (y > 0.25 ? 0.3333 : 0.0));
            return vec4(q, q, q, p.a);
          }
        ]])
        if ok then shadesShader = sh end
      end
    end
    return shadesShader or nil
  end

  --- Frame `f` of a cell fitted to a bw x bh box, for the games whose screens draw a pic as a
  --- plain image of the box's size (Gen 1 / 2): none of Gen 3's placement data is used. The
  --- art's union over the whole animation (ux0..uy1) is what is placed, so the Pokemon stays
  --- still in its box while it animates; it is drawn as tectorifter's g9-battle-sprites drew it.
  ---   opts.divisor  0 (default): 1:1, shrunk only to fit; n: the art divided by n, still fitted
  ---   opts.anchor   "feet" (default) or "box": the art bottom-centred in the box; "pack": moved
  ---                 by the pack's own SpeciesMetrics (the record's `pm`)
  ---   opts.float    "feet" only: a floating species (`fl`) is lifted by a share of its height
  ---   opts.shadow   the pack's contact shadow behind it, on the box's bottom (a battle pic)
  ---   opts.shrink   a further factor (the summary's size option), 1 by default
  ---   opts.mirror   flipped left to right
  ---   opts.dpi      the canvas's dpiscale (1: the game's own pixels)
  ---   opts.silhouette  all black (Gen 1's credits show each Pokemon as a silhouette)
  ---   opts.shades   in the Game Boy's four shades (shadesShader), for the game's colour pass
  ---   opts.reuse    a battle pic (asked for every frame): its canvas is rendered into again
  ---                 once dropped, as picFrame's battle canvases are
  ---   opts.hdSide   a battle pic in its own colours: "enemy" / "player". With WoobleView
  ---                 (gen3-hd-sprites) on for battles, the canvas is tagged so WoobleView draws
  ---                 the full frame at window resolution where the canvas is drawn (the canvas
  ---                 stays the stand-in it shows when it cannot). Not for a shaded frame or a
  ---                 silhouette (the tag has no shade of its own), and a mirrored one only
  ---                 where WoobleView has `features.flip`.
  ---   opts.hdDex    a Pokedex / summary pic: tagged the same way (no side) when WoobleView is
  ---                 on for its "dex" pass; a shaded one too where it has `features.shades`
  ---                 (the tag carries the shades shader). Not with the shadow or a silhouette.
  --- Nearest-neighbour throughout, as the game draws its own pics. nil when the atlas has no
  --- such frame or a canvas cannot be made.
  function self.boxFrame(key, variant, f, bw, bh, opts)
    fresh()
    opts = opts or {}
    local cell = self.cell(key, variant)
    if not cell then return nil end
    local info = self.info(key) or {}
    local isBack = variant == "back" or variant == "back_shiny"
    local anchor = (opts.anchor == "pack" or opts.anchor == "box") and opts.anchor or "feet"
    local div = tonumber(opts.divisor) or 0
    local shrink = tonumber(opts.shrink) or 1
    local float = anchor == "feet" and opts.float and info.fl and true or false
    local pm = anchor == "pack" and type(info.pm) == "table" and info.pm or nil
    local shadowSize = type(info.pm) == "table" and tonumber(info.pm.sz) or 1
    local shadow = opts.shadow and shadowSize ~= 0
      and shadowArt(math.max(1, math.min(3, shadowSize))) or nil
    local mirror = opts.mirror and true or false
    local dpi = tonumber(opts.dpi) or 1
    local black = opts.silhouette and true or false
    local shades = not black and opts.shades and self.shadesShader() or nil
    -- WoobleView: a battle pic (hdSide) in its own colours, or a Pokedex / summary pic (hdDex),
    -- shaded too where WoobleView can draw through the shades shader (`features.shades`).
    -- Never a silhouette. (The shadow is in the stand-in only: a battle pic is tagged with it
    -- all the same, a Pokedex / summary pic is not)
    local hd, hdPass = nil, opts.hdSide and "battle" or opts.hdDex and "dex" or nil
    if hdPass and self.hd and not black and not (shadow and hdPass == "dex") then
      local okH, live = pcall(function()
        local feats = type(self.hd.features) == "table" and self.hd.features or {}
        if shades and not (hdPass == "dex" and feats.shades == true) then return false end
        if opts.shades and not shades then return false end
        -- (a mirrored frame only where WoobleView can mirror it: its `flip` spec field)
        return (self.hd.isActive == nil or self.hd.isActive()) and self.hd.enabled(hdPass)
          and (not mirror or feats.flip == true)
      end)
      if okH and live then hd = self.hd end
    end
    local ckey = string.format("box:%s:%s:%d:%dx%d:%s:%g:%g:%s:%s:%s:%g:%s%s%s", tostring(key), variant, f,
      bw, bh, anchor, div, shrink, float and "f" or "", shadow and "s" or "", mirror and "m" or "",
      dpi, black and "k" or "", shades and "g" or "",
      hd and (opts.hdSide and ":hd:" .. opts.hdSide or ":dex") or "")
    local hit = self.frames[ckey]
    if hit then
      touch(ckey)
      return hit
    end
    local img, qx, qy = frameSource(variant, cell, f)
    if not img then return nil end
    local fs = cell.fs
    local x0, y0, x1, y1 = 0, 0, fs, fs
    if cell.ux0 then x0, y0, x1, y1 = cell.ux0, cell.uy0, cell.ux1, cell.uy1 end
    local cw, ch = math.max(1, x1 - x0), math.max(1, y1 - y0)
    -- the size: 1:1 when it fits (never larger), else shrunk to fit; or divided by `div`
    local s = math.min(div > 0 and 1 / div or 1, bw / cw, bh / ch) * shrink
    local dw, dh = math.max(1, math.floor(cw * s + 0.5)), math.max(1, math.floor(ch * s + 0.5))
    -- the place: bottom-centred, then moved by the pack's metrics (in the pack's own units,
    -- `offset * 2 / its render scale` sheet px, with the margins the union trimmed put back)
    -- or lifted off the bottom when it floats; kept inside the box
    local offX, offY = 0, 0
    if pm then
      local d = isBack and PACK_BACK or PACK_FRONT
      local mx, my = tonumber(isBack and pm.bx or pm.fx), tonumber(isBack and pm.by or pm.fy)
      if mx then offX = mx * 2 / d - ((fs - x1) - x0) / 2 end
      if my then offY = my * 2 / d - (fs - y1) end
    elseif float then
      offY = -math.max(FLOAT_LIFT_MIN, math.floor(ch * FLOAT_LIFT + 0.5))
    end
    local ox = math.floor((bw - dw) / 2 + offX * s)
    local oy = math.floor(bh - dh + offY * s)
    ox = math.max(0, math.min(bw - dw, ox))
    oy = math.max(0, math.min(bh - dh, oy))
    local shape = opts.reuse and string.format("box:%dx%d:%g", bw, bh, dpi) or nil
    local canvas = shape and spareFor(shape)
    if not canvas then
      local okC, made = pcall(love.graphics.newCanvas, bw, bh, { dpiscale = dpi })
      if not okC then
        warnCanvas("boxFrame", made)
        return nil
      end
      canvas = made
      if shape then shapeOf[canvas] = shape end
    end
    canvas:setFilter("nearest", "nearest")
    local quad = love.graphics.newQuad(qx, qy, fs, fs, img:getDimensions())
    -- the page is sampled nearest for this draw only (it keeps its own filter for picFrame)
    local fmin, fmag = img:getFilter()
    img:setFilter("nearest", "nearest")
    drawClean(function()
      local G = love.graphics
      G.setCanvas(canvas)
      G.clear(0, 0, 0, 0)
      if mirror then
        G.translate(bw, 0)
        G.scale(-1, 1)
      end
      if shades then G.setShader(shades) end
      if shadow and not black then
        -- the shadow first, so the Pokemon is drawn over it: a share of its width (by the
        -- pack's ShadowSize), on the box's bottom, under its middle plus the pack's x offset
        local frac = shadowSize >= 1 and SHADOW_W.base + (shadowSize - 1) * SHADOW_W.step
          or SHADOW_W.base + shadowSize * SHADOW_W.neg
        frac = math.max(SHADOW_W.min, math.min(SHADOW_W.max, frac))
        local sW = math.max(3, math.floor(dw * frac + 0.5))
        local k = sW / shadow.cw
        local sH = math.max(1, math.floor(shadow.ch * k + 0.5))
        local d = isBack and PACK_BACK or PACK_FRONT
        local shX = (tonumber(type(info.pm) == "table" and info.pm.sx) or 0) * 2 / d * s
        G.draw(shadow.image, shadow.quad, math.floor(ox + dw / 2 + shX - sW / 2 + 0.5), bh - sH, 0, k, k)
      end
      if black then G.setColor(0, 0, 0, 1) end
      G.draw(img, quad, ox - x0 * s, oy - y0 * s, 0, s, s)
    end)
    img:setFilter(fmin, fmag)
    if hd then
      -- anchored on the FEET (the resting pose's bottom row, `ffr` / `bfr`; a back's x is its
      -- body's centre), where they sit in the stand-in, in its own units (the box's px)
      local px, py
      if isBack then
        px, py = ((cell.cx0 or 0) + (cell.cx1 or fs)) / 2, tonumber(cell.bfr) or fs / 2
      else
        px, py = fs / 2, tonumber(cell.ffr) or fs
      end
      local bx, by = ox - x0 * s, oy - y0 * s
      local lx = bx + px * s
      local spec = {
        texture = img, quad = quad,
        pivot = { px, py },
        -- (a mirrored stand-in: its feet mirrored about the box; WoobleView mirrors the frame
        -- about its pivot)
        lowPivot = { mirror and bw - lx or lx, by + py * s },
        flip = mirror or nil,
        scale = s,
        -- (the four shades: WoobleView draws the frame through the same shader)
        shades = shades or nil,
      }
      if opts.hdSide then
        spec.top = tonumber(cell.uy0)
        spec.side = opts.hdSide
        spec.body = isBack and cell.cx0 and { cell.cx0, cell.cy0, cell.cx1, cell.cy1 } or nil
      end
      pcall(hd.tag, canvas, spec)
    elseif self.hd and type(self.hd.untag) == "function" then
      -- (a reused canvas may carry an earlier frame's tag)
      pcall(self.hd.untag, canvas)
    end
    remember(ckey, canvas)
    return canvas
  end

  -- The box of an icon frame's opaque pixels in its cell, { x, y, w, h } (cached), or nil when
  -- the page cannot be read: other mods crop a portrait from the icon by it.
  local iconData, iconBoxes = {}, {}
  function self.iconBox(key, f)
    local cell = self.cell(key, "icon")
    if not cell then return nil end
    local id = tostring(key) .. ":" .. tostring(f)
    if iconBoxes[id] ~= nil then return iconBoxes[id] or nil end
    iconBoxes[id] = false
    local data = iconData[cell.page]
    if data == nil then
      local ok, d = pcall(love.image.newImageData,
        mod.path .. "/assets/atlas/party_icons_" .. tostring(cell.page) .. ".png")
      data = ok and d or false
      iconData[cell.page] = data
    end
    if not data then return nil end
    local size = cell.cell or 32
    local cx, cy = cell.x + (f or 0) * size, cell.y
    local x0, y0, x1, y1 = size, size, -1, -1
    for y = 0, size - 1 do
      for x = 0, size - 1 do
        local _, _, _, a = data:getPixel(cx + x, cy + y)
        if a > 0 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    if x1 < x0 then return nil end
    iconBoxes[id] = { x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }
    return iconBoxes[id]
  end

  -- The engine's icon entry for an atlas icon cell: two frames side by side in
  -- the icon page, each a cell x cell quad.
  local function iconEntry(cell)
    local img = page(string.format("party_icons_%d", cell.page))
    if not img then return nil end
    local w, h = img:getDimensions()
    local size = cell.cell or 32
    local quads = {}
    for f = 0, (cell.frames or 2) - 1 do
      quads[f] = love.graphics.newQuad(cell.x + f * size, cell.y, size, size, w, h)
    end
    return { image = img, w = size, h = size, sheetH = h,
             frames = cell.frames or 2, quads = quads }
  end

  -- The icon entry for a species slot, cached per slot.
  function self.icon(dex)
    dex = tonumber(dex)
    if self.icons[dex] ~= nil then return self.icons[dex] or nil end
    local cell = self.cell(dex, "icon")
    local entry = cell and iconEntry(cell)
    if not entry then self.icons[dex] = false return nil end
    self.icons[dex] = entry
    return entry
  end

  -- The Ruby/Sapphire/Emerald Pokedex builds an entry's pic ONCE (when the page opens) and
  -- keeps that image, so a pic for one frame would stand still. It gets a "live" canvas
  -- instead, redrawn with the current frame each time the screen draws (refreshLive, from the
  -- hooks' wrap of the screen's draw): the cart's two-frame front pic, or for a species without
  -- one the battle sheet (whose gen3-hd-sprites tag then follows the frame). The wheel's
  -- sprites are live too: opening an entry slides the wheel's sprite over and keeps its image.
  -- The last LIVE_CAP asked for are kept.
  local LIVE_CAP = 24          -- a FORMS page shows up to 9 at once (Alcremie)
  self.dexSpecs = setmetatable({}, { __mode = "k" })   -- frame canvas -> its Pokedex HD spec
  self.live, self.liveOrder = {}, {}

  -- The game's own front pic for a Gen 1-3 slot: function(key, f, personality) -> frame f's
  -- 64x64 image, or nil (not a Gen 1-3 slot, or no such frame). Set by the hooks: these pics
  -- are not packed, the game already has them.
  self.cartFrame = nil

  -- The cart's front pic: frame f (0 or 1) as a 64x64 image, or nil when the species has none.
  -- #387+ come from dex_fronts_<n>.png (pokeemerald-expansion), cached two per species;
  -- Gen 1-3 from cartFrame (the game caches its own).
  self.dexPics = {}
  function self.dexPic(key, f, personality)
    fresh()
    local c = self.cell(key, "dexpic")
    if not c and self.cartFrame then
      local ok, img = pcall(self.cartFrame, key, f, personality)
      if ok and img then return img end
    end
    local id = tostring(key) .. ":" .. f
    local hit = self.dexPics[id]
    if hit ~= nil then return hit or nil end
    local img = c and page(string.format("dex_fronts_%d", c.page))
    local ok, canvas = false, nil
    if img then ok, canvas = pcall(love.graphics.newCanvas, PIC_BOX, PIC_BOX) end
    if not (img and ok) then self.dexPics[id] = false return nil end
    canvas:setFilter("nearest", "nearest")
    local w, h = img:getDimensions()
    local quad = love.graphics.newQuad(c.x + f * PIC_BOX, c.y, PIC_BOX, PIC_BOX, w, h)
    drawClean(function()
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.draw(img, quad, 0, 0)
    end)
    self.dexPics[id] = canvas
    return canvas
  end

  -- function() -> true while the cart pics hold their first frame (the RSE Pokedex wheel: its
  -- sprites become the entry's when one opens, so they are live, but still until then). Set by
  -- the hooks.
  self.holdLive = nil

  local function refresh(rec)
    if rec.dex then
      -- the cart pic: its two frames in turn (never HD: it is 64x64 already)
      local f = math.floor(love.timer.getTime() / DEX_FRAME_TIME) % 2
      if self.holdLive and self.holdLive() then f = 0 end
      if f == rec.f then return end
      local src = self.dexPic(rec.key, f, rec.personality) or self.dexPic(rec.key, 0, rec.personality)
      if not src then return end
      drawClean(function()
        love.graphics.setCanvas(rec.canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.draw(src, 0, 0)
      end)
      rec.f = f
      return
    end
    local f = self.frameIndex(rec.cell)
    local hdOn = self.hd and self.hd.enabled("dex") and true or false
    if f == rec.f and hdOn == rec.hdOn then return end
    local src = self.picFrame(rec.key, rec.variant, rec.cell, f, false, "dex")
    if not src then return end
    drawClean(function()
      love.graphics.setCanvas(rec.canvas)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.draw(src, 0, 0)
    end)
    rec.f, rec.hdOn = f, hdOn
    if self.hd then
      local spec = self.dexSpecs[src]
      if spec then self.hd.tag(rec.canvas, spec) elseif self.hd.untag then self.hd.untag(rec.canvas) end
    end
  end

  --- A live pic for an RSE Pokedex entry: the cart's two-frame front pic when the species has
  --- one (`variant` is then ignored: the Pokedex never shows a shiny), else the battle sheet.
  --- `personality`: handed to the game's own pic (Spinda's spots), one live canvas each.
  function self.livePic(key, variant, cell, personality)
    fresh()
    local dex = self.dexPic(key, 0, personality) ~= nil
    local id = tostring(key) .. ":" .. (dex and ("dexpic:" .. tostring(personality or 0)) or variant)
    local rec = self.live[id]
    if not rec then
      local ok, c
      if dex then
        ok, c = pcall(love.graphics.newCanvas, PIC_BOX, PIC_BOX)
      else
        ok, c = pcall(love.graphics.newCanvas, PIC_BOX, PIC_BOX, { dpiscale = PIC_SCALE })
      end
      if not ok then return nil end
      c:setFilter("nearest", "nearest")
      rec = { canvas = c, key = key, variant = variant, cell = cell, dex = dex, personality = personality }
      self.live[id] = rec
      self.liveOrder[#self.liveOrder + 1] = id
      if #self.liveOrder > LIVE_CAP then self.live[table.remove(self.liveOrder, 1)] = nil end
    else
      -- asked for again: the last to be dropped (the wheel asks for each row as it scrolls in)
      for i, v in ipairs(self.liveOrder) do
        if v == id then table.remove(self.liveOrder, i) break end
      end
      self.liveOrder[#self.liveOrder + 1] = id
    end
    refresh(rec)
    return rec.canvas
  end

  function self.refreshLive()
    fresh()
    for _, rec in pairs(self.live) do refresh(rec) end
  end

  -- A 64x64 pic made of a species' party icon (its first frame at 2x, nearest), for screens that
  -- list many Pokemon (the RSE Pokedex wheel) and should not play the full animated sheet.
  -- Cached per slot; nil when the atlas has no icon for it.
  function self.iconPic(dex)
    fresh()
    dex = tonumber(dex)
    self.iconPics = self.iconPics or {}
    if self.iconPics[dex] ~= nil then return self.iconPics[dex] or nil end
    local entry = self.icon(dex)
    local ok, canvas = false, nil
    if entry then ok, canvas = pcall(love.graphics.newCanvas, PIC_BOX, PIC_BOX) end
    if not (entry and ok) then self.iconPics[dex] = false return nil end
    canvas:setFilter("nearest", "nearest")
    local k = PIC_BOX / entry.w
    drawClean(function()
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.draw(entry.image, entry.quads[0], 0, 0, 0, k, k)
    end)
    self.iconPics[dex] = canvas
    return canvas
  end

  return self
end

return Atlas
