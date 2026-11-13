-- Run from the mod root: luajit tests/gen2_test.lua
-- Gen 2 (Gold / Silver / Crystal): the battle's pic (its boxes, DPI, the colour modes and the
-- screen's own colour effects, Crystal's animation kept off ours), the screens, Unown's letters,
-- the National Dex's forms, Crystal's animated pics, the party icons, the G9 page and the exports.
local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. msg) end
end

-- a graphics fake that records each draw and the transform it was made under
local draws, color, tx, sx = {}, { 1, 1, 1, 1 }, 0, 1
local function image(w, h)
  local f = "linear"
  return { getDimensions = function() return w or 4096, h or 4096 end,
           getWidth = function() return w or 4096 end, getHeight = function() return h or 4096 end,
           setFilter = function(_, a) f = a end, getFilter = function() return f, f end,
           type = function() return "Image" end }
end
love = {
  graphics = {
    newImage = function() return image() end,
    newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
    newCanvas = function(w, h, o)
      local c = image(w, h)
      c.dpi = o and o.dpiscale or 1
      c.type = function() return "Canvas" end
      return c
    end,
    setCanvas = function() end, clear = function() end,
    push = function() end, pop = function() tx, sx = 0, 1 end,
    origin = function() tx, sx = 0, 1 end,
    translate = function(x) tx = tx + x end,
    scale = function(x) sx = sx * x end,
    setScissor = function() end, setShader = function() end, setBlendMode = function() end,
    newShader = function() return { shader = true } end, getShader = function() return nil end,
    setColor = function(r, g, b, a) color = { r, g, b, a } end,
    draw = function(img, quad, x, y, r, kx, ky)
      draws[#draws + 1] = { img = img, quad = quad, x = x, y = y, kx = kx, ky = ky,
                            tx = tx, sx = sx, black = color[1] == 0 }
    end,
  },
  image = { newImageData = function()
    -- a 10x6 shadow whose opaque pixels are its middle 8x4
    return { getDimensions = function() return 10, 6 end,
             getPixel = function(_, x, y) return 0, 0, 0, (x >= 1 and x <= 8 and y >= 1 and y <= 4) and 1 or 0 end }
  end },
  timer = { getTime = function() return NOW or 0 end },
}

local Atlas = dofile("src/atlas.lua")
local index = dofile("data/atlas_index.lua")
local atlas = Atlas.new({ path = "x", log = { warn = function() end } },
  function(path) return path == "data/atlas_index.lua" and index or nil end)
local Gen1 = dofile("src/gen1.lua")

local Gen2 = dofile("src/gen2.lua")
local opts = {}
Gen1.options = function(key) return opts[key] end

-- the engine's Gen 2 modules, as far as the hooks use them
local gbc = { mode = "gbc", available = function() return true end,
              with = function(colors, body) body() end, use = function() end }
local function class(t) t.__index = t return t end
local BattleState = class({
  pic = function(self, mon, back) return "VANILLA", false, "vanilla.png" end,
  picScale = function() return 2 end,
  frontAnimFrame = function() return "SHEET", "QUAD", 56 end,
  introGrayscale = function(self) return self.intro == true end,
  animPicState = function(self, side)
    return self.shade and { shade = self.shade == true and 1 or self.shade } or nil
  end,
})
local Summary = class({ picFor = function() return "VANILLA", false end })
local Dex = class({ picFor = function() return "VANILLA", false end, drawUnownPic = function() return "VANILLA" end })
local Evo = class({ pic = function() return "VANILLA", false end })
local Party = class({
  drawIcon = function() return "VANILLA" end,
  iconIdFor = function(self, mon) return self.ids[mon.species] end,
  iconFrame = function() return 1 end,
  heldMarkerRow = function(mon) return mon.item and 1 or nil end,
  heldMarkerImage = function() return { getDimensions = function() return 8, 16 end } end,
  drawPanel = function() end,
  drawWidescreen = function() return "VANILLA" end,
})
local View = { start = function(def, mon, scene) return { scene = scene } end, frame = function() return "SHEET" end }
local preload = {
  ["src.render.GbcPalette"] = gbc,
  ["src.core.gen2.Unown"] = {
    index = function(l) return type(l) == "number" and l or ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):find(l, 1, true) end,
    monLetter = function(mon) return mon.letter end },
  ["src.render.MonAnimView"] = View,
  ["src.ui.gen2.BattleState"] = BattleState, ["src.ui.gen2.SummaryMenu"] = Summary,
  ["src.ui.gen2.PokedexMenu"] = Dex, ["src.ui.gen2.EvolutionAnim"] = Evo, ["src.ui.gen2.PartyMenu"] = Party,
  ["src.world.gen2.Palettes"] = { monColors = function() return { 1, 2, 3, 4 } end },
  ["src.ui.gen2.Chrome"] = { playfieldRect = function(w, h) return 0, 0, w, h end, letterbox = function() end,
                             fitOrigin = function() return 0, 0 end },
}
for name, m in pairs(preload) do package.loaded[name] = m end

local done = Gen2.install(atlas, Gen1)
local list = table.concat(done, ",")
check(list:find("battle") and list:find("summary") and list:find("pokedex") and list:find("evolution")
  and list:find("party icons") and list:find("party screen"), "installed: " .. list)
local wrapped = Summary.picFor
Gen2.install(atlas, Gen1)
check(Summary.picFor == wrapped and BattleState.__woobleSprites2, "never wrapped twice")

-- ids
check(Gen2.unownId(1) == "UNOWN" and Gen2.unownId(7) == "UNOWN_G" and Gen2.unownId("Z") == "UNOWN_Z", "Unown letters")
check(Gen2.speciesOf({ species = "UNOWN", letter = 2 }) == "UNOWN_B", "an Unown is drawn as its letter")
check(Gen2.speciesOf({ species = "PIKACHU" }) == "PIKACHU", "anything else as its species")

-- colour
check(Gen2.keepsColour() == true, "GEN 2 colours: the art as it is")
gbc.mode = "dmg"
check(Gen2.keepsColour() == false, "DMG: recoloured")
gbc.mode = "gbc"

-- battle
local game = { data = { pokemon = { TURTWIG = { dex = 387 } } } }
do
  local b = setmetatable({ game = game }, BattleState)
  local mon = { species = "CYNDAQUIL" }
  local f, tc, path = b:pic(mon, false)
  check(type(f) == "table" and f:getWidth() == 56 and f.dpi == 4, "the foe: a 56x56 frame at 4x")
  check(tc == true and type(path) == "string" and path ~= "vanilla.png", "true colour, under a path of ours")
  check(b:picScale(path, mon, false) == 1, "drawn at its own size")
  check(b:frontAnimFrame(mon) == nil, "Crystal's own animation is not played over it")
  local back = b:pic({ species = "CYNDAQUIL" }, true)
  check(back:getWidth() == 48, "the player's back: 48x48")
  local unown = b:pic({ species = "UNOWN", letter = 7 }, false)
  check(unown ~= f and unown ~= b:pic({ species = "UNOWN", letter = 1 }, false), "an Unown's letter")
  check(b:pic({ species = "TURTWIG" }, false) ~= "VANILLA", "a National Dex species")
  check(b:pic({ species = "NOT_A_MON" }, false) == "VANILLA", "no art: the game's own")
  check(b:frontAnimFrame({ species = "NOT_A_MON" }) == "SHEET", "and its own animation")
  gbc.mode = "dmg"
  check(select(2, b:pic(mon, false)) == false, "DMG: the shaded frame, for the palette")
  gbc.mode = "gbc"
  b.intro = true
  check(select(2, b:pic(mon, false)) == false, "the intro's blackout takes it too")
  b.intro = nil
  b.shade = true
  check(select(2, b:pic(mon, false)) == false, "and a move's flash")
  b.shade = nil
  -- a move that recolours nothing: its pic shade rests on the identity
  b.shade = 0xE4
  check(select(2, b:pic(mon, false)) == true, "a move with its shade at rest (0xE4): true colour")
  b.shade = nil
  gbc.bgp = 0x1B
  check(select(2, b:pic(mon, false)) == false, "a move changing the BG palette (a flash): shaded")
  gbc.bgp = nil
  opts.enable_battle_sprites = false
  check(b:pic(mon, false) == "VANILLA", "BATTLE SPRITES off: the game's own")
  opts.enable_battle_sprites = nil
  opts.battle_frontal = true
  check(b:pic(mon, true):getWidth() == 48, "3DB FRONTAL: the front, in the back's box")
  opts.battle_frontal = nil

  -- WoobleView: tagged where the frame keeps its own colours
  local hd = { tags = setmetatable({}, { __mode = "k" }) }
  function hd.isActive() return true end
  function hd.enabled(pass) return pass == "battle" end
  function hd.tag(image, spec) hd.tags[image] = spec end
  function hd.untag(image) hd.tags[image] = nil end
  atlas.hd = hd
  local tf = b:pic(mon, false)
  local tb = b:pic(mon, true)
  check(hd.tags[tf] and hd.tags[tf].side == "enemy" and hd.tags[tb] and hd.tags[tb].side == "player",
    "WoobleView: both battle frames tagged")
  check(hd.tags[tf] and hd.tags[tf].lowPivot[2] <= 56 and hd.tags[tb].lowPivot[2] <= 48,
    "in the stand-in's box units (56 / 48), not its DPI pixels")
  gbc.mode = "dmg"
  check(hd.tags[b:pic(mon, false)] == nil, "DMG colours: not tagged")
  gbc.mode = "gbc"
  b.intro = true
  check(hd.tags[b:pic(mon, false)] == nil, "the intro's blackout: not tagged")
  b.intro = nil
  atlas.hd = nil
end

-- the screens
do
  local s = setmetatable({ game = game }, Summary)
  check(s:picFor({ species = "CHIKORITA" }) ~= "VANILLA", "summary: ours")
  check(s:picFor({ species = "CHIKORITA", isEgg = true }) == "VANILLA", "an egg: the game's")
  opts.summary_sprites = false
  check(s:picFor({ species = "CHIKORITA" }) == "VANILLA", "SUMMARY SPRITES off")
  opts.summary_sprites = nil

  local d = setmetatable({ game = game, save = { firstUnownSeen = 3 } }, Dex)
  d.formId, d.formBase = "CHARIZARD_MEGA_X", "CHARIZARD"
  check(d:picFor("CHARIZARD") ~= "VANILLA", "a National Dex form with no art: its base")
  d.formId, d.formBase = "RATTATA_ALOLA", "RATTATA"
  local alola = d:picFor("RATTATA")
  d.formId = nil
  check(alola ~= "VANILLA" and alola ~= d:picFor("RATTATA"), "a form's own art")
  local other = setmetatable({ game = game, save = { firstUnownSeen = 1 } }, Dex)
  check(d:picFor("UNOWN") ~= other:picFor("UNOWN"), "Unown as the letter met first")
  opts.dex_sprites = false
  check(d:picFor("CHARIZARD") == "VANILLA" and d:drawUnownPic(3, 0, 0) == "VANILLA", "DEX SPRITES off")
  opts.dex_sprites = nil
  draws = {}
  d:drawUnownPic(3, 1, 2)
  check(#draws == 1 and draws[1].quad == 8 and draws[1].x == 16, "the Unown page: ours at its tile (an unquadded draw: x, y)")

  -- WoobleView's "dex" pass: the summary, Pokedex and Unown page frames are tagged (no side),
  -- a DMG-shaded one only where it can draw through the shades shader
  local hd = { tags = setmetatable({}, { __mode = "k" }) }
  function hd.isActive() return true end
  function hd.enabled(pass) return pass == "dex" end
  function hd.tag(image, spec) hd.tags[image] = spec end
  function hd.untag(image) hd.tags[image] = nil end
  atlas.hd = hd
  local ts = s:picFor({ species = "CHIKORITA" })
  local td = d:picFor("RATTATA")
  check(hd.tags[ts] and hd.tags[ts].side == nil and hd.tags[td] and hd.tags[td].lowPivot[2] <= 56,
    "dex pass: the summary and Pokedex frames tagged, in box units")
  draws = {}
  d:drawUnownPic(5, 0, 0)
  -- (the last draw is the page's; one before it is the frame's render)
  check(#draws >= 1 and hd.tags[draws[#draws].img] ~= nil, "and the Unown page's")
  gbc.mode = "dmg"
  check(hd.tags[s:picFor({ species = "BAYLEEF" })] == nil, "DMG: not tagged without features.shades")
  hd.features = { shades = true }
  local sh = s:picFor({ species = "MEGANIUM" })
  check(hd.tags[sh] and hd.tags[sh].shades ~= nil, "with features.shades: tagged, with the shader")
  gbc.mode = "gbc"
  hd.features, atlas.hd = nil, nil

  local e = setmetatable({ game = game, mon = { species = "CYNDAQUIL" } }, Evo)
  check(select(2, e:pic("QUILAVA")) == true, "evolution: ours")
  e.blackout = true
  check(select(2, e:pic("QUILAVA")) == false, "its silhouette: shaded, for the palette to blacken")
  opts.other_sprites = false
  check(e:pic("QUILAVA") == "VANILLA", "OTHER SCREENS off")
  opts.other_sprites = nil
end

-- Crystal's animated pics on a screen that shows ours
do
  local v = View.start({ id = "CYNDAQUIL", dex = 155 }, nil, "menu")
  check(View.frame(v) == nil, "the summary's animation: none over ours")
  opts.summary_sprites = false
  check(View.frame(v) == "SHEET", "plays when the summary shows the game's own")
  opts.summary_sprites = nil
  check(View.frame(View.start({ id = "NOT_A_MON" }, nil, "menu")) == "SHEET", "and for a species with no art")
end

-- party icons: the game's own where it has one; ours for the rest, and for all on the G9 page
do
  local p = setmetatable({ game = game, ids = { CHIKORITA = "ICON_CHIK" }, icons = { icons = { ICON_CHIK = {} } },
    palettes = { partyMenu = { { 1, 2, 3, 4 } } } }, Party)
  check(p:drawIcon({ species = "CHIKORITA" }, 0, 0) == "VANILLA", "a cart species keeps its icon")
  draws = {}
  check(p:drawIcon({ species = "TURTWIG" }, 8, 4) == nil and #draws > 0, "a National Dex species: ours")
  check(draws[#draws].quad == 8 and draws[#draws].x == 4, "in the icon's slot (an unquadded draw: x, y)")
  draws = {}
  p:drawIcon({ species = "TURTWIG", item = "BERRY" }, 0, 0)
  check(#draws >= 4, "holding an item: three quarters and the game's marker")
  opts.party_icons = false
  check(p:drawIcon({ species = "TURTWIG" }, 0, 0) == "VANILLA", "PARTY ICONS off")
  opts.party_icons = nil
  check(p:battlePanelScale(800, 720) == nil and p:drawWidescreen(800, 720) == "VANILLA", "G9 off: the game's page")
  opts.g9_party_screen = true
  check(p:drawIcon({ species = "CHIKORITA" }, 0, 0) == nil, "G9 PARTY SCREEN: ours for every Pokemon")
  check(p:battlePanelScale(800, 720) == 5 and p:drawWidescreen(800, 720) == nil, "and the page fills the window")
  opts.g9_party_screen = nil
end

-- the exports
do
  local ex = Gen2.exports(atlas, function() return game.data end)
  check(ex.frontArt({ species = "TURTWIG" }) ~= nil and ex.iconArtHD({ species = "TURTWIG" }) ~= nil, "frontArt, iconArtHD")
  draws = {}
  check(ex.drawSummaryFrame({ species = "CHIKORITA" }) == true and draws[#draws].kx == nil, "drawSummaryFrame: not mirrored")
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 gen 2)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
