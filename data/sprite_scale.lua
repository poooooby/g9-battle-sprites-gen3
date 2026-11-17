-- Fine-tune how big each Pokemon is drawn in battle. Edit and restart the game (no rebuild).
--
-- Only used when the WoobleView mod (gen3-hd-sprites) is installed and Battle HD is on (on every
-- game: Red to Crystal's battles use the same sizes, in the Game Boy's pixels):
-- it draws these at your screen's full resolution, so ANY value keeps every pixel of the art.
-- Without it, the sizes are fixed (the game's pixel grid can only do clean steps).
--
-- Key: the species id (the names in data/atlas_index.lua, e.g. NOIVERN, MR_MIME, WORMADAM_SANDY).
-- Each field is optional; leave it out to keep the default:
--
--   front    size of the ENEMY's front pic, 1 = 100%. Default 1 (the sprite's own size). It scales
--            about the feet, so a smaller Pokemon keeps standing on its spot.
--   back     size of YOUR Pokemon's back pic, 1 = 100%. Default 1, about the feet too.
--   height   its height, 1 = the Pokedex's. Default 1. For a long Pokemon whose Pokedex height
--            is its length end to end (Gyarados' 6.5 m): 0.5 sizes it by half that. WoobleView's
--            Battle Fit sizes the two battlers against each other by height, and `realism` uses it.
--   size     its share of the size it is drawn at, front and back, 1 = 100%. Default 1. Unlike
--            front / back it holds with WoobleView's Battle Fit too, which otherwise sizes the
--            battlers itself; the other battler keeps its size. About the feet, like the rest.
--   front_dx, front_dy, back_dx, back_dy
--            nudge in game pixels (positive = right / down), on top of where the sprite already
--            stands: feet on the middle of its pad (worked out in the atlas, with or without HD
--            Sprites). These nudges are WoobleView only; a nudge for everyone goes in the atlas
--            (FRONT_NUDGE, tools/build_atlas.py).
--
-- `all` below scales every Pokemon on top of the above (1 = no change).
--
-- `realism` sizes each Pokemon by its real height (the Pokedex's), on top of the above:
--   on       false turns it off (every Pokemon at its sprite's own size)
--   center   the neutral height in metres (1.65 = 5'5"): a Pokemon this tall keeps its size
--   grow     how much the tallest grows (0.25 = 25% bigger at `tallest`)
--   shrink   how much the shortest shrinks (0.15 = 15% smaller at `shortest`)
--   curve    the rubber band: 1 = even steps, higher = more Pokemon stay near their own size
--            and only the true extremes reach the limits (1.5: Pikachu 95%, Gyarados 110%)
--   shortest, tallest   the heights (m) that get the full shrink / grow
--   front    the enemy's front pic is this much smaller for perspective (it stands farther
--            away; the cart's own fronts are about 0.90 the width of its backs, and 0.85 reads
--            better next to the art's own sizes)
--   match_backs   true: each Pokemon's back is first brought to its own front's size (the two
--            sheets are drawn at different sizes for some species: Tinkaton's back is small,
--            Tatsugiri's big), so a Pokemon is the same size from both sides
--
-- Examples:
--   NOIVERN  = { front = 0.6 },                        -- 60% (the front frame is 182 px tall)
--   TYRANITAR = { back = 1.15, back_dy = 4 },         -- 15% bigger, 4 px lower
--   PIKACHU  = { back = 1.4, back_dx = -2 },           -- 40% bigger, 2 px left

return {
  all = { front = 1, back = 1 },

  realism = { on = true, center = 1.65, grow = 0.25, shrink = 0.15, curve = 1.5,
              shortest = 0.1, tallest = 20, front = 0.9, match_backs = true },

  NOIVERN = { front = 0.6, front_dy = -2 },

  -- long Pokemon: the Pokedex's height is their length, end to end
  GYARADOS = { height = 0.5 },

  -- long and coiled Pokemon too: the Pokedex measures them head to tail, so each is sized by
  -- this share of it
  EKANS = { height = 0.25 },
  ARBOK = { height = 0.35 },
  ONIX = { height = 0.5 },
  DRATINI = { height = 0.5 },
  DRAGONAIR = { height = 0.5 },
  STEELIX = { height = 0.5 },
  WURMPLE = { height = 0.6 },
  SEVIPER = { height = 0.3 },
  MILOTIC = { height = 0.35 },
  HUNTAIL = { height = 0.3 },
  GOREBYSS = { height = 0.5 },
  SERPERIOR = { height = 0.8 },
  ZYGARDE = { height = 0.6 },
  DRAMPA = { height = 0.7 },
  SILICOBRA = { height = 0.5 },
  SANDACONDA = { height = 0.5 },
  DREEPY = { height = 0.8 },
}
