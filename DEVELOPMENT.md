# G9 Battle Sprites (Gen 3): developer guide

For contributors. Players only need the [README](README.md).

## Assets

Everything ships in `assets/atlas/`. No page is larger than 4096×4096, the texture limit on
many Android GPUs (a larger image fails to load there and the engine shows a red missing-pic
box).

- `battle_<variant>_<n>.png`: four variants (`front`, `front_shiny`, `back`, `back_shiny`),
  several pages each. A page holds blocks of uniform `fs × fs` cells; a species' frames sit in
  consecutive cells of one block, and the index records the block's corner (`ox`, `oy`).
- `party_icons_0.png`: two-frame 32×32 menu icons for #387–1025 and the forms, one page.
- `dex_fronts_0.png`: the cart-style 64×64 Ruby / Sapphire / Emerald Pokédex pics, from a
  pokeemerald-expansion checkout (`graphics/pokemon/<id>/anim_front_gba.png`, else
  `anim_front.png`, else `front.png`); a species with none uses its base species' pic.
- `data/atlas_index.lua`: each species (and form) to its engine `slot` (for Generations 1–3
  the game's own internal species id, read with the names from the engine's extracted data,
  `--gen3-data`), its cells, and for back pics where the Pokémon sits in its frame
  (`cx0, cy0, cx1, cy1`).

The atlases are built from the third-party DBK sprite pack and the "icones animados" icon
pack (not in this repo; credits in [CREDITS.md](CREDITS.md)). Rebuild them with:

```bash
python tools/build_atlas.py --sheets <DBK pack>/assets \
    --payload ../national_dex_gen3/data/species \
    --dbk <dbk_data.lua> --icons <icon_data.lua> --icon-atlas <party_icons.png>
```

Output is deterministic: the same inputs give identical bytes. Supporting tools:

- `tools/trim_loops.py` -> `tools/loop_trims.json`: long animations are trimmed to the median
  length of their kind (58 frames for fronts, 52 for backs), cut where the loop closes on a
  matching frame; a sheet with no clean loop keeps every frame.
- `tools/front_pose.py`: the resting pose of an animation (the frames most alike) and its median
  bottom row: where a Pokémon's feet are, for fronts and backs alike.
- Fronts stand on the enemy pad's middle (y 66): `tools/front_feet.py --write` ->
  `tools/front_drop.json` (grounded species floating 8 px or more are lowered), then
  `tools/front_anchor.py write` -> `tools/front_anchor.json` (those resting too low are raised);
  `FRONT_NUDGE` in `tools/build_atlas.py` holds hand nudges. All of it is baked into the front
  cell's drop `fy`, so it holds with and without Gen 3 HD Sprites. `front_feet.py --dips` /
  `--tops` list sprites dipping into the player's HP box or going above the window.
- Backs stand on the player pad's middle (y 119, partly under the text box as on the cart), at
  their own size: the build writes each back cell's resting feet row `bfr` and its feet line in
  the pic box `bfl` (`BACK_FEET_ROW` less the engine's per-species back offset). Ruby / Sapphire
  draw the player's pic 4 px higher; `Atlas.backShift` adds them back at runtime. A tall back is
  left to Gen 3 HD Sprites' Battle Fit. (`tools/back_framing.py` and `tools/back_fit.py`, the old
  cart framing, are no longer used by the build.)
- Both are placed against FireRed / LeafGreen's per-species offsets (the engine's
  `pic_coords.lua` FRLG tables). Ruby / Sapphire / Emerald have their own front / back offsets and
  enemy elevations (Emerald's Pidgey hovers 16 px for its flying-pose art), so on game start
  `main.lua` sets `Atlas.coordShift` from `Atlas.gameCoordShift(FRLG, active)` and every battle
  pic is moved by its slot's difference. Empty on FireRed / LeafGreen.
- Realism scaling (Gen 3 HD Sprites only, `Atlas.realism`, settings in `data/sprite_scale.lua`
  `realism`): each species' height `ht` (dm) is written to the index from the cart's Pokédex
  entries (`pokemon/pokedex/entries.lua`, keyed by engine slot) for Gen 1–3 and national_dex_gen3's
  `dexEntry.height` (PokeAPI) for #387+; forms and female sheets take their base's. The scale is a
  power curve on log height around 1.65 m: up to +25% at 20 m, down to −15% at 0.1 m, exponent
  1.5, so most species stay within a few percent. Why asymmetric: the art already grows with roughly
  the 0.3 power of real height but flattens above ~1.7 m (Charizard 81 px, Wailord 74), so the
  giants need the help and the small ones are already small. Each back is first brought to its
  own front's size (`bn` on back cells: the front's resting body height over the back's, held to
  0.67–1.5; Tinkaton's back art is small, Tatsugiri's big), then fronts are a further ×0.85 for
  perspective (the cart's own fronts are a median 0.90× the width of its backs; ×0.85 reads
  better: Wailord's back vs Joltik's front then shows a bigger gap than the other way round, as
  depth should). Every size change is made about the feet (`ffr` on front cells, `bfr` on back
  cells), so the Pokémon stays on its pad.

Every file under `tools/` and `tests/` is listed by exact path in `.modkitignore` so none of
them ships; add a line for each new one.

## How it draws

`src/hooks.lua` wraps three functions of the gen3 engine's `Pokemon` module: `frontPic`,
`backPic` and `icon`. Each answers for the species the atlas has art for and calls the original
for everything else; the wrappers are reinstalled after each species reload and never wrapped
twice.

Pics are rendered from the current frame into a canvas (a bounded cache, least recently used
first). In battle, fronts and backs are drawn at full size in a canvas that may extend past the
64×64 pic box (up to 96 px, `BACK_WIDE_MAX` in `src/atlas.lua`), so wings and tails are never
cut by the canvas; a small wrap on `love.graphics.draw` points the engine's draw at that
canvas's centre. If the wrap can't be installed (or `BACK_WIDE = false`), a giant is reduced just
far enough to keep 70% of its width in view. Other screens (Pokédex, summary, PC) get the
fit-to-box pic. Animation runs at 8 frames per second; battlers of one species share one clock.

With Gen 3 HD Sprites, battle pics are drawn at window resolution and `data/sprite_scale.lua`
tunes each Pokémon's front and back size and offset by hand (edit and restart, no rebuild).
Each battle tag also passes `top`: the cell's `uy0` in `data/atlas_index.lua`, which is the
first row of art over the whole animation, written by `tools/build_atlas.py`. With that,
Gen 3 HD Sprites' Battle Fit pulls the camera back to fit the art, not the frame's empty
margin. Each tag also passes `side`, `"enemy"` or `"player"`. A back adds `body`, its resting
body box (`cx0`…`cy1`). Battle Fit keeps that body's top at or below the tallest cart back sprite's (y 52). When it can, it also keeps at most 30% of the body under the player's HP box and the text box. A back's `top` (its whole animation) only has to stay on the screen.

## Tests

```sh
luajit tests/hooks_test.lua            # the gate test
luajit tests/forms_coverage_test.lua   # forms coverage
# plus the atlas layout, back framing, clean state, dex HD and gen3 coverage suites in tests/
```

Keep [README.md](README.md) describing the mod as it is now (players read it); what changed
goes in the release notes.
