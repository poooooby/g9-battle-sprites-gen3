-- mod.exports: what other mods read from g9-battle-sprites-gen3.
--
--   local g9 = mod:find("g9-battle-sprites-gen3")
--   if g9 and g9.exports.isActive() then ... end

return function(mod, state)
  local exports = {}

  exports.isActive = function() return state.active == true end
  exports.provider = function() return state.provider or "g9-battle-sprites-gen3" end

  -- true when the atlas holds a sprite for this National Dex number and variant
  -- ("front", "front_shiny", "back", "back_shiny", "icon")
  exports.hasSprite = function(dex, variant)
    local atlas = state.atlas and state.atlas()
    -- (the atlas is keyed by its own slots: a dex number finds its base species)
    local key = atlas and atlas.keyFor(nil, dex)
    return key ~= nil and atlas.cell(key, variant or "front") ~= nil
  end

  mod.exports = exports
end
