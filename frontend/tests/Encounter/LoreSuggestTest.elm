module Encounter.LoreSuggestTest exposing (suite)

{-| Behavior tests for `Encounter.RandomEncounter.Lore.Suggest`.
The suggester back-solves the Random Encounter generator inputs
that should most reliably select a given lore group, so the
tests pin down:

  - habitat / type union math across resolved members
  - min/max XP arithmetic
  - the suggested party budget lands inside the group's
    natural XP envelope (where the eligibility gates pass)
  - unresolved members surface in a warning list

-}

import Compendium
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter.Lore as Lore
import Encounter.RandomEncounter.Lore.Suggest as Suggest
import Expect
import Test exposing (Test, describe, test)



-- ── FIXTURES ─────────────────────────────────────────────────────────────


mkCreature :
    { id : String
    , name : String
    , race : String
    , xp : Int
    , habitats : List Compendium.Habitat
    }
    -> Compendium.Creature
mkCreature args =
    { id = args.id
    , name = args.name
    , kind = Compendium.Enemy
    , size = Compendium.Medium
    , race = args.race
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
    , xpInLair = 0
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
    , habitats = args.habitats
    , treasures = []
    , tags = []
    , loot = []
    , createdAt = 0
    , updatedAt = 0
    , isBundled = False
    , hasSpecialReactions = False
    }


goblin : Compendium.Creature
goblin =
    mkCreature
        { id = "goblin"
        , name = "Goblin Warrior"
        , race = "Humanoid"
        , xp = 50
        , habitats = [ Compendium.Forest, Compendium.Hill ]
        }


hobgoblin : Compendium.Creature
hobgoblin =
    mkCreature
        { id = "hobgoblin"
        , name = "Hobgoblin Warrior"
        , race = "Humanoid"
        , xp = 100
        , habitats = [ Compendium.Forest, Compendium.Underdark ]
        }


pool : List Compendium.Creature
pool =
    [ goblin, hobgoblin ]


warband : Lore.Group
warband =
    { id = "warband"
    , name = "Goblinoid Warband"
    , members =
        [ { name = "Goblin Warrior", role = Lore.Member, countMin = 2, countMax = 4 }
        , { name = "Hobgoblin Warrior", role = Lore.Leader, countMin = 1, countMax = 2 }
        ]
    , weight = 5
    , source = Lore.UserCurated
    , description = ""
    }



-- ── SUITE ────────────────────────────────────────────────────────────────


suite : Test
suite =
    describe "Encounter.RandomEncounter.Lore.Suggest"
        [ xpRangeSuite
        , habitatTypeSuite
        , partyRecommendationSuite
        , unresolvedSuite
        ]


xpRangeSuite : Test
xpRangeSuite =
    describe "XP envelope"
        [ test "minXp sums (creature.xp × countMin) across members" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                -- 2 goblins × 50 + 1 hobgoblin × 100 = 200
                Expect.equal s.minXp 200
        , test "maxXp sums (creature.xp × countMax)" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                -- 4 goblins × 50 + 2 hobgoblins × 100 = 400
                Expect.equal s.maxXp 400
        , test "midXp is the midpoint of min and max" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                Expect.equal s.midXp 300
        ]


habitatTypeSuite : Test
habitatTypeSuite =
    describe "habitat + type unions"
        [ test "habitats union the resolved members' lists" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                -- Forest appears on both, Hill only on goblin,
                -- Underdark only on hobgoblin → all three.
                Expect.equalLists
                    (List.sortBy Compendium.habitatLabel s.habitats)
                    [ Compendium.Forest, Compendium.Hill, Compendium.Underdark ]
        , test "types union the resolved members' races, deduped" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                Expect.equal s.creatureTypes [ "Humanoid" ]
        , test "no-habitat creatures yield empty habitat list (panel shows Any)" <|
            \_ ->
                let
                    naked =
                        mkCreature
                            { id = "ghost", name = "Ghost", race = "Undead", xp = 100, habitats = [] }

                    group =
                        { id = "g"
                        , name = "Single Ghost"
                        , members = [ { name = "Ghost", role = Lore.Leader, countMin = 1, countMax = 1 } ]
                        , weight = 1
                        , source = Lore.UserCurated
                        , description = ""
                        }

                    s =
                        Suggest.suggestFor [ naked ] group
                in
                Expect.equalLists s.habitats []
        ]


partyRecommendationSuite : Test
partyRecommendationSuite =
    describe "party + difficulty recommendation"
        [ test "suggests a party + difficulty whose budget brackets the group's mid-XP" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband

                    suggestedBudget =
                        s.budgetAtSuggestion
                in
                -- Group's natural envelope is 200-400 XP; the
                -- recommended budget should sit inside the
                -- eligibility window (minXp ≤ budget × 1.2 AND
                -- maxXp × 2 ≥ budget).
                Expect.all
                    [ \_ ->
                        Expect.atLeast (s.minXp * 10 // 12)
                            suggestedBudget
                    , \_ ->
                        Expect.atMost (s.maxXp * 2) suggestedBudget
                    ]
                    ()
        , test "party count defaults to 4" <|
            \_ ->
                let
                    s =
                        Suggest.suggestFor pool warband
                in
                Expect.equal s.partyCount 4
        , test "high-XP group recommends a higher-level party" <|
            \_ ->
                let
                    bigBoss =
                        mkCreature
                            { id = "boss"
                            , name = "Big Boss"
                            , race = "Fiend"
                            , xp = 5000
                            , habitats = [ Compendium.Underdark ]
                            }

                    group =
                        { id = "boss"
                        , name = "Boss Encounter"
                        , members = [ { name = "Big Boss", role = Lore.Leader, countMin = 1, countMax = 1 } ]
                        , weight = 1
                        , source = Lore.UserCurated
                        , description = ""
                        }

                    s =
                        Suggest.suggestFor [ bigBoss ] group
                in
                -- A 5000 XP encounter way exceeds any low-level
                -- party budget; expect a recommendation in the
                -- high single-digit levels or above.
                Expect.atLeast 7 s.partyLevel
        ]


unresolvedSuite : Test
unresolvedSuite =
    describe "unresolved members"
        [ test "names not in the compendium show up in unresolved" <|
            \_ ->
                let
                    typo =
                        { id = "g"
                        , name = "Typo Group"
                        , members =
                            [ { name = "Goblin Warrior", role = Lore.Member, countMin = 1, countMax = 2 }
                            , { name = "Goblin Warroir", role = Lore.Member, countMin = 1, countMax = 2 }
                            ]
                        , weight = 1
                        , source = Lore.UserCurated
                        , description = ""
                        }

                    s =
                        Suggest.suggestFor pool typo
                in
                Expect.equal s.unresolved [ "Goblin Warroir" ]
        , test "all unresolved yields empty habitats + types but does not crash" <|
            \_ ->
                let
                    ghosts =
                        { id = "g"
                        , name = "Ghost Group"
                        , members =
                            [ { name = "Phantom", role = Lore.Leader, countMin = 1, countMax = 1 } ]
                        , weight = 1
                        , source = Lore.UserCurated
                        , description = ""
                        }

                    s =
                        Suggest.suggestFor pool ghosts
                in
                Expect.all
                    [ \r -> Expect.equal r.minXp 0
                    , \r -> Expect.equal r.maxXp 0
                    , \r -> Expect.equal r.habitats []
                    , \r -> Expect.equal r.creatureTypes []
                    , \r -> Expect.equal r.unresolved [ "Phantom" ]
                    ]
                    s
        ]
