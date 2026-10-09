-- Run from the mod root: luajit tests/gen3_coverage_test.lua
-- Generations 1-3 (#1-386) are in the atlas at their internal slots, with a front, back and
-- both shiny sheets each, and no party icon (the game's own are kept). Unown is left to the
-- engine: its 28 letter forms are separate species and the pack has one sheet.
local index = dofile("data/atlas_index.lua").species

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local bySlot, classic = {}, {}
for id, rec in pairs(index) do
  if rec.slot then bySlot[rec.slot] = { id = id, rec = rec } end
  -- (an alternate form, like Hisuian Qwilfish, reports its base species' dex but has a slot above 450)
  if rec.dex and rec.dex <= 386 and rec.slot and rec.slot < 451 then classic[#classic + 1] = { id = id, rec = rec } end
end

check(#classic == 385, "385 Gen 1-3 species (#1-386 without Unown), got " .. #classic)
local dexes = {}
for _, e in ipairs(classic) do
  local r = e.rec
  check(dexes[r.dex] == nil, e.id .. ": its dex " .. r.dex .. " is listed once")
  dexes[r.dex] = true
  for _, v in ipairs({ "front", "front_shiny", "back", "back_shiny" }) do
    check(r[v] ~= nil, e.id .. " has a " .. v .. " sheet")
  end
  check(r.back and r.back.cx0 ~= nil and r.back.ux1 ~= nil, e.id .. " has its back pic's boxes")
  check(r.icon == nil, e.id .. " has no party icon (the game's own is kept)")
  -- the internal id: #1-251 are their own; Hoenn's (#252-386) are scattered over 277-411
  if r.dex <= 251 then
    check(r.slot == r.dex, e.id .. " (#" .. r.dex .. ") is at its own slot, got " .. tostring(r.slot))
  else
    check(r.slot >= 277 and r.slot <= 411, e.id .. " (#" .. r.dex .. ") is in 277-411, got " .. tostring(r.slot))
  end
end
local seen = {}
for _, e in ipairs(classic) do
  check(seen[e.rec.slot] == nil, e.id .. "'s slot " .. tostring(e.rec.slot) .. " is its own")
  seen[e.rec.slot] = true
end
check(dexes[201] == nil, "Unown (#201) is left to the engine")
check(bySlot[412] == nil, "the Egg (slot 412) has no sheet")
for slot = 413, 437 do check(bySlot[slot] == nil, "Unown's letter slot " .. slot .. " has no sheet") end
check(bySlot[25] and bySlot[25].id == "PIKACHU", "slot 25 is Pikachu")
check(bySlot[248] and bySlot[248].id == "TYRANITAR", "slot 248 is Tyranitar")
check(bySlot[277] and bySlot[277].id == "TREECKO", "slot 277 is Treecko (dex 252)")
check(bySlot[410] and bySlot[410].id == "DEOXYS", "slot 410 is Deoxys (dex 386)")
check(bySlot[372] and bySlot[372].id == "EXPLOUD" and bySlot[335] and bySlot[335].id == "MAKUHITA",
  "Hoenn's internal ids are not in dex order: Exploud is 372, Makuhita 335")
check(bySlot[29] and bySlot[29].id == "NIDORAN_F" and bySlot[32] and bySlot[32].id == "NIDORAN_M",
  "the Nidorans keep their ids")
check(bySlot[122] and bySlot[122].id == "MR_MIME" and bySlot[250] and bySlot[250].id == "HO_OH",
  "Mr. Mime and Ho-Oh keep their ids")
-- Gen 4-9 are where they were (slot = dex + 64)
check(bySlot[451] and bySlot[451].id == "TURTWIG", "slot 451 is still Turtwig")
check(bySlot[1089] and bySlot[1089].id == "PECHARUNT", "slot 1089 is still Pecharunt")

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 gen 1-3 coverage)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
