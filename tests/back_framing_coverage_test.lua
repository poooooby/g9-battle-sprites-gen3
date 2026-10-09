-- Run from the mod root: luajit tests/back_framing_coverage_test.lua
-- Every back sprite the atlas packs has its body box (from the first frame of the kept
-- animation) and its cart framing: the row its body's top sits on (0-63) and one of the clean
-- scales. Female sheets and forms that reuse a base species' art share its cells.
local index = dofile("data/atlas_index.lua").species

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

local scales = { [1] = true, [1.5] = true, [2] = true }
local counts = { [1] = 0, [1.5] = 0, [2] = 0 }
local n = 0
for id, rec in pairs(index) do
  for _, variant in ipairs({ "back", "back_shiny" }) do
    local c = rec[variant]
    if c then
      n = n + 1
      check(c.cx0 and c.cx1 > c.cx0 and c.cy1 > c.cy0, id .. " " .. variant .. " has a body box")
      check(c.ux0 and c.ux0 <= c.cx0 and c.ux1 >= c.cx1 and c.uy0 <= c.cy0 and c.uy1 >= c.cy1,
        id .. " " .. variant .. ": the animation's box contains the body's")
      check(c.bt and c.bt >= 0 and c.bt <= 63, id .. " " .. variant .. " has a reference row (0-63)")
      check(scales[c.bs], id .. " " .. variant .. " has a clean scale, got " .. tostring(c.bs))
      if c.bs and counts[c.bs] then counts[c.bs] = counts[c.bs] + 1 end
    end
  end
end
check(n >= 2200, "a back and a shiny back for every species (" .. n .. ")")
check(counts[1] > counts[1.5] and counts[1.5] >= counts[2], "most sprites stay at 1x")
-- a shiny back shares its normal sheet's framing
for id, rec in pairs(index) do
  if rec.back and rec.back_shiny then
    check(rec.back.bt == rec.back_shiny.bt and rec.back.bs == rec.back_shiny.bs,
      id .. ": shiny shares the framing")
  end
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 back framing)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
