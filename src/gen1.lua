-- Gen 1 (Red / Blue / Yellow): the atlas art on the game's own screens.
--
-- Gen 1 names a species by its id (mon.species = "ABRA"), so a pic is found by id, then by the
-- base species of a form the atlas has no art for (a Mega shows its base), then by dex number
-- (Atlas keyFor). The screens draw a pic as a plain image the size of its box, in Game Boy
-- pixels, so every frame comes from Atlas boxFrame, fitted to that box.
--
-- The hook approach follows tectorifter's g9-battle-sprites (the Gen 1 / 2 mod this one was
-- forked from): the battle's pic is chosen by locals (makeBattler, getImage), so the frame is
-- put in the battler's `sprite` on every draw of the pics layer.
--
--   battle   BattleState.drawPicsLayer   the frame for each battler, every draw
--            BattleState.resolveBattleScale  1 for ours (the frames come at their box's size;
--                                         the game draws its 28x28 back pic at 2x)
--            BattleState.drawBattlerPic  marks the pic's rect true colour for the colour pass
--            BattleState.speciesSprite   notes whom a Transform copies

local Gen1 = {}

local CART_SPECIES = 151     -- the atlas keys of Red / Blue / Yellow's own species (1-151)
local FRONT_BOX = 56         -- the enemy's 7x7-tile pic box
local BACK_BOX = 64          -- the player's back pic (the cart's is 28x28 drawn at 2x; 64 as
                             -- g9-battle-sprites drew it, its feet on the text box at y 96)

-- The player's options (options.lua), through the getter main.lua sets: nil means the default.
Gen1.options = nil
local function opt(key, default)
  local ok, v = pcall(function() return Gen1.options and Gen1.options(key) end)
  if not ok or v == nil then return default end
  return v
end
local function on(key) return opt(key, true) ~= false end
local ANCHORS = { [0] = "feet", [1] = "pack", [2] = "box" }

-- Colour. The colour pass recolours a pic by its shade unless it keeps the pic's own colours:
-- off the battle screen only with the ADVANCED COLORS (PaletteFX.honorsTrueColor), and in
-- battle in every mode but the mono ones (OG, OG INV, CLASSIC), which re-shade the whole
-- screen. Where it would recolour, the art goes in the Game Boy's four shades (Atlas
-- shadesShader), so the pass colours it as it does the game's own pics, not in blotches.
local function paletteFX()
  local ok, P = pcall(require, "src.render.PaletteFX")
  return ok and type(P) == "table" and P or nil
end
function Gen1.keepsColour()
  local P = paletteFX()
  if not (P and type(P.honorsTrueColor) == "function") then return true end
  local ok, keeps = pcall(P.honorsTrueColor)
  return not ok or keeps == true
end
function Gen1.monoBattle()
  local P = paletteFX()
  if not P then return false end
  if P.mode == "og" or P.mode == "og_inv" or P.mode == "classic" then return true end
  local ok, raw = pcall(function() return type(P.forcesRawGrays) == "function" and P.forcesRawGrays() end)
  return ok and raw == true
end

-- the engine's own fields for the Pokemon Tower ghost's disguise: the pic stays the game's
-- ghost until the Silph Scope reveals what is underneath (species-blind on purpose: a
-- randomizer may put anything there)
local function ghostEncounter(battle)
  return type(battle) == "table" and (battle.ghost == true or battle.scopeReveal == true
    or battle.ghostReveal ~= nil) or false
end

-- The atlas key of a species id: the id itself, else its record's base species (a form with
-- no art), else its dex number.
function Gen1.keyOf(atlas, data, species)
  if species == nil then return nil end
  local def = type(data) == "table" and type(data.pokemon) == "table" and data.pokemon[species] or nil
  local dex = type(def) == "table" and tonumber(def.dex) or nil
  local base = type(def) == "table" and def.baseSpecies or nil
  return atlas.keyFor(species, dex, base)
end

-- Gen 1 has no shiny Pokemon, but the engine keeps Gen 2's rule for its DVs ("virtual shiny");
-- a mod may also set mon.shiny
function Gen1.shinyOf(mon)
  if type(mon) ~= "table" then return false end
  if mon.shiny ~= nil then return mon.shiny == true end
  if type(mon.dvs) ~= "table" then return false end
  local ok, Stats = pcall(require, "src.pokemon.Stats")
  if not (ok and type(Stats) == "table" and type(Stats.isShiny) == "function") then return false end
  local okS, shiny = pcall(Stats.isShiny, mon.dvs)
  return okS and shiny == true
end

-- (a National Dex mod's gender fields; Gen 1 itself has none)
function Gen1.femaleOf(mon)
  if type(mon) ~= "table" then return false end
  return mon.isFemale == true or mon.gender == "female" or mon.gender == "F" or mon.sex == "female"
end

-- The variant to draw: the shiny one when the Pokemon is shiny and the atlas has it.
local function variantFor(atlas, key, side, shiny)
  if shiny and atlas.cell(key, side .. "_shiny") then return side .. "_shiny" end
  return side
end

-- The frame playing now: ANIMATE and SPRITE SPEED.
local function frameNo(cell)
  local n = math.max(1, tonumber(cell.frames) or 1)
  if n == 1 or not on("animate_sprites") then return 0 end
  local fps = tonumber(opt("sprite_fps", 12)) or 12
  fps = math.max(1, math.min(60, fps))
  return math.floor(love.timer.getTime() * fps) % n
end

--- The current animation frame of `species` for one side ("front" / "back") in a w x h box,
--- or nil when the atlas has no art for it. `mon` (optional) picks shiny and female art; the
--- size and placement follow the options (SPRITE SIZE, GROUND ANCHOR, FLOATERS), and `extra`
--- adds a screen's own boxFrame options (shadow, mirror, shrink ...).
function Gen1.frame(atlas, data, species, side, w, h, mon, extra)
  local key = Gen1.keyOf(atlas, data, species)
  if not key then return nil end
  if mon and on("sprite_female") and Gen1.femaleOf(mon) then key = atlas.femaleKey(key) or key end
  local variant = variantFor(atlas, key, side, mon and on("sprite_shiny") and Gen1.shinyOf(mon))
  local cell = atlas.cell(key, variant)
  if not cell then return nil end
  local opts = {
    divisor = tonumber(opt("sprite_size", 0)) or 0,
    anchor = ANCHORS[tonumber(opt("sprite_anchor", 0)) or 0] or "feet",
    float = on("sprite_float"),
  }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return atlas.boxFrame(key, variant, frameNo(cell), w, h, opts)
end

function Gen1.installBattle(atlas, BattleState)
  if type(BattleState) ~= "table" or type(BattleState.drawPicsLayer) ~= "function" then return false end
  if BattleState.__woobleSprites then return true end
  BattleState.__woobleSprites = true

  local ours = setmetatable({}, { __mode = "k" })         -- our frames
  local transformed = setmetatable({}, { __mode = "k" })  -- a Transform's pic -> the species it copies
  -- species shown with our art on a side this draw ("front" / "back"): the scale wrap answers 1
  -- for them (resolveBattleScale is asked with the species, not the pic)
  local managed = { front = {}, back = {} }

  -- The frame into battler.sprite. A pic the engine set since our last frame (a send-out's, or
  -- a Transform's) is remembered, so it can be put back when there is no art for the species.
  local function swap(battle, battler, back)
    if type(battler) ~= "table" or type(battler.mon) ~= "table" then return end
    local cur = battler.sprite
    if cur ~= nil and not ours[cur] then
      battler.__woobleVanilla = cur
      battler.__woobleAs = transformed[cur]
    end
    local species = battler.__woobleAs or battler.mon.species
    local side = back and "back" or "front"
    -- 3DB FRONTAL / 3DB FLIP: the player's Pokemon shows its front, optionally facing the foe
    local frontal = back and opt("battle_frontal", false) == true
    local box = back and BACK_BOX or FRONT_BOX
    -- (hdSide: tagged for WoobleView, which redraws it at window resolution in the original
    -- battle screen; not in the mono modes, where the pics are drawn after the colour pass)
    local mono = Gen1.monoBattle()
    local frame = Gen1.frame(atlas, battle.data, species, frontal and "front" or side, box, box,
      battler.mon, { reuse = true, shadow = on("battle_shadows"), shades = mono,
                     mirror = frontal and opt("battle_front_flip", false) == true,
                     hdSide = not mono and (back and "player" or "enemy") or nil })
    if frame then
      ours[frame] = true
      battler.sprite = frame
      managed[side][battler.mon.species] = true
    else
      if battler.__woobleVanilla ~= nil then battler.sprite = battler.__woobleVanilla end
      managed[side][battler.mon.species] = nil
    end
  end

  local function restore(battler, side)
    if type(battler) ~= "table" then return end
    if ours[battler.sprite] and battler.__woobleVanilla ~= nil then battler.sprite = battler.__woobleVanilla end
    if type(battler.mon) == "table" then managed[side][battler.mon.species] = nil end
  end

  local ghostFront = false
  local origLayer = BattleState.drawPicsLayer
  function BattleState:drawPicsLayer(...)
    ghostFront = ghostEncounter(self)
    if not on("enable_battle_sprites") then
      restore(self.enemy, "front")
      restore(self.player, "back")
    else
      if ghostFront then restore(self.enemy, "front") else swap(self, self.enemy, false) end
      swap(self, self.player, true)
    end
    local ok, a, b, c = pcall(origLayer, self, ...)
    ghostFront = false
    if not ok then error(a, 0) end
    return a, b, c
  end

  local origScale = BattleState.resolveBattleScale
  if type(origScale) == "function" then
    BattleState.resolveBattleScale = function(data, side, path, species, ...)
      if species ~= nil and managed[side] and managed[side][species]
          and not (ghostFront and side == "front") then
        return 1
      end
      return origScale(data, side, path, species, ...)
    end
  end

  -- the colour pass (SGB / GBC zones) would shade our pic like the game's four-shade one: the
  -- engine's own opt-out marks its rect as true colour (x, y already carry shake and slide)
  local origPic = BattleState.drawBattlerPic
  if type(origPic) == "function" then
    local PaletteFX
    function BattleState:drawBattlerPic(battler, x, y, scale, shakeX, shakeY)
      local img = type(battler) == "table" and battler.sprite
      if img and ours[img] then
        if PaletteFX == nil then
          local okP, m = pcall(require, "src.render.PaletteFX")
          PaletteFX = okP and type(m) == "table" and m or false
        end
        if PaletteFX and PaletteFX.markTrueColor then
          pcall(PaletteFX.markTrueColor, x, y, img:getWidth() * (scale or 1), img:getHeight() * (scale or 1))
        end
      end
      return origPic(self, battler, x, y, scale, shakeX, shakeY)
    end
  end

  local origSpecies = BattleState.speciesSprite
  if type(origSpecies) == "function" then
    function BattleState:speciesSprite(species, isPlayerSide, ...)
      local img = origSpecies(self, species, isPlayerSide, ...)
      if img ~= nil then transformed[img] = species end
      return img
    end
  end
  return true
end

-- Replaces T[name] with make(current). Asked again on every install: a function that is no
-- longer ours (a mod that loaded later put its own there, the National Dex's Pokedex page)
-- is wrapped in turn, and ours is never wrapped twice. True when ours is in place.
local function wrap(T, name, make)
  if type(T) ~= "table" or type(T[name]) ~= "function" then return false end
  T.__woobleSprites = type(T.__woobleSprites) == "table" and T.__woobleSprites or {}
  if T.__woobleSprites[name] == T[name] then return true end
  local fn = make(T[name])
  T[name] = fn
  T.__woobleSprites[name] = fn
  return true
end

local function markTrue(x, y, w, h)
  local ok, PaletteFX = pcall(require, "src.render.PaletteFX")
  if ok and type(PaletteFX) == "table" and PaletteFX.markTrueColor then
    pcall(PaletteFX.markTrueColor, x, y, w, h)
  end
end

-- the species id of a pokemon record (DexEntryMenu.render is handed the record, not the id)
local idOfDef = setmetatable({}, { __mode = "k" })
local function speciesOfDef(data, def)
  if type(def) ~= "table" then return nil end
  local hit = idOfDef[def]
  if hit ~= nil then return hit or nil end
  for id, d in pairs(type(data) == "table" and type(data.pokemon) == "table" and data.pokemon or {}) do
    if type(d) == "table" then idOfDef[d] = id end
  end
  if idOfDef[def] == nil then idOfDef[def] = false end
  return idOfDef[def] or nil
end

local function require_(name)
  local ok, m = pcall(require, name)
  return ok and type(m) == "table" and m or nil
end

--- Every other screen that shows a Pokemon's picture. Their pics are kept in a field the
--- screen draws each frame (self.sprite ...) or come from a method; the field is set to the
--- current frame before each draw, so the art animates. Each gets the frame and whether it is
--- true colour (Gen1.keepsColour: else it is in the four shades, for the colour pass to colour).
--- Returns the names of those hooked.
function Gen1.installScreens(atlas)
  local done = {}
  -- -> the frame, and true when it is in its own colours; nil when there is no art
  local function front(game, species, mon, w, h, opts)
    if species == nil then return nil end
    local keeps = Gen1.keepsColour()
    local o = { shades = not keeps }
    for k, v in pairs(opts or {}) do o[k] = v end
    local f = Gen1.frame(atlas, game and game.data, species, "front", w or FRONT_BOX, h or FRONT_BOX, mon, o)
    if not f then return nil end
    return f, keeps
  end
  -- the screens the original never drew (OTHER SCREENS)
  local function other(game, species, mon, w, h, opts)
    if not on("other_sprites") then return nil end
    return front(game, species, mon, w, h, opts)
  end
  local function hooked(name, ok) if ok then done[#done + 1] = name end end

  -- the status screen (drawn mirrored, as the cart's): SUMMARY SPRITES, SUMMARY SIZE
  hooked("summary", wrap(require_("src.ui.SummaryMenu"), "draw", function(orig)
    return function(self, ...)
      if on("summary_sprites") and type(self.mon) == "table" then
        local f, tc = front(self.game, self.mon.species, self.mon, nil, nil,
                            { shrink = (tonumber(opt("summary_size", 100)) or 100) / 100, hdDex = true })
        if f then self.sprite, self.spriteTrueColor = f, tc end
      end
      return orig(self, ...)
    end
  end))

  -- the Pokedex entry: the species or the National Dex form on show (its LEFT / RIGHT form
  -- browsing sets formId); render is also used on its own, by the printer
  local Dex = require_("src.ui.DexEntryMenu")
  local inDexDraw = false
  hooked("pokedex", wrap(Dex, "draw", function(orig)
    return function(self, ...)
      if on("dex_sprites") then
        local f, tc = front(self.game, self.formId or self.species, nil, nil, nil, { hdDex = true })
        if f then self.sprite, self.spriteTrueColor = f, tc end
      end
      inDexDraw = true
      local ok, a, b = pcall(orig, self, ...)
      inDexDraw = false
      if not ok then error(a, 0) end
      return a, b
    end
  end))
  wrap(Dex, "render", function(orig)
    return function(game, def, sprite, forceOwned, trueColor, ...)
      if sprite ~= nil and not inDexDraw and on("dex_sprites") then
        local f, tc = front(game, speciesOfDef(game and game.data, def), nil, nil, nil, { hdDex = true })
        if f then sprite, trueColor = f, tc end
      end
      return orig(game, def, sprite, forceOwned, trueColor, ...)
    end
  end)

  -- the evolution movie: the species it starts as (noted on the first draw: mon.species
  -- turns into the new one when it ends) and the one it becomes
  hooked("evolution", wrap(require_("src.ui.EvolutionState"), "draw", function(orig)
    return function(self, ...)
      local mon = self.mon
      if type(mon) == "table" then
        self.__woobleFrom = self.__woobleFrom or mon.species
        local a, atc = other(self.game, self.__woobleFrom, mon)
        if a then self.oldSprite, self.oldSpriteTrueColor = a, atc end
        local b, btc = other(self.game, self.newSpecies, mon)
        if b then self.newSprite, self.newSpriteTrueColor = b, btc end
      end
      return orig(self, ...)
    end
  end))

  -- the trade movie: the Pokemon sent and the one received
  hooked("trade", wrap(require_("src.ui.TradeAnim"), "draw", function(orig)
    return function(self, ...)
      if type(self.sent) == "table" then
        local a, tc = other(self.game, self.sent.species, self.sent)
        if a then self.sentSprite, self.sentSpriteTrueColor = a, tc end
      end
      if type(self.received) == "table" then
        local b, tc = other(self.game, self.received.species, self.received)
        if b then self.recvSprite, self.recvSpriteTrueColor = b, tc end
      end
      return orig(self, ...)
    end
  end))

  -- the Hall of Fame: each party member's front, and its back for the sweep ahead of it (a
  -- 28x28 crop the screen draws at 2x: the frame holds twice that, so it keeps its detail)
  local HoF = require_("src.ui.HallOfFame")
  hooked("hall of fame", wrap(HoF, "spriteFor", function(orig)
    return function(self, species, ...)
      local f, tc = other(self.game, species)
      if f then
        if type(self.spriteTrueColor) == "table" then self.spriteTrueColor[species] = tc end
        return f
      end
      return orig(self, species, ...)
    end
  end))
  wrap(HoF, "backPicFor", function(orig)
    return function(self, ...)
      local party = self.game and self.game.save and self.game.save.party
      local mon = type(party) == "table" and party[self.index] or nil
      if type(mon) == "table" and on("other_sprites") then
        local keeps = Gen1.keepsColour()
        local f = Gen1.frame(atlas, self.game.data, mon.species, "back", 28, 28, mon,
                             { dpi = 2, shades = not keeps })
        if f then return f, keeps end
      end
      return orig(self, ...)
    end
  end)

  -- the Hall of Fame PC
  hooked("league pc", wrap(require_("src.ui.LeaguePC"), "draw", function(orig)
    return function(self, ...)
      local mon = type(self.currentMon) == "function" and self:currentMon() or nil
      if type(mon) == "table" and type(self.sprites) == "table" then
        local f, tc = other(self.game, mon.species, mon)
        if f then
          self.sprites[mon.species] = f
          if type(self.spriteTrueColor) == "table" then self.spriteTrueColor[mon.species] = tc end
        end
      end
      return orig(self, ...)
    end
  end))

  -- the title screen's cycling Pokemon
  hooked("title", wrap(require_("src.ui.TitleState"), "currentSprite", function(orig)
    return function(self, ...)
      local species = type(self.cycleSpecies) == "table" and self.cycleSpecies[self.cycleIndex] or nil
      local f, tc = other(self.game, species)
      if f then return f, tc end
      return orig(self, ...)
    end
  end))

  -- Oak's speech: the Pokemon he shows (a bare species id, or { type = "pokemon" })
  local Oak = require_("src.ui.OakSpeech")
  local PEOPLE = { oak = true, rival = true, player = true }
  hooked("oak speech", wrap(Oak, "resolvePic", function(orig)
    return function(game, desc, speech, ...)
      local img, flip, trueColor = orig(game, desc, speech, ...)
      local species
      if type(desc) == "string" and not PEOPLE[desc] then
        species = desc
      elseif type(desc) == "table" and desc.type == "pokemon" then
        species = desc.id
      end
      local f, tc = other(game, species)
      if f then return f, flip, tc end
      return img, flip, trueColor
    end
  end))

  -- the credits: each Pokemon as a silhouette (black in every colour mode)
  hooked("credits", wrap(require_("src.ui.Credits"), "monSprite", function(orig)
    return function(self, species, ...)
      local f = other(self.game, species, nil, nil, nil, { silhouette = true })
      if f then return f, false end
      return orig(self, species, ...)
    end
  end))

  -- party icons: a National Dex species or form has none of its own in the game; #1-151 keep
  -- the game's (atlas keys 1-151 are the cart's species), except on the G9 PARTY SCREEN, whose
  -- page is drawn 4x for ours. Two frames, alternating as the game's own do.
  hooked("party icons", wrap(require_("src.ui.PartyMenu"), "drawIcon", function(orig)
    return function(game, mon, x, y, selected, counter, forceAlt, obp, ...)
      local key = on("party_icons") and type(mon) == "table" and not mon.isEgg
        and Gen1.keyOf(atlas, game and game.data, mon.species) or nil
      if key and key > 0 and key <= CART_SPECIES and not Gen1.g9On() then key = nil end
      local entry = key and atlas.icon(key)
      if not entry then return orig(game, mon, x, y, selected, counter, forceAlt, obp, ...) end
      local alt = forceAlt or false
      if selected and type(mon.stats) == "table" then
        -- engine/gfx/mon_icons.asm:24: the lower the HP, the slower the icon steps
        local px = math.floor((mon.hp or 0) * 48 / math.max(1, mon.stats.hp or 1))
        local speed = px >= 27 and 5 or px >= 10 and 16 or 32
        alt = math.floor((counter or 0) / speed) % 2 == 1
      end
      local quad = entry.quads[alt and 1 or 0] or entry.quads[0]
      local keeps = Gen1.keepsColour()
      local shades = not keeps and atlas.shadesShader() or nil
      local G = love.graphics
      local prev = shades and G.getShader and G.getShader() or nil
      if shades then G.setShader(shades) end
      G.draw(entry.image, quad, x, y, 0, 16 / entry.w, 16 / entry.h)
      if shades then G.setShader(prev) end
      if keeps then markTrue(x, y, 16, 16) end
    end
  end))
  return done
end

--- The exports tectorifter's g9-battle-sprites gave other mods (portraits, party icons), with
--- its signatures and return values, from this atlas. `dataOf()` -> the game's data (for a
--- species' dex number and base species; nil before a game is up).
function Gen1.exports(atlas, dataOf)
  local ex = {}
  local function keyOfMon(mon)
    if type(mon) ~= "table" or mon.isEgg == true then return nil end
    local key = Gen1.keyOf(atlas, dataOf(), mon.species)
    if key and on("sprite_female") and Gen1.femaleOf(mon) then key = atlas.femaleKey(key) or key end
    return key
  end
  local function iconFrame(frame)
    if tonumber(frame) then return math.max(0, math.min(1, math.floor(tonumber(frame)))) end
    if not on("animate_sprites") then return 0 end
    return math.floor(love.timer.getTime() * (tonumber(opt("sprite_fps", 12)) or 12)) % 2
  end

  --- The front art's first frame at 1:1, cut to the art (always on, whatever the options):
  --- (image, width, height, box = the whole image, head = 0), or nil when there is none.
  ex.frontArt = function(mon)
    local key = keyOfMon(mon)
    if not key then return nil end
    local variant = variantFor(atlas, key, "front", on("sprite_shiny") and Gen1.shinyOf(mon))
    local cell = atlas.cell(key, variant)
    if not cell then return nil end
    local w = (tonumber(cell.ux1) or cell.fs) - (tonumber(cell.ux0) or 0)
    local h = (tonumber(cell.uy1) or cell.fs) - (tonumber(cell.uy0) or 0)
    local img = atlas.boxFrame(key, variant, 0, w, h, {})
    if not img then return nil end
    return img, w, h, { x = 0, y = 0, w = w, h = h }, 0
  end

  --- The party icon at its own detail: (quads = { full = quad }, image, cell pixels, box of its
  --- opaque pixels in the cell), or nil when there is none. `frame` (0-based) picks one frame,
  --- else the one playing now.
  ex.iconArtHD = function(mon, frame)
    local key = keyOfMon(mon)
    local entry = key and atlas.icon(key)
    if not entry then return nil end
    local f = iconFrame(frame)
    return { full = entry.quads[f] or entry.quads[0] }, entry.image, entry.w, atlas.iconBox(key, f)
  end

  --- The same icon, for callers that draw it in a 16x16 slot: (quads, image, cell pixels).
  ex.iconArt16 = function(mon, frame)
    local key = keyOfMon(mon)
    local entry = key and atlas.icon(key)
    if not entry then return nil end
    local f = iconFrame(frame)
    return { full = entry.quads[f] or entry.quads[0] }, entry.image, entry.w
  end

  --- The summary screen's picture, live, drawn into the caller's box ({ x, w, bottom }; the
  --- game's own by default): centred, its feet on `bottom`, mirrored as the summary draws it.
  --- false when SUMMARY SPRITES is off or there is no art.
  ex.drawSummaryFrame = function(mon, box)
    box = type(box) == "table" and box or { x = 8, w = 56, bottom = 56 }
    if not on("summary_sprites") or type(mon) ~= "table" or mon.isEgg == true then return false end
    local keeps = Gen1.keepsColour()
    local f = Gen1.frame(atlas, dataOf(), mon.species, "front", FRONT_BOX, FRONT_BOX, mon,
      { shrink = (tonumber(opt("summary_size", 100)) or 100) / 100, shades = not keeps })
    if not f then return false end
    local w, h = f:getDimensions()
    local x = (box.x or 0) + ((box.w or w) - w) / 2
    local y = math.max(0, (box.bottom or h) - h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(f, x + w, y, 0, -1, 1)
    if keeps then markTrue(math.floor(x), math.floor(y), w, h) end
    return true
  end
  return ex
end

-- The G9 PARTY SCREEN (g9_party_screen): the party menu drawn on a 640x576 page, 4x the Game
-- Boy's screen and filling the window, from the game's own parts (rows, HP bars, cursor, its
-- own action list), so each Pokemon's icon shows at its own detail. A classic screen pushed
-- over it (a message box, the summary) is drawn on the same page. tectorifter's
-- g9-battle-sprites' party screen, as it drew it on Red / Blue / Yellow.
local G9_SCALE = 4
local G9_W, G9_H = 160 * G9_SCALE, 144 * G9_SCALE

function Gen1.g9On() return opt("g9_party_screen", false) == true end

-- `name` on a state, its own or through its class (an __index table or function)
local function methodOf(state, name)
  if type(state[name]) == "function" then return state[name] end
  local mt = getmetatable(state)
  local idx = type(mt) == "table" and mt.__index or nil
  if type(idx) == "table" then
    if type(idx[name]) == "function" then return idx[name] end
  elseif type(idx) == "function" then
    local ok, fn = pcall(idx, state, name)
    if ok and type(fn) == "function" then return fn end
  end
  return nil
end

-- a screen's colour zones are in its own 160x144 pixels: on the page they take its 4x
local function scaleZones(zones)
  if type(zones) ~= "table" then return zones end
  local out = {}
  for i, z in ipairs(zones) do
    if type(z) == "table" then
      out[i] = { colors = z.colors, x = (z.x or 0) * G9_SCALE, y = (z.y or 0) * G9_SCALE,
                 w = (z.w or 0) * G9_SCALE, h = (z.h or 0) * G9_SCALE }
    end
  end
  return out
end

-- runs a classic draw under the page's 4x, its true-colour marks scaled with it
local function drawOnPage(draw, self, ...)
  local P = paletteFX()
  local mark = P and P.markTrueColor
  if type(mark) == "function" then
    P.markTrueColor = function(x, y, w, h) return mark(x * G9_SCALE, y * G9_SCALE, w * G9_SCALE, h * G9_SCALE) end
  end
  local G = love.graphics
  G.push()
  G.scale(G9_SCALE, G9_SCALE)
  local ok, a, b = pcall(draw, self, ...)
  G.pop()
  if type(mark) == "function" then P.markTrueColor = mark end
  if not ok then error(a, 0) end
  return a, b
end

-- Is the party menu on the stack this page? Another mod can take the menu over with a page of
-- its own size; dressing a screen over it for 640x576 would then take the surface from it.
local function ownsPage(party)
  local ui = methodOf(party, "uiSize")
  if not ui then return false end
  local ok, w, h = pcall(ui, party)
  return ok and w == G9_W and h == G9_H
end

-- A classic 160x144 screen pushed over the page is drawn on it at the same 4x (one that already
-- has a wide layout of its own is left alone).
local function dress(state)
  if type(state) ~= "table" or state.__woobleDressed then return end
  if methodOf(state, "uiSize") or methodOf(state, "drawsWidescreen") then return end
  local wideFn = methodOf(state, "isWideBattleLayout")
  if wideFn then
    local ok, wide = pcall(wideFn, state)
    if ok and wide then return end
  end
  local draw = methodOf(state, "draw")
  if not draw then return end
  state.__woobleDressed = true
  state.uiSize = function()
    if not Gen1.g9On() then return 160, 144 end
    return G9_W, G9_H
  end
  state.isWideBattleLayout = function() return Gen1.g9On() end
  state.wantsFillScale = function() return Gen1.g9On() end
  local sgb = methodOf(state, "sgbPalettes")
  if sgb then
    state.sgbPalettes = function(self, game)
      local zones = sgb(self, game)
      if not Gen1.g9On() then return zones end
      return scaleZones(zones)
    end
  end
  state.draw = function(self, ...)
    if not Gen1.g9On() then return draw(self, ...) end
    return drawOnPage(draw, self, ...)
  end
end

--- Installs the page on the party menu and the dressing of what is pushed over it. With the
--- option off, everything answers as the game's own.
function Gen1.installPartyScreen(PartyMenu, StateStack)
  if type(PartyMenu) ~= "table" or type(PartyMenu.draw) ~= "function" then return false end
  if PartyMenu.__woobleG9 then return true end
  PartyMenu.__woobleG9 = true
  local draw, sgb = PartyMenu.draw, PartyMenu.sgbPalettes
  -- (the engine asks uiSize every frame: the anchor hold, a plain field it reads from the
  -- stack, follows the option from there)
  PartyMenu.uiSize = function()
    local g9 = Gen1.g9On()
    PartyMenu.holdsUIAnchors = g9 and function() return true end or nil
    if not g9 then return 160, 144 end
    return G9_W, G9_H
  end
  PartyMenu.isWideBattleLayout = function() return Gen1.g9On() end
  PartyMenu.wantsFillScale = function() return Gen1.g9On() end
  PartyMenu.draw = function(self, ...)
    if not Gen1.g9On() then return draw(self, ...) end
    return drawOnPage(draw, self, ...)
  end
  PartyMenu.sgbPalettes = function(self, game)
    local zones = sgb and sgb(self, game) or nil
    if not Gen1.g9On() then return zones end
    return scaleZones(zones)
  end
  -- every screen pushed while the page is on the stack is dressed for it (StateStack.push is
  -- where screen.pushed comes from too)
  if type(StateStack) == "table" and type(StateStack.push) == "function" and not StateStack.__woobleG9 then
    StateStack.__woobleG9 = true
    local push = StateStack.push
    StateStack.push = function(self, state, ...)
      local a, b = push(self, state, ...)
      if Gen1.g9On() and type(self) == "table" and type(self.states) == "table" then
        for i = 1, #self.states do
          local party = self.states[i]
          local mt = getmetatable(party)
          if mt == PartyMenu or (type(mt) == "table" and mt.__index == PartyMenu) then
            if party ~= state and ownsPage(party) then pcall(dress, state) end
            break
          end
        end
      end
      return a, b
    end
  end
  return true
end

--- Installs every Gen 1 hook it can (again on each call: a screen another mod replaced since is
--- wrapped in turn). Returns the names of the screens hooked.
function Gen1.install(atlas, log)
  local done = {}
  local okB, BattleState = pcall(require, "src.battle.BattleState")
  if okB and Gen1.installBattle(atlas, BattleState) then done[#done + 1] = "battle" end
  for _, name in ipairs(Gen1.installScreens(atlas)) do done[#done + 1] = name end
  if Gen1.installPartyScreen(require_("src.ui.PartyMenu"), require_("src.core.StateStack")) then
    done[#done + 1] = "party screen"
  end
  return done
end

-- shared with src/gen2.lua (Gold / Silver / Crystal), which draws from the same atlas the same
-- way and reads the same options
Gen1.opt, Gen1.on, Gen1.wrap, Gen1.require_ = opt, on, wrap, require_
Gen1.variantFor, Gen1.speciesOfDef = variantFor, speciesOfDef

return Gen1
