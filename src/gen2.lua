-- Gen 2 (Gold / Silver / Crystal): the atlas art on the game's own screens.
--
-- The same art, options and fitting as Red / Blue / Yellow (src/gen1.lua: Gen1.frame, the
-- options, the exports), on Gold's screens. Those differ from Gen 1's in three ways:
--
--   * every screen asks a method for its pic (BattleState:pic, SummaryMenu:picFor ...), which
--     is handed back as (image, trueColor), so each is wrapped where it asks;
--   * the screen is drawn at the window's resolution, so a frame is rendered at DPI times the
--     Game Boy's pixels and keeps its detail however the art was shrunk to fit its box;
--   * the colour is the GBC palette shader (GbcPalette), which draws a true-colour pic as it
--     is only in the GEN 2 colour mode. In DMG, CLASSIC and a custom palette it recolours the
--     pic by its shade, so the art goes in the Game Boy's four shades there, for the palette to
--     colour as it does the game's own.
--
-- Crystal's own animated pics (MonAnimView, and the battle's frontAnim) are not played over
-- ours: ours animate.
--
--   battle      BattleState:pic / :picScale / :frontAnimFrame
--   summary     SummaryMenu:picFor
--   Pokedex     PokedexMenu:picFor / :drawUnownPic (the National Dex's form browsing too)
--   PC box      BoxMenu:picFor
--   hatching    EggHatchAnim:pic
--   evolution   EvolutionAnim:pic
--   Hall of Fame  HallOfFame:monPic
--   trade       TradeAnimView:pic / :drawIcon
--   Oak         OakSpeech:drawPic (the Pokemon he shows)
--   photo       PhotoStudio:picFor
--   Unown printer  UnownPrinter:picFor
--   party       PartyMenu:drawIcon, and the G9 PARTY SCREEN (PartyMenu:drawWidescreen)

local Gen2 = {}

local DPI = 4                -- frame canvases: this many pixels per Game Boy pixel
local FRONT_BOX = 56         -- the 7x7-tile front pic box
local BACK_BOX = 48          -- the player's 6x6-tile back pic box

-- src/gen1.lua: the shared frame, options and helpers (set by Gen2.install)
local Gen1 = nil
local function opt(key, default) return Gen1.opt(key, default) end
local function on(key) return Gen1.on(key) end
local function require_(name) return Gen1.require_(name) end

local function gbc() return require_("src.render.GbcPalette") end
local function palettes() return require_("src.world.gen2.Palettes") end

--- Does the palette shader leave a true-colour pic in its own colours? Only in the GEN 2
--- colour mode (and when there is no shader at all).
function Gen2.keepsColour()
  local P = gbc()
  if not P then return true end
  local ok, avail = pcall(function() return P.available() end)
  if not (ok and avail) then return true end
  return P.mode == "gbc"
end

-- The atlas id an Unown of this letter is drawn from (A is the species' own sheet).
function Gen2.unownId(letter)
  local Unown = require_("src.core.gen2.Unown")
  local i = Unown and Unown.index(letter) or tonumber(letter)
  if not i or i <= 1 or i > 26 then return "UNOWN" end
  return "UNOWN_" .. ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):sub(i, i)
end

-- The id to draw for a Pokemon: its species, an Unown by its letter.
function Gen2.speciesOf(mon, species)
  species = species or (type(mon) == "table" and mon.species) or nil
  if species == "UNOWN" and type(mon) == "table" then
    local Unown = require_("src.core.gen2.Unown")
    local ok, letter = pcall(function() return Unown and Unown.monLetter(mon) end)
    if ok and letter then return Gen2.unownId(letter) end
  end
  return species
end

--- The frame of `species` (an atlas id, or a species id) for one side in a box x box box, at
--- DPI, or nil when the atlas has no art for it.
function Gen2.frame(atlas, data, species, side, box, mon, extra)
  local o = { dpi = DPI }
  for k, v in pairs(extra or {}) do o[k] = v end
  return Gen1.frame(atlas, data, species, side, box, box, mon, o)
end

-- the game's palette for a species (for a pic drawn here rather than by the screen)
local function monColors(pals, species, shiny)
  local P = palettes()
  if not (P and pals and species) then return nil end
  local ok, colors = pcall(P.monColors, pals, species, shiny)
  return ok and colors or nil
end

-- draws `body` through `colors` unless the art keeps its own (the engine's rule for a pic)
local function paint(colors, keeps, body)
  local P = gbc()
  if colors and not keeps and P and P.available() then
    P.with(colors, body)
  else
    body()
  end
end

-- Crystal's animated pics: a view whose Pokemon we draw plays no frames of its own. The view
-- notes its scene and the atlas key of its Pokemon (from the species record it is started
-- with) when it starts; `serves[scene]()` says whether that screen shows ours.
local serves = {}
local function installAnimViews(atlas)
  local View = require_("src.render.MonAnimView")
  Gen1.wrap(View, "start", function(orig)
    return function(def, mon, scene, ...)
      local view = orig(def, mon, scene, ...)
      if type(view) == "table" and type(def) == "table" then
        view.__woobleScene = scene
        view.__woobleKey = atlas.keyFor(Gen2.speciesOf(mon, def.id), tonumber(def.dex), def.baseSpecies)
      end
      return view
    end
  end)
  Gen1.wrap(View, "frame", function(orig)
    return function(self, ...)
      local check, key = serves[self.__woobleScene], self.__woobleKey
      if check and key and check() and atlas.cell(key, "front") then return nil end
      return orig(self, ...)
    end
  end)
end

function Gen2.installBattle(atlas, BattleState)
  if type(BattleState) ~= "table" or type(BattleState.pic) ~= "function" then return false end
  if BattleState.__woobleSprites2 then return true end
  BattleState.__woobleSprites2 = true
  local managed = setmetatable({}, { __mode = "k" })   -- mon -> true while ours is drawn

  local origPic = BattleState.pic
  function BattleState:pic(mon, back)
    if on("enable_battle_sprites") and type(mon) == "table" and mon.species ~= nil then
      local side = back and "back" or "front"
      -- 3DB FRONTAL / 3DB FLIP: the player's Pokemon shows its front, optionally facing the foe
      local frontal = back and opt("battle_frontal", false) == true
      -- the screen's own colour effects (the intro's blackout, a move's flash) recolour the
      -- pic, so it goes in the four shades for them as it does in the mono colour modes
      local effect = false
      pcall(function()
        if self:introGrayscale() then effect = true end
        local anim = self:animPicState(back and "player" or "enemy")
        if anim and anim.shade then effect = true end
      end)
      local shaded = effect or not Gen2.keepsColour()
      local f = Gen2.frame(atlas, self.game and self.game.data, Gen2.speciesOf(mon),
        frontal and "front" or side, back and BACK_BOX or FRONT_BOX, mon,
        { reuse = true, shadow = on("battle_shadows"), shades = shaded,
          mirror = frontal and opt("battle_front_flip", false) == true,
          -- tagged for WoobleView (window resolution in the original battle screen) when it
          -- keeps its own colours
          hdSide = not shaded and (back and "player" or "enemy") or nil })
      if f then
        managed[mon] = true
        -- (a path the game has none of: frontPicReplaced then keeps Crystal's own animation
        -- from starting over ours)
        return f, not shaded, "wooble-sprite:" .. side
      end
    end
    if type(mon) == "table" then managed[mon] = nil end
    return origPic(self, mon, back)
  end

  -- our frames come at their box's size
  local origScale = BattleState.picScale
  if type(origScale) == "function" then
    function BattleState:picScale(path, mon, back, ...)
      if type(mon) == "table" and managed[mon] then return 1 end
      return origScale(self, path, mon, back, ...)
    end
  end

  local origAnim = BattleState.frontAnimFrame
  if type(origAnim) == "function" then
    function BattleState:frontAnimFrame(mon, ...)
      if type(mon) == "table" and managed[mon] then return nil end
      return origAnim(self, mon, ...)
    end
  end
  return true
end

--- Every other screen that shows a Pokemon's picture. Returns the names of those hooked.
function Gen2.installScreens(atlas)
  local done = {}
  local function hooked(name, ok) if ok then done[#done + 1] = name end end
  local wrap = Gen1.wrap
  -- -> the frame and whether it is true colour; nil when there is no art. `opts.blackout`:
  -- the screen is showing it as a silhouette, in shades for the palette to blacken.
  local function front(game, species, mon, side, box, opts)
    if species == nil or (type(mon) == "table" and mon.isEgg) then return nil end
    local keeps = Gen2.keepsColour() and not (opts and opts.blackout)
    local o = { shades = not keeps }
    for k, v in pairs(opts or {}) do if k ~= "blackout" then o[k] = v end end
    local f = Gen2.frame(atlas, game and game.data, species, side or "front", box or FRONT_BOX, mon, o)
    if not f then return nil end
    return f, keeps
  end
  local function other(game, species, mon, side, box, opts)
    if not on("other_sprites") then return nil end
    return front(game, species, mon, side, box, opts)
  end

  -- the status screen: SUMMARY SPRITES, SUMMARY SIZE
  hooked("summary", wrap(require_("src.ui.gen2.SummaryMenu"), "picFor", function(orig)
    return function(self, mon, ...)
      if on("summary_sprites") and type(mon) == "table" then
        local f, tc = front(self.game, Gen2.speciesOf(mon), mon, "front", FRONT_BOX,
          { shrink = (tonumber(opt("summary_size", 100)) or 100) / 100, hdDex = true })
        if f then return f, tc end
      end
      return orig(self, mon, ...)
    end
  end))
  serves.menu = function() return on("summary_sprites") end

  -- the Pokedex: the species on show (the National Dex's form browsing sets formId while one
  -- of its forms is on show), Unown as the letter the player met first
  local Dex = require_("src.ui.gen2.PokedexMenu")
  hooked("pokedex", wrap(Dex, "picFor", function(orig)
    return function(self, species, ...)
      if on("dex_sprites") and species ~= nil then
        local shown = species
        if self.formId and self.formId ~= species and self.formBase == species then shown = self.formId end
        if species == "UNOWN" then
          shown = Gen2.unownId(self.save and tonumber(self.save.firstUnownSeen) or 0)
        end
        local dex = { hdDex = true }
        local f, tc = front(self.game, shown, nil, nil, nil, dex)
        if not f and shown ~= species then f, tc = front(self.game, species, nil, nil, nil, dex) end
        if f then return f, tc end
      end
      return orig(self, species, ...)
    end
  end))
  -- the Unown page's pic of each letter
  wrap(Dex, "drawUnownPic", function(orig)
    return function(self, letter, tx, ty, ...)
      local f, keeps = nil, nil
      if on("dex_sprites") then f, keeps = front(self.game, Gen2.unownId(letter), nil, nil, nil, { hdDex = true }) end
      if not f then return orig(self, letter, tx, ty, ...) end
      local G = love.graphics
      G.setColor(1, 1, 1, 1)
      paint(monColors(self.palettes, "UNOWN"), keeps, function() G.draw(f, tx * 8, ty * 8) end)
    end
  end)

  -- the PC's selected Pokemon
  hooked("pc box", wrap(require_("src.ui.gen2.BoxMenu"), "picFor", function(orig)
    return function(self, mon, ...)
      if type(mon) == "table" then
        local f, tc = other(self.game, Gen2.speciesOf(mon), mon)
        if f then return f, tc end
      end
      return orig(self, mon, ...)
    end
  end))

  -- an egg hatching: the Pokemon once the shell is gone
  hooked("hatching", wrap(require_("src.ui.gen2.EggHatchAnim"), "pic", function(orig)
    return function(self, ...)
      if self.showMon then
        local mon = self.mon
        local f, tc = other(self.game or { data = self.data },
          Gen2.speciesOf(mon, self.species), type(mon) == "table" and not mon.isEgg and mon or nil)
        if f then return f, tc end
      end
      return orig(self, ...)
    end
  end))
  serves.hatch = function() return on("other_sprites") end

  -- evolution: both species, as a silhouette while it flashes (blackout)
  hooked("evolution", wrap(require_("src.ui.gen2.EvolutionAnim"), "pic", function(orig)
    return function(self, species, ...)
      local f, tc = other(self.game or { data = self.data }, Gen2.speciesOf(self.mon, species),
        self.mon, "front", FRONT_BOX, { blackout = self.blackout and true or nil })
      if f then return f, tc end
      return orig(self, species, ...)
    end
  end))
  serves.evolve = function() return on("other_sprites") end

  -- the Hall of Fame: each Pokemon's front, and its back for the sweep ahead of it
  hooked("hall of fame", wrap(require_("src.ui.gen2.HallOfFame"), "monPic", function(orig)
    return function(self, mon, back, ...)
      if type(mon) == "table" then
        local f, tc = other(self.game or { data = self.data }, Gen2.speciesOf(mon), mon,
          back and "back" or "front", back and BACK_BOX or FRONT_BOX)
        if f then return f, tc end
      end
      return orig(self, mon, back, ...)
    end
  end))
  serves.hof = function() return on("other_sprites") end

  -- the trade movie: the Pokemon sent and the one received, and their icons in the tube
  local Trade = require_("src.ui.gen2.TradeAnim")
  hooked("trade", wrap(Trade, "pic", function(orig)
    return function(self, record, ...)
      if type(record) == "table" then
        local f, tc = other({ data = self.data }, Gen2.speciesOf(record), record)
        if f then return f, tc end
      end
      return orig(self, record, ...)
    end
  end))
  serves.trade = function() return on("other_sprites") end

  -- Oak's speech: the Pokemon he shows (the demo's, or one a build names)
  local Oak = require_("src.ui.gen2.OakSpeech")
  local shownBy = setmetatable({}, { __mode = "k" })   -- a pic image -> the species it shows
  wrap(Oak, "resolvePic", function(orig)
    return function(self, desc, ...)
      local img, colors = orig(self, desc, ...)
      if img ~= nil and type(desc) == "table" and desc.type == "pokemon" then shownBy[img] = desc.id end
      return img, colors
    end
  end)
  hooked("oak speech", wrap(Oak, "drawPic", function(orig)
    return function(self, ...)
      local pic = self.pic
      local species = pic ~= nil and (shownBy[pic] or (pic == self.marillPic and self.demoSpecies)) or nil
      local f, keeps = nil, nil
      if species then f, keeps = other(self.game, species) end
      if not f then return orig(self, ...) end
      local colors = self.picColors
      self.pic = f
      self.picColors = (not keeps) and (colors or monColors(self.palettes, species)) or nil
      local ok, err = pcall(orig, self, ...)
      self.pic, self.picColors = pic, colors
      if not ok then error(err, 0) end
    end
  end))

  -- the photo studio's portrait
  hooked("photo studio", wrap(require_("src.ui.gen2.PhotoStudio"), "picFor", function(orig)
    return function(self, species, ...)
      local mon = self.mon
      local f, tc = other(self.game, Gen2.speciesOf(mon, species), mon)
      if f then return f, tc end
      return orig(self, species, ...)
    end
  end))

  -- the Unown printer's letters
  hooked("unown printer", wrap(require_("src.ui.gen2.UnownPrinter"), "picFor", function(orig)
    return function(self, letter, ...)
      local f, tc = other(self.game, Gen2.unownId(letter))
      if f then return f, tc end
      return orig(self, letter, ...)
    end
  end))

  return done
end

-- The party icons. A Pokemon the game has an icon for (#1-251) keeps it, except on the G9
-- PARTY SCREEN; one it has none for (a National Dex species or form) gets ours. Two frames, in
-- the game's own step; drawn through the party's palette in the colour modes that recolour.
local iconCanvases, iconCount, iconEpoch = {}, 0, nil
local function iconCanvas(atlas, entry, key, f, shades)
  -- (a window mode change may have emptied them: Atlas.watchWindow)
  local epoch = type(atlas.epoch) == "function" and atlas.epoch() or 0
  if epoch ~= iconEpoch then iconCanvases, iconCount, iconEpoch = {}, 0, epoch end
  local ck = key .. ":" .. f .. (shades and "g" or "")
  local hit = iconCanvases[ck]
  if hit then return hit end
  if iconCount >= 48 then iconCanvases, iconCount = {}, 0 end
  local G = love.graphics
  local okC, canvas = pcall(G.newCanvas, 16, 16, { dpiscale = entry.w / 16 })
  if not okC then return nil end
  canvas:setFilter("nearest", "nearest")
  local quad = entry.quads[f] or entry.quads[0]
  local sh = shades and atlas.shadesShader() or nil
  G.push("all")
  G.origin()
  G.setCanvas(canvas)
  G.clear(0, 0, 0, 0)
  G.setColor(1, 1, 1, 1)
  G.setShader(sh)
  G.draw(entry.image, quad, 0, 0, 0, 16 / entry.w, 16 / entry.h)
  G.pop()
  iconCanvases[ck] = canvas
  iconCount = iconCount + 1
  return canvas
end

function Gen2.g9On() return opt("g9_party_screen", false) == true end

-- The atlas key of a Pokemon's icon, or nil when it keeps the game's own: one the game has
-- an icon for (`own`) keeps it, except on the G9 PARTY SCREEN.
local function iconKey(atlas, data, mon, own)
  if not on("party_icons") or type(mon) ~= "table" or mon.isEgg then return nil end
  if own and not Gen2.g9On() then return nil end
  local key = Gen1.keyOf(atlas, data, Gen2.speciesOf(mon))
  if not key then return nil end
  if on("sprite_female") and Gen1.femaleOf(mon) then key = atlas.femaleKey(key) or key end
  return atlas.icon(key) and key or nil
end

local quads = {}
local function reQuad(slot, x, y, w, h, sw, sh)
  local q = quads[slot]
  if q then q:setViewport(x, y, w, h, sw, sh) return q end
  q = love.graphics.newQuad(x, y, w, h, sw, sh)
  quads[slot] = q
  return q
end

function Gen2.installIcons(atlas)
  local done = {}
  local Party = require_("src.ui.gen2.PartyMenu")
  local ok = Gen1.wrap(Party, "drawIcon", function(orig)
    return function(self, mon, px, py, ...)
      local okI, id = pcall(self.iconIdFor, self, mon)
      local own = okI and id ~= nil and type(self.icons) == "table" and type(self.icons.icons) == "table"
        and self.icons.icons[id] ~= nil
      local key = iconKey(atlas, self.game and self.game.data, mon, own)
      if not key then return orig(self, mon, px, py, ...) end
      local entry = atlas.icon(key)
      local okF, f = pcall(self.iconFrame, self, mon)
      local keeps = Gen2.keepsColour()
      local canvas = iconCanvas(atlas, entry, key, okF and tonumber(f) or 0, not keeps)
      if not canvas then return orig(self, mon, px, py, ...) end
      local G = love.graphics
      local P = gbc()
      local pals = self.palettes and self.palettes.partyMenu
      local colors = pals and pals[1] or nil
      local shaded = colors and P and P.available()
      local iconShaded = shaded and not keeps
      local previous = G.getShader and G.getShader() or nil
      G.setColor(1, 1, 1, 1)
      if iconShaded then P.use(colors) end
      -- a Pokemon holding something: the bottom-left 8x8 of its icon is the game's marker
      -- (.SpawnItemIcon), as the game draws it
      local row = Party.heldMarkerRow and Party.heldMarkerRow(mon) or nil
      local marker = row and self:heldMarkerImage() or nil
      if marker then
        G.draw(canvas, reQuad("tl", 0, 0, 8, 8, 16, 16), px, py)
        G.draw(canvas, reQuad("tr", 8, 0, 8, 8, 16, 16), px + 8, py)
        G.draw(canvas, reQuad("br", 8, 8, 8, 8, 16, 16), px + 8, py + 8)
        if shaded and not iconShaded then P.use(colors) end
        local mw, mh = marker:getDimensions()
        G.draw(marker, reQuad("held", 0, row * 8, 8, 8, mw, mh), px, py + 8)
      else
        G.draw(canvas, px, py)
      end
      if shaded then G.setShader(previous) end
    end
  end)
  if ok then done[#done + 1] = "party icons" end

  -- the trade tube's icon (the first frame, as the game's)
  Gen1.wrap(require_("src.ui.gen2.TradeAnim"), "drawIcon", function(orig)
    return function(self, record, x, y, ...)
      local icons = type(self.data) == "table" and self.data.gen2Icons or nil
      local id = type(record) == "table" and icons and icons.species and icons.species[record.species]
      local own = id ~= nil and icons.icons ~= nil and icons.icons[id] ~= nil
      local key = iconKey(atlas, self.data, record, own)
      if not key then return orig(self, record, x, y, ...) end
      local keeps = Gen2.keepsColour()
      local canvas = iconCanvas(atlas, atlas.icon(key), key, 0, not keeps)
      if not canvas then return orig(self, record, x, y, ...) end
      love.graphics.setColor(1, 1, 1, 1)
      paint(monColors(self.palettes, record.species, record.shiny), keeps,
        function() love.graphics.draw(canvas, x, y) end)
    end
  end)
  return done
end

-- The G9 PARTY SCREEN on Gold / Silver / Crystal: the party list fills the window (the game
-- draws it at the largest whole scale that fits), every Pokemon with its own icon. A screen
-- pushed over it (a message box, the summary) is drawn at the same scale.
local function fillScale(winW, winH)
  local Chrome = require_("src.ui.gen2.Chrome")
  local w, h = tonumber(winW) or 160, tonumber(winH) or 144
  if Chrome and Chrome.playfieldRect then
    local ok, _, _, pw, ph = pcall(Chrome.playfieldRect, winW, winH)
    if ok and pw and ph then w, h = pw, ph end
  end
  local s = math.min(w / 160, h / 144)
  return s > 0 and s or 1
end

function Gen2.installPartyScreen(PartyMenu)
  if type(PartyMenu) ~= "table" or type(PartyMenu.drawPanel) ~= "function" then return false end
  if PartyMenu.__woobleG9 then return true end
  PartyMenu.__woobleG9 = true
  local origScale = PartyMenu.battlePanelScale
  PartyMenu.battlePanelScale = function(self, winW, winH, ...)
    if Gen2.g9On() then return fillScale(winW, winH) end
    if origScale then return origScale(self, winW, winH, ...) end
    return nil
  end
  local origWide = PartyMenu.drawWidescreen
  PartyMenu.drawWidescreen = function(self, winW, winH, ...)
    if not Gen2.g9On() or type(origWide) ~= "function" then
      if origWide then return origWide(self, winW, winH, ...) end
      return
    end
    local Chrome = require_("src.ui.gen2.Chrome")
    local G = love.graphics
    local s = fillScale(winW, winH)
    Chrome.letterbox(winW, winH, 1, 1, 1)
    G.push()
    G.translate(Chrome.fitOrigin(winW, winH, s))
    G.scale(s, s)
    self:drawPanel()
    G.pop()
  end
  return true
end

--- The exports (src/gen1.lua Gen1.exports), with the summary picture drawn as Gold's: not
--- mirrored, in the 7x7 block at the top left, through the Pokemon's palette where the colour
--- mode recolours.
function Gen2.exports(atlas, dataOf)
  local ex = Gen1.exports(atlas, dataOf)
  ex.drawSummaryFrame = function(mon, box)
    box = type(box) == "table" and box or { x = 0, w = FRONT_BOX, bottom = FRONT_BOX }
    if not on("summary_sprites") or type(mon) ~= "table" or mon.isEgg == true then return false end
    local data = dataOf()
    local keeps = Gen2.keepsColour()
    local f = Gen2.frame(atlas, data, Gen2.speciesOf(mon), "front", FRONT_BOX, mon,
      { shrink = (tonumber(opt("summary_size", 100)) or 100) / 100, shades = not keeps })
    if not f then return false end
    local w, h = f:getDimensions()
    local x = (box.x or 0) + ((box.w or w) - w) / 2
    local y = math.max(0, (box.bottom or h) - h)
    love.graphics.setColor(1, 1, 1, 1)
    paint(monColors(data and data.gen2Palettes, mon.species, mon.shiny), keeps,
      function() love.graphics.draw(f, x, y) end)
    return true
  end
  return ex
end

--- Installs every Gen 2 hook it can (again on each call: a screen another mod replaced since is
--- wrapped in turn). Returns the names of the screens hooked.
function Gen2.install(atlas, gen1)
  Gen1 = gen1
  local done = {}
  installAnimViews(atlas)
  if Gen2.installBattle(atlas, require_("src.ui.gen2.BattleState")) then done[#done + 1] = "battle" end
  for _, name in ipairs(Gen2.installScreens(atlas)) do done[#done + 1] = name end
  for _, name in ipairs(Gen2.installIcons(atlas)) do done[#done + 1] = name end
  if Gen2.installPartyScreen(require_("src.ui.gen2.PartyMenu")) then done[#done + 1] = "party screen" end
  return done
end

return Gen2
