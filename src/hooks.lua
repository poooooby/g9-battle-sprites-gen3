-- Puts the atlas art in front of the gen 3 engine's own picture functions.
--
-- Only species #387-1025 are answered (slot = dex + 64, the numbering
-- national_dex_gen3 registers under). Every other slot falls through to the
-- engine's own functions, so the game's gen 1-3 sprites stay exactly as they
-- are.
--
--   Pokemon.frontPic  battle (enemy), Pokedex front, party summary
--   Pokemon.backPic   battle (player)
--   Pokemon.icon      party list icon (and any other 16x16 icon user)

local Hooks = {}

local FIRST_DEX, LAST_DEX = 387, 1025
local SLOT_OFFSET = 64

local function dexOf(slot)
  local dex = (tonumber(slot) or 0) - SLOT_OFFSET
  if dex < FIRST_DEX or dex > LAST_DEX then return nil end
  return dex
end

-- Pokemon.frontPic(species, form, shiny, personality) / backPic(species, form, shiny)
local function picFor(atlas, side, slot, shiny)
  local dex = dexOf(slot)
  if not dex then return nil end
  -- a shiny asks for the shiny sheet, and falls back to the normal one when
  -- the atlas has no shiny for the species
  local variant = side
  if shiny and atlas.cell(dex, side .. "_shiny") then variant = side .. "_shiny" end
  local cell = atlas.cell(dex, variant)
  if not cell then return nil end
  local f = atlas.frameIndex(cell)
  local canvas = atlas.picFrame(dex, variant, cell, f)
  if not canvas then return nil end
  return { image = canvas, w = 64, h = 64 }
end

-- Our own wrappers, so a reload that finds one still in place does not wrap it
-- again (wrapping a wrapper would stack the lookups).
local ours = setmetatable({}, { __mode = "k" })

-- Installs the wrappers over whatever the engine currently has. Safe to call
-- again after a reload: a function that is already ours is left alone.
-- Returns the number of functions wrapped.
function Hooks.install(Pokemon, atlas)
  if type(Pokemon) ~= "table" then return 0 end
  local wrapped = 0

  local origFront = Pokemon.frontPic
  if type(origFront) == "function" and not ours[origFront] then
    Pokemon.frontPic = function(species, form, shiny, personality)
      local entry = picFor(atlas, "front", species, shiny)
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
      local entry = picFor(atlas, "back", species, shiny)
      if entry then return entry end
      return origBack(species, form, shiny)
    end
    ours[Pokemon.backPic] = true
    wrapped = wrapped + 1
  end

  local origIcon = Pokemon.icon
  if type(origIcon) == "function" and not ours[origIcon] then
    Pokemon.icon = function(species)
      local dex = dexOf(species)
      local entry = dex and atlas.icon(dex)
      if entry then return entry end
      return origIcon(species)
    end
    ours[Pokemon.icon] = true
    wrapped = wrapped + 1
  end

  return wrapped
end

Hooks._dexOf = dexOf

return Hooks
