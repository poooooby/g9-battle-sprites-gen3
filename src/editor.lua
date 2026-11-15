-- The gen1recomp save editor with a Red / Blue / Yellow or Gold / Silver / Crystal save open.
-- Its Gen 3 pictures come through Pokemon.frontPic (src/hooks.lua), but for Gen 1 / 2 it loads
-- each species' spriteFront PNG itself (tools/save-editor/panels/MonEditor.lua MonEditor.sprite),
-- with nothing a mod can hook. So MonEditor.sprite is wrapped: for a Gen 1 / 2 save it answers
-- our front art's first frame (shiny / female / Unown's letter as the options and the Pokemon
-- say), cut to the creature's pixels and copied out of the frame cache into an image of its own
-- (Hooks.fit), so the editor can keep it. A species with no art, an egg, and Gen 3 saves get the
-- editor's own.
--
-- The wrap is put on once per process; each load of this mod (the editor makes a loader per game
-- version) hands it its own atlas through MonEditor.__woobleEditor.

local Editor = {}

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- the atlas id of a Gold / Silver / Crystal Unown, by its letter (A is the species' own sheet)
local function unownId(mon)
  local ok, Unown = pcall(require, "src.core.gen2.Unown")
  if not (ok and type(Unown) == "table") then return "UNOWN" end
  local okL, letter = pcall(Unown.monLetter, mon)
  if not okL or letter == nil then return "UNOWN" end
  local okI, i = pcall(Unown.index, letter)
  i = okI and tonumber(i) or tonumber(letter)
  if not i or i <= 1 or i > 26 then return "UNOWN" end
  return "UNOWN_" .. LETTERS:sub(i, i)
end

--- The still front picture for a species in a Gen `g` (1 or 2) save, or nil when there is no art:
--- an image the caller may keep. `state` = { atlas, gen1, fit, cache }.
function Editor.pic(state, g, data, species, mon)
  local atlas, Gen1 = state.atlas, state.gen1
  if type(mon) == "table" and (mon.isEgg == true or mon.egg == true) then return nil end
  local id = species
  if g == 2 and species == "UNOWN" and type(mon) == "table" then id = unownId(mon) end
  local key = Gen1.keyOf(atlas, data, id)
  if not key then return nil end
  local on = function(k) return Gen1.on(k) end
  if type(mon) == "table" and on("sprite_female") and Gen1.femaleOf(mon) then
    key = atlas.femaleKey(key) or key
  end
  local variant = Gen1.variantFor(atlas, key, "front", type(mon) == "table" and on("sprite_shiny")
    and Gen1.shinyOf(mon))
  local ck = tostring(key) .. ":" .. variant
  local hit = state.cache[ck]
  if hit ~= nil then return hit or nil end
  local cell = atlas.cell(key, variant)
  local img = nil
  if cell then
    local w = (tonumber(cell.ux1) or cell.fs) - (tonumber(cell.ux0) or 0)
    local h = (tonumber(cell.uy1) or cell.fs) - (tonumber(cell.uy0) or 0)
    local frame = atlas.boxFrame(key, variant, 0, w, h, {})
    local fitted = frame and state.fit({ image = frame, w = w, h = h }) or nil
    -- (only a copy: a frame the cache could drop or draw over is never handed out)
    if fitted and fitted.image ~= frame then img = fitted.image end
  end
  state.cache[ck] = img or false
  return img
end

--- Wraps the editor's MonEditor.sprite (once) and points it at this load's atlas. Returns true
--- when the editor's module is there.
function Editor.install(atlas, Gen1, fit)
  local okM, MonEditor = pcall(require, "MonEditor")
  local okG, Gen = pcall(require, "Gen")
  if not (okM and type(MonEditor) == "table" and type(MonEditor.sprite) == "function"
      and okG and type(Gen) == "table" and type(Gen.ofState) == "function") then
    return false
  end
  MonEditor.__woobleEditor = { atlas = atlas, gen1 = Gen1, fit = fit, cache = {} }
  if MonEditor.__woobleWrapped then return true end
  MonEditor.__woobleWrapped = true
  local orig = MonEditor.sprite
  MonEditor.sprite = function(S, species, mon, ...)
    local state = MonEditor.__woobleEditor
    if state and species ~= nil then
      local okS, g = pcall(Gen.ofState, S)
      if okS and (g == 1 or g == 2) then
        local ok, img = pcall(Editor.pic, state, g, type(S) == "table" and S.data or nil, species, mon)
        if ok and img then return img end
      end
    end
    return orig(S, species, mon, ...)
  end
  return true
end

return Editor
