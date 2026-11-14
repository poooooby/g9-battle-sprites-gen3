-- Mod Manager option schema (manifest.json "options_schema"), read by the manager even while
-- the mod is off; main.lua defines the same table with mod.options:define at load. The keys and
-- choice values are tectorifter's g9-battle-sprites' own, so a player's saved settings carry
-- over and mods that read them keep working.
--
-- They apply to Red, Blue, Yellow, Gold, Silver and Crystal. FireRed, LeafGreen, Ruby,
-- Sapphire and Emerald place their sprites by the cart's own layout and are not changed by any
-- of them.
return {
  {
    key = "enable_battle_sprites",
    label = "BATTLE SPRITES",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): battle Pokemon use the animated true-colour art. OFF: battles keep the game's own pics.",
  },
  {
    key = "animate_sprites",
    label = "ANIMATE",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): the art plays its animation. OFF: its first frame only, as a still picture.",
  },
  {
    key = "sprite_fps",
    label = "SPRITE SPEED",
    type = "choice",
    default = 12,
    choices = {
      { "SLOW", 6 },
      { "NORMAL", 12 },
      { "FAST", 18 },
      { "VERY FAST", 24 },
    },
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. How fast the animation plays (frames per second).",
  },
  {
    key = "sprite_shiny",
    label = "SHINY ART",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): a shiny Pokemon (by its DVs, as Gold and Silver tell) shows its shiny colours. OFF: the normal colours for every Pokemon.",
  },
  {
    key = "sprite_female",
    label = "FEMALE ART",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): a female Pokemon shows its own female art where there is one (on Gold/Silver/Crystal, or with a National Dex mod that gives Pokemon a gender). OFF: one look for both.",
  },
  {
    key = "sprite_size",
    label = "SPRITE SIZE",
    type = "choice",
    default = 0,
    choices = {
      { "MAX DETAIL", 0 },
      { "SMALL", 3 },
      { "NORMAL", 2 },
      { "BIG", 1 },
    },
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. MAX DETAIL (default): every Pokemon as detailed as it can be: at its own size when it fits its picture box, shrunk only as far as it must when it does not. SMALL / NORMAL / BIG: every Pokemon divided by 3 / 2 / 1, so their sizes stay in proportion (still shrunk to fit when too big).",
  },
  {
    key = "sprite_anchor",
    label = "GROUND ANCHOR",
    type = "choice",
    default = 0,
    choices = {
      { "FEET", 0 },
      { "PACK", 1 },
      { "BOX", 2 },
    },
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. FEET (default): every Pokemon stands its feet on the same line, and one that floats or flies hovers above it (see FLOATERS). PACK: placed by the sprite pack's own offsets for each species. BOX: simply bottom-centred in its picture box.",
  },
  {
    key = "sprite_float",
    label = "FLOATERS",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): with GROUND ANCHOR on FEET, a Pokemon that floats or flies is lifted off the ground line by a share of its own height, so a big flyer hovers higher than a small one. OFF: every Pokemon stands on the line.",
  },
  {
    key = "battle_shadows",
    label = "BATTLE SHADOWS",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): every Pokemon in battle casts a soft shadow on the ground beneath it, sized by the sprite pack for each species. OFF: no shadows.",
  },
  {
    key = "battle_frontal",
    label = "3DB FRONTAL",
    type = "toggle",
    default = false,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. OFF (default): your Pokemon shows its back in battle, as the game intends. ON: it shows its front, so both Pokemon face you. Turn on 3DB FLIP too to have it face the foe.",
  },
  {
    key = "battle_front_flip",
    label = "3DB FLIP",
    type = "toggle",
    default = false,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. With 3DB FRONTAL on: your Pokemon's front art is mirrored so it faces the foe. Does nothing while your Pokemon shows its back.",
  },
  {
    key = "dex_sprites",
    label = "DEX SPRITES",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): the Pokedex shows the animated true-colour art, including a National Dex mod's own species and forms. OFF: the game's own pics.",
  },
  {
    key = "summary_sprites",
    label = "SUMMARY SPRITES",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): the summary screen shows the Pokemon's animated true-colour art (shiny and female where it is). OFF: the game's own pic.",
  },
  {
    key = "summary_size",
    label = "SUMMARY SIZE",
    type = "choice",
    default = 100,
    choices = {
      { "REAL SIZE", 100 },
      { "75%", 75 },
      { "50%", 50 },
      { "25%", 25 },
    },
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. How big the summary screen's picture is: REAL SIZE (default) is the same as in battle; 75% / 50% / 25% draw it smaller in the same box. Nothing else changes size.",
  },
  {
    key = "other_sprites",
    label = "OTHER SCREENS",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): every other screen with a Pokemon's picture shows the true-colour art too: Prof. Oak's speech, evolution, trades and the Hall of Fame, plus the title screen, the Hall of Fame PC and the credits on Red/Blue/Yellow, and the PC box, egg hatching, the photo studio and the Unown printer on Gold/Silver/Crystal. OFF: the game's own pics there.",
  },
  {
    key = "party_icons",
    label = "PARTY ICONS",
    type = "toggle",
    default = true,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. ON (default): a National Dex species or form, which the game has no icon for, gets its own animated true-colour party icon. The game's own species (#1-151 on Red/Blue/Yellow, #1-251 on Gold/Silver/Crystal) keep the game's icons (with HD PARTY SCREEN on, every Pokemon gets ours). OFF: the game's own for all.",
  },
  {
    key = "g9_party_screen",
    label = "HD PARTY SCREEN",
    type = "toggle",
    default = false,
    description = "Red/Blue/Yellow and Gold/Silver/Crystal. Shows our party icons big and sharp. OFF (default): the normal party list, where icons are shrunk to the game's tiny 16x16 size. ON: the party list is drawn as large as your window, so every icon shows in full detail, and the game's own Pokemon (#1-151 / #1-251) get our icons too. Needs PARTY ICONS on. Anything opened from it (the summary, a message box) is drawn just as large.",
  },
}
