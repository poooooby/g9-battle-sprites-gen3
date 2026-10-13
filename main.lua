-- G9 Battle Sprites (gen 3): animated true-colour battle pics, Pokedex and
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

return function(mod)
  local Hooks = loadSibling(mod, "src/hooks.lua")
  local Api = loadSibling(mod, "src/api.lua")
  local Atlas = loadSibling(mod, "src/atlas.lua")
  if not (Hooks and Api and Atlas) then return end

  -- national_dex_gen3 is optional: without it the species slots are simply
  -- never asked for, and the hooks answer nothing.
  local dex = mod:find("national_dex_gen3")
  if not dex then
    mod.log:info("national_dex_gen3 is not installed -- only species #1-386 to draw")
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
