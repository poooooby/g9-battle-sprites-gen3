-- Run from the mod root: luajit tests/dex_hd_test.lua
-- The Pokedex pics with gen3-hd-sprites: a front pic asked for with kind "dex" is the plain
-- fit-to-box pic, tagged so the library draws the whole frame at window resolution, fitted
-- to the same box. Without the library, or with its Pokedex option off, and for every other
-- screen, nothing is tagged.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a graphics fake that tracks the state a real draw would be affected by
local state = { scissor = nil, identity = true, canvas = "screen" }
local stack, draws = {}, {}
local function image() return { getDimensions = function() return 4096, 4096 end, setFilter = function() end } end
love = { graphics = {
  newImage = function() return image() end,
  newQuad = function() return {} end,
  newCanvas = function(w, h)
    return { getDimensions = function() return w, h end, setFilter = function() end, release = function() end }
  end,
  getCanvas = function() return state.canvas end,
  setCanvas = function(c) state.canvas = c or "screen" end,
  setScissor = function(x, y, w, h) state.scissor = x and { x, y, w, h } or nil end,
  getScissor = function() return state.scissor and unpack(state.scissor) end,
  origin = function() state.identity = true end,
  setShader = function() end, setBlendMode = function() end, setColor = function() end,
  clear = function() end,
  push = function(what)
    stack[#stack + 1] = { scissor = state.scissor, identity = state.identity, canvas = state.canvas }
  end,
  pop = function()
    local s = table.remove(stack)
    state.scissor, state.identity, state.canvas = s.scissor, s.identity, s.canvas
  end,
  draw = function()
    draws[#draws + 1] = { scissor = state.scissor, identity = state.identity, canvas = state.canvas }
  end,
}, timer = { getTime = function() return NOW or 0 end } }

local Atlas = dofile("src/atlas.lua")
local index = { species = {
  BIG = { dex = 387, slot = 451, front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 1, ox = 0, oy = 0 } },
  CART = { dex = 390, slot = 454, front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 4, ox = 0, oy = 0 },
    dexpic = { page = 0, x = 128, y = 0 } },
  MOVER = { dex = 389, slot = 453, front = { sheet = 0, start = 0, fs = 96, cols = 10, frames = 4, ox = 0, oy = 0 } },
  SMALL = { dex = 388, slot = 452, front = { sheet = 0, start = 0, fs = 48, cols = 10, frames = 1, ox = 0, oy = 0 } },
} }
local function newAtlas()
  return Atlas.new({ path = "x", log = { warn = function() end } },
    function(path) return path == "data/atlas_index.lua" and index or nil end)
end

-- a fake gen3-hd-sprites
local function fakeHd(on)
  local hd = { tags = {} }
  function hd.enabled(pass) return on[pass] == true end
  function hd.tag(image, spec) hd.tags[image] = spec end
  function hd.isActive() return true end
  return hd
end

do
  local atlas = newAtlas()
  local hd = fakeHd({ dex = true, battle = true })
  atlas.hd = hd
  local big = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false, "dex")
  local spec = hd.tags[big]
  check(spec ~= nil, "a Pokedex pic is tagged")
  check(spec and spec.quad ~= nil and spec.texture ~= nil, "...with the atlas page and its frame")
  check(spec and spec.pivot[1] == 48 and spec.pivot[2] == 96, "...standing on the frame's bottom-centre")
  check(spec and spec.lowPivot[1] == 32 and spec.lowPivot[2] == 64, "...on the box's bottom-centre")
  check(spec and math.abs(spec.scale - 64 / 96) < 1e-9, "...fitted to the box (" .. tostring(spec and spec.scale) .. ")")
  local small = atlas.picFrame(452, "front", atlas.cell(452, "front"), 0, false, "dex")
  check(hd.tags[small] and hd.tags[small].scale == 1, "a frame smaller than the box is not enlarged")
  local summary = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false)
  check(summary ~= big and hd.tags[summary] == nil, "another screen's pic is a separate canvas, not tagged")
  check(atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false, "dex") == big, "the Pokedex pic is cached")
end

do
  local atlas = newAtlas()
  local hd = fakeHd({ battle = true })                -- the Pokedex option off
  atlas.hd = hd
  local c = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false, "dex")
  check(c ~= nil and next(hd.tags) == nil, "Pokedex HD off: the plain pic, nothing tagged")
end

do
  local atlas = newAtlas()                            -- no library
  local c = atlas.picFrame(451, "front", atlas.cell(451, "front"), 0, false, "dex")
  check(c ~= nil, "no library: the plain pic")
end

-- the RSE entry page keeps the image it is given: a live canvas that follows the frame
do
  local atlas = newAtlas()
  local hd = fakeHd({ dex = true })
  hd.untag = function(image) hd.tags[image] = nil end
  atlas.hd = hd
  NOW = 0
  local cell = atlas.cell(453, "front")
  local live = atlas.livePic(453, "front", cell)
  check(live ~= nil, "a live pic is made")
  local first = hd.tags[live]
  check(first ~= nil, "...tagged for Pokedex HD")
  check(atlas.livePic(453, "front", cell) == live, "...and the same canvas next time")
  NOW = 1 / 8 + 0.01                                  -- the next frame at 8 fps
  local n = #draws
  atlas.refreshLive()
  check(#draws > n, "a new frame is drawn into it")
  check(hd.tags[live] ~= nil and hd.tags[live] ~= first, "...and its tag follows the new frame")
  n = #draws
  atlas.refreshLive()
  check(#draws == n, "the same frame is not drawn again")
  NOW = nil
end

-- the cart's two-frame front pic, for the RSE Pokedex
do
  local atlas = newAtlas()
  local hd = fakeHd({ dex = true })
  hd.untag = function(image) hd.tags[image] = nil end
  atlas.hd = hd
  check(atlas.dexPic(453, 0) == nil, "no cart pic for a species without one")
  local still = atlas.dexPic(454, 0)
  check(still ~= nil and atlas.dexPic(454, 0) == still, "the cart pic's first frame, cached")
  check(atlas.dexPic(454, 1) ~= still, "its second frame is another canvas")
  NOW = 0
  local live = atlas.livePic(454, "front", atlas.cell(454, "front"))
  check(live ~= nil and hd.tags[live] == nil, "an entry with a cart pic is live, and not HD (it is 64x64 already)")
  local n = #draws
  NOW = 0.1
  atlas.refreshLive()
  check(#draws == n, "it holds its frame for half a second")
  NOW = 0.6
  atlas.refreshLive()
  check(#draws > n, "then shows the other frame")
  NOW = nil
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 dex hd)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
