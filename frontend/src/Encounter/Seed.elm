module Encounter.Seed exposing (initialEncounter, seedCreatures)

{-| Test-only seed data for the encounter manager.

The running app boots into `Encounter.empty`; the eight-creature
mock cast here is kept around purely so the elm-test suite can
exercise `nextTurn` / `setActive` / sort behavior against a
populated queue.

The data lives in this submodule so `Encounter.elm` doesn't have
to ship 250 lines of literal records inline.

@docs initialEncounter, seedCreatures

-}

import Encounter exposing (AutoRollMode(..), Cover(..), Creature, Duration(..), Encounter, TurnPhase(..))
import Set


{-| Test-only encounter fixture used by the elm-test suite. The
running app no longer boots into this — it boots into
`Encounter.empty` — but the unit tests still need a populated
cast.
-}
initialEncounter : Encounter
initialEncounter =
    { creatures = seedCreatures
    , activeName = "Brakka, Ogre Brute"
    , round = 1
    }


{-| Hard-coded mock cast. Order is descending initiative.
-}
seedCreatures : List Creature
seedCreatures =
    [ { name = "Lyra Vale (PC)"
      , kind = "Half-elf rogue, lvl 5"
      , initiative = 22
      , initiativeBonus = 5
      , currentHp = 0
      , maxHp = 42
      , tempHp = 0
      , armorClass = 16
      , speed = 30
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = HalfCover
      , concentrating = False
      , hiding = True
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , deathSaves = { successes = 0, failures = 1 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Brakka, Ogre Brute"
      , kind = "Large giant, chaotic evil"
      , initiative = 18
      , initiativeBonus = -1
      , currentHp = 27
      , maxHp = 59
      , tempHp = 0
      , armorClass = 11
      , speed = 40
      , conditions =
            [ { id = 1
              , name = "Frightened"
              , note = "of Lyra"
              , duration = DurationCountdown AtEnd 3 False
              , saveToEnd = Just { ability = "WIS", dc = 13, bonus = 1, autoRoll = AutoRollManual }
              }
            ]
      , saveNotices = []
      , selected = True
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Captain Vex"
      , kind = "Medium humanoid (human), bandit captain"
      , initiative = 17
      , initiativeBonus = 2
      , currentHp = 34
      , maxHp = 65
      , tempHp = 0
      , armorClass = 15
      , speed = 30
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , deathSaves = { successes = 0, failures = 0 }
      , readied = True
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Goblin Skirmisher"
      , kind = "Small humanoid, neutral evil"
      , initiative = 15
      , initiativeBonus = 2
      , currentHp = 7
      , maxHp = 7
      , tempHp = 0
      , armorClass = 15
      , speed = 30
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = ThreeQuartersCover
      , concentrating = False
      , hiding = False
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Goblin Boss"
      , kind = "Small humanoid, neutral evil"
      , initiative = 12
      , initiativeBonus = 2
      , currentHp = 21
      , maxHp = 21
      , tempHp = 0
      , armorClass = 17
      , speed = 30
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = FullCover
      , concentrating = False
      , hiding = False
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Thornwhip Shaman"
      , kind = "Small humanoid, druid"
      , initiative = 9
      , initiativeBonus = 1
      , currentHp = 4
      , maxHp = 27
      , tempHp = 0
      , armorClass = 13
      , speed = 30
      , conditions = []
      , saveNotices = []
      , selected = True
      , cover = NoCover
      , concentrating = True
      , hiding = False
      , dodging = False
      , flying = True
      , flyHeight = 30
      , bloodied = False
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Stone Sentinel"
      , kind = "Large construct, unaligned"
      , initiative = 8
      , initiativeBonus = -1
      , currentHp = 78
      , maxHp = 78
      , tempHp = 0
      , armorClass = 18
      , speed = 25
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = HalfCover
      , concentrating = False
      , hiding = False
      , dodging = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    , { name = "Shadow Wisp"
      , kind = "Tiny undead, neutral evil"
      , initiative = 6
      , initiativeBonus = 3
      , currentHp = 12
      , maxHp = 18
      , tempHp = 0
      , armorClass = 12
      , speed = 0
      , conditions = []
      , saveNotices = []
      , selected = False
      , cover = NoCover
      , concentrating = False
      , hiding = True
      , dodging = False
      , flying = True
      , flyHeight = 15
      , bloodied = False
      , deathSaves = { successes = 0, failures = 0 }
      , readied = False
      , inactive = False
      , note = ""
      , memo = ""
      , timer = Nothing
      , creatureId = Nothing
      , hasLegendaryActions = False
      , legendaryActionsUsed = Set.empty
      , hasLegendaryResistance = False
      , legendaryResistanceUsed = Set.empty
      }
    ]
