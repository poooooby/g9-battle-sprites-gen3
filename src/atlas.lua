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
function Atlas.backLayout(cell, wide, exact, force)
  local fs = cell.fs or PIC_BOX
  local x0, y0 = cell.cx0 or 0, cell.cy0 or 0
  local x1, y1 = cell.cx1 or fs, cell.cy1 or fs
  local cw, ch = math.max(1, x1 - x0), math.max(1, y1 - y0)
  local s, oy, anchorX, zoomTop
  if cell.bt then
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
function Atlas.frontLayout(cell)
  local fs = cell.fs or PIC_BOX
  local drop = cell.fy or 0       -- a species drawn lower than its frame's bottom edge puts it
  local ox, oy = (PIC_BOX - fs) / 2, PIC_BOX - fs + drop
  local m = BACK_WIDE_MAX
  local xmin = math.max(-m, math.min(0, math.floor(ox)))
  local xmax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(ox + fs)))
  local ymin = math.max(-m, math.min(0, math.floor(oy)))
  local ymax = math.min(PIC_BOX + m, math.max(PIC_BOX, math.ceil(oy + fs)))
  return 1, ox, oy, xmin, xmax, ymin, ymax
end

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

-- mod: the mod table (for mod.path and mod.log); load: loadSibling-style reader
function Atlas.new(mod, load)
  local bySlot = loadIndex(load)
  if not bySlot then return nil end

  local self = { pages = {}, icons = {}, frames = {}, order = {} }

  -- Hand-tuned sizes (data/sprite_scale.lua), used with gen3-hd-sprites. A missing or broken
  -- file just means the defaults.
  local tuning = {}
  do
    local ok, t = pcall(load, "data/sprite_scale.lua")
    if ok and type(t) == "table" then tuning = t end
  end
  -- how far each enemy front pic is raised so its feet are no lower than the platform's
  -- centre (data/front_anchor.lua, tools/front_anchor.py); sprite_scale.lua's front_dy wins
  local anchors = {}
  do
    local ok, t = pcall(load, "data/front_anchor.lua")
    if ok and type(t) == "table" then anchors = t end
  end
  local function tuned(slot)
    local rec = bySlot[tonumber(slot)]
    local own = rec and tuning[rec.id]
    local all = type(tuning.all) == "table" and tuning.all or {}
    return type(own) == "table" and own or {}, all, rec and anchors[rec.id] or 0
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

  local function remember(key, canvas)
    self.frames[key] = canvas
    self.order[#self.order + 1] = key
    if #self.order > CANVAS_CAP then
      local old = table.remove(self.order, 1)
      -- dropped, not released: whoever else still holds this picture (the save
      -- editor keeps the ones it has drawn) keeps a valid image, and the garbage
      -- collector frees it once nothing does
      self.frames[old] = nil
    end
  end

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
  -- `kind` (front pics only): "dex" for the Pokedex screens, which gen3-hd-sprites draws at
  -- window resolution too (fitted to the box, the size the plain pic has).
  function self.picFrame(dex, variant, cell, f, battle, kind)
    local isBack = variant == "back" or variant == "back_shiny"
    local big = isBack or battle == true
    -- gen3-hd-sprites (when installed and on): the pic is drawn from the atlas at the
    -- window's resolution, so the canvas only has to be the low-res stand-in
    local hd = big and self.hd and self.hd.enabled("battle") and self.hd or nil
    local dexHd = not big and kind == "dex" and self.hd and self.hd.enabled("dex") and self.hd or nil
    local key = tostring(dex) .. ":" .. variant .. ":" .. f
      .. (hd and ":hd" or big and ":w" or dexHd and ":dex" or "")
    local hit = self.frames[key]
    if hit then return hit end
    local img = page(string.format("battle_%s_%s", variant, cell.sheet))
    if not img then return nil end
    local fs = cell.fs
    -- frame n of a species is cell start + n; cells are fs x fs, cols per row,
    -- in a block whose corner is (ox, oy) on the page
    local idx = (cell.start or 0) + f
    local cols = cell.cols or 1
    local quad = love.graphics.newQuad((cell.ox or 0) + (idx % cols) * fs,
      (cell.oy or 0) + math.floor(idx / cols) * fs,
      fs, fs, img:getDimensions())
    local fw, fh = fs, fs
    local src, sq, w, h, temps = reduce(img, quad, fw, fh)
    if not src then return nil end
    -- the canvas is PIC_SCALE times the box in pixels, but drawing on a dpiscale
    -- canvas uses the logical box, so layout below is in PIC_BOX units
    -- 1:1 with the game's pixel grid (the atlas already holds game pixels), so a
    -- small species stays small; only a sprite larger than the box is reduced
    local s, ox, oy, wide, ls
    local own, all, autoDy = tuned(dex)
    local xmin, xmax, ymin, ymax = 0, PIC_BOX, 0, PIC_BOX
    if hd then
      -- the same layout as the wide canvas, but the canvas stays the 64x64 box: the
      -- full frame is drawn by gen3-hd-sprites, this is only what shows if it cannot
      if isBack then
        ls, ox, oy = Atlas.backLayout(cell, true, true, tonumber(own.back))
      else
        ls, ox, oy = Atlas.frontLayout(cell)
      end
      s = ls / (w / fw)
    elseif not isBack and battle and BACK_WIDE and installDrawWrap() then
      local ls
      ls, ox, oy, xmin, xmax, ymin, ymax = Atlas.frontLayout(cell)
      s = ls / (w / fw)
    elseif isBack then
      -- a close-up at full size, cropped at the bottom (Atlas.backLayout); the layout
      -- is in source px, and `src` may be a reduced copy of the frame
      local ls
      wide = BACK_WIDE and installDrawWrap()
      ls, ox, oy, xmin, xmax, ymin, ymax = Atlas.backLayout(cell, wide)
      s = ls / (w / fw)
    else
      s = math.min(1, PIC_BOX / w, PIC_BOX / h)
      ox, oy = (PIC_BOX - w * s) / 2, PIC_BOX - h * s
    end
    -- px; bigger than the box only for a back pic whose animation needs the room
    local dpi = (xmax - xmin > PIC_BOX or ymax - ymin > PIC_BOX) and PIC_SCALE_BIG or PIC_SCALE
    local okC, canvas = pcall(love.graphics.newCanvas, (xmax - xmin) * dpi,
      (ymax - ymin) * dpi, { dpiscale = dpi })
    if not okC then
      warnCanvas("picFrame", canvas)
      for _, t in ipairs(temps) do t:release() end
      return nil
    end
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
      -- the point the HD frame is anchored on: the feet (bottom-centre of the frame) for a
      -- front, so a size change keeps it standing on its spot; the box's centre for a back
      local lx, ly
      if isBack then
        lx, ly = PIC_BOX / 2, PIC_BOX / 2
      else
        lx, ly = ox + ls * fs / 2, oy + ls * fs
      end
      -- hand-tuned size and nudge (data/sprite_scale.lua)
      local mul = tonumber(isBack and all.back or all.front) or 1
      local dx = tonumber(isBack and own.back_dx or own.front_dx) or 0
      local dy = tonumber(isBack and own.back_dy or own.front_dy) or (isBack and 0 or autoDy)
      local k = isBack and 1 or (tonumber(own.front) or 1)
      hd.tag(canvas, {
        texture = img, quad = quad,
        lowPivot = { lx + dx, ly + dy },
        pivot = { (lx - ox) / ls, (ly - oy) / ls },
        scale = ls * k * mul,
      })
    elseif dexHd then
      -- the Pokedex: the whole frame at window resolution, fitted to the box exactly as the
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
  -- one the battle sheet (whose gen3-hd-sprites tag then follows the frame). The last LIVE_CAP
  -- are kept.
  local LIVE_CAP = 6
  self.dexSpecs = setmetatable({}, { __mode = "k" })   -- frame canvas -> its Pokedex HD spec
  self.live, self.liveOrder = {}, {}

  -- The cart's front pic (pokeemerald-expansion, built into dex_fronts_<n>.png): frame f (0 or
  -- 1) as a 64x64 canvas, or nil when the species has none. Cached, two per species.
  self.dexPics = {}
  function self.dexPic(key, f)
    local id = tostring(key) .. ":" .. f
    local hit = self.dexPics[id]
    if hit ~= nil then return hit or nil end
    local c = self.cell(key, "dexpic")
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

  local function refresh(rec)
    if rec.dex then
      -- the cart pic: its two frames in turn, as the game's own (never HD: it is 64x64 already)
      local f = math.floor(love.timer.getTime() / DEX_FRAME_TIME) % 2
      if f == rec.f then return end
      local src = self.dexPic(rec.key, f) or self.dexPic(rec.key, 0)
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
  function self.livePic(key, variant, cell)
    local dex = self.cell(key, "dexpic") ~= nil
    local id = tostring(key) .. ":" .. (dex and "dexpic" or variant)
    local rec = self.live[id]
    if not rec then
      local ok, c
      if dex then
        ok, c = pcall(love.graphics.newCanvas, PIC_BOX, PIC_BOX)
      else
        ok, c = pcall(love.graphics.newCanvas, PIC_BOX * PIC_SCALE, PIC_BOX * PIC_SCALE,
          { dpiscale = PIC_SCALE })
      end
      if not ok then return nil end
      c:setFilter("nearest", "nearest")
      rec = { canvas = c, key = key, variant = variant, cell = cell, dex = dex }
      self.live[id] = rec
      self.liveOrder[#self.liveOrder + 1] = id
      if #self.liveOrder > LIVE_CAP then self.live[table.remove(self.liveOrder, 1)] = nil end
    end
    refresh(rec)
    return rec.canvas
  end

  function self.refreshLive()
    for _, rec in pairs(self.live) do refresh(rec) end
  end

  -- A 64x64 pic made of a species' party icon (its first frame at 2x, nearest), for screens that
  -- list many Pokemon (the RSE Pokedex wheel) and should not play the full animated sheet.
  -- Cached per slot; nil when the atlas has no icon for it.
  function self.iconPic(dex)
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
