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
  `tools/front_drop.json` (grounded species floating 4 px or more are lowered), then
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
  0.67–1.5; Tinkaton's back art is small, Tatsugiri's big), then fronts are a further ×0.9 for
  perspective (the cart's own fronts are a median 0.90× the width of its backs: Wailord's back vs
  Joltik's front then shows a bigger gap than the other way round, as depth should). Every size change is made about the feet (`ffr` on front cells, `bfr` on back
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
margin. Each tag also passes `side`, `"enemy"` or `"player"`, and `body`, its resting body box
(`cx0`…`cy1`: a back's typical box, a front's first frame's). Battle Fit keeps a back's body out
from under the UI, and its minimum size (the smaller battler's body at least a share of the
other's) measures both, so a flier whose animation spans far more than itself (Cutiefly) is
not lost beside a big foe. Each also passes `art`, the art's box over the whole animation (`ux0`…`uy1`),
and `height`, the real height in metres of that art box (the index's `ht` / 10 times
`sprite_scale.lua`'s `height`, measured for every sprite by poke-scale-realism: feet row to the
top of the art over the animation, over the Pokédex's height). That is measured on the front; a
back's tag carries it times the back art's reach over its resting body (`uy0` / `cy0` from
`bfr`) over the front's (from `ffr`), `atlas.tagHeight`, since some leap on one side only
(Finizen's front: 0.46 on its back; Galarian Stunfisk's back: 1.59). With them WoobleView's
Battle Fit sizes the two battlers against each other (the taller fills its room, the other is
shrunk by height), not by the tag's `scale`. A species' hand-set `size` (`atlas.sizeOf`: long
and coiled Pokémon whose art reads too big) multiplies the `scale` (Battle Fit off) and grows
the tag's `art` box about the feet by 1 / `size` (`atlas.fitArt`): Battle Fit fills the room with
that box, so the art itself fills that share of it, and the art's height at its fill is the same,
so the other battler is sized as before. Nothing in WoobleView is needed for it. Battle Fit keeps the back's body top at or below the
enemy's HP box (y 44; on the Game Boy, the enemy's HUD's bottom, y 32). When it can, it also keeps at most 30% of the body under the player's HP box and the text box. A back's `top` (its whole animation) only has to stay on the screen.

**Gen 3 takes five options.** `main.lua` defines only `GEN3_OPTIONS` there
(`enable_battle_sprites`, `animate_sprites`, `battle_frontal`, `battle_front_flip` and Gen 3's
own `animated_trainers`, below), so the in-game Mod Manager lists only those; the launcher reads
`options.lua` as data without knowing the game and lists all 17. The first four
are read live through `atlas.option` (the mod's getter):

- BATTLE SPRITES off (`Hooks._gameBattlePic`): inside `Battle.draw` `frontPic` hands on to the
  engine, `backPic` always, and `MonAnim.framePic` gives the cart's frame-1 art again, for
  slots under 451 (Gen 1-3 and Unown's letters). #387 onward keep the pack's, the cart has none.
- ANIMATE off: `atlas.frameIndex` answers 0, and the live Pokédex pics hold the pack's own
  two-frame `dexpic` (the cart's two frames are the game's and keep playing).
- 3DB FRONTAL: `backPic` asks `picFrame` for the front variant with `frontal` "front" (or "flip"
  with 3DB FLIP). It is laid out as a back (`backLayout`) from a copy of the front cell whose
  `bfr` is the front's `ffr` and `bfl` the species' back's, so its feet land where the back's do,
  centred on its body box, sized as a back (hand-set `back` x realism, no `bn`, no perspective).
  Its tag is the player's, with the front's own height. FLIP mirrors the canvas (and its wide
  pivot) and tags `flip = true`, only where WoobleView has `features.flip` (else the plain
  mirrored canvas). A female's own front comes from the Pokémon's personality (`backPic`'s `mon`).

**A window mode change empties canvases.** `love.window.setMode` (and `updateMode`) can
recreate the graphics context, which leaves every Canvas blank; an Image is reloaded by LOVE.
The colour-number blocks are decoded into canvases and every rendered frame is one, so
`Atlas.watchWindow` wraps `setMode`, `updateMode` and `setFullscreen` (once, a counter on
`love.window.__woobleGfx`), and each atlas checks it where a pic is asked for (`fresh`): on a
new count it drops its blocks, frames, Pokédex and icon pics and redraws its live pics. A
screen that keeps a pic it was handed earlier shows it blank until it asks again. Gen 2's
party-icon canvases check `atlas.epoch()` the same way.

**A render mid-draw puts the caller's scissor back itself.** A pic is rendered the first time
it is asked for, often in the middle of another screen's draw, so every render runs in
`drawClean` (`src/atlas.lua`): `push("all")`, the state cleared, the canvas drawn, `pop()`.
LÖVE's `pop()` restores the scissor *before* the canvas, converting it to pixels at the DPI
scale of the canvas still bound: ours, 4 for a pic. So `drawClean` reads the caller's scissor
before the push and sets it again after the pop (`Atlas.rescissor`), with the caller's canvas
bound. Gen 2's party-icon render and the GPU block decode do the same. Without it, a pic
rendered inside Crystal's battle panel (scissored to the panel) clipped the rest of the panel
to a rectangle four times too far right. Only the panel's right edge was left, which showed as
the battle flashing whenever a new animation frame was rendered. It showed with Facets'
battle scenery, which is drawn before the pics. `tests/clean_state_test.lua` restores in LÖVE's
order and checks the scissor comes back at the caller's scale.

## Animated trainers (FireRed to Emerald) and VS screens (FireRed / LeafGreen)

Coverage: FireRed / LeafGreen 118 of its 148 trainer pics, Emerald 57 of 93, Ruby / Sapphire 52
of 83; the rest (Hoenn's Elite Four, Teams Aqua and Magma, the Frontier Brains, some classes) keep
the game's own. VS screens are FireRed / LeafGreen only: neither source has Hoenn VS portraits.

**Art.** `tools/build_trainers.py --zip "<Animated Trainer Intros.zip>" --essentials
"<Pokemon Essentials v21.1>"` reads the pack (Lucidious89's DBK add-on) and Essentials without
extracting either. It packs only what `data/trainer_map.lua` names for a pic the game has (its
`TRAINER_PIC_` list, read from the gen1recomp checkout next to this repo):

- `assets/trainers/fronts_<n>.png`: each strip's frames, read as the plugin reads them (square
  frames as tall as the image, `ceil(w / h)` of them; a still if `w <= 2h`). The pack's shadow is
  baked under each frame: the frame's silhouette at 1.1 × 0.25 of its size, 100/255 black,
  bottom-centred, moved by the PBS `ShadowXY` (screen px at its `SpriteScale`, 2), none with
  `HideShadow`.
- `data/trainer_index.lua`: per sprite, the page, cell size, frames and cols, and the pivot (the
  frame's bottom centre in its cell).
- `assets/trainers/vs/`: the VS files as they are.

Rebuild after editing the map.

**The map.** `fronts[game][PIC]` keys each constants set (`firered`, `emerald`, `ruby`) by its
`TRAINER_PIC_` name without the prefix (FRLG's `RS_*` pics, the Trainer Tower's Hoenn classes,
share the names; Ruby / Sapphire's leaders have no `LEADER_` prefix; Emerald's champion Wallace
uses the pack's leader Wallace). Notes on it:

- A pic not listed keeps the game's own.
- The pack's `RIVAL1` / `RIVAL2` are Silver and Hugh, so FRLG's three Blue pics use `CHAMPION`.
- `vs.firered[PIC]` is the HGSS screen: `foe` portrait and `bar`. It uses only foe-side art: the
  pack's and Essentials' "POKEMONTRAINER_Red/Leaf" VS portraits are Ethan, Lyra, Nate and Rosa.
- `scale` = 2 × 160 / 384 (Essentials draws trainers at 2× on 384 rows); `seconds` = 1.5.

**Fronts** (`src/trainers.lua`). `Trainers.install` wraps the engine's `TrainerPic.front(picId)`
(`src.core.game3.trainer_pic`; every trainer front pic goes through it). For a mapped pic, while
`animated_trainers` is on, it answers one live 64×64 canvas per pic id (dpiscale 4). The current
frame is drawn there with its pivot on the box's bottom centre, at the pack's scale, shrunk only to
fit the box.

The frame:
- 0 while the enemy trainer (`battle.anim` stage `trainer.enemy`, `picId`/`pic2`) has `ox ~= 0`
  (sliding in).
- From the first frame it stands at 0, the strip plays once over `seconds` and holds its last
  frame. `main.lua`'s `battle.started` handler resets the clocks.
- Off the battle (a mugshot, the Hall of Fame): the last frame.

In battle (`Hooks._inBattle`), with WoobleView's battle pass on, the canvas is tagged with the
full frame: `texture`/`quad`, `pivot` = the cell's pivot, `lowPivot` = (32, 64), `scale`,
`side = "enemy"`, `trainer = true`. WoobleView's own `TrainerPic.front` wrapper skips images
already tagged, so it is drawn at window resolution and moves with the enemy's side (through the
side bars under Fill Screen). Off the battle the tag is removed, so the transition's mugshot slice
reads the plain canvas.

**VS screens** (`src/vs.lua`). `vs.install` wraps `BattleTransition.start`, `tick` and `abort`.
- `start`: if the battle gets a VS screen, it is kept as pending. That means a single battle (not
  `doubleBattle`, wild, Trainer Tower or e-Reader) whose trainer (`scripting.trainers.get(
  trainerId).pic`) is in `vs`, with the option on.
- `tick`: the game's opening flashes run (`_phase` "intro"). From the next phase the screen
  replaces the effect (the original `tick` is not called) and is drawn from a `render.hud` wrap
  over the whole window. After `VS.DURATION` (4.0 s, real time) it calls `BattleTransition.finish()`,
  which starts the battle as the game's own transition would.
- The port follows Essentials' `Transitions::VSTrainer` timings and motion. The layout is 384 rows
  tall and the window's width: the bar tiles across, the logo and the name keep their offset from
  the centre, the foe from the right edge. The foe's silhouette is a shader of its alpha. The name
  is the game's font at 3×.

## Red, Blue and Yellow

`main.lua` picks the game from `src.core.GameVersion.generation()` before it requires any engine
module (a Gen 2 module on a Gen 1 boot is an error); the save editor is always Gen 3. Gen 3 runs
`src/hooks.lua` as above. Gen 1 runs `src/gen1.lua` on the same atlas; Gen 2 runs
`src/gen2.lua`, which builds on it (see the next section).

- **Save editor, Red to Crystal saves** (`src/editor.lua`): the editor loads a Gen 1 / 2
  species' `spriteFront` PNG itself, so `MonEditor.sprite` is wrapped (once per process;
  each load hands it its atlas through `MonEditor.__woobleEditor`). For a Gen 1 / 2 save it
  answers the front art's first frame, copied out of the frame cache by `Hooks.fit`, with
  shiny / female / Unown's letter as in the game (`Gen1.shinyOf`, `Gen1.femaleOf`, the letter
  from `Unown.monLetter`). An egg or a species with no art gets the editor's own. It is
  installed before the Gen 3 Pokémon module is required, which a Gen 1 / 2 editor session
  does not have.

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
  `dbk_float.lua` is made from types and abilities, so it flags Flying types drawn standing
  (Pidgey); `FLOAT_STANDS` in `tools/build_atlas.py` (picked by eye) drops their `fl`. A
  floater is lifted 35% of its height (`FLOAT_LIFT` in `src/atlas.lua`), or by its own share
  where `FLOAT_LIFTS` gives one: the index then has `fl = <share>` in place of `fl = true`.
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
    body-centre x and `bfr`), `lowPivot` where they sit in the box, `top`, `side`, a back's
    `body`), so its capture of the original battle screen redraws it at window resolution and
    Battle Fit pulls back for tall Pokémon. Its `scale` is not the box's fit but the species'
    size as on Gen 3 (`atlas.battleSize`: `sprite_scale.lua`'s hand-set size × realism × the
    front's perspective, or a back's `bn`; × `all`, plus the hand-set nudge), times
    `Atlas.GB_UNIT` (144 / 160: the same share of the screen as on the GBA). The box-fitted
    size squeezed every big Pokémon to 56 px and drew small ones at their full size, so a
    Diglett stood as tall as a Typhlosion; `sprite_size` only shapes the stand-in now. Not in the mono COLORS (the
    pics are drawn after the colour pass there). A mirrored 3DB FLIP frame adds `flip = true`
    (its `lowPivot` mirrored about the box, the rest as in the atlas), only where WoobleView
    has `features.flip`; with an older one it stays untagged. The contact shadow is baked into
    the stand-in, which WoobleView replaces, so the tag carries it too (`spec.shadow`: its
    width and bottom-middle offset from the feet in the frame's pixels, so it follows the
    species' size and the flip), where WoobleView has `features.shadow`.
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
  the 32 px cells hold every art pixel. Every species gets ours, keys 1–151 (the cart's
  species) included: Red / Blue / Yellow's own icons are a handful of shared shapes.
- **HD party screen** (`Gen1.installPartyScreen`, on whenever PARTY ICONS is: `Gen1.hdParty`;
  the old `g9_party_screen` option is gone and a saved value is ignored): `PartyMenu.uiSize`
  answers 640×576, `isWideBattleLayout` / `wantsFillScale` true, and its draw runs under
  `scale(4)`, with `markTrueColor` rects and `sgbPalettes` zones scaled to match.
  `holdsUIAnchors`, a field the engine reads off the stack, is set from `uiSize`. A classic
  screen pushed over the page (`StateStack.push`) is dressed the same way. The icons are
  the same `PartyMenu.drawIcon` ones, drawn in full on the 4x page.

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
  a move's flash). The summary's, the Pokédex's and the Unown page's
  frames pass `hdDex`, as Gen 1's do (shaded ones under `features.shades`, which WoobleView
  then draws under the GbcPalette shader set at the time).
- **Window resolution:** Gold draws its 160×144 panel scaled up on a window-sized canvas, so
  frames are `boxFrame`s at `dpi` 4 and keep their detail however far the art is shrunk.
- **Unown:** `Unown.monLetter` picks `UNOWN` (A) or `UNOWN_B` … `UNOWN_Z` (`Gen2.unownId`).
- **Colour:** `GbcPalette` draws a true-colour pic as it is only in the GEN 2 colour mode
  (`Gen2.keepsColour`); in DMG, CLASSIC and a custom palette it maps the pic's shades to the
  palette, so the frame is drawn through `shadesShader` and answered as not true colour. The
  battle's own colour effects and the evolution's blackout take the shaded frame too: a pic's
  shade (`animPicState().shade`: Giga Drain, Growl ...) and the BG palette register
  (`GbcPalette.bgp`, set while the battle is drawn: the flashes and inverts of 61 of the 251
  moves, Thunder, Psychic, Night Shade ...). Both rest on the identity `0xE4` (never nil during
  an animation), which is not an effect: every other move keeps the art in its own colours.
  The intro's grey slide-in (`introGrayscale`) is not one either: the art keeps its colours.
- **The intro's slide-in:** `BattleAnimView:presentSlide` bakes the scene into a canvas and
  blits it in bands, which WoobleView never sees. While it runs, a wild Pokemon of ours is kept
  out of the bake (`drawPic` skips the foe under `__woobleLiftEnemy`) and drawn after the bands
  from `drawSceneBody`, translated by the top band's offset (`BattleAnimView.slideOffsets`:
  the whole enemy box is in rows 0-63), as the engine does the player's back pic. The offset is
  not wrapped as the bands' blit wraps a scroll over 128: unwrapped the box comes in from the
  left, its right edge first, as on the cart, and is never parked right of the panel, where a
  screen WoobleView's Fill Screen fills would show it. It is drawn
  as a method (`self:drawPic`): Battle Art's staged scene puts an empty `drawPic` on the battle.
  A trainer's pic and a Pokemon with no art of ours are baked as before.
- **Crystal's animated pics:** `MonAnimView.start` notes each view's scene and atlas key (from
  the species record it starts with), and `MonAnimView:frame` answers nil while that scene's
  screen shows ours (`serves[scene]`: `menu` the summary, `hatch`, `evolve`, `hof`, `trade`).
- **Party icons:** every Pokémon gets ours, the cart's species included (the game's own are
  a few dozen shared shapes), in the party list and the trade tube, drawn into a small canvas
  (shaded where the palette recolours) so the game's held-item marker can replace its
  bottom-left quarter as the game does. The screens are drawn at window resolution, so the
  icons are at full detail on the game's own party page (no HD party screen here).
- **Exports:** as Gen 1's, with `drawSummaryFrame` unmirrored in the 7×7 block at the top left.

## Tests

```sh
luajit tests/hooks_test.lua            # the gate test
luajit tests/forms_coverage_test.lua   # forms coverage
luajit tests/gen1_test.lua             # Red / Blue / Yellow: keys, box frames, options, hooks
luajit tests/gen2_test.lua             # Gold / Silver / Crystal: pics, colour, anims, icons, exports
luajit tests/editor_test.lua           # the save editor with a Red to Crystal save
luajit tests/host_test.lua             # the host: a game started after the save editor closed is a game
luajit tests/trainers_test.lua         # FireRed to Emerald: trainer map, fronts, clock, VS screen
# plus the atlas layout, back framing, clean state, dex HD and gen3 coverage suites in tests/
```

Keep [README.md](README.md) describing the mod as it is now (players read it); what changed
goes in the release notes.
