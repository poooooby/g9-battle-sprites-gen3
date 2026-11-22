-- Which animated trainer art (the Animated Trainer Intros pack, assets/trainers/) each Gen 3 game's
-- trainer pics use, and which battles get a VS screen. Read by src/trainers.lua and src/vs.lua,
-- and by tools/build_trainers.py (which packs only the art named here).
--
-- fronts[game][PIC] = the pack's sprite, where PIC is the game's TRAINER_PIC_ name without its
-- prefix (src/core/game3/constants/<game>/trainer_classes.lua) and game is the constants set:
-- "firered" (FireRed / LeafGreen), "emerald", "ruby" (Ruby / Sapphire). A pic not listed keeps the
-- game's own: Hoenn's Elite Four, Teams Aqua and Magma, the Frontier Brains and some classes have
-- no art in the pack.
--
-- vs.firered[PIC] (FireRed / LeafGreen only: there are no Hoenn VS portraits) = the HGSS-style VS screen shown before a single battle against that trainer:
-- `foe` the portrait (Graphics/Transitions hgss_vs_* / vsE4_*), `bar` the bar behind it. Only the
-- foe is shown: the pack's and Essentials' player VS portraits are other games' heroes (Ethan,
-- Lyra, Nate, Rosa), so the player appears as the game's own sprite, matching the chosen gender.

-- the classes the games share (FRLG's own names; FRLG's RS_* pics and RSE's use them too)
local shared = {
  YOUNGSTER = "YOUNGSTER", BUG_CATCHER = "BUGCATCHER", LASS = "LASS", SAILOR = "SAILOR",
  CAMPER = "CAMPER", PICNICKER = "PICNICKER", POKEMANIAC = "POKEMANIAC", SUPER_NERD = "SUPERNERD",
  HIKER = "HIKER", BIKER = "BIKER", BURGLAR = "BURGLAR", ENGINEER = "ENGINEER",
  FISHERMAN = "FISHERMAN", SWIMMER_M = "SWIMMER_M", SWIMMER_F = "SWIMMER_F", CUE_BALL = "CUEBALL",
  GAMER = "GAMBLER", BEAUTY = "BEAUTY", PSYCHIC_M = "PSYCHIC_M", PSYCHIC_F = "PSYCHIC_F",
  ROCKER = "ROCKER", JUGGLER = "JUGGLER", TAMER = "TAMER", BIRD_KEEPER = "BIRDKEEPER",
  BLACK_BELT = "BLACKBELT", SCIENTIST = "SCIENTIST", GENTLEMAN = "GENTLEMAN",
  CHANNELER = "CHANNELER", TWINS = "TWINS", COOL_COUPLE = "COOLCOUPLE",
  YOUNG_COUPLE = "YOUNGCOUPLE", CRUSH_KIN = "CRUSHKIN", SIS_AND_BRO = "SISANDBRO",
  CRUSH_GIRL = "CRUSHGIRL", TUBER_F = "TUBER_F", TUBER_M = "TUBER_M",
  POKEMON_BREEDER = "POKEMONBREEDER", POKEMON_BREEDER_F = "POKEMONBREEDER",
  POKEMON_RANGER_M = "POKEMONRANGER_M", POKEMON_RANGER_F = "POKEMONRANGER_F",
  AROMA_LADY = "AROMALADY", RUIN_MANIAC = "RUINMANIAC", LADY = "LADY", PAINTER = "PAINTER",
  COOLTRAINER_M = "COOLTRAINER_M", COOLTRAINER_F = "COOLTRAINER_F",
  COOL_TRAINER_M = "COOLTRAINER_M", COOL_TRAINER_F = "COOLTRAINER_F",
  SCHOOL_KID_M = "SCHOOLKID_M", SCHOOL_KID_F = "SCHOOLKID_F", RICH_BOY = "RICHBOY",
  GUITARIST = "GUITARIST", POKEFAN_M = "POKEFAN_M", POKEFAN_F = "POKEFAN_F",
  PARASOL_LADY = "PARASOLLADY", BATTLE_GIRL = "CRUSHGIRL",
  CYCLING_TRIATHLETE_M = "CYCLIST_M", CYCLING_TRIATHLETE_F = "CYCLIST_F",
  -- the heroes and Hoenn's leading characters
  RED = "POKEMONTRAINER_Red", LEAF = "POKEMONTRAINER_Leaf",
  BRENDAN = "POKEMONTRAINER_Brendan", MAY = "POKEMONTRAINER_May",
  WALLY = "POKEMONTRAINER_Wally", STEVEN = "CHAMPION_Steven", CHAMPION_STEVEN = "CHAMPION_Steven",
  -- Hoenn's gym leaders (Emerald / FRLG names; Ruby / Sapphire's below)
  LEADER_ROXANNE = "LEADER_Roxanne", LEADER_BRAWLY = "LEADER_Brawly",
  LEADER_WATTSON = "LEADER_Wattson", LEADER_FLANNERY = "LEADER_Flannery",
  LEADER_NORMAN = "LEADER_Norman", LEADER_WINONA = "LEADER_Winona",
  LEADER_TATE_AND_LIZA = "LEADERS", LEADER_JUAN = "LEADER_Juan", LEADER_WALLACE = "LEADER_Wallace",
}

local function with(base, extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- FireRed / LeafGreen: Kanto's own, and its RS_* pics (the Trainer Tower's Hoenn classes)
local firered = with(shared, {
  ROCKET_GRUNT_M = "TEAMROCKET_M", ROCKET_GRUNT_F = "TEAMROCKET_F", PROFESSOR_OAK = "PROFESSOR",
  -- the pack's RIVAL1 / RIVAL2 are Silver and Hugh: Blue is its CHAMPION
  RIVAL_EARLY = "CHAMPION", RIVAL_LATE = "CHAMPION", CHAMPION_RIVAL = "CHAMPION",
  LEADER_BROCK = "LEADER_Brock", LEADER_MISTY = "LEADER_Misty", LEADER_LT_SURGE = "LEADER_Surge",
  LEADER_ERIKA = "LEADER_Erika", LEADER_KOGA = "LEADER_Koga", LEADER_SABRINA = "LEADER_Sabrina",
  LEADER_BLAINE = "LEADER_Blaine", LEADER_GIOVANNI = "LEADER_Giovanni",
  ELITE_FOUR_LORELEI = "ELITEFOUR_Lorelei", ELITE_FOUR_BRUNO = "ELITEFOUR_Bruno",
  ELITE_FOUR_AGATHA = "ELITEFOUR_Agatha", ELITE_FOUR_LANCE = "ELITEFOUR_Lance",
  RS_BRENDAN_1 = "POKEMONTRAINER_Brendan", RS_BRENDAN_2 = "POKEMONTRAINER_Brendan",
  RS_MAY_1 = "POKEMONTRAINER_May", RS_MAY_2 = "POKEMONTRAINER_May",
})
for k, v in pairs(shared) do firered["RS_" .. k] = v end

-- Emerald: Wallace is its champion (the pack has him as a leader)
local emerald = with(shared, {
  RS_BRENDAN = "POKEMONTRAINER_Brendan", RS_MAY = "POKEMONTRAINER_May",
  CHAMPION_WALLACE = "LEADER_Wallace",
})

-- Ruby / Sapphire: the leaders' pics have no LEADER_ prefix
local ruby = with(shared, {
  ROXANNE = "LEADER_Roxanne", BRAWLY = "LEADER_Brawly", WATTSON = "LEADER_Wattson",
  FLANNERY = "LEADER_Flannery", NORMAN = "LEADER_Norman", WINONA = "LEADER_Winona",
  TATE_AND_LIZA = "LEADERS", WALLACE = "LEADER_Wallace",
})

-- HGSS VS screens (FireRed / LeafGreen: Kanto's leaders and Giovanni from Essentials, Bruno and
-- Lance from the pack, Blue as Essentials' champion portrait; Lorelei, Agatha and Hoenn have none)
local GENERIC_BAR = "hgss_vsBar"
local function leader(name) return { foe = "hgss_vs_LEADER_" .. name, bar = "hgss_vsBar_LEADER_" .. name } end
local blue = { foe = "vsE4_CHAMPION", bar = GENERIC_BAR }

return {
  -- Essentials draws trainers at 2x on its 512x384 screen: 2 * 160 / 384 Gen 3 px per pack px
  scale = 2 * 160 / 384,
  -- each strip plays once in this many seconds, then holds its last frame
  seconds = 1.5,
  fronts = { firered = firered, emerald = emerald, ruby = ruby },
  vs = {
    firered = {
      LEADER_BROCK = leader("Brock"), LEADER_MISTY = leader("Misty"),
      LEADER_LT_SURGE = leader("Surge"), LEADER_ERIKA = leader("Erika"),
      LEADER_KOGA = leader("Koga"), LEADER_SABRINA = leader("Sabrina"),
      LEADER_BLAINE = leader("Blaine"), LEADER_GIOVANNI = leader("Giovanni"),
      ELITE_FOUR_BRUNO = { foe = "hgss_vs_ELITEFOUR_Bruno", bar = GENERIC_BAR },
      ELITE_FOUR_LANCE = { foe = "hgss_vs_ELITEFOUR_Lance", bar = GENERIC_BAR },
      RIVAL_EARLY = blue, RIVAL_LATE = blue, CHAMPION_RIVAL = blue,
    },
  },
  -- what every VS screen draws besides the foe and bar
  vsParts = { "hgss_vs1", "hgss_vs2" },
}
