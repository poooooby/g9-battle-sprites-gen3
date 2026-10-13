-- Puts the atlas art in front of the gen 3 engine's own picture functions.
--
-- The atlas index (data/atlas_index.lua) says which slots have art: Gen 1-3 (#1-386) at
-- their own internal slots, the species national_dex_gen3 registers (#387-1025 at slot
-- dex + 64) and its alternate forms (WORMADAM_SANDY, ...) at slots of their own above
-- that, and Unown's letters at the cart's letter slots (B .. ? at 413 .. 439). Every other
-- slot (the Egg ...) falls through to the engine's own
-- functions, as does a Castform in one of its weather forms (the pic call carries `form`).
--
--   Pokemon.frontPic  battle (enemy), Pokedex front, party summary
--   Pokemon.backPic   battle (player)
--   Pokemon.icon      party list icon (and any other 16x16 icon user)
--   MonAnim.framePic  the cart's frame-1 art mid entry animation (RSE): ours keep their pic

local Hooks = {}

-- the slot, when the atlas has art for it
local function slotOf(atlas, slot)
  slot = tonumber(slot)
  if slot and atlas.hasSlot(slot) then return slot end
  return nil
end

-- A female Meowstic or Oinkologne has a sheet of its own, kept under the negative of the
-- species' slot (src/atlas.lua); every other Pokemon, and a male, has the species' own.
local function keyFor(atlas, Pokemon, slot, personality)
  local key = slotOf(atlas, slot)
  if key and personality ~= nil and atlas.hasSlot(-key) and type(Pokemon.gender) == "function"
      and Pokemon.gender(key, personality) == "F" then
    return -key
  end
  return key
end

-- A pic asked for in an alternate form (Castform's sun / rain / hail look) is not ours:
-- the atlas has one sheet per species, so it would show the normal Castform in every
-- weather.
local function inForm(form)
  return (tonumber(form) or 0) ~= 0
end

-- Pokemon.frontPic(species, form, shiny, personality) / backPic(species, form, shiny)
-- `key`: the atlas key, from keyFor
-- `kind`: what the engine says the pic is for ("dex" for the Pokedex screens)
local function picFor(atlas, side, key, shiny, battle, kind)
  if not key then return nil end
  -- a shiny asks for the shiny sheet, and falls back to the normal one when
  -- the atlas has no shiny for the species
  local variant = side
  if shiny and atlas.cell(key, side .. "_shiny") then variant = side .. "_shiny" end
  local cell = atlas.cell(key, variant)
  if not cell then return nil end
  local f = atlas.frameIndex(cell)
  local canvas = atlas.picFrame(key, variant, cell, f, battle, kind)
  if not canvas then return nil end
  return { image = canvas, w = 64, h = 64 }
end

-- True while the engine's battle scene is being drawn. The battle draws a pic with its
-- centre on the battler's spot, so a pic bigger than 64x64 can be pointed at there; the
-- Pokedex, summary, PC and the other screens draw it as a plain 64x64 image and must not
-- get one. (Found by running the real engine: a mod cannot inspect the call stack, its
-- sandbox has no `debug`, so the scene's own draw function is wrapped instead.)
-- The Ruby/Sapphire/Emerald Pokedex screen module, through require: a mod's `package.loaded` is
-- not the engine's. nil in a game without it (looked up once).
local rseDexModule, rseDexTried = nil, false
local function rseDex()
  if not rseDexTried and type(require) == "function" then
    rseDexTried = true
    local ok, m = pcall(require, "src.ui.game3.rse.pokedex")
    if ok and type(m) == "table" then rseDexModule = m end
  end
  return rseDexModule
end
Hooks._rseDex = rseDex
Hooks._resetRseDex = function(m) rseDexModule, rseDexTried = m, m ~= nil end   -- tests

-- Which RSE Pokedex page is up: "list" (the wheel, or search results), "page" (an entry, its
-- area, cry and size pages, the caught screen), or nil when that Pokedex is not open.
function Hooks._rseDexPage()
  local Dex = rseDex()
  local s = Dex and type(Dex.active) == "function" and Dex.active()
  if type(s) ~= "table" then return nil end
  local P = Dex.PAGE or {}
  if not s.caught and (s.page == P.MAIN or s.page == P.SEARCH_RESULTS) then return "list" end
  return "page"
end
function Hooks._inDexList() return Hooks._rseDexPage() == "list" end

local drawingBattle = 0
local function inBattle() return drawingBattle > 0 end
Hooks._inBattle = inBattle

-- Our own wrappers, so a reload that finds one still in place does not wrap it
-- again (wrapping a wrapper would stack the lookups).
local ours = setmetatable({}, { __mode = "k" })
Hooks._ours = ours

-- Installs the wrappers over whatever the engine currently has. Safe to call
-- again after a reload: a function that is already ours is left alone.
-- Returns the number of functions wrapped.
--- `Battle` is the engine's battle module and `MonAnim` its entry-animation module (each
--- looked up when nil).
--- Wrap the RSE Pokedex's draws (the module's and its stack Host's: national_dex_gen3 swaps in
--- a copy whose Host.draw calls the copy's own draw) so each frame first redraws the live
--- entry pics. Safe to call often: a draw already wrapped is left alone.
function Hooks.tickRseDex(atlas)
  local Dex = rseDex()
  if not (Dex and atlas and atlas.refreshLive) then return end
  for _, t in ipairs({ Dex, Dex.Host }) do
    local draw = type(t) == "table" and t.draw
    if type(draw) == "function" and not Hooks._ours[draw] then
      t.draw = function(...)
        pcall(atlas.refreshLive)
        return draw(...)
      end
      Hooks._ours[t.draw] = true
    end
  end
end

-- The gen1recomp save editor draws a species pic scaled to fit its slot. The engine's own pics
-- fill their 64x64 box, but ours keep the game's true size, so a small species sits in a mostly
-- empty canvas and came out a speck. When the editor is the host (main.lua sets Hooks.inEditor),
-- a front pic asked for without a `kind` (the editor's call) is cut to the creature's own pixels,
-- read once per canvas. Anything that cannot be read back is returned as it is.
Hooks.inEditor = false
local fitted = setmetatable({}, { __mode = "k" })
function Hooks.fit(entry)
  local canvas = type(entry) == "table" and entry.image
  if not (canvas and love and love.image and love.graphics) then return entry end
  local hit = fitted[canvas]
  if hit == nil then
    local ok, cut = pcall(function()
      if type(canvas.newImageData) ~= "function" then return false end
      local data = canvas:newImageData()
      local pw, ph = data:getDimensions()
      local x0, y0, x1, y1 = pw, ph, -1, -1
      for py = 0, ph - 1 do
        for px = 0, pw - 1 do
          local _, _, _, a = data:getPixel(px, py)
          if a > 0.05 then
            if px < x0 then x0 = px end
            if px > x1 then x1 = px end
            if py < y0 then y0 = py end
            if py > y1 then y1 = py end
          end
        end
      end
      if x1 < x0 then return false end
      local w, h = x1 - x0 + 1, y1 - y0 + 1
      local part = love.image.newImageData(w, h)
      part:paste(data, 0, 0, x0, y0, w, h)
      local img = love.graphics.newImage(part)
      img:setFilter("nearest", "nearest")
      return img
    end)
    hit = ok and cut or false
    fitted[canvas] = hit
  end
  if not hit then return entry end
  local w, h = hit:getDimensions()
  return { image = hit, w = w, h = h }
end

function Hooks.install(Pokemon, atlas, Battle, MonAnim)
  if type(Pokemon) ~= "table" then return 0 end
  local wrapped = 0

  -- the battle scene's draw: everything it asks for is a battle pic
  if Battle == nil then
    local loaded = package and package.loaded
    Battle = loaded and loaded["src.core.game3.battle"]
    if Battle == nil and type(require) == "function" then
      local ok, mod = pcall(require, "src.core.game3.battle")
      Battle = ok and mod or nil
    end
  end
  local origDraw = type(Battle) == "table" and Battle.draw
  if type(origDraw) == "function" and not ours[origDraw] then
    local function finish(ok, ...)
      drawingBattle = math.max(0, drawingBattle - 1)
      if not ok then error((...), 0) end
      return ...
    end
    Battle.draw = function(...)
      drawingBattle = drawingBattle + 1
      return finish(pcall(origDraw, ...))
    end
    ours[Battle.draw] = true
  end

  local origFront = Pokemon.frontPic
  if type(origFront) == "function" and not ours[origFront] then
    Pokemon.frontPic = function(species, form, shiny, personality, kind)
      local rsePage = kind == "dex" and Hooks._rseDexPage() or nil
      if rsePage == "list" then
        -- the RSE Pokedex wheel: one still frame, the cart's own front pic (else the party icon's)
        local key = keyFor(atlas, Pokemon, species, personality)
        local canvas = key and ((atlas.dexPic and atlas.dexPic(key, 0))
          or (atlas.iconPic and atlas.iconPic(key)))
        if canvas then return { image = canvas, w = 64, h = 64 } end
        return origFront(species, form, shiny, personality, kind)
      elseif rsePage == "page" and not inForm(form) and atlas.livePic then
        -- an RSE entry keeps the image it is given: a live canvas, so it animates (the cart's
        -- two frames, else the battle sheet)
        Hooks.tickRseDex(atlas)
        local key = keyFor(atlas, Pokemon, species, personality)
        local variant = "front"
        if key and shiny and atlas.cell(key, "front_shiny") then variant = "front_shiny" end
        local cell = key and atlas.cell(key, variant)
        local canvas = cell and atlas.livePic(key, variant, cell)
        if canvas then return { image = canvas, w = 64, h = 64 } end
      end
      local entry = not inForm(form)
        and picFor(atlas, "front", keyFor(atlas, Pokemon, species, personality), shiny, inBattle(), kind)
      if entry and Hooks.inEditor and kind == nil then return Hooks.fit(entry) end
      if entry then return entry end
      return origFront(species, form, shiny, personality, kind)
    end
    ours[Pokemon.frontPic] = true
    -- the engine keeps an alias to the same function
    if Pokemon.frontSprite == origFront then Pokemon.frontSprite = Pokemon.frontPic end
    wrapped = wrapped + 1
  end

  local origBack = Pokemon.backPic
  if type(origBack) == "function" and not ours[origBack] then
    Pokemon.backPic = function(species, form, shiny)
      local entry = not inForm(form) and picFor(atlas, "back", slotOf(atlas, species), shiny)
      if entry then return entry end
      return origBack(species, form, shiny)
    end
    ours[Pokemon.backPic] = true
    wrapped = wrapped + 1
  end

  local origIcon = Pokemon.icon
  if type(origIcon) == "function" and not ours[origIcon] then
    Pokemon.icon = function(species)
      local key = slotOf(atlas, species)
      local entry = key and atlas.icon(key)
      if entry then return entry end
      return origIcon(species)
    end
    ours[Pokemon.icon] = true
    wrapped = wrapped + 1
  end

  -- Ruby / Sapphire / Emerald play the cart's entry animation as a Pokemon comes out, and on
  -- its second frame the battle draws the cart's own frame-1 art (MonAnim.framePic) in place of
  -- the pic. For a species with atlas art that flashed the old sprite (its palette, size and
  -- pose) mid-intro; answering nil keeps our animated pic, still moved by the cart's motion.
  if MonAnim == nil and type(require) == "function" then
    local ok, mod = pcall(require, "src.core.game3.mon_anim")
    MonAnim = ok and type(mod) == "table" and mod or nil
  end
  local origFrame = type(MonAnim) == "table" and MonAnim.framePic
  if type(origFrame) == "function" and not ours[origFrame] then
    MonAnim.framePic = function(species, frame, shiny, ...)
      if slotOf(atlas, species) then return nil end
      return origFrame(species, frame, shiny, ...)
    end
    ours[MonAnim.framePic] = true
    wrapped = wrapped + 1
  end

  pcall(Hooks.tickRseDex, atlas)
  return wrapped
end

Hooks._slotOf = slotOf

return Hooks
