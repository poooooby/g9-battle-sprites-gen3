# G9 Battle Sprites (Gen 3)

Animated, true-colour battle sprites, Pokédex and summary front pics, and party
icons for National Dex species **#387–1025** (Generations 4–9) on the gen3
games in gen1recomp: **FireRed, LeafGreen, Ruby, Sapphire and Emerald**.

Species #1–386 are never touched. They keep the game's own sprites.

This is a gen3-only rewrite of [g9-battle-sprites](https://github.com/tectorifter/g9-battle-sprites),
which targets gen1 and gen2. It works best with
[national_dex_gen3](https://github.com/poooooby/national_dex_gen3), which
registers the species (an optional dependency; without it there are no
species #387–1025 to draw).

## What it draws

| Where | Species #387–1025 | Species #1–386 |
|---|---|---|
| Battle, enemy front | animated sheet (front, or front shiny) | the game's own |
| Battle, player back | animated sheet (back, or back shiny) | the game's own |
| Pokédex front pic | animated sheet | the game's own |
| Party summary front pic | animated sheet | the game's own |
| Party list icon | two-frame 32×32 icon | the game's own |

Back (player-side) pics are a close-up, like the built-in ones: the Pokémon is
shown at full size, never shrunk to fit, centred on the pic box, with whatever
overflows cut off at the bottom (the battle screen's text box covers it). Small
Pokémon are shown whole with their feet on the bottom edge. The engine's pic box
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

Animation runs at 8 frames per second. Battlers of one species share one
clock, so they stay in step.

Not in this version: tera crystal, dynamax cloud and battle shadow overlays,
female and alternate-form sheets, and the 4× party page from the gen1/gen2 mod.

## Assets

Everything ships in `assets/atlas/`: 74 PNGs, 77 MB. The gen1/gen2 mod shipped
2,556 loose sheets for all species. No page is larger than 4096×4096, which is
the texture size limit on many Android GPUs; a larger image fails to load there
and the engine shows a red missing-pic box.

- `battle_<variant>_<n>.png`: four variants (`front`, `front_shiny`, `back`,
  `back_shiny`), several pages each. A page holds blocks of uniform `fs × fs`
  cells; a species' frames sit in consecutive cells of one block, and the index
  records the block's corner (`ox`, `oy`).
- `party_icons_0.png`: two-frame 32×32 menu icons for the 639 species, one page.
  Forms and variants are not packed; the Pokédex and summary use the front pic.
- `data/atlas_index.lua`: maps each species to its cells (and, for back pics, where the Pokémon sits in its frame).

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
species #387–1025 and calls the original function for everything else.

Battle and Pokédex pics are rendered from the current frame into a 64×64
canvas, which matches the engine's pic box. The canvas cache is bounded at 128
frames, least recently used first. Icons use the engine's own icon shape: an
image plus one quad per frame.

The wrappers are reinstalled after each species reload, and a wrapper is never
wrapped twice.

## Status

**Not yet tested in-game.** The headless checks pass: the gate test
(`luajit tests/hooks_test.lua`, 12 checks), the atlas index bounds (all 2,556
battle cells inside their pages), and the engine module exposes the three functions
the hooks wrap. The manifest is marked experimental until it has run in a
real FireRed or Emerald session.

## Credits and licence

GPL-3.0-or-later, as the original mod. See [LICENSE](LICENSE),
[CREDITS.md](CREDITS.md) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
