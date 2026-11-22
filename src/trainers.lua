-- Animated trainer fronts for FireRed to Emerald, from the Animated Trainer Intros pack
-- (assets/trainers/fronts_<n>.png, data/trainer_index.lua; built by tools/build_trainers.py).
--
-- The engine loads every trainer's front pic through src.core.game3.trainer_pic's
-- TrainerPic.front(picId) and draws it as a 64x64 image centred on the trainer's spot. For a pic
-- data/trainer_map.lua names, that call answers one live canvas per pic instead: the pack's
-- current frame, drawn into the 64x64 box (feet on its bottom centre) as the stand-in, and tagged
-- for WoobleView (gen3-hd-sprites) with the full frame, so it is drawn at window resolution and,
-- with its Fill Screen, slides in across the whole window.
--
-- The animation is the pack's: frame 0 while the trainer slides in, then the whole strip once in
-- `seconds` (1.5) and its last frame held, for the rest of the battle (the slide back in after a
-- win too) and on every other screen (the Hall of Fame, the mugshot transitions ...).

local Trainers = {}

local BOX = 64      -- the engine's trainer pic box
local DPI = 4       -- the stand-in canvas's detail

-- -> the running game's constants set ("firered", "emerald", "ruby"), or nil
local function constants()
  local ok, C = pcall(function() return require("src.core.game3.constants").active() end)
  return ok and C or nil
end

--- mod: the mod table (mod.path, mod.log); load: the sibling loader; Atlas: src/atlas.lua's
--- module (gfxEpoch, rescissor). Returns nil without the index or the map.
function Trainers.new(mod, load, Atlas)
  local okI, index = pcall(load, "data/trainer_index.lua")
  local okM, map = pcall(load, "data/trainer_map.lua")
  if not (okI and type(index) == "table" and okM and type(map) == "table") then return nil end
  local self = { index = index, map = map, pages = {}, live = {} }
  local seconds = tonumber(map.seconds) or 1.5
  local scale = tonumber(map.scale) or (2 * 160 / 384)

  -- the player's options (main.lua sets it); ANIMATED TRAINERS on unless set off
  self.option = nil
  function self.enabled()
    local ok, v = pcall(function() return self.option and self.option("animated_trainers") end)
    return not (ok and v == false)
  end
  -- WoobleView's exports (main.lua's linkHd keeps it current), or nil
  self.hd = nil
  -- true while the battle scene is drawing (src/hooks.lua)
  self.inBattle = function() return false end
  -- the battle's stage (src.core.game3.battle.anim), looked up when first needed
  self.stage = function()
    local ok, Anim = pcall(require, "src.core.game3.battle.anim")
    return ok and type(Anim) == "table" and type(Anim.stage) == "function" and Anim.stage() or nil
  end
  self.now = function() return love.timer.getTime() end

  --- The game's name for a trainer pic id (TRAINER_PIC_ without its prefix), and the constants
  --- set's game, or nil.
  function self.picName(picId)
    local C = constants()
    if not C or type(picId) ~= "number" then return nil end
    local ok, name = pcall(function() return C.trainer_classes.byId.TRAINER_PIC_[picId] end)
    if not ok or type(name) ~= "string" then return nil end
    return (name:gsub("^TRAINER_PIC_", "")), rawget(C, "game") or C.game
  end

  --- The pack sprite (its index entry and name) a pic id is drawn with in this game, or nil.
  function self.spriteFor(picId)
    local name, game = self.picName(picId)
    local fronts = name and map.fronts and map.fronts[game]
    local sprite = fronts and fronts[name]
    local e = sprite and index[sprite]
    if not e then return nil end
    return e, sprite
  end

  local function page(n)
    local hit = self.pages[n]
    if hit then return hit end
    local ok, img = pcall(love.graphics.newImage, mod.path .. "/assets/trainers/fronts_" .. n .. ".png")
    if not (ok and img) then return nil end
    img:setFilter("nearest", "nearest")
    self.pages[n] = img
    return img
  end

  -- the frame f's quad on its page
  local function quadOf(e, img, f)
    local col, row = f % e.cols, math.floor(f / e.cols)
    return love.graphics.newQuad(e.x + col * e.cw, e.y + row * e.ch, e.cw, e.ch, img:getDimensions())
  end

  -- the stand-in's size: the pack's scale, shrunk only as far as the box needs (no WoobleView: a
  -- big trainer is not cut by the 64x64 box)
  local function fit(e)
    return math.min(scale, BOX / e.py, (BOX / 2) / e.px, (BOX / 2) / math.max(1, e.cw - e.px))
  end

  --- Which frame a pic shows now: frame 0 while its trainer slides in (before the strip has
  --- played this battle), then the strip once over `seconds`, then the last frame held.
  function self.frameOf(picId, e)
    local n = math.max(1, e.frames)
    if n == 1 then return 0 end
    local rec = self.live[picId]
    local t0 = rec and rec.t0
    if self.inBattle() then
      local ok, s = pcall(self.stage)
      local te = ok and type(s) == "table" and type(s.trainer) == "table" and s.trainer.enemy or nil
      local ours = type(te) == "table" and te.visible and (te.picId == picId or te.pic2 == picId)
      if ours and not t0 then
        if (tonumber(te.ox) or 0) ~= 0 then return 0 end
        t0 = self.now()
        if rec then rec.t0 = t0 end
      end
    end
    if not t0 then return n - 1 end
    return math.min(n - 1, math.floor((self.now() - t0) * n / seconds))
  end

  --- A new battle: every pic plays its strip again once its trainer has slid in.
  function self.resetBattle()
    for _, rec in pairs(self.live) do rec.t0 = nil end
  end

  local function render(rec, e, img, quad)
    local G = love.graphics
    local sx, sy, sw, sh
    if G.getScissor then sx, sy, sw, sh = G.getScissor() end
    G.push("all")
    local ok, err = pcall(function()
      G.origin()
      if G.setScissor then G.setScissor() end
      if G.setShader then G.setShader() end
      G.setBlendMode("alpha")
      G.setColor(1, 1, 1, 1)
      G.setCanvas(rec.canvas)
      G.clear(0, 0, 0, 0)
      local s = fit(e)
      G.draw(img, quad, BOX / 2 - e.px * s, BOX - e.py * s, 0, s, s)
    end)
    G.pop()
    if Atlas and Atlas.rescissor then Atlas.rescissor(sx, sy, sw, sh) end
    if not ok then error(err, 0) end
  end

  --- The engine's entry for a mapped pic: { image = live canvas, w = 64, h = 64 }, or nil.
  function self.entry(picId)
    local e = self.spriteFor(picId)
    if not e then return nil end
    local img = page(e.page)
    if not img then return nil end
    local rec = self.live[picId]
    local epoch = Atlas and Atlas.gfxEpoch and Atlas.gfxEpoch() or 0
    if not rec or rec.e ~= e then
      local ok, c = pcall(love.graphics.newCanvas, BOX, BOX, { dpiscale = DPI })
      if not ok then return nil end
      c:setFilter("nearest", "nearest")
      rec = { canvas = c, e = e, entry = { image = c, w = BOX, h = BOX }, t0 = rec and rec.t0 }
      self.live[picId] = rec
    end
    local f = self.frameOf(picId, e)
    local battle = self.inBattle()
    local hd = battle and self.hd or nil
    local hdOn = false
    if hd then
      local ok, on = pcall(function() return hd.enabled("battle") end)
      hdOn = ok and on and true or false
    end
    if f ~= rec.f or epoch ~= rec.epoch or hdOn ~= rec.hdOn then
      local quad = quadOf(e, img, f)
      render(rec, e, img, quad)
      rec.f, rec.epoch, rec.hdOn = f, epoch, hdOn
      if hdOn then
        -- the full frame at window resolution: its pivot (the frame's bottom centre) on the
        -- stand-in's, at the pack's scale; a trainer, so WoobleView moves it with its side
        local s = fit(e)
        pcall(hd.tag, rec.canvas, {
          texture = img, quad = quad,
          pivot = { e.px, e.py }, lowPivot = { BOX / 2, BOX },
          scale = scale, side = "enemy", trainer = true,
        })
        rec.tagged = true
      end
    end
    -- off the battle (a mugshot, the Hall of Fame): the plain canvas, not the battle's tag
    if not hdOn and rec.tagged and self.hd and self.hd.untag then
      pcall(self.hd.untag, rec.canvas)
      rec.tagged = false
    end
    return rec.entry
  end

  return self
end

--- Wraps TrainerPic.front (the engine's src.core.game3.trainer_pic) so a mapped pic is drawn
--- from the pack while ANIMATED TRAINERS is on. Safe to call again: an installed wrapper is left
--- alone. Returns whether it is in place.
function Trainers.install(self, TrainerPic)
  if type(TrainerPic) ~= "table" or type(TrainerPic.front) ~= "function" then return false end
  local front = TrainerPic.front
  if Trainers._ours[front] then return true end
  TrainerPic.front = function(picId, ...)
    if type(picId) == "number" and self.enabled() then
      local ok, entry = pcall(self.entry, picId)
      if ok and entry then return entry end
    end
    return front(picId, ...)
  end
  Trainers._ours[TrainerPic.front] = true
  return true
end
Trainers._ours = setmetatable({}, { __mode = "k" })

return Trainers
