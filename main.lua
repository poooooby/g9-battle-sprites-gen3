-- WoobleSpritePack (g9-battle-sprites-gen3): animated true-colour battle pics, Pokedex and
-- summary front pics for every species, #1-1025, and party icons for #387-1025, on
-- FireRed, LeafGreen, Ruby, Sapphire and Emerald.
--
-- Everything is drawn from the atlases in assets/atlas/ (built by
-- tools/build_atlas.py). The game's own party icons for #1-386 are kept, and so is a
-- Castform in its weather forms. Unown's letters have a sheet each, at the cart's letter slots.
--
-- Module map:
--   src/atlas.lua  reads the atlases, renders animation frames, builds icons
--   src/hooks.lua  wraps Pokemon.frontPic / backPic / icon for the species the atlas has
--   src/api.lua    mod.exports

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod", name)
    return nil
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod", name, tostring(result))
    return nil
  end
  return result
end

-- The generation being played: 1 or 2 from the engine's version, else 3. The save editor is a
-- Gen 3 host whatever the version module says (its default version is Red's).
local function generation()
  local okE, Gen = pcall(require, "Gen")
  if okE and type(Gen) == "table" and type(Gen.bindGame3Data) == "function" then return 3 end
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not (ok and type(GameVersion) == "table" and type(GameVersion.generation) == "function") then
    return 3
  end
  local okG, gen = pcall(GameVersion.generation)
  gen = okG and tonumber(gen) or 3
  return (gen == 1 or gen == 2) and gen or 3
end

-- Gen 1 / 2: the same atlas, fitted to those games' pic boxes (src/gen1.lua, and src/gen2.lua
-- on top of it for Gold / Silver / Crystal).
local function classic(mod, gen, Api, Atlas)
  local Gen1 = loadSibling(mod, "src/gen1.lua")
  local Gen2 = gen == 2 and loadSibling(mod, "src/gen2.lua") or nil
  if gen == 2 and not Gen2 then Gen1 = nil end
  local atlas, logged = nil, nil
  local function install()
    if not Gen1 then return end
    if not atlas then
      atlas = Atlas.new(mod, function(path) return loadSibling(mod, path) end)
      if not atlas then
        mod.log:error("data/atlas_index.lua is missing -- reinstall the mod")
        Gen1 = nil
        return
      end
    end
    Gen1.options = function(key) return mod.options:get(key) end
    local list = Gen2 and Gen2.install(atlas, Gen1) or Gen1.install(atlas, mod.log)
    local done = table.concat(list, ", ")
    if done ~= "" and done ~= logged then
      logged = done
      mod.log:info("Gen %d: hooked %s", gen, done)
    end
  end
  -- WoobleView (gen3-hd-sprites, optional): the battle frames are tagged for it (Atlas
  -- boxFrame's hdSide), and it redraws them at window resolution in the original battle screen
  local function linkHd()
    if not atlas then return end
    local hd = mod:find("gen3-hd-sprites")
    local ex = hd and hd.exports
    atlas.hd = (type(ex) == "table" and type(ex.tag) == "function" and type(ex.enabled) == "function")
      and ex or nil
  end
  local game = nil
  mod.events:on("game.ready", function(ev)
    game = ev and ev.game or game
    install()
    linkHd()
  end, 0)
  -- (the library may finish installing after this mod's game.ready ran)
  mod.events:on("battle.started", function() pcall(linkHd) end)
  -- (a screen another mod replaces after this one loaded is wrapped once it is pushed)
  -- (and WoobleView linked for the Pokedex / summary, which may be opened before any battle)
  mod.events:on("screen.pushed", function()
    pcall(install)
    pcall(linkHd)
  end)
  pcall(install)
  Api(mod, { active = Gen1 ~= nil, atlas = function() return atlas end })
  -- the exports g9-battle-sprites gave other mods (src/gen1.lua Gen1.exports, Gen2.exports)
  if Gen1 then
    local function dataOf()
      local g = game or mod.game
      return type(g) == "table" and g.data or nil
    end
    local ex = nil
    local function exports()
      if not atlas then return nil end
      ex = ex or (Gen2 and Gen2.exports(atlas, dataOf) or Gen1.exports(atlas, dataOf))
      return ex
    end
    for _, name in ipairs({ "frontArt", "iconArtHD", "iconArt16", "drawSummaryFrame" }) do
      mod.exports[name] = function(...)
        local e = exports()
        if not e then return nil end
        return e[name](...)
      end
    end
    -- the engine's seam for a sprite mod's pictures outside the game's own screens: answered at
    -- natural size (NaviPlay's MODDED pictures); any other request gets the caller's own
    if mod.hooks and mod.hooks.wrap then
      mod.hooks:wrap("battle.mon_pic", function(nxt, img, ctx)
        local e = exports()
        local ok, pic = pcall(function() return e and e.monPic(ctx) end)
        if ok and pic then return pic end
        return nxt(img, ctx)
      end)
    end
  end
end

return function(mod)
  local Hooks = loadSibling(mod, "src/hooks.lua")
  local Api = loadSibling(mod, "src/api.lua")
  local Atlas = loadSibling(mod, "src/atlas.lua")
  if not (Hooks and Api and Atlas) then return end

  -- the options (options.lua, also the manifest's options_schema): Red / Blue / Yellow's
  local schema = loadSibling(mod, "options.lua")
  if type(schema) == "table" and mod.options and mod.options.define then
    local ok, err = pcall(mod.options.define, mod.options, schema)
    if not ok then mod.log:warn("options could not be defined: %s", tostring(err)) end
  end

  local gen = generation()
  if gen ~= 3 then return classic(mod, gen, Api, Atlas) end

  -- national_dex_gen3 is optional: without it the species slots are simply
  -- never asked for, and the hooks answer nothing. Checked once every mod has loaded
  -- (game.ready): national_dex_gen3 lists this mod as optional, so it loads after it.
  local dexChecked = false
  local function checkDex()
    if dexChecked then return end
    dexChecked = true
    if not mod:find("national_dex_gen3") then
      mod.log:info("national_dex_gen3 is not installed -- only species #1-386 to draw")
    end
  end
  local atlas = nil
  local function install(game)
    if atlas then return end
    atlas = Atlas.new(mod, function(path) return loadSibling(mod, path) end)
    if not atlas then
      mod.log:error("data/atlas_index.lua is missing -- reinstall the mod")
      return
    end
    local okPok, Pokemon = pcall(require, "src.core.game3.pokemon")
    if not (okPok and type(Pokemon) == "table") then
      mod.log:error("the gen 3 Pokemon module is not available -- no sprites will draw")
      return
    end
    -- the save editor is the only host with its own `Gen` module (Hooks.fit)
    local okGen, Gen = pcall(require, "Gen")
    Hooks.inEditor = okGen and type(Gen) == "table" and type(Gen.bindGame3Data) == "function"
    local n = Hooks.install(Pokemon, atlas)
    mod.log:info("hooked %d picture functions", n)
    if type(Pokemon.onReload) == "function" then
      Pokemon.onReload(function() Hooks.install(Pokemon, atlas) end, "g9-battle-sprites-gen3")
    end
  end

  -- gen3-hd-sprites (optional): battle pics are then drawn from the atlas at the window's
  -- resolution, at any size, instead of through the 64x64 canvases' pixel grid
  local hdLogged = false
  local function linkHd()
    if not atlas then return end
    local hd = mod:find("gen3-hd-sprites")
    local ex = hd and hd.exports
    -- linked as soon as the library is there: its enabled(pass) is false until it has
    -- installed, so a pic asked for before then is the plain one
    atlas.hd = (type(ex) == "table" and type(ex.tag) == "function" and type(ex.enabled) == "function")
      and ex or nil
    local ok, active = pcall(function() return atlas.hd and atlas.hd.isActive() end)
    if ok and active and not hdLogged then
      hdLogged = true
      mod.log:info("gen3-hd-sprites found: battle and Pokedex pics are drawn at window resolution")
    end
  end

  -- Ruby / Sapphire draw the player's pic 4 px higher than FireRed / LeafGreen / Emerald
  -- (battle/ui.lua battler_sprite_center): lower the backs by those 4 so the feet line holds
  local function setBackShift()
    local ok, rs = pcall(function()
      local ui = require("src.core.game3.profile").forSession().ui
      return ui and ui.battleSpriteLayout == "rs"
    end)
    Atlas.backShift = (ok and rs) and 4 or 0
    -- the atlas places feet against FireRed's per-species offsets: cancel this game's own
    -- (Emerald's Pidgey hovers 16 px for its flying-pose art, the Gen 9 one stands)
    local okC, shift = pcall(function()
      local PicCoords = require("src.core.game3.battle.pic_coords")
      return Atlas.gameCoordShift(PicCoords.FRLG, PicCoords.active())
    end)
    Atlas.coordShift = (okC and type(shift) == "table") and shift or { front = {}, back = {} }
  end

  mod.events:on("game.ready", function(ev)
    checkDex()
    setBackShift()
    install(ev and ev.game or mod.game)
    linkHd()
  end, 0)
  -- the library may have finished installing after this mod's game.ready ran
  mod.events:on("battle.started", function() linkHd() end)
  -- Also at load: tools that load mods without starting a game (the save
  -- editor) never fire game.ready, and draw species pics through the same
  -- Pokemon.frontPic. install() is idempotent, so the game.ready call above
  -- is then a no-op.
  pcall(install, mod.game)

  Api(mod, { active = true, atlas = function() return atlas end })
end
