-- Run from the mod root: luajit tests/editor_test.lua
-- The save editor with a Gen 1 / 2 save (src/editor.lua): MonEditor.sprite answers our front
-- art's first frame, copied out of the frame cache, for Red to Crystal saves only; an egg, a
-- species with no art and Gen 3 saves get the editor's own; shiny, female and Unown's letter
-- pick the art; the wrap is put on once, and a later load points it at its own atlas.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

love = { timer = { getTime = function() return 0 end } }

local Gen1 = dofile("src/gen1.lua")
local Editor = dofile("src/editor.lua")
local opts = {}
Gen1.options = function(key) return opts[key] end

-- a fake atlas: PIKACHU 25 (shiny too), UNOWN 201, UNOWN_C its own sheet, MEOWSTIC 678 (female 10678)
local framesDrawn = {}
local function fakeAtlas(tag)
  local keys = { PIKACHU = 25, UNOWN = 201, UNOWN_C = 2001, MEOWSTIC = 678 }
  local a = {}
  function a.keyFor(id) return keys[id] end
  function a.femaleKey(k) return k == 678 and 10678 or nil end
  function a.cell(k, variant)
    if variant == "front_shiny" and k ~= 25 then return nil end
    return { fs = 96, ux0 = 10, ux1 = 70, uy0 = 20, uy1 = 90, frames = 4 }
  end
  function a.boxFrame(k, variant, f, w, h)
    local frame = { tag = tag, key = k, variant = variant, f = f, w = w, h = h }
    framesDrawn[#framesDrawn + 1] = frame
    return frame
  end
  return a
end
local function fit(entry) return { image = { copy = entry.image }, w = entry.w, h = entry.h } end

-- the editor's modules
package.loaded["Gen"] = { ofState = function(S) return S.gen end }
local MonEditor = { sprite = function(S, species) return "EDITOR'S " .. tostring(species) end }
package.loaded["MonEditor"] = MonEditor
package.loaded["src.core.gen2.Unown"] = {
  monLetter = function(mon) return mon.letter end,
  index = function(letter) return ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):find(letter, 1, true) end,
}

check(Editor.install(fakeAtlas("first"), Gen1, fit), "installed with the editor's modules there")
local wrapped = MonEditor.sprite
local red = { gen = 1, data = { pokemon = { PIKACHU = { dex = 25 } } } }
local crystal = { gen = 2, data = { pokemon = { UNOWN = { dex = 201 }, PIKACHU = { dex = 25 } } } }
local emerald = { gen = 3, data = {} }

local pic = MonEditor.sprite(red, "PIKACHU", { species = "PIKACHU" })
check(type(pic) == "table" and pic.copy and pic.copy.key == 25, "Red: Pikachu is ours")
check(pic.copy.f == 0 and pic.copy.w == 60 and pic.copy.h == 70, "... the first frame, the art's own box")
check(pic.copy.variant == "front", "... the front")
check(MonEditor.sprite(red, "PIKACHU", { species = "PIKACHU" }) == pic, "kept: asked again, the same image")
check(MonEditor.sprite(red, "PIKACHU", nil) == pic, "a species alone (no Pokemon) too")
check(MonEditor.sprite(emerald, 25, {}) == "EDITOR'S 25", "a Gen 3 save: the editor's own (Pokemon.frontPic is hooked there)")
check(MonEditor.sprite(red, "MISSINGNO", {}) == "EDITOR'S MISSINGNO", "no art: the editor's own")
check(MonEditor.sprite(red, "PIKACHU", { species = "PIKACHU", isEgg = true }) == "EDITOR'S PIKACHU", "an egg: the editor's own")

-- shiny (a mod's mon.shiny, or the DVs), and SHINY ART off
local shiny = MonEditor.sprite(red, "PIKACHU", { species = "PIKACHU", shiny = true })
check(shiny.copy.variant == "front_shiny", "a shiny Pikachu shows its shiny art")
opts.sprite_shiny = false
check(MonEditor.sprite(red, "PIKACHU", { species = "PIKACHU", shiny = true }).copy.variant == "front", "SHINY ART off: the normal art")
opts.sprite_shiny = nil

-- female, and FEMALE ART off
red.data.pokemon.MEOWSTIC = { dex = 678 }
check(MonEditor.sprite(red, "MEOWSTIC", { species = "MEOWSTIC", gender = "female" }).copy.key == 10678, "a female Meowstic: her own art")
opts.sprite_female = false
check(MonEditor.sprite(red, "MEOWSTIC", { species = "MEOWSTIC", gender = "female" }).copy.key == 678, "FEMALE ART off: one look")
opts.sprite_female = nil

-- Unown's letters on Gold / Silver / Crystal
check(MonEditor.sprite(crystal, "UNOWN", { species = "UNOWN", letter = "C" }).copy.key == 2001, "Crystal: Unown C, its own letter")
check(MonEditor.sprite(crystal, "UNOWN", { species = "UNOWN", letter = "A" }).copy.key == 201, "Unown A: the species' sheet")
check(MonEditor.sprite(crystal, "PIKACHU", {}).copy.key == 25, "Crystal: Pikachu is ours")

-- only a copy is handed out: a frame that could not be read back gives the editor's own
local frame = nil
check(Editor.install(fakeAtlas("second"), Gen1, function(e) frame = e.image return e end), "a second load")
check(MonEditor.sprite == wrapped, "the wrap is put on once")
check(MonEditor.sprite(red, "PIKACHU", {}) == "EDITOR'S PIKACHU" and frame and frame.tag == "second",
  "a frame that is not copied: the editor's own (and the new load's atlas is used)")
Editor.install(fakeAtlas("third"), Gen1, fit)
check(MonEditor.sprite(red, "PIKACHU", {}).copy.tag == "third", "a later load: its own atlas, its own pictures")

-- a failing lookup never breaks the editor
Editor.install({ keyFor = function() error("boom") end }, Gen1, fit)
check(MonEditor.sprite(red, "PIKACHU", {}) == "EDITOR'S PIKACHU", "an error: the editor's own")

-- outside the editor
package.loaded["MonEditor"] = nil
check(not Editor.install(fakeAtlas("x"), Gen1, fit), "not the editor: nothing to wrap")

print(("%d/%d checks passed (g9-battle-sprites-gen3 save editor)"):format(passed, passed + failed))
if failed > 0 then os.exit(1) end
