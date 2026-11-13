# WoobleSpritePack: developer guide

For contributors. Players only need the [README](README.md).

## Assets

`tools/build_atlas.py` writes the pages in `assets/atlas/`. No page is larger than 4096×4096, the
texture limit on many Android GPUs (a larger image fails to load there and the engine shows a red
missing-pic box). The battle pages are build input only: what ships is their colour-number form
(below), and `tools/build_dist.py` keeps them out of the package.

- `battle_<variant>_<n>.png`: four variants (`front`, `front_shiny`, `back`, `back_shiny`),
  several pages each. A page holds blocks of uniform `fs × fs` cells; a species' frames sit in
  consecutive cells of one block, and the index records the block's corner (`ox`, `oy`).
- `party_icons_0.png`: two-frame 32×32 menu icons for #387–1025 and the forms, one page.
- `dex_fronts_0.png`: the cart-style 64×64 Ruby / Sapphire / Emerald Pokédex pics for #387+
  and the forms, from a pokeemerald-expansion checkout (`graphics/pokemon/<id>/anim_front.png`,
  else `front.png`). A form found under another folder name is listed in `DEX_FRONT_DIRS`;
  one the expansion draws as a recolour (Flabébé's line, Alcremie's creams on the Strawberry
  Sweet pic) in `DEX_FRONT_RECOLOURS`, with its palette. All 763 have one
  (`tests/forms_coverage_test.lua` checks it). Generations 1–3 (and Unown's
  letters) are not packed: `src/hooks.lua` sets `atlas.cartFrame` to the game's own front pic
  (frame 0) and `MonAnim.framePic` (frame 1; Spinda keeps frame 0, the one with its spots),
  fetched with every wrapper of ours stepping aside (`passThrough`).
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

Then pack the battle pages as colour numbers (what the game draws from):

```bash
python tools/build_numbers.py           # -> assets/numbers/ + data/numbers_index.lua (~1 min)
python tools/build_dist.py              # refuses to pack while they are older than the pages
```

A battle sprite uses few colours (at most ~130 normal/shiny pairs, usually ~15), and its shiny is
the same animation recoloured. So each species' front (and back) animation, normal and shiny
together, is stored once as a greyscale strip of colour numbers (`assets/numbers/num_<n>.png`, the
number in red), each number one (normal, shiny) colour pair; the real colours are one row per
variant of `assets/numbers/palette.png`. `data/numbers_index.lua` maps each cell of
`data/atlas_index.lua` (`"<variant>:<sheet>:<start>:<ox>:<oy>"`) to `{ shard, y, w, h, palette row }`
and records the pages' SHA-256 for `--check`. The tool decodes every block back and compares it with
its page before writing. ~44 MB shipped instead of ~100 MB of pages.

`src/atlas.lua` rebuilds a species' block the first time it is drawn: the strip is cut from its
shard, laid out as a grid of frames (`Atlas.blockCols`, about square, so no side passes 4096 px),
and decoded on the GPU (a palette shader drawn into a canvas, written as-is). Once per session the
GPU's result is compared with the exact CPU decode (`Atlas._expand`); if they differ the CPU decodes
from then on. 24 blocks and 3 decoded shards are kept (least recently used dropped). Measured in a
real Emerald battle: battle start +39 MB of VRAM instead of +151 MB, and 30 more species in 0.3 s
and +69 MB instead of 8 s and +2.3 GB (each whole page used to stay loaded). Without
`data/numbers_index.lua` the pages are read as before.

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
  cell's drop `fy`, so it holds with and without WoobleView. `front_feet.py --dips` /
  `--tops` list sprites dipping into the player's HP box or going above the window.
- Backs stand on the player pad's middle (y 119, partly under the text box as on the cart), at
  their own size: the build writes each back cell's resting feet row `bfr` and its feet line in
  the pic box `bfl` (`BACK_FEET_ROW` less the engine's per-species back offset). Ruby / Sapphire
  draw the player's pic 4 px higher; `Atlas.backShift` adds them back at runtime. A tall back is
  left to WoobleView's Battle Fit. (`tools/back_framing.py` and `tools/back_fit.py`, the old
  cart framing, are no longer used by the build.)
- Both are placed against FireRed / LeafGreen's per-species offsets (the engine's
  `pic_coords.lua` FRLG tables). Ruby / Sapphire / Emerald have their own front / back offsets and
  enemy elevations (Emerald's Pidgey hovers 16 px for its flying-pose art), so on game start
  `main.lua` sets `Atlas.coordShift` from `Atlas.gameCoordShift(FRLG, active)` and every battle
  pic is moved by its slot's difference. Empty on FireRed / LeafGreen.
- Ruby / Sapphire / Emerald play the cart's entry animation as a Pokémon comes out; on its
  frame 1 the battle draws the cart's own art (`MonAnim.framePic`) in place of the pic.
  `src/hooks.lua` answers nil there for every slot with atlas art, so our animated pic stays
  (the cart's motion and colour flashes still apply to it).
- The RSE Pokédex keeps the image it is given, and opening an entry slides the wheel's sprite
  over with its image. So the wheel and the entry pages get live canvases (`atlas.livePic`,
  redrawn from the hooks' wrap of the screen's draw): on the wheel they hold frame 0
  (`atlas.holdLive`), on an entry they alternate the cart pic's two frames every 0.5 s.
- Pics are canvases made at the box's own size with `dpiscale` (LÖVE 11 sizes them in
  DPI-scaled units), so a host that fits a pic by `getDimensions` sees 64×64.
- Realism scaling (WoobleView only, `Atlas.realism`, settings in `data/sprite_scale.lua`
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

With WoobleView, battle pics are drawn at window resolution and `data/sprite_scale.lua`
tunes each Pokémon's front and back size and offset by hand (edit and restart, no rebuild).
Each battle tag also passes `top`: the cell's `uy0` in `data/atlas_index.lua`, which is the
first row of art over the whole animation, written by `tools/build_atlas.py`. With that,
WoobleView's Battle Fit pulls the camera back to fit the art, not the frame's empty
margin. Each tag also passes `side`, `"enemy"` or `"player"`. A back adds `body`, its resting
body box (`cx0`…`cy1`). Battle Fit keeps that body's top at or below the tallest cart back sprite's (y 52). When it can, it also keeps at most 30% of the body under the player's HP box and the text box. A back's `top` (its whole animation) only has to stay on the screen.

**A window mode change empties canvases.** `love.window.setMode` (and `updateMode`) can
recreate the graphics context, which leaves every Canvas blank; an Image is reloaded by LOVE.
The colour-number blocks are decoded into canvases and every rendered frame is one, so
`Atlas.watchWindow` wraps `setMode`, `updateMode` and `setFullscreen` (once, a counter on
`love.window.__woobleGfx`), and each atlas checks it where a pic is asked for (`fresh`): on a
new count it drops its blocks, frames, Pokédex and icon pics and redraws its live pics. A
screen that keeps a pic it was handed earlier shows it blank until it asks again. Gen 2's
party-icon canvases check `atlas.epoch()` the same way.

## Red, Blue and Yellow

`main.lua` picks the game from `src.core.GameVersion.generation()` before it requires any engine
module (a Gen 2 module on a Gen 1 boot is an error); the save editor is always Gen 3. Gen 3 runs
`src/hooks.lua` as above. Gen 1 runs `src/gen1.lua` on the same atlas; Gen 2 runs
`src/gen2.lua`, which builds on it (see the next section).

- **Species:** Gen 1 names a species by id (`"ABRA"`). `atlas.keyFor(id, dex, base)` finds it
  by the index's own ids (the National Dex mods use the same ones), then by the record's
  `baseSpecies` (a Mega shows its base), then by dex number.
- **Frames:** `atlas.boxFrame` fits a frame to the screen's pic box in Game Boy pixels:
  - the art's union over the animation (front cells now carry `ux0`…`uy1` too) is placed, so
    the Pokémon stays still while it animates;
  - 1:1 when it fits, else shrunk; nearest-neighbour;
  - none of Gen 3's placement data is used.

  The options decide the rest:
  - `sprite_size`: a divisor;
  - `sprite_anchor`: feet / pack / box;
  - `sprite_float`: lifts records with `fl`;
  - PACK reads `pm`, the pack's SpeciesMetrics;
  - `battle_shadows`: draws `assets/shadow/1..3.png` behind the Pokémon, sized by `pm.sz`.

  `fl` and `pm` come from the pack's `dbk_float.lua` and `dbk_metrics.lua` at build time.
- **Battle** (`src/battle/BattleState.lua`):
  - `makeBattler` is local, so `drawPicsLayer` puts the current frame in each battler's
    `sprite`: front 56×56, back 64×64.
  - `resolveBattleScale` answers 1 for those species.
  - `drawBattlerPic` marks the pic true colour.
  - `speciesSprite` notes whom a Transform copies.
  - The Pokémon Tower ghost's disguise (`battle.ghost` / `scopeReveal` / `ghostReveal`) is left
    alone.
  - WoobleView (its Gen 1 support): each frame is tagged as Gen 3's battle pics are
    (`boxFrame`'s `hdSide`: `texture` / `quad` the full frame, `pivot` the feet (`ffr`; a back's
    body-centre x and `bfr`), `lowPivot` where they sit in the box, `scale` the fit factor,
    `top`, `side`, a back's `body`), so its capture of the original battle screen redraws it at
    window resolution and Battle Fit pulls back for tall Pokémon. Not in the mono COLORS (the
    pics are drawn after the colour pass there). A mirrored 3DB FLIP frame adds `flip = true`
    (its `lowPivot` mirrored about the box, the rest as in the atlas), only where WoobleView
    has `features.flip`; with an older one it stays untagged. The contact shadow is in the
    stand-in only.
- **Other screens:** each `draw` (or the method that answers the pic) is wrapped to put the
  current frame where the screen keeps its pic:

  | Screen | Wrapped |
  |---|---|
  | Summary | `SummaryMenu.draw` |
  | Pokédex | `DexEntryMenu.draw` (the National Dex's form browsing sets `formId`), `.render` (the printer) |
  | Evolution | `EvolutionState.draw` |
  | Trade | `TradeAnim.draw` |
  | Hall of Fame | `HallOfFame:spriteFor` / `:backPicFor` (a 28×28 frame at `dpi` 2, drawn 2×) |
  | League PC | `LeaguePC.draw` |
  | Title | `TitleState:currentSprite` |
  | Oak's speech | `OakSpeech.resolvePic` |
  | Credits | `Credits:monSprite` (a silhouette) |
  | Party icons | `PartyMenu.drawIcon` |

  `wrap` remembers its own function per name, so a reinstall leaves it alone and wraps again a
  function another mod put there since. `main.lua` reinstalls on `screen.pushed` (and links
  WoobleView there too, for a Pokédex opened before any battle).

  The summary's and the Pokédex entry's frames (draw and render) pass `boxFrame`'s `hdDex`:
  with WoobleView's "dex" pass on they are tagged as the battle's are, without `side` / `top` /
  `body` (the screens' own mirrored draw is WoobleView's to handle, so no `flip`). A shaded
  frame is tagged only where WoobleView has `features.shades`, and then carries the shader as
  `shades`, which WoobleView draws the full frame through before the colour pass colours it.
  Never with the shadow (in the stand-in only) or a silhouette. The key gets `:dex`.
- **Exports:** `mod.exports.frontArt`, `iconArtHD`, `iconArt16` and `drawSummaryFrame` keep
  g9-battle-sprites' signatures. The icon ones return `({ full = quad }, image, cell px[, box])`.
- **Colour:** the engine's colour pass recolours a pic by its shade (the red channel) unless it
  keeps its colours: in battle except the og, og_inv and classic COLORS (`Gen1.monoBattle`), and
  elsewhere only in ADVANCED (`Gen1.keepsColour`, `PaletteFX.honorsTrueColor`). Where it
  recolours, `boxFrame`'s `shades` draws the art through `atlas.shadesShader()` (brightness to
  the Game Boy's four shades), and the pic is not marked true colour, so the pass colours it
  with the species' palette as it does the game's own.
- **Party icons:** the icon page holds every species' icon, #1–386 included (Gen 3's
  `Pokemon.icon` wrap leaves keys below 451 to the game). The icon sources are 2× pixel art, so
  the 32 px cells hold every art pixel. On the game's list, keys 1–151 (the cart's species)
  keep the game's icons.
- **G9 party screen** (`g9_party_screen`, `Gen1.installPartyScreen`): `PartyMenu.uiSize`
  answers 640×576, `isWideBattleLayout` / `wantsFillScale` true, and its draw runs under
  `scale(4)`, with `markTrueColor` rects and `sgbPalettes` zones scaled to match.
  `holdsUIAnchors`, a field the engine reads off the stack, is set from `uiSize`. A classic
  screen pushed over the page (`StateStack.push`) is dressed the same way. Every icon is ours
  there.

## Gold, Silver and Crystal

`src/gen2.lua` reuses Gen 1's frame (`Gen1.frame`: the options, `keyOf`, shiny, female), its
`wrap` and its exports; `Gen2.install(atlas, Gen1)` hands it over. What differs:

- **Every screen asks a method for its pic**, answered as `(image, trueColor)`. The engine's
  `pokemon.sprite` seam only substitutes a path, so each method is wrapped:

  | Screen | Wrapped |
  |---|---|
  | Battle | `BattleState:pic` (front 56×56, back 48×48), `:picScale` → 1, `:frontAnimFrame` → nil |
  | Summary | `SummaryMenu:picFor` |
  | Pokédex | `PokedexMenu:picFor` (the National Dex's `formId` / `formBase`; Unown as `save.firstUnownSeen`), `:drawUnownPic` |
  | PC box | `BoxMenu:picFor` |
  | Hatching | `EggHatchAnim:pic` (once `showMon`) |
  | Evolution | `EvolutionAnim:pic` (shaded while `blackout`) |
  | Hall of Fame | `HallOfFame:monPic` (front and back) |
  | Trade | `TradeAnimView:pic`, `:drawIcon` |
  | Oak's speech | `OakSpeech:drawPic` (the demo's `marillPic`, or a `{ type = "pokemon" }` pic noted by `:resolvePic`) |
  | Photo studio | `PhotoStudio:picFor` |
  | Unown printer | `UnownPrinter:picFor` |
  | Party icons | `PartyMenu:drawIcon` |

  The battle's pic answers a path of its own (`wooble-sprite:front`), so `frontPicReplaced`
  keeps Crystal's battle animation from starting.
  With WoobleView (its Gen 2 support) the battle frames are tagged as Gen 1's are (`lowPivot`
  in the box's units, 56 / 48, not the canvas's DPI pixels), for its capture of the original
  white-background battle; only while they keep their own colours (GEN 2 colours, not during
  the intro's blackout or a move's flash). The summary's, the Pokédex's and the Unown page's
  frames pass `hdDex`, as Gen 1's do (shaded ones under `features.shades`, which WoobleView
  then draws under the GbcPalette shader set at the time).
- **Window resolution:** Gold draws its 160×144 panel scaled up on a window-sized canvas, so
  frames are `boxFrame`s at `dpi` 4 and keep their detail however far the art is shrunk.
- **Unown:** `Unown.monLetter` picks `UNOWN` (A) or `UNOWN_B` … `UNOWN_Z` (`Gen2.unownId`).
- **Colour:** `GbcPalette` draws a true-colour pic as it is only in the GEN 2 colour mode
  (`Gen2.keepsColour`); in DMG, CLASSIC and a custom palette it maps the pic's shades to the
  palette, so the frame is drawn through `shadesShader` and answered as not true colour. The
  battle's own colour effects (the intro's blackout, `animPicState().shade`) and the
  evolution's blackout take the shaded frame too.
- **Crystal's animated pics:** `MonAnimView.start` notes each view's scene and atlas key (from
  the species record it starts with), and `MonAnimView:frame` answers nil while that scene's
  screen shows ours (`serves[scene]`: `menu` the summary, `hatch`, `evolve`, `hof`, `trade`).
- **Party icons:** a Pokémon the game has an icon for (`PartyMenu:iconIdFor`, `gen2Icons`)
  keeps it; others get ours, drawn into a small canvas (shaded where the palette recolours)
  so the game's held-item marker can replace its bottom-left quarter as the game does. On the
  G9 party screen every icon is ours, `battlePanelScale` answers the window's fill scale
  (`panelBlit` draws a screen pushed over it at the same scale), and `drawWidescreen` draws
  the panel at it.
- **Exports:** as Gen 1's, with `drawSummaryFrame` unmirrored in the 7×7 block at the top left.

## Tests

```sh
luajit tests/hooks_test.lua            # the gate test
luajit tests/forms_coverage_test.lua   # forms coverage
luajit tests/gen1_test.lua             # Red / Blue / Yellow: keys, box frames, options, hooks
luajit tests/gen2_test.lua             # Gold / Silver / Crystal: pics, colour, anims, icons, exports
# plus the atlas layout, back framing, clean state, dex HD and gen3 coverage suites in tests/
```

Keep [README.md](README.md) describing the mod as it is now (players read it); what changed
goes in the release notes.
