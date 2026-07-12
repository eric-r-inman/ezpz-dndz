module Encounter.RandomEncounterTest exposing (suite)

{-| Behavior tests for `Encounter.RandomEncounter` — the random
encounter generator. Two layers:

  - Pure helpers: the `scaleWire` / `scaleFromWire` round-trip
    and `budgetFor`'s deferral to `Encounter.Difficulty`.
  - The `Random.Generator` itself, exercised via `Random.step`
    over a spread of fixed seeds (same approach as
    `TreasureFairnessTest`). Assertions are invariants — pool
    membership, XP-budget ceilings, Scale count caps, filter
    respect, pinned/excluded precedence — rather than exact
    sequences, so a change in RNG call order won't break them.

The lore-leaning path has its own coverage in `LoreSuggestTest`;
every param set here uses `loreLeaning = False`.

-}

import Compendium
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter as RandomEncounter
    exposing
        ( GenParams
        , RollResult
        , Scale(..)
        , TargetDifficulty(..)
        )
import Expect exposing (Expectation)
import Random
import Set
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


kobold : Compendium.Creature
kobold =
    mkCreature
        { id = "kobold"
        , name = "Kobold"
        , race = "Humanoid"
        , xp = 25
        , habitats = [ Compendium.Forest, Compendium.Hill ]
        }


wolf : Compendium.Creature
wolf =
    mkCreature
        { id = "wolf"
        , name = "Wolf"
        , race = "Beast"
        , xp = 50
        , habitats = [ Compendium.Forest ]
        }


imp : Compendium.Creature
imp =
    mkCreature
        { id = "imp"
        , name = "Imp"
        , race = "Fiend"
        , xp = 200
        , habitats = [ Compendium.Underdark ]
        }


ogre : Compendium.Creature
ogre =
    mkCreature
        { id = "ogre"
        , name = "Ogre"
        , race = "Giant"
        , xp = 450
        , habitats = [ Compendium.Hill ]
        }


youngDragon : Compendium.Creature
youngDragon =
    mkCreature
        { id = "young-dragon"
        , name = "Young Green Dragon"
        , race = "Dragon"
        , xp = 3900
        , habitats = [ Compendium.Forest, Compendium.Hill ]
        }


{-| Missing habitats — `hasRequiredFields` must drop it.
-}
homelessGhost : Compendium.Creature
homelessGhost =
    mkCreature
        { id = "ghost"
        , name = "Ghost"
        , race = "Undead"
        , xp = 450
        , habitats = []
        }


{-| Zero XP — `hasRequiredFields` must drop it.
-}
inertHusk : Compendium.Creature
inertHusk =
    mkCreature
        { id = "husk"
        , name = "Inert Husk"
        , race = "Construct"
        , xp = 0
        , habitats = [ Compendium.Underdark ]
        }


basePool : List Compendium.Creature
basePool =
    [ kobold, wolf, imp, ogre, youngDragon ]


baseParams : Int -> GenParams
baseParams budget =
    { budget = budget
    , habitat = Nothing
    , creatureTypes = []
    , scale = ScaleFew
    , includeMinions = False
    , pinned = []
    , excludedIds = []
    , loreLeaning = False
    , userLoreGroups = []
    }



-- ── SEEDED-ROLL INFRASTRUCTURE ───────────────────────────────────────────


trials : Int
trials =
    60


rollMany : GenParams -> List Compendium.Creature -> List RollResult
rollMany params pool =
    List.range 1 trials
        |> List.map
            (\i ->
                Random.step
                    (RandomEncounter.generator params pool)
                    (Random.initialSeed (i * 7919 + 13))
                    |> Tuple.first
            )


{-| Assert an invariant over every seeded roll; reports how many
seeds violated it.
-}
expectAllRolls : (RollResult -> Bool) -> List RollResult -> Expectation
expectAllRolls prop rolls =
    rolls
        |> List.filter (not << prop)
        |> List.length
        |> Expect.equal 0


groupIds : RollResult -> List String
groupIds r =
    List.map (\( c, _ ) -> c.id) r.groups


totalXp : RollResult -> Int
totalXp r =
    List.foldl (\( c, n ) acc -> acc + c.xp * n) 0 r.groups


totalCount : RollResult -> Int
totalCount r =
    List.foldl (\( _, n ) acc -> acc + n) 0 r.groups



-- ── SUITE ────────────────────────────────────────────────────────────────


suite : Test
suite =
    describe "Encounter.RandomEncounter"
        [ wireSuite
        , budgetForSuite
        , generatorInvariantSuite
        , pinnedSuite
        , minionSuite
        ]


wireSuite : Test
wireSuite =
    describe "scaleWire / scaleFromWire"
        [ test "round-trips every Scale" <|
            \_ ->
                RandomEncounter.allScales
                    |> List.map (RandomEncounter.scaleWire >> RandomEncounter.scaleFromWire)
                    |> Expect.equal (List.map Just RandomEncounter.allScales)
        , test "unknown wire value decodes to Nothing" <|
            \_ ->
                RandomEncounter.scaleFromWire "swarm"
                    |> Expect.equal Nothing
        ]


budgetForSuite : Test
budgetForSuite =
    describe "budgetFor"
        [ test "four level-1 members sum the DMG per-character budgets (50/75/100 each)" <|
            \_ ->
                let
                    party =
                        List.map (\i -> { id = i, level = 1 }) (List.range 1 4)
                in
                Expect.all
                    [ \p -> RandomEncounter.budgetFor p Low |> Expect.equal 200
                    , \p -> RandomEncounter.budgetFor p Moderate |> Expect.equal 300
                    , \p -> RandomEncounter.budgetFor p High |> Expect.equal 400
                    ]
                    party
        , test "mixed-level party defers to Difficulty.partyBudget (single source of truth)" <|
            \_ ->
                let
                    party =
                        [ { id = 1, level = 3 }, { id = 2, level = 5 } ]
                in
                RandomEncounter.budgetFor party Moderate
                    |> Expect.equal (Difficulty.partyBudget party).moderate
        ]


generatorInvariantSuite : Test
generatorInvariantSuite =
    describe "generator invariants (seeded)"
        [ test "every rolled creature comes from the supplied pool" <|
            \_ ->
                let
                    poolIds =
                        Set.fromList (List.map .id basePool)
                in
                rollMany (baseParams 1000) basePool
                    |> expectAllRolls
                        (\r -> List.all (\id -> Set.member id poolIds) (groupIds r))
        , test "creatures missing required fields (xp = 0, no habitats) never appear" <|
            \_ ->
                rollMany (baseParams 1000) (basePool ++ [ homelessGhost, inertHusk ])
                    |> expectAllRolls
                        (\r ->
                            not (List.member "ghost" (groupIds r))
                                && not (List.member "husk" (groupIds r))
                        )
        , test "total XP never exceeds budget x 1.2 (top-up over-tolerance ceiling)" <|
            \_ ->
                let
                    params =
                        baseParams 1000
                in
                rollMany { params | scale = ScaleMany } basePool
                    |> expectAllRolls (\r -> totalXp r <= 1000 * 12 // 10)
        , test "ScaleOne rolls exactly one creature" <|
            \_ ->
                let
                    params =
                        baseParams 500
                in
                rollMany { params | scale = ScaleOne } basePool
                    |> expectAllRolls (\r -> totalCount r == 1)
        , test "ScaleFew total count stays within 1..4" <|
            \_ ->
                rollMany (baseParams 400) basePool
                    |> expectAllRolls (\r -> totalCount r >= 1 && totalCount r <= 4)
        , test "habitat filter: every creature lists the requested habitat" <|
            \_ ->
                let
                    params =
                        baseParams 1000
                in
                rollMany { params | habitat = Just Compendium.Underdark } basePool
                    |> expectAllRolls
                        (\r ->
                            List.all
                                (\( c, _ ) -> List.member Compendium.Underdark c.habitats)
                                r.groups
                        )
        , test "type filter: every creature's race is among the selected types" <|
            \_ ->
                let
                    params =
                        baseParams 1000
                in
                rollMany { params | creatureTypes = [ "Beast" ] } basePool
                    |> expectAllRolls
                        (\r -> List.all (\( c, _ ) -> c.race == "Beast") r.groups)
        , test "excluded ids never appear in the roll" <|
            \_ ->
                let
                    params =
                        baseParams 1000
                in
                rollMany { params | excludedIds = [ "kobold", "wolf" ] } basePool
                    |> expectAllRolls
                        (\r ->
                            not (List.member "kobold" (groupIds r))
                                && not (List.member "wolf" (groupIds r))
                        )
        , test "no species repeats within a single roll" <|
            \_ ->
                let
                    params =
                        baseParams 2000
                in
                rollMany { params | scale = ScaleMany } basePool
                    |> expectAllRolls
                        (\r ->
                            List.length (groupIds r)
                                == Set.size (Set.fromList (groupIds r))
                        )
        , test "an empty pool yields an empty result rather than crashing" <|
            \_ ->
                rollMany (baseParams 500) []
                    |> expectAllRolls
                        (\r -> r.groups == [] && r.minionIds == [])
        ]


pinnedSuite : Test
pinnedSuite =
    describe "pinned creatures"
        [ test "pinned pairs lead the groups list verbatim" <|
            \_ ->
                let
                    params =
                        baseParams 2000
                in
                rollMany { params | pinned = [ ( ogre, 1 ) ] } basePool
                    |> expectAllRolls
                        (\r -> List.take 1 r.groups == [ ( ogre, 1 ) ])
        , test "pinned XP at or above the budget returns exactly the pins" <|
            \_ ->
                let
                    params =
                        baseParams 500
                in
                -- 3900 XP dragon vs a 500 XP budget: remaining
                -- collapses to 0, so no random fill runs at all.
                rollMany { params | pinned = [ ( youngDragon, 1 ) ] } basePool
                    |> expectAllRolls
                        (\r ->
                            r.groups
                                == [ ( youngDragon, 1 ) ]
                                && r.minionIds
                                == []
                        )
        , test "a pinned creature survives its own exclusion and appears exactly once" <|
            \_ ->
                let
                    params =
                        baseParams 1000
                in
                rollMany
                    { params
                        | pinned = [ ( wolf, 2 ) ]
                        , excludedIds = [ "wolf" ]
                    }
                    basePool
                    |> expectAllRolls
                        (\r ->
                            (groupIds r
                                |> List.filter ((==) "wolf")
                                |> List.length
                            )
                                == 1
                        )
        ]


minionSuite : Test
minionSuite =
    describe "minions"
        [ test "minionIds mark low-XP (<= 100) groups of 2-6 that are part of the roster" <|
            \_ ->
                let
                    params =
                        baseParams 2000

                    rolls =
                        rollMany
                            { params | scale = ScaleMany, includeMinions = True }
                            basePool

                    minionRowsValid r =
                        List.all
                            (\minionId ->
                                List.any
                                    (\( c, n ) ->
                                        (c.id == minionId)
                                            && (c.xp <= 100)
                                            && (n >= 2 && n <= 6)
                                    )
                                    r.groups
                            )
                            r.minionIds
                in
                Expect.all
                    [ expectAllRolls minionRowsValid
                    , \rs ->
                        -- The invariant above is vacuous on rolls
                        -- without minions, so demand that the toggle
                        -- actually produced some across the seeds.
                        rs
                            |> List.any (\r -> not (List.isEmpty r.minionIds))
                            |> Expect.equal True
                    ]
                    rolls
        , test "ScaleOne leaves no room for minions even when the toggle is on" <|
            \_ ->
                let
                    params =
                        baseParams 500
                in
                -- The minion pick needs a count cap of at least 2;
                -- ScaleOne's total cap of 1 is already spent by the
                -- main fill, so the roll must stay minion-free.
                rollMany
                    { params | scale = ScaleOne, includeMinions = True }
                    basePool
                    |> expectAllRolls (\r -> r.minionIds == [])
        ]
