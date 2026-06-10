module Encounter.XpTest exposing (suite)

{-| Behavior tests for `Encounter.Xp` — XP totals computation
across a creature queue + scope filtering.
-}

import Compendium
import Encounter exposing (Cover(..), Creature, Encounter)
import Encounter.Treasure
import Encounter.Xp as Xp exposing (XpScope(..))
import Expect
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.Xp"
        [ totalsForSuite
        , formatThousandsSuite
        ]



-- ── FIXTURES ─────────────────────────────────────────────────────────────


mkInstance :
    { name : String
    , compId : String
    , selected : Bool
    }
    -> Creature
mkInstance args =
    { name = args.name
    , kind = ""
    , initiative = 10
    , initiativeBonus = 0
    , currentHp = 10
    , maxHp = 10
    , tempHp = 0
    , armorClass = 10
    , speed = 30
    , conditions = []
    , saveNotices = []
    , selected = args.selected
    , cover = NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = { successes = 0, failures = 0 }
    , acceptingDeathSaves = False
    , reactionUsed = False
    , rechargeAbilities = []
    , readied = False
    , inactive = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Just args.compId
    , legendaryActionsCount = 0
    , legendaryActionsLairBonus = 0
    , legendaryActionsUsed = Set.empty
    , legendaryResistanceCount = 0
    , legendaryResistanceLairBonus = 0
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = False
    , creatureKind = "enemy"
    , race = ""
    , alignment = ""
    }


mkSource :
    { id : String
    , kind : Compendium.CreatureKind
    , xp : Int
    , xpInLair : Int
    }
    -> Compendium.Creature
mkSource args =
    { id = args.id
    , name = args.id
    , kind = args.kind
    , size = Compendium.Medium
    , race = ""
    , subrace = ""
    , alignment = ""
    , source = ""
    , description = ""
    , armorClass = 10
    , armorClassNote = ""
    , maxHp = 10
    , hpFormula = ""
    , initiativeBonus = 0
    , speed =
        { walk = 30
        , fly = 0
        , swim = 0
        , climb = 0
        , burrow = 0
        , hover = False
        }
    , abilities =
        { str = 10, dex = 10, con = 10, int = 10, wis = 10, cha = 10 }
    , savingThrows = []
    , skills = []
    , damageVulnerabilities = []
    , damageResistances = []
    , damageImmunities = []
    , conditionImmunities = []
    , senses =
        { blindsight = 0
        , darkvision = 0
        , tremorsense = 0
        , truesight = 0
        , passivePerception = 10
        }
    , languages = []
    , challengeRating = "1"
    , xp = args.xp
    , xpInLair = args.xpInLair
    , proficiencyBonus = 2
    , traits = []
    , actions = []
    , bonusActions = []
    , reactions = []
    , legendaryActions = Nothing
    , lairActions = Nothing
    , regionalEffects = Nothing
    , spellcasting = Nothing
    , customSections = []
    , habitats = []
    , treasures = []
    , tags = []
    , createdAt = 0
    , updatedAt = 0
    , isBundled = False
    }


mixedEncounter : Encounter
mixedEncounter =
    { creatures =
        [ mkInstance { name = "Goblin", compId = "goblin", selected = True }
        , mkInstance { name = "Innkeeper", compId = "innkeeper", selected = False }
        , mkInstance { name = "Bard", compId = "bard", selected = False }
        ]
    , activeName = "Goblin"
    , round = 1
    , treasure = Nothing
    , treasureSettings = Encounter.Treasure.defaultSettings
    }


mixedDb : Compendium.Db
mixedDb =
    Compendium.fromList
        [ mkSource { id = "goblin", kind = Compendium.Enemy, xp = 50, xpInLair = 0 }
        , mkSource { id = "innkeeper", kind = Compendium.Npc, xp = 25, xpInLair = 0 }
        , mkSource { id = "bard", kind = Compendium.Player, xp = 9999, xpInLair = 0 }
        ]



-- ── totalsFor ────────────────────────────────────────────────────────────


totalsForSuite : Test
totalsForSuite =
    describe "totalsFor"
        [ test "empty encounter is zero" <|
            \_ ->
                Xp.totalsFor ScopeXpEnemiesAndNpcs Encounter.empty mixedDb
                    |> Expect.equal { total = 0, lairTotal = 0 }
        , test "EnemiesAndNpcs sums enemies + NPCs but excludes Players" <|
            \_ ->
                Xp.totalsFor ScopeXpEnemiesAndNpcs mixedEncounter mixedDb
                    |> .total
                    |> Expect.equal 75
        , test "EnemiesOnly sums enemies and excludes NPCs" <|
            \_ ->
                Xp.totalsFor ScopeXpEnemiesOnly mixedEncounter mixedDb
                    |> .total
                    |> Expect.equal 50
        , test "NpcsOnly sums NPCs and excludes enemies" <|
            \_ ->
                Xp.totalsFor ScopeXpNpcsOnly mixedEncounter mixedDb
                    |> .total
                    |> Expect.equal 25
        , test "SelectedOnly counts only selected creatures (Players still excluded)" <|
            \_ ->
                Xp.totalsFor ScopeXpSelectedOnly mixedEncounter mixedDb
                    |> .total
                    |> Expect.equal 50
        , test "lairTotal falls back to xp when xpInLair is zero" <|
            \_ ->
                Xp.totalsFor ScopeXpEnemiesAndNpcs mixedEncounter mixedDb
                    |> .lairTotal
                    |> Expect.equal 75
        , test "lairTotal prefers xpInLair when non-zero" <|
            \_ ->
                let
                    enc =
                        { creatures = [ mkInstance { name = "Dragon", compId = "dragon", selected = False } ]
                        , activeName = "Dragon"
                        , round = 1
                        , treasure = Nothing
                        , treasureSettings = Encounter.Treasure.defaultSettings
                        }

                    db =
                        Compendium.fromList
                            [ mkSource { id = "dragon", kind = Compendium.Enemy, xp = 15000, xpInLair = 18000 }
                            ]
                in
                Xp.totalsFor ScopeXpEnemiesAndNpcs enc db
                    |> Expect.equal { total = 15000, lairTotal = 18000 }
        , test "creatures with no creatureId are skipped" <|
            \_ ->
                let
                    orphan =
                        { name = "Mystery"
                        , kind = ""
                        , initiative = 10
                        , initiativeBonus = 0
                        , currentHp = 10
                        , maxHp = 10
                        , tempHp = 0
                        , armorClass = 10
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
                        , bloodied = False
                        , deathSaves = { successes = 0, failures = 0 }
                        , acceptingDeathSaves = False
                        , reactionUsed = False
                        , rechargeAbilities = []
                        , readied = False
                        , inactive = False
                        , note = ""
                        , memo = ""
                        , timer = Nothing
                        , creatureId = Nothing
                        , legendaryActionsCount = 0
                        , legendaryActionsLairBonus = 0
                        , legendaryActionsUsed = Set.empty
                        , legendaryResistanceCount = 0
                        , legendaryResistanceLairBonus = 0
                        , legendaryResistanceUsed = Set.empty
                        , isPlaceholder = False
                        , creatureKind = "enemy"
                        , race = ""
                        , alignment = ""
                        }

                    enc =
                        { creatures = [ orphan ]
                        , activeName = "Mystery"
                        , round = 1
                        , treasure = Nothing
                        , treasureSettings = Encounter.Treasure.defaultSettings
                        }
                in
                Xp.totalsFor ScopeXpEnemiesAndNpcs enc mixedDb
                    |> Expect.equal { total = 0, lairTotal = 0 }
        ]



-- ── formatThousands ──────────────────────────────────────────────────────


formatThousandsSuite : Test
formatThousandsSuite =
    describe "formatThousands"
        [ test "small numbers are unchanged" <|
            \_ -> Xp.formatThousands 0 |> Expect.equal "0"
        , test "three-digit numbers are unchanged" <|
            \_ -> Xp.formatThousands 999 |> Expect.equal "999"
        , test "four-digit gets one comma" <|
            \_ -> Xp.formatThousands 1500 |> Expect.equal "1,500"
        , test "five-digit gets one comma" <|
            \_ -> Xp.formatThousands 15000 |> Expect.equal "15,000"
        , test "seven-digit gets two commas" <|
            \_ -> Xp.formatThousands 1500000 |> Expect.equal "1,500,000"
        , test "negatives keep their sign" <|
            \_ -> Xp.formatThousands -1500 |> Expect.equal "-1,500"
        ]
