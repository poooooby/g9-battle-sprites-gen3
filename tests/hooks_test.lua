-- Headless check of the dex gate in src/hooks.lua: species #1-386 must reach
-- the engine's own functions untouched, #387-1025 must reach the atlas, and a
-- second install must not stack wrappers. Run from the mod root:
--   luajit tests/hooks_test.lua
local Hooks = dofile("src/hooks.lua")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a fake atlas: answers every dex in 387-1025 with one cell per variant
local calls = {}
local atlas = {
  cell = function(dex, variant)
    if dex >= 387 and dex <= 1025 then return { page = 0, x = 0, y = 0, fw = 64, fh = 64, cols = 1, frames = 1 } end
    return nil
  end,
  frameIndex = function() return 0 end,
  picFrame = function(dex, variant, _cell, _f, battle) calls[#calls + 1] = dex .. ":" .. variant; calls.battle = battle; return { fake = variant } end,
  icon = function(dex) return dex >= 387 and { fake_icon = dex } or nil end,
}

local function origFront(species) return { orig = "front", species = species } end
local function origBack(species) return { orig = "back", species = species } end
local function origIcon(species) return { orig = "icon", species = species } end
local Pokemon = { frontPic = origFront, backPic = origBack, icon = origIcon }

local n = Hooks.install(Pokemon, atlas)
check(n == 3, "three functions wrapped, got " .. tostring(n))

-- gen 3 species below the new range keep the engine's own pic
check(Pokemon.frontPic(25, 0, false).orig == "front", "dex 25 front stays vanilla")
check(Pokemon.backPic(25, 0, false).orig == "back", "dex 25 back stays vanilla")
check(Pokemon.icon(25).orig == "icon", "dex 25 icon stays vanilla")
-- slot 451 is dex 387, the first new species
check(Pokemon.frontPic(451, 0, false).image.fake == "front", "dex 387 front comes from the atlas")
check(Pokemon.backPic(451, 0, false).image.fake == "back", "dex 387 back comes from the atlas")
check(Pokemon.icon(451).fake_icon == 387, "dex 387 icon comes from the atlas")
-- the top of the range, and one past it
check(Pokemon.frontPic(1089, 0, false).image.fake == "front", "dex 1025 (slot 1089) from the atlas")
check(Pokemon.frontPic(1090, 0, false).orig == "front", "slot 1090 (past the range) stays vanilla")
-- shiny asks for the shiny variant
Pokemon.frontPic(500, 0, true)
check(calls[#calls] == "436:front_shiny", "shiny asks for front_shiny, got " .. tostring(calls[#calls]))

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

-- a second install (a reload) must not wrap the wrappers
local before = Pokemon.frontPic
Hooks.install(Pokemon, atlas)
check(Pokemon.frontPic == before, "second install leaves the wrapper in place")
check(Pokemon.frontPic(25, 0, false).orig == "front", "still falls through after a second install")

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 hooks)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
