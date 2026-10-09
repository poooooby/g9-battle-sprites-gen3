-- Puts the atlas art in front of the gen 3 engine's own picture functions.
--
-- The atlas index (data/atlas_index.lua) says which slots have art: Gen 1-3 (#1-386) at
-- their own internal slots, the species national_dex_gen3 registers (#387-1025 at slot
-- dex + 64) and its alternate forms (WORMADAM_SANDY, ...) at slots of their own above
-- that. Every other slot (Unown's letters, the Egg ...) falls through to the engine's own
-- functions, as does a Castform in one of its weather forms (the pic call carries `form`).
--
--   Pokemon.frontPic  battle (enemy), Pokedex front, party summary
--   Pokemon.backPic   battle (player)
--   Pokemon.icon      party list icon (and any other 16x16 icon user)

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
local function picFor(atlas, side, key, shiny, battle)
  if not key then return nil end
  -- a shiny asks for the shiny sheet, and falls back to the normal one when
  -- the atlas has no shiny for the species
  local variant = side
  if shiny and atlas.cell(key, side .. "_shiny") then variant = side .. "_shiny" end
  local cell = atlas.cell(key, variant)
  if not cell then return nil end
  local f = atlas.frameIndex(cell)
  local canvas = atlas.picFrame(key, variant, cell, f, battle)
  if not canvas then return nil end
  return { image = canvas, w = 64, h = 64 }
end

-- True while the engine's battle scene is being drawn. The battle draws a pic with its
-- centre on the battler's spot, so a pic bigger than 64x64 can be pointed at there; the
-- Pokedex, summary, PC and the other screens draw it as a plain 64x64 image and must not
-- get one. (Found by running the real engine: a mod cannot inspect the call stack, its
-- sandbox has no `debug`, so the scene's own draw function is wrapped instead.)
local drawingBattle = 0
local function inBattle() return drawingBattle > 0 end
Hooks._inBattle = inBattle

-- Our own wrappers, so a reload that finds one still in place does not wrap it
-- again (wrapping a wrapper would stack the lookups).
local ours = setmetatable({}, { __mode = "k" })

-- Installs the wrappers over whatever the engine currently has. Safe to call
-- again after a reload: a function that is already ours is left alone.
-- Returns the number of functions wrapped.
--- `Battle` is the engine's battle module (looked up when nil).
function Hooks.install(Pokemon, atlas, Battle)
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
    Pokemon.frontPic = function(species, form, shiny, personality)
      local entry = not inForm(form)
        and picFor(atlas, "front", keyFor(atlas, Pokemon, species, personality), shiny, inBattle())
      if entry then return entry end
      return origFront(species, form, shiny, personality)
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

  return wrapped
end

Hooks._slotOf = slotOf

return Hooks
