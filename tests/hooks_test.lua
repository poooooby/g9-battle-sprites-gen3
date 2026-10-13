-- Headless check of the slot gate in src/hooks.lua: the slots the atlas has art for (Gen 1-3
-- at their internal ids, #387-1025 and the forms above them) reach the atlas, everything else
-- (Unown's letters, the Egg) reaches the engine's own functions untouched, and a second install
-- must not stack wrappers. Run from the mod root:
--   luajit tests/hooks_test.lua
local Hooks = dofile("src/hooks.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a fake atlas: answers every slot it has art for -- the base species (451-1089,
-- dex + 64) and the alternate forms (1090-1217), plus the female Meowstic sheet kept under -742 -- with one cell per variant
-- the Gen 1-3 slots: 1-251, then Treecko .. Deoxys (277-411), minus Unown (201)
local function has(slot)
  return (slot >= 451 and slot <= 1217) or slot == -742
    or (slot >= 1 and slot <= 251 and slot ~= 201) or (slot >= 277 and slot <= 411)
end
local calls = {}
local atlas = {
  hasSlot = has,
  cell = function(slot, variant)
    if has(slot) then return { page = 0, x = 0, y = 0, fw = 64, fh = 64, cols = 1, frames = 1 } end
    return nil
  end,
  frameIndex = function() return 0 end,
  picFrame = function(dex, variant, _cell, _f, battle, kind)
    calls[#calls + 1] = dex .. ":" .. variant; calls.battle = battle; calls.kind = kind; return { fake = variant }
  end,
  -- Gen 1-3 keep the game's own party icons: the atlas has none for them
  icon = function(slot) return (slot >= 451 and has(slot)) and { fake_icon = slot } or nil end,
}

local function origFront(species) return { orig = "front", species = species } end
local function origBack(species) return { orig = "back", species = species } end
local function origIcon(species) return { orig = "icon", species = species } end
local Pokemon = { frontPic = origFront, backPic = origBack, icon = origIcon }

local n = Hooks.install(Pokemon, atlas)
check(n == 3, "three functions wrapped, got " .. tostring(n))

-- Gen 1-3 come from the atlas, at their internal slots, except for the party icon
check(Pokemon.frontPic(25, 0, false).image.fake == "front", "slot 25 (Pikachu) front comes from the atlas")
check(Pokemon.backPic(25, 0, false).image.fake == "back", "slot 25 back comes from the atlas")
check(Pokemon.frontPic(277, 0, false).image.fake == "front", "slot 277 (Treecko, dex 252) front comes from the atlas")
check(Pokemon.icon(25).orig == "icon", "slot 25 icon stays the game's own")
check(Pokemon.icon(277).orig == "icon", "slot 277 icon stays the game's own")
-- what has no sheet stays the engine's: Unown, the Egg and Unown's letters, the unused slots
check(Pokemon.frontPic(201, 0, false).orig == "front", "Unown (201) front stays vanilla")
check(Pokemon.frontPic(412, 0, false).orig == "front", "the Egg (412) stays vanilla")
check(Pokemon.frontPic(413, 0, false).orig == "front", "Unown B (413) stays vanilla")
check(Pokemon.backPic(260, 0, false).orig == "back", "an unused slot (260) stays vanilla")
-- a pic asked for in an alternate form (Castform's weather looks) is the engine's
check(Pokemon.frontPic(385, 2, false).orig == "front", "Castform in a weather form (form 2) front stays vanilla")
check(Pokemon.backPic(385, 3, false).orig == "back", "...and back")
check(Pokemon.frontPic(385, 0, false).image.fake == "front", "...but form 0 is the atlas's")
-- slot 451 is dex 387, the first new species
check(Pokemon.frontPic(451, 0, false).image.fake == "front", "dex 387 front comes from the atlas")
check(Pokemon.backPic(451, 0, false).image.fake == "back", "dex 387 back comes from the atlas")
check(Pokemon.icon(451).fake_icon == 451, "dex 387 icon comes from the atlas")
-- the top of the range, and one past it
check(Pokemon.frontPic(1089, 0, false).image.fake == "front", "dex 1025 (slot 1089) from the atlas")
check(Pokemon.frontPic(1218, 0, false).orig == "front", "slot 1218 (past the last form) stays vanilla")

-- a female Meowstic (slot 742) has a sheet of its own, reached by the personality
do
  local P = { frontPic = origFront, backPic = origBack, icon = origIcon,
              gender = function(slot, personality) return personality % 2 == 1 and "F" or "M" end }
  Hooks.install(P, atlas)
  calls[#calls + 1] = "mark"
  P.frontPic(742, 0, false, 3)
  check(calls[#calls] == "-742:front", "a female Meowstic gets the female sheet, got " .. tostring(calls[#calls]))
  P.frontPic(742, 0, false, 2)
  check(calls[#calls] == "742:front", "a male gets the species' own, got " .. tostring(calls[#calls]))
  P.frontPic(742, 0, false)
  check(calls[#calls] == "742:front", "with no personality too, got " .. tostring(calls[#calls]))
  P.frontPic(742, 0, true, 3)
  check(calls[#calls] == "-742:front_shiny", "shiny and female, got " .. tostring(calls[#calls]))
  P.frontPic(743, 0, false, 3)
  check(calls[#calls] == "743:front", "a species with no female sheet keeps its own, got " .. tostring(calls[#calls]))
end
-- an alternate form has a slot of its own and is answered like any other
check(Pokemon.frontPic(1105, 0, false).image.fake == "front", "a form slot (ROTOM_HEAT, 1105) comes from the atlas")
check(Pokemon.backPic(1105, 0, false).image.fake == "back", "and its back")
check(Pokemon.icon(1105).fake_icon == 1105, "and its icon")
-- shiny asks for the shiny variant
Pokemon.frontPic(500, 0, true)
check(calls[#calls] == "500:front_shiny", "shiny asks for front_shiny, got " .. tostring(calls[#calls]))

-- the battle scene gets the full-size front pic, every other screen the plain one:
-- the engine's Battle.draw is wrapped, and a pic asked for inside it is a battle pic
do
  local drawn = 0
  local Battle = { draw = function(...)
    drawn = drawn + 1
    calls.battle = nil
    Pokemon.frontPic(451, 0, false)
    calls.inside = calls.battle
    return "drew"
  end }
  local P2 = { frontPic = origFront, backPic = origBack, icon = origIcon }
  Hooks.install(P2, atlas, Battle)
  Pokemon = P2 -- the wrappers on P2 are the ones under test
  calls.battle = nil
  P2.frontPic(451, 0, false)
  check(calls.battle == false, "outside the battle scene: the plain pic")
  check(Battle.draw(1, 2, 3) == "drew", "Battle.draw still returns what the engine's does")
  check(calls.inside == true, "inside Battle.draw: the battle pic")
  calls.battle = nil
  P2.frontPic(451, 0, false)
  check(calls.battle == false, "after it: the plain pic again")
  -- an error in the scene's draw still leaves the flag cleared and propagates
  local Broken = { draw = function() Pokemon.frontPic(451, 0, false); error("boom", 0) end }
  local P3 = { frontPic = origFront, backPic = origBack, icon = origIcon }
  Hooks.install(P3, atlas, Broken)
  Pokemon = P3
  local ok, err = pcall(Broken.draw)
  check(not ok and err == "boom", "an error in Battle.draw propagates")
  calls.battle = nil
  P3.frontPic(451, 0, false)
  check(calls.battle == false, "...and does not leave the scene flagged as drawing")
  -- installing twice does not wrap Battle.draw twice
  local before = Battle.draw
  Hooks.install(P2, atlas, Battle)
  check(Battle.draw == before, "a second install leaves Battle.draw alone")
  Pokemon = P2
end

-- the RSE entry animation: on its frame 1 the battle asks MonAnim.framePic for the cart's own
-- art; a species with atlas art answers nil (its pic stays), the rest keep the cart's frame
do
  local function cartFrame(species, frame) return { cart = species, frame = frame } end
  local MonAnim = { framePic = cartFrame }
  local P4 = { frontPic = origFront, backPic = origBack, icon = origIcon }
  local n4 = Hooks.install(P4, atlas, false, MonAnim)
  check(n4 == 4, "framePic is wrapped too, got " .. tostring(n4))
  check(MonAnim.framePic(16, 1, false) == nil, "Pidgey (16) mid-intro keeps our pic, not the cart's frame")
  check(MonAnim.framePic(451, 1, true) == nil, "...a new species too")
  check(MonAnim.framePic(201, 1, false).cart == 201, "Unown (no atlas art) keeps the cart's frame")
  local wrappedFrame = MonAnim.framePic
  Hooks.install(P4, atlas, false, MonAnim)
  check(MonAnim.framePic == wrappedFrame, "a second install leaves framePic's wrapper alone")
end

-- a second install (a reload) must not wrap the wrappers
local before = Pokemon.frontPic
Hooks.install(Pokemon, atlas)
check(Pokemon.frontPic == before, "second install leaves the wrapper in place")
check(Pokemon.frontPic(413, 0, false).orig == "front", "still falls through after a second install")

-- the RSE Pokedex wheel gets the party icon, an entry's page keeps the animated sheet
do
  atlas.iconPic = function(slot) return (slot >= 451 and has(slot)) and { fake_icon_pic = slot } or nil end
  local dexState = { page = 0 }
  Hooks._resetRseDex({ PAGE = { MAIN = 0, INFO = 1, SEARCH_RESULTS = 3 }, active = function() return dexState end })
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.fake_icon_pic == 500, "the dex list draws the icon pic")
  check(Pokemon.frontPic(25, 0, false, 0, "dex").orig == "front", "no icon (Gen 1-3): the game's own pic in the list")
  check(Pokemon.frontPic(500, 0, false, 0).image.fake == "front", "no kind: still the animated sheet")
  dexState.page = 1
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.fake == "front", "an entry's page keeps the animated sheet")
  check(calls.kind == "dex", "...and the atlas is told it is for the Pokedex")
  Pokemon.frontPic(500, 0, false, 0)
  check(calls.kind == nil, "a pic for another screen has no kind")
  dexState.page = 0; dexState.caught = {}
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.fake == "front", "the caught screen keeps the animated sheet")
  -- with an atlas that has live pics, an RSE entry page gets the live canvas
  dexState.caught = nil; dexState.page = 1
  atlas.livePic = function(key, variant) return { live = key .. ":" .. variant } end
  atlas.refreshLive = function() end
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.live == "500:front", "an RSE entry page gets the live pic")
  check(Pokemon.frontPic(500, 0, true, 0, "dex").image.live == "500:front_shiny", "...the shiny one when shiny")
  dexState.page = 0
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.fake_icon_pic == 500, "...and the wheel still the icon")
  atlas.livePic, atlas.refreshLive = nil, nil
  Hooks._resetRseDex(nil)
  check(Pokemon.frontPic(500, 0, false, 0, "dex").image.fake == "front", "no Pokedex screen: the animated sheet")
end

-- the save editor: a front pic asked for without a kind is cut to the creature's own pixels
do
  local savedLove = love
  local pasted
  love = {
    image = { newImageData = function(w, h)
      return { w = w, h = h, paste = function(self, _, dx, dy, sx, sy, sw, sh) pasted = { sx, sy, sw, sh } end }
    end },
    graphics = { newImage = function(data)
      return { data = data, setFilter = function() end, getDimensions = function() return data.w, data.h end }
    end },
  }
  -- a 64x64 canvas whose creature fills x 20..29, y 40..59
  local canvas = { newImageData = function()
    return { getDimensions = function() return 64, 64 end,
             getPixel = function(_, x, y) return 0, 0, 0, (x >= 20 and x <= 29 and y >= 40 and y <= 59) and 1 or 0 end }
  end }
  local out = Hooks.fit({ image = canvas, w = 64, h = 64 })
  check(out.w == 10 and out.h == 20, "the editor's pic is the creature's own size")
  check(pasted and pasted[1] == 20 and pasted[2] == 40, "cut from where the creature is")
  check(Hooks.fit({ image = canvas }).image == out.image, "read once per canvas")
  local blank = { newImageData = function()
    return { getDimensions = function() return 4, 4 end, getPixel = function() return 0, 0, 0, 0 end }
  end }
  local entry = { image = blank, w = 64, h = 64 }
  check(Hooks.fit(entry) == entry, "an empty canvas is returned as it is")
  local image = { getDimensions = function() return 64, 64 end }   -- an Image cannot be read back
  local plain = { image = image }
  check(Hooks.fit(plain) == plain, "and so is a pic that cannot be read back")
  love = savedLove
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 hooks)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
