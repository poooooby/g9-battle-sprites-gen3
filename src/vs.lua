-- HGSS-style VS screens before the big battles of FireRed / LeafGreen (data/trainer_map.lua `vs`:
-- the gym leaders, Giovanni, Blue, Bruno and Lance), over the whole window.
--
-- A port of Pokemon Essentials v21.1's Transitions::VSTrainer (Maruno's HGSS VS animation; timings,
-- sizes and motion as there, 4.0 s): a bar scrolls across the screen, the VS logo zooms in, the
-- foe slides in as a silhouette, a flash shows them in colour with their name, then white, then
-- black. Essentials lays it out on a 512x384 screen; here the screen is 384 tall and as wide as the
-- window (683 at 16:9): the bar tiles across the full width, the logo and name keep their place
-- from the centre and the foe from the right edge.
--
-- The game's own transition runs its opening flashes as usual (src.core.game3.battle_transition
-- phase "intro"); where it would play its effect ("main") this plays instead, and then finishes the
-- transition, which starts the battle as the game's own would.

local VS = {}

local H = 384                -- Essentials' screen height: the layout's units
local DURATION = 4.0
local BAR_Y = 80
local BAR_SCROLL_SPEED = 1800
local BAR_MASK = { 8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7 }
local VS_X = 144 - 256       -- from the centre (Essentials: 144 on 512)
local FOE_LIMIT = 128        -- from the right edge: slides to here (Essentials: 384 on 512) ...
local FOE_X = 84             -- ... then jumps to here (428)
local NAME_X = 244 - 256     -- from the centre
local NAME_Y = 86            -- in the bar
local NAME_SCALE = 3         -- the game's font, about Essentials' system font's size on 384 rows
local T = {
  barEnd = 0.2, vsStart = 0.7, vsStart2 = 0.9, vsShrink = 0.2, vsFinal = 1.1,
  foeStart = 1.25, foeEnd = 1.4, flash = 1.9, flashDur = 0.25,
  whiteStart = 3.0, whiteEnd = 3.5, blackStart = 3.8,
}
VS.DURATION, VS.T = DURATION, T

--- mod: the mod table; trainers: src/trainers.lua's instance (picName, enabled, map).
function VS.new(mod, trainers)
  local self = { images = {}, active = nil, pending = nil }
  self.now = function() return love.timer.getTime() end

  local function image(name)
    local hit = self.images[name]
    if hit ~= nil then return hit or nil end
    local ok, img = pcall(love.graphics.newImage, mod.path .. "/assets/trainers/vs/" .. name .. ".png")
    if ok and img then img:setFilter("nearest", "nearest") end
    self.images[name] = ok and img or false
    return ok and img or nil
  end
  self.image = image

  --- The VS screen for a battle about to start (BattleTransition's pick options), or nil: a single
  --- trainer battle (not the Trainer Tower's or an e-Reader's) against a trainer data/trainer_map.lua
  --- gives a VS screen, with ANIMATED TRAINERS on.
  function self.screenFor(opts)
    if type(opts) ~= "table" or opts.wild or opts.headless or opts.trainerTower or opts.eReader then
      return nil
    end
    if not trainers.enabled() then return nil end
    local id = tonumber(opts.trainerId)
    if not id then return nil end
    local ok, info = pcall(function() return require("src.core.game3.scripting.trainers").get(id) end)
    if not (ok and type(info) == "table") or info.doubleBattle then return nil end
    local name, game = trainers.picName(tonumber(info.pic))
    local vs = trainers.map.vs and trainers.map.vs[game]
    local entry = name and vs and vs[name]
    if not entry then return nil end
    return { foe = entry.foe, bar = entry.bar, name = type(info.name) == "string" and info.name or "" }
  end

  -- ---- drawing ---------------------------------------------------------------------------------

  local function lerp(a, b, p) return a + (b - a) * p end

  --- The screen at `t` seconds into it, over a window w x h.
  function self.draw(screen, t, w, h)
    local G = love.graphics
    local bar, foe = image(screen.bar), image(screen.foe)
    local vs1, vs2 = image("hgss_vs1"), image("hgss_vs2")
    if not (bar and foe and vs1 and vs2) then return end
    local k = h / H
    local W = w / k
    -- (the HUD's own transform and clip are kept: the window's game viewport)
    local cx, cy, cw, ch
    if G.getScissor then cx, cy, cw, ch = G.getScissor() end
    G.push("all")
    G.scale(k, k)
    G.setColor(1, 1, 1, 1)
    local bw, bh = bar:getDimensions()
    local flashMid = T.flash + T.flashDur / 2

    -- the dark backdrop (after the flash: the field no longer shows through)
    if t >= flashMid then
      G.setColor(0, 0, 0, 224 / 255)
      G.rectangle("fill", 0, 0, W, H)
      G.setColor(1, 1, 1, 1)
    end

    -- the bar, scrolling left, tiled across the width; it wipes in from the right with a jagged edge
    local bx = -((t * BAR_SCROLL_SPEED) % bw)
    local function bars()
      local x = bx
      while x < W do
        G.draw(bar, x, BAR_Y)
        x = x + bw
      end
    end
    if t >= T.barEnd then
      bars()
    else
      local start = W * (1 - t / T.barEnd)
      for i = 0, bh / 2 - 1 do
        local x = start - BAR_MASK[(i % #BAR_MASK) + 1] * 4
        if x < W then
          G.setScissor(math.max(0, x) * k, (BAR_Y + i * 2) * k, (W - math.max(0, x)) * k + 1, 2 * k + 1)
          if cx then G.intersectScissor(cx, cy, cw, ch) end
          bars()
        end
      end
      if cx then G.setScissor(cx, cy, cw, ch) else G.setScissor() end
    end

    -- the VS logo: two copies zoom in and shrink, then the logo shudders in place
    local vx, vy = W / 2 + VS_X, BAR_Y + bh / 2
    local function logo(img, zoom, dx, dy)
      local iw, ih = img:getDimensions()
      G.draw(img, vx + (dx or 0), vy + (dy or 0), 0, zoom, zoom, iw / 2, ih / 2)
    end
    -- (the logo itself, once the second copy has shrunk away: under the copies, as in Essentials)
    if t >= T.vsStart2 + T.vsShrink / 2 then
      local phase = math.floor(t * 30) % 3
      logo(vs1, 1, ({ 0, 4, 0 })[phase + 1], ({ 0, 0, -4 })[phase + 1])
    end
    if t >= T.vsStart and t < T.vsStart2 + T.vsShrink / 2 then
      -- the second copy (drawn under the first): 2.0 -> 1.2, then 1.6 -> 1.2, hidden at 1.2
      local z2 = t < T.vsStart2 and (2.0 - 0.8 * (t - T.vsStart) / T.vsShrink)
        or (1.6 - 0.8 * (t - T.vsStart2) / T.vsShrink)
      local z1
      if t >= T.vsStart + T.vsShrink / 2 then
        z1 = t < T.vsStart2 and (2.0 - 0.8 * (t - T.vsStart - T.vsShrink / 2) / T.vsShrink)
          or (2.0 - 0.8 * (t - T.vsStart2) / T.vsShrink)
      end
      if z1 then logo(vs2, z1) end
      logo(vs2, z2)
    elseif t >= T.vsStart2 + T.vsShrink / 2 and t < T.vsFinal then
      logo(vs2, 2.0 - 0.8 * (t - T.vsStart2) / T.vsShrink)
    end

    -- the foe: slides in from the right as a silhouette, jumps to its place, shown at the flash
    if t >= T.foeStart then
      local fw, fh = foe:getDimensions()
      local x
      if t >= T.foeEnd then
        x = W - FOE_X
      else
        local p = (t - T.foeStart) / (T.foeEnd - T.foeStart)
        x = lerp(W + fw / 2, W - FOE_LIMIT, p)
      end
      local y = BAR_Y + bh - 12
      if t < flashMid then
        -- (a silhouette: the portrait's shape in black)
        G.setColor(0, 0, 0, 1)
        if G.setShader and VS.silhouette() then G.setShader(VS.silhouette()) end
      end
      G.draw(foe, x, y, 0, 1, 1, fw / 2, fh)
      if G.setShader then G.setShader() end
      G.setColor(1, 1, 1, 1)
    end

    -- the foe's name on the bar, from the flash on until the fade to white
    if t >= flashMid and t < T.whiteStart and screen.name ~= "" then
      local ok, Font = pcall(function() return require("src.ui.game3.font").active() end)
      if ok and type(Font) == "table" and Font.draw then
        G.push()
        G.translate(W / 2 + NAME_X, BAR_Y + NAME_Y - 12)
        G.scale(NAME_SCALE, NAME_SCALE)
        local white = Font.COLOR and Font.COLOR.WHITE
        pcall(Font.draw, screen.name, 0, 0, white and { colors = white } or nil)
        G.pop()
      end
    end

    -- the white flash, the slow fade to white, then black
    local white = 0
    if t >= T.blackStart then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, W, H)
      white = 1 - (t - T.blackStart) / (DURATION - T.blackStart)
    elseif t >= T.whiteStart then
      white = math.min(1, (t - T.whiteStart) / (T.whiteEnd - T.whiteStart))
    elseif t >= T.flash and t < T.flash + T.flashDur then
      local p = (t - T.flash) / T.flashDur
      white = math.min(1, (p < 0.5 and 640 * p or 640 * (1 - p)) / 255)
    end
    if white > 0 then
      G.setColor(1, 1, 1, math.max(0, math.min(1, white)))
      G.rectangle("fill", 0, 0, W, H)
    end
    G.pop()
  end

  -- ---- the transition hooks --------------------------------------------------------------------

  --- Wraps BattleTransition's start / tick / abort (src.core.game3.battle_transition). Safe to
  --- call again. Returns whether it is in place.
  function self.install(BT)
    if type(BT) ~= "table" or type(BT.start) ~= "function" or type(BT.tick) ~= "function" then
      return false
    end
    if VS._ours[BT.tick] then return true end
    local start, tick, abort = BT.start, BT.tick, BT.abort
    BT.start = function(tid, opts, done, ...)
      self.active = nil
      local ok, screen = pcall(self.screenFor, opts)
      self.pending = ok and screen or nil
      return start(tid, opts, done, ...)
    end
    BT.tick = function(...)
      if self.pending and BT._active and BT._phase ~= "intro" then
        self.active, self.pending = { screen = self.pending, t0 = self.now() }, nil
      end
      local a = self.active
      if a then
        if not BT._active then
          self.active = nil
        elseif self.now() - a.t0 >= DURATION then
          self.active = nil
          BT.finish()
        end
        return true
      end
      return tick(...)
    end
    if type(abort) == "function" then
      BT.abort = function(...)
        self.active, self.pending = nil, nil
        return abort(...)
      end
      VS._ours[BT.abort] = true
    end
    VS._ours[BT.start], VS._ours[BT.tick] = true, true
    return true
  end

  --- Draws the running screen over the whole window (the render.hud seam: after everything).
  function self.drawHud(w, h)
    local a = self.active
    if not a then return end
    self.draw(a.screen, self.now() - a.t0, w, h)
  end

  return self
end

VS._ours = setmetatable({}, { __mode = "k" })

-- a shader that draws a texture's shape in the current colour (the foe's silhouette)
local silhouette = nil
function VS.silhouette()
  if silhouette == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        return vec4(color.rgb, color.a * Texel(tex, uv).a);
      }
    ]])
    silhouette = ok and sh or false
  end
  return silhouette or nil
end

return VS
