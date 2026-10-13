-- Run from the mod root: luajit tests/numbers_test.lua
-- The battle art as colour numbers (tools/build_numbers.py, src/atlas.lua): the palette lookup is
-- exact, every battle cell of data/atlas_index.lua has a block of the right size, a block's frame
-- grid fits the texture limit, and without the numbers index the pages are read as before.
-- (That every rebuilt frame equals its page pixel for pixel is checked by tools/build_numbers.py
-- at build time, and in game on the real GPU by the one-time self-check in src/atlas.lua.)
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

love = { graphics = {
  newImage = function(path)
    return { path = path, getDimensions = function() return 4032, 4032 end, setFilter = function() end }
  end,
  newQuad = function(x, y) return { x = x, y = y } end,
}, timer = { getTime = function() return 0 end } }

local Atlas = dofile("src/atlas.lua")

-- ------- the palette lookup: number (red) -> 4 bytes, normal and shiny from the same numbers
do
  local function px(n) return string.char(n, n, n, 255) end
  local numbers = px(0) .. px(2) .. px(1)
  local normal = "\0\0\0\0" .. "\255\0\0\255" .. "\9\8\7\128"
  local shiny = "\1\2\3\0" .. "\0\0\255\255" .. "\9\8\7\128"
  check(Atlas._expand(numbers, 3, normal) == "\0\0\0\0" .. "\9\8\7\128" .. "\255\0\0\255", "expand: normal")
  check(Atlas._expand(numbers, 3, shiny) == "\1\2\3\0" .. "\9\8\7\128" .. "\0\0\255\255",
    "expand: shiny from the same numbers, transparent keeps its own RGB")
  check(Atlas._expand(px(9), 1, normal) == "\0\0\0\0", "expand: a number past the row is transparent")
end

check(Atlas.blockCols(1) == 1 and Atlas.blockCols(50) == 8 and Atlas.blockCols(172) == 14, "blockCols: about square")
check(Atlas.blockKey("front_shiny", { sheet = 23, start = 0, ox = 0, oy = 820 }) == "front_shiny:23:0:0:820",
  "blockKey matches tools/build_numbers.py cell_key")

-- ------- every battle cell has its block, of the right size, within its shard and palette
local index = dofile("data/atlas_index.lua")
local numbers = dofile("data/numbers_index.lua")
local LIMIT = 4096
local cells, missing, wrong, tooBig = 0, 0, 0, 0
for id, rec in pairs(index.species) do
  for _, v in ipairs({ "front", "front_shiny", "back", "back_shiny" }) do
    local c = rec[v]
    if type(c) == "table" then
      cells = cells + 1
      local b = numbers.blocks[Atlas.blockKey(v, c)]
      if not b then
        missing = missing + 1
        if missing <= 3 then print("  no block for " .. id .. " " .. v) end
      else
        local shard = numbers.shards[b[1] + 1]
        if b[3] ~= c.fs or b[4] ~= c.fs * c.frames or not shard or b[2] + b[4] > shard.h
          or b[5] < 0 or b[5] >= numbers.palette.h then
          wrong = wrong + 1
        end
        local cols = Atlas.blockCols(c.frames)
        if cols * c.fs > LIMIT or math.ceil(c.frames / cols) * c.fs > LIMIT then tooBig = tooBig + 1 end
      end
    end
  end
end
check(cells > 4000, "the index has the battle cells (" .. cells .. ")")
check(missing == 0, missing .. " battle cells have no colour-number block")
check(wrong == 0, wrong .. " blocks have the wrong size or point outside their shard / palette")
check(tooBig == 0, tooBig .. " blocks would pass the " .. LIMIT .. " px texture limit")
check(numbers.palette.w <= 256, "at most 256 colour numbers")

-- ------- without the numbers index the pages are read exactly as before
do
  local function load(path)
    if path == "data/numbers_index.lua" then return nil end
    return dofile(path)
  end
  local atlas = Atlas.new({ path = "." }, load)
  check(atlas and atlas.numbers == false, "no numbers index -> pages")
  local cell = { sheet = 3, start = 5, fs = 40, cols = 10, frames = 8, ox = 100, oy = 200 }
  local img, x, y = atlas._frameSource("front", cell, 7)
  check(img and img.path == "./assets/atlas/battle_front_3.png", "page path")
  check(x == 100 + (12 % 10) * 40 and y == 200 + 1 * 40, "page frame position: cell start + f")
end

print(("numbers_test: %d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
