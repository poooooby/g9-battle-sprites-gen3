-- Run from the mod root: luajit tests/gen1_test.lua
-- Gen 1 (Red / Blue / Yellow): species ids to atlas keys, the fit-to-box frames (size, feet,
-- floaters, the pack's metrics, shadows, mirroring), the options, the battle hooks (the frame
-- in the battler's sprite, the Tower ghost left alone, the scale, Transform) and the screen
-- wraps (never wrapped twice, wrapped again when another mod replaces one).
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

-- ids to keys
check(atlas.keyFor("CHARIZARD") == 6, "CHARIZARD is slot 6")
check(atlas.keyFor("CHARIZARD_MEGA_X", 6, "CHARIZARD") == 6, "a Mega the atlas has no art for shows its base")
check(atlas.keyFor("SOMETHING_NEW", 25) == 25, "an unknown id falls back to its dex number")
check(atlas.keyFor(nil, 387) == 451, "dex 387 (Turtwig) is slot 451")
check(atlas.keyFor(nil, 201) == 201, "dex 201 is Unown A, not a letter")
check(atlas.keyFor("RATTATA_ALOLA") ~= nil and atlas.keyFor("RATTATA_ALOLA") ~= 19, "a form has its own key")
check(atlas.keyFor("NIDORAN_F") == 29 and atlas.keyFor("MR_MIME") == 122, "the Gen 1 ids match")
check(atlas.femaleKey(atlas.keyFor("MEOWSTIC")) == -atlas.keyFor("MEOWSTIC"), "Meowstic's female sheet")
check(atlas.femaleKey(6) == nil, "no female sheet for Charizard")
local data = { pokemon = { CHARIZARD_MEGA_X = { dex = 6, baseSpecies = "CHARIZARD" }, TURTWIG = { dex = 387 } } }
check(Gen1.keyOf(atlas, data, "CHARIZARD_MEGA_X") == 6, "keyOf reads the record's base species")
check(Gen1.keyOf(atlas, data, "TURTWIG") == 451, "keyOf: a National Dex species")

-- the last sprite draw of a boxFrame call (not its shadow)
local function lastDraw() return draws[#draws] end

-- fit to the box: 1:1 when it fits, bottom-centred on its union box
do
  draws = {}
  local cell = atlas.cell(1, "front")
  local c = atlas.boxFrame(1, "front", 0, 56, 56)
  check(c and c:getWidth() == 56 and c:getHeight() == 56, "a 56x56 canvas")
  local d = lastDraw()
  local cw, ch = cell.ux1 - cell.ux0, cell.uy1 - cell.uy0
  check(d.kx == 1, "Bulbasaur (" .. cw .. "x" .. ch .. ") is drawn 1:1")
  check(d.y + cell.uy1 == 56, "its art's bottom on the box's bottom")
  check(math.abs((d.x + cell.ux0 + cw / 2) - 28) <= 1, "centred")
  check(atlas.boxFrame(1, "front", 0, 56, 56) == c, "cached")
end
do
  draws = {}
  local cell = atlas.cell(atlas.keyFor("WAILORD"), "front")
  atlas.boxFrame(atlas.keyFor("WAILORD"), "front", 0, 56, 56)
  local d = lastDraw()
  local cw, ch = cell.ux1 - cell.ux0, cell.uy1 - cell.uy0
  check(d.kx < 1 and math.max(cw, ch) * d.kx <= 56.001, "a giant is shrunk to fit (" .. d.kx .. ")")
  draws = {}
  atlas.boxFrame(1, "front", 0, 56, 56, { divisor = 2 })
  check(lastDraw().kx == 0.5, "SPRITE SIZE NORMAL halves it")
end
-- floaters, the pack's metrics, shadows, mirror, silhouette
do
  local key = 16                       -- Pidgey: floats, has metrics
  check(atlas.info(key).fl == true and type(atlas.info(key).pm) == "table", "Pidgey's pack data is in the index")
  draws = {}
  atlas.boxFrame(key, "front", 0, 56, 56)
  local ground, groundX = lastDraw().y, lastDraw().x
  draws = {}
  atlas.boxFrame(key, "front", 0, 56, 56, { float = true })
  check(lastDraw().y < ground, "a floater is lifted off the ground")
  check(atlas.boxFrame(1, "front", 0, 56, 56, { float = true }) == atlas.boxFrame(1, "front", 0, 56, 56),
    "a grounded species is not (the same frame)")
  draws = {}
  atlas.boxFrame(key, "front", 0, 56, 56, { anchor = "pack" })
  -- Pidgey: fx 3 in the pack's units is 3 sheet px at its front scale, less half the margin
  -- its union trimmed (1 px): 2.5 to the right; fy 2 is clamped by the box's bottom
  check(lastDraw().x == groundX + 3 and lastDraw().y == ground, "PACK moves it by the pack's metrics")
  draws = {}
  atlas.boxFrame(1, "back", 0, 64, 64, { shadow = true })
  check(#draws == 2 and draws[1].img ~= draws[2].img, "a shadow is drawn first, under the Pokemon")
  check(draws[1].y + 4 * draws[1].ky == 64, "the shadow sits on the box's bottom")
  draws = {}
  atlas.boxFrame(1, "front", 0, 56, 56, { mirror = true })
  check(lastDraw().sx == -1 and lastDraw().tx == 56, "mirrored about the box")
  draws = {}
  atlas.boxFrame(1, "front", 0, 56, 56, { silhouette = true })
  check(lastDraw().black, "a silhouette is drawn black")
  local hd = atlas.boxFrame(1, "back", 0, 28, 28, { dpi = 2 })
  check(hd.dpi == 2 and hd:getWidth() == 28, "a dpiscale canvas reports its box")
end
-- a window mode change may empty every canvas: the frames are made again
do
  love.window = { setMode = function() return true end, setFullscreen = function() return true end }
  Atlas.watchWindow()
  local before = atlas.boxFrame(1, "front", 0, 56, 56)
  check(love.window.setMode(800, 600) == true, "setMode still answers as LOVE's")
  local after = atlas.boxFrame(1, "front", 0, 56, 56)
  check(after ~= before, "after setMode: a new frame, not the emptied canvas")
  check(atlas.boxFrame(1, "front", 0, 56, 56) == after, "then cached again")
  love.window.setFullscreen(true)
  check(atlas.boxFrame(1, "front", 0, 56, 56) ~= after, "and after setFullscreen")
  love.window = nil
end

-- the options
do
  local opts = {}
  Gen1.options = function(key) return opts[key] end
  NOW = 0.5
  local still = atlas.boxFrame(1, "front", 0, 56, 56)
  check(Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56) ~= still, "animated: a later frame at 0.5 s")
  opts.animate_sprites = false
  check(Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56) == still, "ANIMATE off: the first frame")
  opts.animate_sprites = nil
  opts.sprite_size = 3
  draws = {}
  Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56)
  check(math.abs(lastDraw().kx - 1 / 3) < 1e-9, "SPRITE SIZE SMALL: a third")
  opts.sprite_size = nil
  local shinyMon = { species = "BULBASAUR", shiny = true }
  check(Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56, shinyMon)
        ~= Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56), "a shiny gets its shiny art")
  opts.sprite_shiny = false
  check(Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56, shinyMon)
        == Gen1.frame(atlas, data, "BULBASAUR", "front", 56, 56), "SHINY ART off: the normal art")
  opts.sprite_shiny = nil
  check(Gen1.frame(atlas, data, "NOT_A_SPECIES", "front", 56, 56) == nil, "nil for a species without art")
  NOW = nil
end

-- the battle hooks
do
  local opts = {}
  Gen1.options = function(key) return opts[key] end
  local BattleState = {}
  local layerSprites
  function BattleState:drawPicsLayer() layerSprites = { self.enemy and self.enemy.sprite, self.player and self.player.sprite } end
  BattleState.resolveBattleScale = function(_, side) return side == "back" and 2 or 1 end
  function BattleState:drawBattlerPic() end
  function BattleState:speciesSprite(species) return { vanilla = species } end
  check(Gen1.installBattle(atlas, BattleState), "battle hooked")
  local wrapped = BattleState.drawPicsLayer
  Gen1.installBattle(atlas, BattleState)
  check(BattleState.drawPicsLayer == wrapped, "not wrapped twice")
  local battle = { data = data,
    enemy = { sprite = "front/pidgey.png", mon = { species = "PIDGEY" } },
    player = { sprite = "back/bulbasaurb.png", mon = { species = "BULBASAUR" }, isPlayer = true } }
  battle.drawPicsLayer = BattleState.drawPicsLayer
  battle:drawPicsLayer()
  check(type(layerSprites[1]) == "table" and layerSprites[1]:getWidth() == 56, "the enemy gets a 56x56 frame")
  check(type(layerSprites[2]) == "table" and layerSprites[2]:getWidth() == 64, "the player a 64x64 one")
  check(BattleState.resolveBattleScale(data, "back", nil, "BULBASAUR") == 1, "our back pic is drawn 1x")
  check(BattleState.resolveBattleScale(data, "back", nil, "MISSINGNO") == 2, "anything else keeps its scale")
  -- the Tower ghost
  battle.ghost = true
  battle:drawPicsLayer()
  check(layerSprites[1] == "front/pidgey.png", "the ghost's disguise keeps the game's pic")
  battle.ghost = nil
  -- Transform: the copied species' art
  battle.player.sprite = BattleState.speciesSprite(battle, "MEW", true)
  battle:drawPicsLayer()
  local mewKey = atlas.keyFor("MEW")
  check(type(layerSprites[2]) == "table"
        and layerSprites[2] == Gen1.frame(atlas, data, "MEW", "back", 64, 64, battle.player.mon,
                                          { reuse = true, shadow = true, mirror = false }),
        "a Transformed Pokemon shows the species it copied (" .. tostring(mewKey) .. ")")
  -- BATTLE SPRITES off: the game's pics back
  opts.enable_battle_sprites = false
  battle:drawPicsLayer()
  check(layerSprites[1] == "front/pidgey.png", "BATTLE SPRITES off: the game's own pic")
  opts.enable_battle_sprites = nil

  -- WoobleView: each battle frame is tagged with its full frame, anchored on the feet
  local hd = { tags = setmetatable({}, { __mode = "k" }), on = true }
  function hd.isActive() return true end
  function hd.enabled(pass) return pass == "battle" and hd.on end
  function hd.tag(image, spec) hd.tags[image] = spec end
  function hd.untag(image) hd.tags[image] = nil end
  atlas.hd = hd
  draws = {}
  battle:drawPicsLayer()
  local foe, mine = hd.tags[layerSprites[1]], hd.tags[layerSprites[2]]
  check(foe and foe.side == "enemy" and foe.texture and foe.quad and foe.body == nil, "WoobleView: the foe's frame is tagged")
  check(mine and mine.side == "player" and type(mine.body) == "table", "and the player's, with its body box")
  local pcell = atlas.cell(16, "front")
  check(foe and foe.pivot[2] == (tonumber(pcell.ffr) or pcell.fs) and foe.top == pcell.uy0, "the foe's feet and its art's top")
  -- the stand-in's draw (the last sprite draw for the foe is the first after its shadow)
  local fd
  for _, d in ipairs(draws) do if d.quad == foe.quad then fd = d break end end
  check(fd and math.abs(foe.lowPivot[1] - (fd.x + foe.pivot[1] * fd.kx)) < 1e-9
        and math.abs(foe.lowPivot[2] - (fd.y + foe.pivot[2] * fd.kx)) < 1e-9 and foe.scale == fd.kx,
        "lowPivot: where the feet sit in the stand-in, at its scale")
  hd.on = false
  battle:drawPicsLayer()
  check(hd.tags[layerSprites[1]] == nil, "WoobleView off for battles: not tagged")
  hd.on = true
  package.loaded["src.render.PaletteFX"] = { mode = "og" }
  battle:drawPicsLayer()
  check(hd.tags[layerSprites[1]] == nil and hd.tags[layerSprites[2]] == nil, "OG colours: not tagged")
  package.loaded["src.render.PaletteFX"] = nil
  opts.battle_frontal, opts.battle_front_flip = true, true
  battle:drawPicsLayer()
  check(hd.tags[layerSprites[2]] == nil, "a mirrored 3DB FLIP frame: not tagged by a WoobleView without flip")
  hd.features = { flip = true }
  draws = {}
  battle:drawPicsLayer()
  local flip = hd.tags[layerSprites[2]]
  local md
  for _, d in ipairs(draws) do if flip and d.quad == flip.quad then md = d end end
  check(flip and flip.flip == true and flip.side == "player", "with features.flip: tagged, flip = true")
  check(flip and md and math.abs(flip.lowPivot[1] - (64 - (md.x + flip.pivot[1] * md.kx))) < 1e-9
        and md.sx == -1, "its lowPivot mirrored about the box, as the stand-in is drawn")
  opts.battle_front_flip = nil
  battle:drawPicsLayer()
  check(hd.tags[layerSprites[2]] and hd.tags[layerSprites[2]].flip == nil, "3DB FRONTAL unflipped: no flip")
  hd.features = nil
  opts.battle_frontal, opts.battle_front_flip = nil, nil
  atlas.hd = nil
end

-- the screen wraps: once each, and again over another mod's replacement
do
  Gen1.options = nil
  package.loaded["src.ui.SummaryMenu"] = { draw = function(self) self.drawn = self.sprite end }
  package.loaded["src.ui.PartyMenu"] = { drawIcon = function() return "game's icon" end }
  local done = Gen1.installScreens(atlas)
  local hooked = table.concat(done, ",")
  check(hooked:find("summary") and hooked:find("party icons"), "the summary and party icons are hooked: " .. hooked)
  local Summary = package.loaded["src.ui.SummaryMenu"]
  local ours = Summary.draw
  Gen1.installScreens(atlas)
  check(Summary.draw == ours, "a second install leaves the wrapper alone")
  local s = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s)
  check(s.drawn and s.drawn:getWidth() == 56 and s.spriteTrueColor == true, "the summary draws our frame, true colour")
  Summary.draw = function(self) self.other = true end      -- another mod replaces it
  Gen1.installScreens(atlas)
  check(Summary.draw ~= ours, "a replacement is wrapped in turn")
  local s2 = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s2)
  check(s2.other and s2.sprite ~= nil, "... and still gets our frame")
  local Party = package.loaded["src.ui.PartyMenu"]
  check(Party.drawIcon({ data = data }, { species = "BULBASAUR" }, 0, 0) == "game's icon", "#1-151 keep the game's icons")
  draws = {}
  Party.drawIcon({ data = data }, { species = "TURTWIG", hp = 10, stats = { hp = 10 } }, 8, 16)
  check(#draws == 1 and draws[1].x == 8 and draws[1].kx == 0.5, "a National Dex species gets ours, at 16x16")
  check(Party.drawIcon({ data = data }, { species = "TURTWIG", isEgg = true }, 0, 0) == "game's icon", "an egg keeps the game's")
end

-- party icons: the game's own for #1-151 on its list, ours for the rest; ours for all on the
-- G9 PARTY SCREEN
do
  local opts = {}
  Gen1.options = function(key) return opts[key] end
  local Party = package.loaded["src.ui.PartyMenu"]
  data.pokemon.CHIKORITA = { dex = 152 }
  check(Party.drawIcon({ data = data }, { species = "PIKACHU" }, 0, 0) == "game's icon", "Pikachu keeps the game's icon")
  draws = {}
  Party.drawIcon({ data = data }, { species = "CHIKORITA" }, 0, 0)
  check(#draws == 1, "Chikorita (#152, none in the game) gets ours")
  opts.g9_party_screen = true
  draws = {}
  Party.drawIcon({ data = data }, { species = "PIKACHU" }, 0, 0)
  check(#draws == 1, "on the G9 PARTY SCREEN, Pikachu gets ours too")
  opts.party_icons = false
  check(Party.drawIcon({ data = data }, { species = "CHIKORITA" }, 0, 0) == "game's icon", "PARTY ICONS off: the game's")
  Gen1.options = nil
end

-- the G9 PARTY SCREEN: a 640x576 page drawn at 4x, the anchors held, and a classic screen pushed
-- over it dressed for the same page
do
  local opts = {}
  Gen1.options = function(key) return opts[key] end
  local PartyMenu = { draw = function() end, sgbPalettes = function() return { { x = 1, y = 2, w = 3, h = 4 } } end }
  PartyMenu.__index = PartyMenu
  local StateStack = {}
  function StateStack:push(state) self.states[#self.states + 1] = state end
  check(Gen1.installPartyScreen(PartyMenu, StateStack), "party screen installed")
  check(select(1, PartyMenu.uiSize()) == 160 and PartyMenu.holdsUIAnchors == nil, "off: the game's 160x144 page")
  opts.g9_party_screen = true
  local w, h = PartyMenu.uiSize()
  check(w == 640 and h == 576 and PartyMenu.holdsUIAnchors ~= nil, "on: a 640x576 page, anchors held")
  check(PartyMenu.isWideBattleLayout() and PartyMenu.wantsFillScale(), "... a wide page that fills the window")
  local z = PartyMenu.sgbPalettes({}, {})[1]
  check(z.x == 4 and z.y == 8 and z.w == 12 and z.h == 16, "its colour zones take the 4x")
  sx = 1
  local drawnAt
  PartyMenu.draw = PartyMenu.draw      -- (the wrapped one)
  local stack = { states = {} }
  setmetatable(stack, { __index = StateStack })
  local menu = setmetatable({}, PartyMenu)
  stack:push(menu)
  local box = { draw = function() drawnAt = sx end }
  stack:push(box)
  check(box.uiSize ~= nil and select(1, box.uiSize()) == 640, "a screen pushed over the page is dressed for it")
  love.graphics.scale = function(k) sx = sx * k end
  box:draw()
  check(drawnAt == 4, "... and drawn at 4x")
  opts.g9_party_screen = nil
  check(select(1, box.uiSize()) == 160, "... and back to its own size with the option off")
  Gen1.options = nil
end

-- colour: where the colour pass would recolour, the art is in the four shades and not marked true
-- colour
do
  local fake = { mode = "gbc", honorsTrueColor = function() return false end }
  package.loaded["src.render.PaletteFX"] = fake
  check(Gen1.keepsColour() == false and Gen1.monoBattle() == false, "SGB: not kept off battle, battle not mono")
  local Summary = package.loaded["src.ui.SummaryMenu"]
  local s = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s)
  check(s.sprite ~= nil and s.spriteTrueColor == false, "the summary pic is the shaded one, not marked")
  fake.honorsTrueColor = function() return true end
  local s2 = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s2)
  check(s2.spriteTrueColor == true and s2.sprite ~= s.sprite, "ADVANCED: the true-colour one, marked")
  fake.mode = "og"
  check(Gen1.monoBattle() == true, "OG: a mono battle")
  package.loaded["src.render.PaletteFX"] = nil
end

-- WoobleView's "dex" pass: the summary and Pokedex entry frames are tagged (no side), a shaded
-- one only where it can draw through the shades shader
do
  local hd = { tags = setmetatable({}, { __mode = "k" }), on = true }
  function hd.isActive() return true end
  function hd.enabled(pass) return pass == "dex" and hd.on end
  function hd.tag(image, spec) hd.tags[image] = spec end
  function hd.untag(image) hd.tags[image] = nil end
  atlas.hd = hd
  local fake = { mode = "gbc", honorsTrueColor = function() return true end }
  package.loaded["src.render.PaletteFX"] = fake
  package.loaded["src.ui.DexEntryMenu"] = {
    draw = function(self) self.drawn = self.sprite end,
    render = function(game, def, sprite) return sprite end,
  }
  Gen1.installScreens(atlas)
  local Summary = package.loaded["src.ui.SummaryMenu"]
  local s = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s)
  local t = hd.tags[s.sprite]
  check(t and t.texture and t.quad and t.side == nil and t.top == nil and t.shades == nil and t.flip == nil,
        "ADVANCED summary: tagged for the dex pass, no side")
  draws = {}
  local Dex = package.loaded["src.ui.DexEntryMenu"]
  local e = { game = { data = data }, species = "PIKACHU" }
  Dex.draw(e)
  local te = hd.tags[e.drawn]
  local ed
  for _, d in ipairs(draws) do if te and d.quad == te.quad then ed = d end end
  check(te and (not ed or math.abs(te.lowPivot[1] - (ed.x + te.pivot[1] * ed.kx)) < 1e-9),
        "the Pokedex entry's frame is tagged, lowPivot where the stand-in's pivot sits")
  local def = { dex = 25 }
  data.pokemon.PIKACHU = def
  check(hd.tags[Dex.render(e.game, def, "game's pic")] ~= nil, "... and the one render is handed")
  -- shaded (SGB): only with features.shades, and then carrying the shader
  fake.honorsTrueColor = function() return false end
  local s2 = { game = { data = data }, mon = { species = "CHARIZARD" } }
  Summary.draw(s2)
  check(s2.spriteTrueColor == false and hd.tags[s2.sprite] == nil, "shaded: not tagged without features.shades")
  hd.features = { shades = true }
  local s3 = { game = { data = data }, mon = { species = "BULBASAUR" } }
  Summary.draw(s3)
  local t3 = hd.tags[s3.sprite]
  check(t3 and t3.shades == atlas.shadesShader() and t3.shades ~= nil, "with features.shades: tagged, with the shader")
  hd.on = false
  local s4 = { game = { data = data }, mon = { species = "IVYSAUR" } }
  Summary.draw(s4)
  check(s4.sprite and hd.tags[s4.sprite] == nil, "the dex pass off: not tagged")
  hd.features, atlas.hd = nil, nil
  package.loaded["src.render.PaletteFX"] = nil
  package.loaded["src.ui.DexEntryMenu"] = nil
end

-- the battle.mon_pic answer (NaviPlay's MODDED pictures): the art at its natural size, the frame
-- playing now, front or back, shiny; nothing for any other request or with BATTLE SPRITES off
do
  local opts = {}
  Gen1.options = function(key) return opts[key] end
  local ex = Gen1.exports(atlas, function() return data end)
  local mon = { species = "BULBASAUR" }
  local cell = atlas.cell(1, "front")
  NOW = 0
  local pic = ex.monPic({ natural = true, side = "front", mon = mon, scale = 1 })
  check(pic and pic:getWidth() == cell.ux1 - cell.ux0 and pic:getHeight() == cell.uy1 - cell.uy0,
    "monPic: the front art at its own size")
  check(pic == atlas.boxFrame(1, "front", 0, cell.ux1 - cell.ux0, cell.uy1 - cell.uy0, {}), "...its first frame at 0 s")
  NOW = 0.5
  check(ex.monPic({ natural = true, side = "front", mon = mon }) ~= pic, "...a later frame later (NaviPlay samples the loop)")
  NOW = 0
  local back = atlas.cell(1, "back")
  local b = ex.monPic({ natural = true, side = "back", mon = mon })
  check(b and b:getWidth() == back.ux1 - back.ux0, "monPic: the back art")
  check(ex.monPic({ natural = true, side = "front", mon = mon, shiny = true }) ~= pic, "monPic: shiny art when asked")
  check(ex.monPic({ natural = true, side = "front", species = "BULBASAUR" }) == pic, "monPic: a species alone")
  check(ex.monPic({ side = "front", mon = mon }) == nil, "monPic: a request not at natural size is the caller's")
  check(ex.monPic({ natural = true, side = "front", mon = { species = "NOT_A_SPECIES" } }) == nil, "monPic: no art, nil")
  check(ex.monPic({ natural = true, side = "front", mon = { species = "BULBASAUR", isEgg = true } }) == nil, "monPic: an egg, nil")
  opts.enable_battle_sprites = false
  check(ex.monPic({ natural = true, side = "front", mon = mon }) == nil, "monPic: BATTLE SPRITES off, nil")
  Gen1.options = nil
end

print(string.format("%d/%d checks passed (g9-battle-sprites-gen3 gen 1)", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
