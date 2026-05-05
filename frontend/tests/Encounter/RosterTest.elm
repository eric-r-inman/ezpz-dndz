module Encounter.RosterTest exposing (suite)

{-| Behavior tests for `Encounter.Roster` — queue mutation
helpers (move up / down, sort by initiative, remove, duplicate,
append).

These exercise the documented invariants:

  - Move helpers are pure position swaps; out-of-bounds is a
    no-op.
  - `sortByInitiative` preserves `activeName` and ties break on
    `initiativeBonus` then alphabetic name.
  - `removeCreature` advances the active marker when it deletes
    the active creature.
  - `duplicateCreature` reseeds `id`s on conditions and notices
    so the copy doesn't share keys with the source.
  - `uniqueInstanceName` threads existing names + reserves a new
    pick across a batch.

-}

import Encounter exposing (Cover(..), Creature, Duration(..), Encounter, TurnPhase(..))
import Encounter.Roster as Roster
import Encounter.Seed as Seed
import Expect
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.Roster"
        [ moveUpSuite
        , moveDownSuite
        , sortByInitiativeSuite
        , removeCreatureSuite
        , duplicateCreatureSuite
        , uniqueInstanceNameSuite
        , appendCreaturesSuite
        ]



-- ── FIXTURES ─────────────────────────────────────────────────────────────


{-| Bare-bones creature with sensible neutral defaults. Tests
override only the fields they care about.
-}
mkCreature : String -> Int -> Creature
mkCreature name initiative =
    { name = name
    , kind = ""
    , initiative = initiative
    , initiativeBonus = 0
    , currentHp = 10
    , maxHp = 10
    , tempHp = 0
    , armorClass = 10
    , speed = 30
    , conditions = []
    , saveNotices = []
    , selected = False
    , surprised = False
    , cover = NoCover
    , concentrating = False
    , hiding = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = { successes = 0, failures = 0 }
    , holding = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Nothing
    , hasLegendaryActions = False
    , legendaryActionsUsed = Set.empty
    , hasLegendaryResistance = False
    , legendaryResistanceUsed = Set.empty
    }


{-| Three-creature fixture: A (init 20), B (init 15), C (init 10).
A is active. Order in the list: A, B, C.
-}
threeCreatures : Encounter
threeCreatures =
    { creatures = [ mkCreature "A" 20, mkCreature "B" 15, mkCreature "C" 10 ]
    , activeName = "A"
    , round = 1
    }


names : Encounter -> List String
names enc =
    List.map .name enc.creatures



-- ── moveUp / moveDown ────────────────────────────────────────────────────


moveUpSuite : Test
moveUpSuite =
    describe "moveUp"
        [ test "swaps a creature with its predecessor" <|
            \_ ->
                Roster.moveUp "B" threeCreatures
                    |> names
                    |> Expect.equal [ "B", "A", "C" ]
        , test "is a no-op on the first creature" <|
            \_ ->
                Roster.moveUp "A" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "C" ]
        , test "is a no-op on a name that isn't in the queue" <|
            \_ ->
                Roster.moveUp "X" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "C" ]
        , test "preserves activeName" <|
            \_ ->
                Roster.moveUp "B" threeCreatures
                    |> .activeName
                    |> Expect.equal "A"
        ]


moveDownSuite : Test
moveDownSuite =
    describe "moveDown"
        [ test "swaps a creature with its successor" <|
            \_ ->
                Roster.moveDown "B" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "C", "B" ]
        , test "is a no-op on the last creature" <|
            \_ ->
                Roster.moveDown "C" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "C" ]
        , test "is a no-op on a name that isn't in the queue" <|
            \_ ->
                Roster.moveDown "X" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "C" ]
        ]



-- ── sortByInitiative ─────────────────────────────────────────────────────


sortByInitiativeSuite : Test
sortByInitiativeSuite =
    describe "sortByInitiative"
        [ test "sorts in descending initiative order" <|
            \_ ->
                let
                    scrambled =
                        { threeCreatures
                            | creatures = [ mkCreature "C" 10, mkCreature "A" 20, mkCreature "B" 15 ]
                        }
                in
                Roster.sortByInitiative scrambled
                    |> names
                    |> Expect.equal [ "A", "B", "C" ]
        , test "ties break on initiativeBonus (descending)" <|
            \_ ->
                let
                    enc =
                        { threeCreatures
                            | creatures =
                                [ { mkCreatureA | initiativeBonus = 1 }
                                , { mkCreatureB | initiativeBonus = 5 }
                                ]
                        }
                in
                Roster.sortByInitiative enc
                    |> names
                    |> Expect.equal [ "B", "A" ]
        , test "ties on init AND bonus break alphabetically" <|
            \_ ->
                let
                    enc =
                        { threeCreatures
                            | creatures =
                                [ mkCreature "Bob" 20
                                , mkCreature "Alice" 20
                                ]
                        }
                in
                Roster.sortByInitiative enc
                    |> names
                    |> Expect.equal [ "Alice", "Bob" ]
        , test "preserves activeName across the sort" <|
            \_ ->
                let
                    scrambled =
                        { threeCreatures
                            | creatures = [ mkCreature "C" 10, mkCreature "A" 20, mkCreature "B" 15 ]
                            , activeName = "B"
                        }
                in
                Roster.sortByInitiative scrambled
                    |> .activeName
                    |> Expect.equal "B"
        ]


mkCreatureA : Creature
mkCreatureA =
    let
        c =
            mkCreature "A" 20
    in
    c


mkCreatureB : Creature
mkCreatureB =
    let
        c =
            mkCreature "B" 20
    in
    c



-- ── removeCreature ───────────────────────────────────────────────────────


removeCreatureSuite : Test
removeCreatureSuite =
    describe "removeCreature"
        [ test "removes a non-active creature" <|
            \_ ->
                Roster.removeCreature "B" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "C" ]
        , test "preserves activeName when removing a non-active creature" <|
            \_ ->
                Roster.removeCreature "B" threeCreatures
                    |> .activeName
                    |> Expect.equal "A"
        , test "advances activeName to the successor when removing the active creature" <|
            \_ ->
                Roster.removeCreature "A" threeCreatures
                    |> .activeName
                    |> Expect.equal "B"
        , test "wraps activeName to the head when removing the last creature in queue" <|
            \_ ->
                let
                    enc =
                        { threeCreatures | activeName = "C" }
                in
                Roster.removeCreature "C" enc
                    |> .activeName
                    |> Expect.equal "A"
        , test "empties the queue and clears activeName when last creature is removed" <|
            \_ ->
                let
                    enc =
                        { creatures = [ mkCreature "A" 20 ]
                        , activeName = "A"
                        , round = 1
                        }
                in
                Roster.removeCreature "A" enc
                    |> Expect.all
                        [ .creatures >> Expect.equal []
                        , .activeName >> Expect.equal ""
                        ]
        , test "is a no-op when the named creature isn't in the queue" <|
            \_ ->
                Roster.removeCreature "X" threeCreatures
                    |> Expect.equal threeCreatures
        ]



-- ── duplicateCreature ────────────────────────────────────────────────────


duplicateCreatureSuite : Test
duplicateCreatureSuite =
    describe "duplicateCreature"
        [ test "inserts the copy immediately after the source" <|
            \_ ->
                Roster.duplicateCreature "B" threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "B (copy)", "C" ]
        , test "names sequential copies (copy) / (copy 2) / (copy 3)" <|
            \_ ->
                threeCreatures
                    |> Roster.duplicateCreature "B"
                    |> Roster.duplicateCreature "B"
                    |> Roster.duplicateCreature "B"
                    |> names
                    |> Expect.equal
                        [ "A", "B", "B (copy 3)", "B (copy 2)", "B (copy)", "C" ]
        , test "is a no-op on a name that isn't in the queue" <|
            \_ ->
                Roster.duplicateCreature "X" threeCreatures
                    |> Expect.equal threeCreatures
        , test "copy gets selected = False even when the source is selected" <|
            \_ ->
                let
                    enc =
                        { threeCreatures
                            | creatures =
                                [ { mkCreatureA | selected = True }
                                , mkCreature "B" 15
                                ]
                        }
                in
                Roster.duplicateCreature "A" enc
                    |> .creatures
                    |> List.filter (\c -> c.name == "A (copy)")
                    |> List.head
                    |> Maybe.map .selected
                    |> Expect.equal (Just False)
        , test "copy of a creature with conditions has fresh condition ids" <|
            \_ ->
                let
                    cond =
                        { id = 5
                        , name = "Frightened"
                        , note = ""
                        , duration = DurationManual
                        , saveToEnd = Nothing
                        }

                    enc =
                        { threeCreatures
                            | creatures =
                                [ { mkCreatureA | conditions = [ cond ] }
                                , mkCreature "B" 15
                                ]
                        }
                in
                Roster.duplicateCreature "A" enc
                    |> .creatures
                    |> List.filter (\c -> c.name == "A (copy)")
                    |> List.head
                    |> Maybe.andThen (\c -> List.head c.conditions)
                    |> Maybe.map .id
                    |> Expect.equal (Just 6)
        ]



-- ── uniqueInstanceName ───────────────────────────────────────────────────


uniqueInstanceNameSuite : Test
uniqueInstanceNameSuite =
    describe "uniqueInstanceName"
        [ test "returns the base name when nothing matches" <|
            \_ ->
                Roster.uniqueInstanceName "Goblin" []
                    |> Expect.equal "Goblin"
        , test "appends ' 2' when the bare name is taken" <|
            \_ ->
                Roster.uniqueInstanceName "Goblin" [ "Goblin" ]
                    |> Expect.equal "Goblin 2"
        , test "skips reserved names: Goblin / Goblin 2 / Goblin 3" <|
            \_ ->
                Roster.uniqueInstanceName "Goblin" [ "Goblin", "Goblin 2" ]
                    |> Expect.equal "Goblin 3"
        , test "preserves case in the base when extending" <|
            \_ ->
                Roster.uniqueInstanceName "Goblin Boss" [ "Goblin Boss" ]
                    |> Expect.equal "Goblin Boss 2"
        ]



-- ── appendCreatures ──────────────────────────────────────────────────────


appendCreaturesSuite : Test
appendCreaturesSuite =
    describe "appendCreatures"
        [ test "appends to a non-empty queue" <|
            \_ ->
                Roster.appendCreatures [ mkCreature "D" 5 ] threeCreatures
                    |> names
                    |> Expect.equal [ "A", "B", "C", "D" ]
        , test "appends to an empty queue" <|
            \_ ->
                Roster.appendCreatures [ mkCreature "X" 5 ] Encounter.empty
                    |> names
                    |> Expect.equal [ "X" ]
        , test "preserves activeName when appending to a non-empty queue" <|
            \_ ->
                Roster.appendCreatures [ mkCreature "D" 5 ] threeCreatures
                    |> .activeName
                    |> Expect.equal "A"
        , test "uses the seed encounter as a smoke-check fixture" <|
            \_ ->
                Seed.initialEncounter
                    |> Roster.appendCreatures []
                    |> Expect.equal Seed.initialEncounter
        ]
