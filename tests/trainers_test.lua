-- Run from the mod root: luajit tests/trainers_test.lua
-- Animated trainer intros (FireRed to Emerald): the map and index agree, each game's trainer pics
-- reach the pack's art through TrainerPic.front (the rest the game's), the strip plays once after
-- the slide-in and holds its last frame, WoobleView gets the full frame in battle only, and the VS
-- screen takes over the transition's effect and finishes it once.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- ---- a graphics fake -----------------------------------------------------------------------------
local draws = 0
local function image(w, h)
  return { getDimensions = function() return w, h end, setFilter = function() end,
           getWidth = function() return w end, getHeight = function() return h end }
end
local canvases = 0
love = {
  graphics = {
    newImage = function(path)
      local f = io.open(path, "rb")
      if not f then error("no image " .. path) end
      local data = f:read(24); f:close()
      local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
      return image(u32(data, 17), u32(data, 21))
    end,
    newCanvas = function(w, h) canvases = canvases + 1; return image(w, h) end,
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
    newShader = function() return {} end,
    push = function() end, pop = function() end, origin = function() end,
    getScissor = function() return nil end, setScissor = function() end, intersectScissor = function() end,
    setShader = function() end, setBlendMode = function() end, setColor = function() end,
    setCanvas = function() end, clear = function() end, rectangle = function() end,
    scale = function() end, translate = function() end,
    draw = function() draws = draws + 1 end,
  },
  timer = { getTime = function() return NOW or 0 end },
}

-- ---- the engine's constants and trainers, faked -------------------------------------------------
local GAME = "firered"
local PICS = {
  firered = { [84] = "TRAINER_PIC_LASS", [116] = "TRAINER_PIC_LEADER_BROCK", [113] = "TRAINER_PIC_ELITE_FOUR_BRUNO",
              [112] = "TRAINER_PIC_ELITE_FOUR_LORELEI", [999] = "TRAINER_PIC_NOT_IN_THE_PACK" },
  emerald = { [40] = "TRAINER_PIC_LEADER_ROXANNE", [1] = "TRAINER_PIC_AQUA_GRUNT_M" },
}
package.loaded["src.core.game3.constants"] = {
  active = function() return { game = GAME, trainer_classes = { byId = { TRAINER_PIC_ = PICS[GAME] } } } end,
}
local TRAINERS = {
  [1] = { pic = 116, name = "BROCK" }, [2] = { pic = 84, name = "LASS" },
  [3] = { pic = 116, name = "BROCK", doubleBattle = true }, [4] = { pic = 112, name = "LORELEI" },
}
package.loaded["src.core.game3.scripting.trainers"] = { get = function(id) return TRAINERS[id] end }

local Atlas = dofile("src/atlas.lua")
local Trainers = dofile("src/trainers.lua")
local VS = dofile("src/vs.lua")
local map = dofile("data/trainer_map.lua")
local index = dofile("data/trainer_index.lua")
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- ---- the map and the index ------------------------------------------------------------------------
local function exists(path) local f = io.open(path, "rb"); if f then f:close() end; return f ~= nil end
do
  local all = true
  for game, fronts in pairs(map.fronts) do
    for pic, name in pairs(fronts) do
      if not index[name] then all = false; print("  no index entry: " .. game .. " " .. pic .. " -> " .. name) end
    end
  end
  check(all, "every mapped front is in the index")
  local pages = true
  for _, e in pairs(index) do
    if not exists("assets/trainers/fronts_" .. e.page .. ".png") then pages = false end
  end
  check(pages, "every index page exists")
  local vsOk = true
  for _, game in pairs(map.vs) do
    for _, e in pairs(game) do
      if not (exists("assets/trainers/vs/" .. e.foe .. ".png") and exists("assets/trainers/vs/" .. e.bar .. ".png")) then
        vsOk = false
      end
    end
  end
  for _, n in ipairs(map.vsParts) do vsOk = vsOk and exists("assets/trainers/vs/" .. n .. ".png") end
  check(vsOk, "every VS file exists")
  check(near(map.scale, 2 * 160 / 384) and map.seconds == 1.5, "Essentials' scale (2x on 384 rows) and speed (1.5 s)")
  check(map.fronts.firered.CHAMPION_RIVAL == "CHAMPION" and map.fronts.firered.RIVAL_EARLY == "CHAMPION",
    "Blue is the pack's CHAMPION (its RIVAL1 / RIVAL2 are Silver and Hugh)")
  check(map.fronts.firered.RED == "POKEMONTRAINER_Red" and map.fronts.firered.LEAF == "POKEMONTRAINER_Leaf"
    and map.fronts.emerald.BRENDAN == "POKEMONTRAINER_Brendan" and map.fronts.emerald.MAY == "POKEMONTRAINER_May",
    "the heroes are the game's own: Red / Leaf, Brendan / May")
  check(map.fronts.emerald.LEADER_ROXANNE == "LEADER_Roxanne" and map.fronts.ruby.ROXANNE == "LEADER_Roxanne"
    and map.fronts.emerald.CHAMPION_WALLACE == "LEADER_Wallace", "Hoenn's leaders and Emerald's champion Wallace")
  check(map.fronts.emerald.ELITE_FOUR_SIDNEY == nil and map.fronts.emerald.AQUA_GRUNT_M == nil,
    "no pack art (Hoenn's Elite Four, Team Aqua): the game's own")
  check(map.vs.emerald == nil and map.vs.ruby == nil, "VS screens: FireRed / LeafGreen only")
  local lass = index.LASS
  check(lass and lass.frames == 12 and lass.fw == 77 and lass.fh == 77, "LASS: 12 frames of 77 px (924 x 77)")
  check(lass and lass.px == lass.cw / 2 and lass.py == lass.fh, "the pivot is the frame's bottom centre")
  check(index.ELITEFOUR_Lorelei and index.ELITEFOUR_Lorelei.frames == 1, "a still is one frame")
end

-- ---- the wrapper ----------------------------------------------------------------------------------
local mod = { path = ".", log = { warn = function() end, info = function() end } }
local function load(path) return dofile(path) end
local t = Trainers.new(mod, load, Atlas)
check(t ~= nil, "Trainers.new reads the map and the index")
local orig = function(picId) return { image = "game's own " .. tostring(picId), w = 64, h = 64 } end
local TP = { front = orig }
check(Trainers.install(t, TP), "TrainerPic.front wrapped")
local wrapped = TP.front
Trainers.install(t, TP)
check(TP.front == wrapped, "a second install leaves it alone")

local opts = {}
t.option = function(key) return opts[key] end
local battle, stage = false, { trainer = { enemy = { visible = true, picId = 84, ox = -120 } } }
t.inBattle = function() return battle end
t.stage = function() return stage end
local hd = { tags = {}, enabled = function() return true end }
function hd.tag(img, spec) hd.tags[img] = spec end
function hd.untag(img) hd.tags[img] = nil end
t.hd = hd

local lass = TP.front(84)
check(type(lass.image) == "table" and lass.w == 64 and lass.h == 64, "LASS: the pack's live canvas, 64 x 64")
check(TP.front(84) == lass, "the same entry every call")
check(TP.front(999).image == "game's own 999", "a pic the pack has no art for: the game's own")
check(TP.front("mods/x/pic.png").image == "game's own mods/x/pic.png", "a mod's own pic (a path): the game's own")
opts.animated_trainers = false
check(TP.front(84).image == "game's own 84", "ANIMATED TRAINERS off: the game's own")
opts.animated_trainers = nil

-- the clock
local e = index.LASS
NOW = 10
t.resetBattle()
check(t.frameOf(84, e) == 11, "off the battle: the last frame")
battle = true
check(t.frameOf(84, e) == 0, "sliding in: frame 0")
stage.trainer.enemy.ox = 0
TP.front(84)
NOW = 10.75
check(t.frameOf(84, e) == 6, "half way through 1.5 s: frame 6 of 12 (" .. t.frameOf(84, e) .. ")")
NOW = 12
check(t.frameOf(84, e) == 11, "after 1.5 s: the last frame, held")
stage.trainer.enemy.ox = 104
check(t.frameOf(84, e) == 11, "sliding out after it played: still the last frame")
t.resetBattle()
stage.trainer.enemy.ox = -240
check(t.frameOf(84, e) == 0, "the next battle: frame 0 again until it has slid in")
stage.trainer.enemy.ox = 0

-- WoobleView: the full frame in battle, nothing off it
NOW = 20
TP.front(84)
local spec = hd.tags[lass.image]
check(spec and spec.trainer == true and spec.side == "enemy", "in battle: tagged as the enemy's trainer")
check(spec and near(spec.scale, map.scale) and spec.pivot[1] == e.px and spec.pivot[2] == e.py
  and spec.lowPivot[1] == 32 and spec.lowPivot[2] == 64, "the frame's bottom centre on the box's, at the pack's scale")
check(spec and spec.quad and spec.quad.w == e.cw and spec.quad.h == e.ch, "the tag's quad is one cell")
battle = false
TP.front(84)
check(hd.tags[lass.image] == nil, "off the battle (a mugshot, the Hall of Fame): untagged")

-- the other games
GAME = "emerald"
check(type(TP.front(40).image) == "table", "Emerald: Roxanne from the pack")
check(TP.front(1).image == "game's own 1", "Emerald: an Aqua grunt keeps the game's own")
GAME = "firered"

-- ---- the VS screen --------------------------------------------------------------------------------
local v = VS.new(mod, t)
check(v.screenFor({ trainerId = 1 }) and v.screenFor({ trainerId = 1 }).foe == "hgss_vs_LEADER_Brock",
  "Brock: his HGSS VS screen")
check(v.screenFor({ trainerId = 2 }) == nil, "a Lass: no VS screen")
check(v.screenFor({ trainerId = 3 }) == nil, "a double battle: none")
check(v.screenFor({ trainerId = 4 }) == nil, "Lorelei (no VS art): the game's own mugshot")
check(v.screenFor({ trainerId = 1, wild = true }) == nil and v.screenFor({ trainerId = 1, trainerTower = true }) == nil,
  "wild battles and the Trainer Tower: none")
opts.animated_trainers = false
check(v.screenFor({ trainerId = 1 }) == nil, "ANIMATED TRAINERS off: none")
opts.animated_trainers = nil

local ticks, finished, aborted = 0, 0, 0
local BT = { _active = false, _phase = "idle" }
function BT.start(tid, o, done) BT._active, BT._phase, BT._done = true, "intro", done; return true end
function BT.tick() ticks = ticks + 1; return true end
function BT.finish() finished = finished + 1; BT._active = false; BT._phase = "done"; if BT._done then BT._done() end end
function BT.abort() aborted = aborted + 1; BT._active = false end
check(v.install(BT), "the transition wrapped")
local tick = BT.tick
v.install(BT)
check(BT.tick == tick, "a second install leaves it alone")

local started = 0
NOW = 100
BT.start(1, { trainerId = 1 }, function() started = started + 1 end)
BT.tick()
check(ticks == 1 and v.active == nil, "its opening flashes are the game's own")
BT._phase = "main"
BT.tick()
check(ticks == 1 and v.active ~= nil, "then the VS screen plays in place of the effect")
NOW = 103.9
BT.tick()
check(finished == 0, "...for 4 seconds")
NOW = 104
BT.tick()
check(finished == 1 and started == 1 and v.active == nil, "then the transition finishes once, and the battle starts")
BT.tick()
check(finished == 1 and ticks == 2, "nothing more after it")

BT.start(1, { trainerId = 2 }, function() end)
BT._phase = "main"
BT.tick()
check(v.active == nil and ticks == 3, "a battle without VS art: the game's own transition")
BT.start(1, { trainerId = 1 }, function() end)
BT._phase = "main"
BT.tick()
BT.abort()
check(v.active == nil and v.pending == nil and aborted == 1, "an abort drops the VS screen")

-- it draws at every moment, over a 16:9 and a 4:3 window
local okAll = true
for i = 0, 40 do
  local ok, err = pcall(v.draw, { foe = "hgss_vs_LEADER_Brock", bar = "hgss_vsBar_LEADER_Brock", name = "BROCK" },
    i * 0.1, 1920, 1080)
  if not ok then okAll = false; print("  draw at " .. i * 0.1 .. ": " .. tostring(err)) end
  ok = pcall(v.draw, { foe = "vsE4_CHAMPION", bar = "hgss_vsBar", name = "BLUE" }, i * 0.1, 1024, 768)
  okAll = okAll and ok
end
check(okAll and draws > 0, "the VS screen draws through all 4 seconds")

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 trainers)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
