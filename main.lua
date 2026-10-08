-- G9 Battle Sprites (gen 3): animated true-colour battle pics, Pokedex and
-- summary front pics, and party icons for National Dex species #387-1025 on
-- FireRed, LeafGreen, Ruby, Sapphire and Emerald.
--
-- Everything is drawn from the atlases in assets/atlas/ (built by
-- tools/build_atlas.py). Species #1-386 are never touched: they keep the
-- game's own sprites.
--
-- Module map:
--   src/atlas.lua  reads the atlases, renders animation frames, builds icons
--   src/hooks.lua  wraps Pokemon.frontPic / backPic / icon for dex 387+
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
    mod.log:info("national_dex_gen3 is not installed -- no species #387-1025 to draw")
  end
  -- 1025Dex registers the same slots with its own art; two sprite sets would fight.
  local okP, provider = pcall(function() return dex and dex.exports.provider() end)
  if okP and provider and provider ~= "national_dex_gen3" then
    mod.log:info("%s provides the species -- g9-battle-sprites-gen3 draws nothing", provider)
    Api(mod, { active = false, provider = provider })
    return
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
    local n = Hooks.install(Pokemon, atlas)
    mod.log:info("hooked %d picture functions for species #387-1025", n)
    if type(Pokemon.onReload) == "function" then
      Pokemon.onReload(function() Hooks.install(Pokemon, atlas) end, "g9-battle-sprites-gen3")
    end
  end

  mod.events:on("game.ready", function(ev)
    install(ev and ev.game or mod.game)
  end, 0)
  -- Also at load: tools that load mods without starting a game (the save
  -- editor) never fire game.ready, and draw species pics through the same
  -- Pokemon.frontPic. install() is idempotent, so the game.ready call above
  -- is then a no-op.
  pcall(install, mod.game)

  Api(mod, { active = true, atlas = function() return atlas end })
end
