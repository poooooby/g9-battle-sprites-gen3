-- Run from the mod root: luajit tests/forms_coverage_test.lua
-- Every alternate form national_dex_gen3 registers has an atlas entry, and every form
-- the packs have art for has art of its own: only the forms the packs have none for
-- (the tea set's looks) and the party icons the Gen 9 Pack shares between sizes
-- (Pumpkaboo, Gourgeist) may be drawn with their base species' picture.
-- Skipped when the sibling national_dex_gen3 checkout is not there.
local formsPath = "../national_dex_gen3/data/species/forms.lua"
local okForms, forms = pcall(dofile, formsPath)
if not okForms then
  print("skipped: " .. formsPath .. " not found")
  os.exit(0)
end
local index = dofile("data/atlas_index.lua").species

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local function same(a, b)
  if a == nil or b == nil then return a == b end
  return a.sheet == b.sheet and a.start == b.start and a.ox == b.ox and a.oy == b.oy
    and a.fs == b.fs and a.page == b.page and a.x == b.x and a.y == b.y
end

-- no sheet or icon of their own anywhere in the packs: shown as their base species
local NO_ART = { SINISTEA_ANTIQUE = true, POLTEAGEIST_ANTIQUE = true,
                 POLTCHAGEIST_ARTISAN = true, SINISTCHA_MASTERPIECE = true }
-- one party icon per line in the Gen 9 Pack
local SHARED_ICON = { PUMPKABOO_SMALL = true, PUMPKABOO_LARGE = true, PUMPKABOO_SUPER = true,
                      GOURGEIST_SMALL = true, GOURGEIST_LARGE = true, GOURGEIST_SUPER = true }

check(#forms >= 85, "forms.lua lists the forms (" .. #forms .. ")")
for _, form in ipairs(forms) do
  local entry, base = index[form.id], index[form.baseSpecies]
  check(entry ~= nil, form.id .. " has an atlas entry")
  check(entry and entry.slot == form.slot, form.id .. " answers for slot " .. tostring(form.slot))
  if entry and base then
    for _, key in ipairs({ "front", "front_shiny", "back", "back_shiny" }) do
      check(entry[key] ~= nil, form.id .. " has " .. key)
      if not NO_ART[form.id] then
        check(not same(entry[key], base[key]), form.id .. " " .. key .. " is not its base's")
      end
    end
    if not NO_ART[form.id] and not SHARED_ICON[form.id] then
      check(entry.icon ~= nil and not same(entry.icon, base.icon), form.id .. " icon is not its base's")
    end
  end
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 forms coverage)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
