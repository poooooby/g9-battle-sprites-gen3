# G9 Battle Sprites (Gen 3)

Animated, true-colour battle sprites and Pokédex and summary front pics for
**every National Dex species, #1–1025** (Generations 1–9), plus party icons for
#387–1025, on the gen3 games in gen1recomp: **FireRed, LeafGreen, Ruby, Sapphire
and Emerald**.

Generations 1–3 (#1–386) are covered too, so a Pokémon of any generation gets the
same animated art. Their party icons stay the game's own, and so do Unown's letters
(the pack has one Unown sheet, not 28) and a Castform in its sun / rain / hail looks.

This is a gen3-only rewrite of [g9-battle-sprites](https://github.com/tectorifter/g9-battle-sprites),
which targets gen1 and gen2. It works best with
[national_dex_gen3](https://github.com/poooooby/national_dex_gen3), which
registers the species #387–1025 (an optional dependency; without it only
Generations 1–3 are drawn).

## What it draws

| Where | Species #387–1025 | Species #1–386 |
|---|---|---|
| Battle, enemy front | animated sheet (front, or front shiny) | animated sheet |
| Battle, player back | animated sheet (back, or back shiny) | animated sheet |
| Pokédex front pic | animated sheet | animated sheet |
| Party summary front pic | animated sheet | animated sheet |
| Party list icon | two-frame 32×32 icon | the game's own |

Long animations are trimmed to the median length of their kind (58 frames for fronts, 52 for
backs), cut where the loop closes on a matching frame so it does not jump
(`tools/trim_loops.py`, which writes `tools/loop_trims.json`; a sheet with no clean loop keeps all
its frames). That takes about a quarter of the frames, and the package from 113 MB to 85 MB.

Back (player-side) pics are a close-up, framed like the cart's own: each Pokémon is placed with
the top of its body on the row the cart sprite's body starts on, at the clean scale (1×, 1.5× or
2×, never below 1×) that brings it nearest the cart sprite's on-screen height, and whatever runs
past the 64 px box is what the battle screen's text box covers. The references are the 64×64
back sprites of a pokeemerald-expansion checkout (`tools/back_framing.py`, which writes
`tools/back_framing.json`); the body is measured on the animation's first frame, so a head flung
up later (Blacephalon) does not set the size. A Pokémon with no reference is shown at full size with its feet on the bottom edge
instead, and a back pic is never shrunk to fit. The engine's pic box
is 64×64, but a wide Pokémon (wings, a long tail) is not cropped to it: its pic is
rendered into a canvas big enough for its whole animation (up to 96 px past the box
in any direction, `BACK_WIDE_MAX` in `src/atlas.lua`), so a head that swings above
its usual pose or a wing tip is never cut by the canvas; only the battle screen's own
text box covers what falls below, and the engine's draw call is pointed at that
canvas's centre by a small wrap on `love.graphics.draw` that only touches these
canvases. If the wrap can't be installed (`BACK_WIDE = false` does the same), a
giant is instead reduced just far enough to keep 70% of its width in view. The
build records where each Pokémon sits inside its frame (`cx0, cy0, cx1, cy1` in
`data/atlas_index.lua`) so empty margins around it don't leave it floating.

Front pics in battle (the enemy) are also shown at full size now, not shrunk to
fit: the whole frame, bottom-centred as before, in a canvas that extends past the
pic box. That only happens when the battle screen asks for the pic (the code
checks who is calling), because the Pokédex, party summary, PC and other screens
draw a pic as a plain 64×64 image and still get the fit-to-box one.

With the Gen 3 HD Sprites mod installed, each Pokémon's battle size can be tuned by hand in
`data/sprite_scale.lua` (percentages for the front and the back pic, plus pixel nudges; edit and
restart, no rebuild). Without that mod, sizes are fixed.

Animation runs at 8 frames per second. Battlers of one species share one
clock, so they stay in step.

**Alternate forms** (national_dex_gen3's 85 forms: Galarian and Hisuian forms, Wormadam's cloaks,
the Rotom appliances, the Therian and Origin forms and more) have a sheet and an icon of their
own, found by the form's own engine slot. Coverage:

- 81 of the 85 forms have their own battle sheets, and 75 their own icon (Galarian Darmanitan,
  Alcremie's nine creams, Flabébé, Floette and Florges in five colours, Shellos and Gastrodon's
  east-sea looks, the white-striped Basculin and female Basculegion included).
- The Gen 9 Pack has one party icon for Pumpkaboo and one for Gourgeist, so their sizes (six forms) share it.
- The tea set's Antique, Artisan and Masterpiece looks (Sinistea, Polteageist, Poltchageist and
  Sinistcha) have no art in any of the packs, so they show the normal look.
- Alcremie's creams use the Strawberry Sweet sheet of their cream; the pack draws one per sweet
  (63), but the game has one Alcremie per cream.
 A female Meowstic or Oinkologne shows her own picture as the enemy and in the Pokédex and
summary (the engine asks for a back view and a menu icon without saying which Pokémon, so those
stay the male's).

Not in this version: tera crystal, dynamax cloud and battle shadow overlays, female-variant
sheets, and the 4× party page from the gen1/gen2 mod.

## Assets

Everything ships in `assets/atlas/`: 81 PNGs, 93 MB. The gen1/gen2 mod shipped
2,556 loose sheets for all species. No page is larger than 4096×4096, which is
the texture size limit on many Android GPUs; a larger image fails to load there
and the engine shows a red missing-pic box.

- `battle_<variant>_<n>.png`: four variants (`front`, `front_shiny`, `back`,
  `back_shiny`), several pages each. A page holds blocks of uniform `fs × fs`
  cells; a species' frames sit in consecutive cells of one block, and the index
  records the block's corner (`ox`, `oy`).
- `party_icons_0.png`: two-frame 32×32 menu icons for the 639 species and the 85 forms, one page.
  Gender variants are not packed; the Pokédex and summary use the front pic.
- `data/atlas_index.lua`: maps each species (and form) to its engine `slot` (for Generations 1–3 the game's own internal species id; the build reads those and the names from the engine's extracted data, `--gen3-data`) and its cells (and, for back pics, where the Pokémon sits in its frame).

The atlases are built from the third-party DBK sprite pack and the "icones
animados" icon pack. The source packs are not in this repo. Artist credits are
in [CREDITS.md](CREDITS.md). Battle frames keep their source pixels (true
size). The runtime shrinks a sprite only when it does not fit the 64px pic box,
using nearest-neighbour sampling.

Rebuild the atlases from the source packs:

```bash
python tools/build_atlas.py --sheets <DBK pack>/assets \
    --payload ../national_dex_gen3/data/species \
    --dbk <dbk_data.lua> --icons <icon_data.lua> --icon-atlas <party_icons.png>
```

Output is deterministic: rebuilding the same inputs gives identical bytes.

## How it draws

The hooks are in `src/hooks.lua`. They wrap three functions on the gen3 engine's
`Pokemon` module: `frontPic`, `backPic` and `icon`. Each wrapper answers for
the species the atlas has art for and calls the original function for everything
else.

Battle and Pokédex pics are rendered from the current frame into a 64×64
canvas, which matches the engine's pic box. The canvas cache is bounded at 128
frames, least recently used first. Icons use the engine's own icon shape: an
image plus one quad per frame.

The wrappers are reinstalled after each species reload, and a wrapper is never
wrapped twice.

## Status

**Not yet tested in-game.** The headless checks pass: the gate test
(`luajit tests/hooks_test.lua`, 27 checks), the atlas index bounds (all 2,900
battle sheets inside their pages), the forms coverage test (899 checks), and the engine module exposes the three functions
the hooks wrap. The manifest is marked experimental until it has run in a
real FireRed or Emerald session.

## Credits and licence

GPL-3.0-or-later, as the original mod. See [LICENSE](LICENSE),
[CREDITS.md](CREDITS.md) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
