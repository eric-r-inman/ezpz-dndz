module Encounter.LifecycleTest exposing (suite)

{-| Behavior tests for `Encounter.Lifecycle` — turn-progression
hooks (`nextTurn`, `applyBeginOfTurn`, `applyEndOfTurn`) plus
the dead-skip behavior of `nextTurn`.
-}

import Encounter exposing (AutoRollMode(..), Cover(..), Creature, Duration(..), Encounter, TurnPhase(..), TurnTarget(..))
import Encounter.Lifecycle as Lifecycle
import Expect
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.Lifecycle"
        [ nextTurnSuite
        , deadSkipSuite
        , countdownTickSuite
        , untilTurnExpireSuite
        ]



-- ── FIXTURES ─────────────────────────────────────────────────────────────


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
    , cover = NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = { successes = 0, failures = 0 }
    , holding = False
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


threeCreatures : Encounter
threeCreatures =
    { creatures = [ mkCreature "A" 20, mkCreature "B" 15, mkCreature "C" 10 ]
    , activeName = "A"
    , round = 1
    }


countdownCondition : Condition
countdownCondition =
    { id = 1
    , name = "Frightened"
    , note = ""
    , duration = DurationCountdown AtEnd 2 False
    , saveToEnd = Nothing
    }


type alias Condition =
    Encounter.Condition



-- ── nextTurn ─────────────────────────────────────────────────────────────


nextTurnSuite : Test
nextTurnSuite =
    describe "nextTurn"
        [ test "advances activeName to the next creature in queue order" <|
            \_ ->
                Lifecycle.nextTurn threeCreatures
                    |> .activeName
                    |> Expect.equal "B"
        , test "wraps from the last creature back to the head" <|
            \_ ->
                let
                    enc =
                        { threeCreatures | activeName = "C" }
                in
                Lifecycle.nextTurn enc
                    |> .activeName
                    |> Expect.equal "A"
        , test "round increments only when the wrap happens" <|
            \_ ->
                let
                    enc =
                        { threeCreatures | activeName = "C", round = 1 }
                in
                Lifecycle.nextTurn enc
                    |> .round
                    |> Expect.equal 2
        , test "round does NOT increment on a non-wrap step" <|
            \_ ->
                Lifecycle.nextTurn threeCreatures
                    |> .round
                    |> Expect.equal 1
        ]



-- ── dead skip ────────────────────────────────────────────────────────────


deadSkipSuite : Test
deadSkipSuite =
    describe "nextTurn dead-skip rule"
        [ test "skips a creature with 3 failed death saves" <|
            \_ ->
                let
                    dead =
                        let
                            c =
                                mkCreature "B" 15
                        in
                        { c | currentHp = 0, deathSaves = { successes = 0, failures = 3 } }

                    enc =
                        { threeCreatures
                            | creatures =
                                [ mkCreature "A" 20, dead, mkCreature "C" 10 ]
                        }
                in
                Lifecycle.nextTurn enc
                    |> .activeName
                    |> Expect.equal "C"
        , test "does NOT skip a creature at 0 HP who isn't dead yet" <|
            \_ ->
                let
                    bleeding =
                        let
                            c =
                                mkCreature "B" 15
                        in
                        { c | currentHp = 0, deathSaves = { successes = 1, failures = 1 } }

                    enc =
                        { threeCreatures
                            | creatures =
                                [ mkCreature "A" 20, bleeding, mkCreature "C" 10 ]
                        }
                in
                Lifecycle.nextTurn enc
                    |> .activeName
                    |> Expect.equal "B"
        ]



-- ── countdown tick ───────────────────────────────────────────────────────


countdownTickSuite : Test
countdownTickSuite =
    describe "applyEndOfTurn countdown"
        [ test "decrements an AtEnd countdown by one" <|
            \_ ->
                let
                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ countdownCondition ] }

                    enc =
                        { threeCreatures | creatures = [ bearer, mkCreature "B" 15 ] }
                in
                Lifecycle.applyEndOfTurn "A" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.andThen (\c -> List.head c.conditions)
                    |> Maybe.map .duration
                    |> Expect.equal (Just (DurationCountdown AtEnd 1 False))
        , test "removes the condition when the countdown hits zero" <|
            \_ ->
                let
                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ { countdownCondition | duration = DurationCountdown AtEnd 1 False } ] }

                    enc =
                        { threeCreatures | creatures = [ bearer, mkCreature "B" 15 ] }
                in
                Lifecycle.applyEndOfTurn "A" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.map .conditions
                    |> Expect.equal (Just [])
        , test "skipNextTick eats the first end-of-turn instead of decrementing" <|
            \_ ->
                let
                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ { countdownCondition | duration = DurationCountdown AtEnd 3 True } ] }

                    enc =
                        { threeCreatures | creatures = [ bearer, mkCreature "B" 15 ] }
                in
                Lifecycle.applyEndOfTurn "A" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.andThen (\c -> List.head c.conditions)
                    |> Maybe.map .duration
                    |> Expect.equal (Just (DurationCountdown AtEnd 3 False))
        , test "AtBegin countdown does NOT tick on end-of-turn" <|
            \_ ->
                let
                    cond =
                        { countdownCondition | duration = DurationCountdown AtBegin 3 False }

                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ cond ] }

                    enc =
                        { threeCreatures | creatures = [ bearer, mkCreature "B" 15 ] }
                in
                Lifecycle.applyEndOfTurn "A" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.andThen (\c -> List.head c.conditions)
                    |> Maybe.map .duration
                    |> Expect.equal (Just (DurationCountdown AtBegin 3 False))
        ]



-- ── until-turn expire ────────────────────────────────────────────────────


untilTurnExpireSuite : Test
untilTurnExpireSuite =
    describe "applyEndOfTurn / applyBeginOfTurn until-turn expiration"
        [ test "DurationUntilTurn AtEnd <name> expires when that creature's turn ends" <|
            \_ ->
                let
                    cond =
                        { id = 1
                        , name = "Hex"
                        , note = ""
                        , duration = DurationUntilTurn AtEnd OnCurrentTurn "B"
                        , saveToEnd = Nothing
                        }

                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ cond ] }

                    enc =
                        { creatures = [ bearer, mkCreature "B" 15 ]
                        , activeName = "B"
                        , round = 1
                        }
                in
                Lifecycle.applyEndOfTurn "B" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.map .conditions
                    |> Expect.equal (Just [])
        , test "DurationUntilTurn AtEnd does NOT expire when a different creature's turn ends" <|
            \_ ->
                let
                    cond =
                        { id = 1
                        , name = "Hex"
                        , note = ""
                        , duration = DurationUntilTurn AtEnd OnCurrentTurn "B"
                        , saveToEnd = Nothing
                        }

                    bearer =
                        let
                            c =
                                mkCreature "A" 20
                        in
                        { c | conditions = [ cond ] }

                    enc =
                        { creatures = [ bearer, mkCreature "B" 15 ]
                        , activeName = "A"
                        , round = 1
                        }
                in
                Lifecycle.applyEndOfTurn "A" enc
                    |> .creatures
                    |> List.head
                    |> Maybe.map (.conditions >> List.length)
                    |> Expect.equal (Just 1)
        ]
