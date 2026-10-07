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
local PIC_FPS = 8           -- animation rate of the sheets, frames per second
local CANVAS_CAP = 128      -- most rendered pic frames kept at once

local function loadIndex(load)
  local index = load("data/atlas_index.lua")
  if type(index) ~= "table" or type(index.species) ~= "table" then return nil end
  local byDex = {}
  for id, rec in pairs(index.species) do
    if type(rec) == "table" and tonumber(rec.dex) then
      byDex[tonumber(rec.dex)] = { id = id, cells = rec }
    end
  end
  return byDex
end

-- mod: the mod table (for mod.path and mod.log); load: loadSibling-style reader
function Atlas.new(mod, load)
  local byDex = loadIndex(load)
  if not byDex then return nil end

  local self = { pages = {}, icons = {}, frames = {}, order = {} }

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
      local c = self.frames[old]
      self.frames[old] = nil
      if c and c.release then c:release() end
    end
  end

  -- The cell for one dex number and variant ("front", "front_shiny", "back",
  -- "back_shiny"), or nil when the atlas has none.
  function self.cell(dex, variant)
    local rec = byDex[tonumber(dex)]
    return rec and rec.cells[variant] or nil
  end

  function self.hasDex(dex)
    return byDex[tonumber(dex)] ~= nil
  end

  -- Which frame plays now. Each cell has `frames`; the clock is shared, so
  -- every battler of one species animates in step.
  function self.frameIndex(cell)
    local n = math.max(1, cell.frames or 1)
    return math.floor(love.timer.getTime() * PIC_FPS) % n
  end

  -- Halves the source until it is within 2x of the detailed box, one 2x2
  -- average per halving, so every pixel of the source contributes. A single
  -- bilinear step from a much larger frame samples only 2x2 of each block and
  -- reads as nearest-neighbour. Returns the (image, quad, w, h) to draw from.
  local function reduce(img, quad, w, h)
    local tmp = {}
    local box = PIC_BOX * PIC_SCALE
    while w / 2 >= box and h / 2 >= box do
      local nw, nh = math.floor(w / 2), math.floor(h / 2)
      local c = love.graphics.newCanvas(nw, nh)
      c:setFilter("linear", "linear")
      local prev = love.graphics.getCanvas()
      love.graphics.setCanvas(c)
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      if quad then
        love.graphics.draw(img, quad, 0, 0, 0, nw / w, nh / h)
      else
        love.graphics.draw(img, 0, 0, 0, nw / w, nh / h)
      end
      love.graphics.setCanvas(prev)
      tmp[#tmp + 1] = c
      img, quad, w, h = c, nil, nw, nh
    end
    return img, quad, w, h, tmp
  end

  -- A canvas holding frame `f` of the cell, bottom-centred, at 1:1 with the game's
  -- pixels (shrunk only when it would overflow the box). It is stored at
  -- PIC_SCALE times the pic box and declared with dpiscale, so it reports
  -- 64x64 to the engine (whose draw origin is 32,32) and draws at full detail.
  function self.picFrame(dex, variant, cell, f)
    local key = tostring(dex) .. ":" .. variant .. ":" .. f
    local hit = self.frames[key]
    if hit then return hit end
    local img = page(string.format("battle_%s_%d", variant, cell.sheet))
    if not img then return nil end
    local fs = cell.fs
    -- frame n of a species is cell start + n; cells are fs x fs, cols per row
    local idx = (cell.start or 0) + f
    local cols = cell.cols or 1
    local quad = love.graphics.newQuad((idx % cols) * fs, math.floor(idx / cols) * fs,
      fs, fs, img:getDimensions())
    local fw, fh = fs, fs
    local src, sq, w, h, temps = reduce(img, quad, fw, fh)
    -- the canvas is PIC_SCALE times the box in pixels, but drawing on a dpiscale
    -- canvas uses the logical box, so layout below is in PIC_BOX units
    -- 1:1 with the game's pixel grid (the atlas already holds game pixels), so a
    -- small species stays small; only a sprite larger than the box is reduced
    local s = math.min(1, PIC_BOX / w, PIC_BOX / h)
    local canvas = love.graphics.newCanvas(PIC_BOX * PIC_SCALE, PIC_BOX * PIC_SCALE,
      { dpiscale = PIC_SCALE })
    -- nearest, as the game draws its own pics: linear here blurs the sprite
    canvas:setFilter("nearest", "nearest")
    local prev = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    local ox, oy = (PIC_BOX - w * s) / 2, PIC_BOX - h * s
    if sq then
      love.graphics.draw(src, sq, ox, oy, 0, s, s)
    else
      love.graphics.draw(src, ox, oy, 0, s, s)
    end
    love.graphics.setCanvas(prev)
    for _, t in ipairs(temps) do t:release() end
    remember(key, canvas)
    return canvas
  end

  -- The engine's icon entry for a dex number: two frames side by side in the
  -- icon page, each a 16x16 quad. Cached per dex.
  function self.icon(dex)
    dex = tonumber(dex)
    if self.icons[dex] ~= nil then return self.icons[dex] or nil end
    local cell = self.cell(dex, "icon")
    if not cell then self.icons[dex] = false return nil end
    local img = page(string.format("party_icons_%d", cell.page))
    if not img then self.icons[dex] = false return nil end
    local w, h = img:getDimensions()
    local size = cell.cell or 16
    local quads = {}
    for f = 0, (cell.frames or 2) - 1 do
      quads[f] = love.graphics.newQuad(cell.x + f * size, cell.y, size, size, w, h)
    end
    local entry = { image = img, w = size, h = size, sheetH = h,
                    frames = cell.frames or 2, quads = quads }
    self.icons[dex] = entry
    return entry
  end

  return self
end

return Atlas
