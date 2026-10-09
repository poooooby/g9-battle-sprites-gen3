-- Fine-tune how big each Pokemon is drawn in battle. Edit and restart the game (no rebuild).
--
-- Only used when the Gen 3 HD Sprites mod (gen3-hd-sprites) is installed and Battle HD is on:
-- it draws these at your screen's full resolution, so ANY value keeps every pixel of the art.
-- Without it, the sizes are fixed (the game's pixel grid can only do clean steps).
--
-- Key: the species id (the names in data/atlas_index.lua, e.g. NOIVERN, MR_MIME, WORMADAM_SANDY).
-- Each field is optional; leave it out to keep the default:
--
--   front    size of the ENEMY's front pic, 1 = 100%. Default 1 (the sprite's own size). It scales
--            about the feet, so a smaller Pokemon keeps standing on its spot.
--   back     size of YOUR Pokemon's back pic, 1 = 100%. Default: zoomed in to match the cart's
--            back sprite (tools/back_framing.py). Setting it replaces that zoom.
--   front_dx, front_dy, back_dx, back_dy
--            nudge in game pixels (positive = right / down). The back default already puts the
--            body where the cart's back sprite has it. front_dy's default is data/front_anchor.lua
--            (feet raised to the platform's centre); setting front_dy here replaces it.
--
-- `all` below scales every Pokemon on top of the above (1 = no change).
--
-- Examples:
--   NOIVERN  = { front = 0.6 },                        -- 60% (the front frame is 182 px tall)
--   TYRANITAR = { back = 1.15, back_dy = 4 },         -- 15% bigger, 4 px lower
--   PIKACHU  = { back = 1.4, back_dx = -2 },           -- 40% bigger, 2 px left

return {
  all = { front = 1, back = 1 },

  NOIVERN = { front = 0.6, front_dy = -2 },
}
