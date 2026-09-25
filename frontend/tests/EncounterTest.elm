module EncounterTest exposing (suite)

{-| Behavior tests for the pure Encounter rules engine: queue
walk, dead skip, and condition lifecycle.

These deliberately exercise the public surface of `Encounter`
(plus the carved-out submodules) and don't reach into internals.
If the surface changes, this file should be the first to fail.

-}

import Encounter
import Encounter.DeathSaves as DeathSaves
import Encounter.Lifecycle
import Encounter.Seed as Seed
import Expect
import Test exposing (Test, describe, test)



-- ── DEATH SAVES ──────────────────────────────────────────────────────────────


deathSavesSuite : Test
deathSavesSuite =
    describe "Encounter.DeathSaves"
        [ test "empty has no successes or failures" <|
            \_ ->
                DeathSaves.empty
                    |> Expect.equal { successes = 0, failures = 0 }
        , test "addSuccesses clamps to 3" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addSuccesses 5
                    |> .successes
                    |> Expect.equal 3
        , test "addFailures clamps to 3 (handles natural-1's +2)" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 2
                    |> DeathSaves.addFailures 2
                    |> .failures
                    |> Expect.equal 3
        , test "negative addition removes pips, clamped at 0" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addSuccesses 2
                    |> DeathSaves.addSuccesses -5
                    |> .successes
                    |> Expect.equal 0
        , test "isStable iff 3 successes and < 3 failures" <|
            \_ ->
                let
                    stable =
                        DeathSaves.empty |> DeathSaves.addSuccesses 3
                in
                Expect.all
                    [ \_ -> DeathSaves.isStable stable |> Expect.equal True
                    , \_ -> DeathSaves.isDead stable |> Expect.equal False
                    ]
                    ()
        , test "isDead iff 3 failures (overrides stable)" <|
            \_ ->
                let
                    deadAndStable =
                        DeathSaves.empty
                            |> DeathSaves.addSuccesses 3
                            |> DeathSaves.addFailures 3
                in
                Expect.all
                    [ \_ -> DeathSaves.isDead deadAndStable |> Expect.equal True
                    , \_ -> DeathSaves.isStable deadAndStable |> Expect.equal False
                    ]
                    ()
        ]



-- ── TURN LIFECYCLE ───────────────────────────────────────────────────────────


turnLifecycleSuite : Test
turnLifecycleSuite =
    describe "Encounter.Lifecycle.nextTurn"
        [ test "advances to the queue successor of the active creature" <|
            \_ ->
                let
                    enc =
                        Seed.initialEncounter

                    expectedNext =
                        successorName enc.activeName enc.creatures

                    after =
                        Encounter.Lifecycle.nextTurn enc
                in
                Expect.equal after.activeName expectedNext
        , test "round increments when wrapping past the last creature" <|
            \_ ->
                let
                    enc0 =
                        Seed.initialEncounter

                    last =
                        List.head (List.reverse enc0.creatures)
                            |> Maybe.map .name
                            |> Maybe.withDefault ""

                    -- Set active to the last creature, then advance
                    primed =
                        Encounter.setActive last enc0

                    after =
                        Encounter.Lifecycle.nextTurn primed
                in
                Expect.equal after.round (enc0.round + 1)
        ]



-- ── HELPERS ──────────────────────────────────────────────────────────────────


successorName : String -> List Encounter.Creature -> String
successorName name creatures =
    case creatures of
        [] ->
            ""

        first :: _ ->
            walk name first.name creatures


walk : String -> String -> List Encounter.Creature -> String
walk target firstName remaining =
    case remaining of
        [] ->
            firstName

        c :: rest ->
            if c.name == target then
                case rest of
                    next :: _ ->
                        next.name

                    [] ->
                        firstName

            else
                walk target firstName rest



-- ── EXHAUSTION ───────────────────────────────────────────────────────────────


exhaustionSuite : Test
exhaustionSuite =
    describe "Exhaustion levels"
        [ test "each step raises the level, and a step past 6 returns it to 0" <|
            \_ ->
                List.map Encounter.nextExhaustionLevel [ 0, 1, 5, 6 ]
                    |> Expect.equal [ 1, 2, 6, 0 ]
        , test "an Exhaustion condition starts at level 1 and keeps the level it has" <|
            \_ ->
                ( Encounter.conditionLevel "Exhaustion" Nothing, Encounter.conditionLevel "Exhaustion" (Just 4) )
                    |> Expect.equal ( Just 1, Just 4 )
        , test "no other condition carries a level" <|
            \_ ->
                Encounter.conditionLevel "Prone" (Just 3)
                    |> Expect.equal Nothing
        ]



-- ── STANDING ─────────────────────────────────────────────────────────────────


{-| How a seed creature stands at the given hit points while
carrying the named conditions and no others.
-}
standingAt : Int -> List String -> Maybe Encounter.Standing
standingAt hp conditionNames =
    let
        condition id name =
            { id = id
            , name = name
            , note = ""
            , duration = Encounter.DurationManual
            , saveToEnd = Nothing
            , linkedTo = Nothing
            , area = Nothing
            , level = Nothing
            }
    in
    List.head Seed.initialEncounter.creatures
        |> Maybe.map
            (\base ->
                Encounter.standing
                    { base
                        | currentHp = hp
                        , deathSaves = DeathSaves.empty
                        , conditions = List.indexedMap condition conditionNames
                    }
            )


standingSuite : Test
standingSuite =
    describe "Encounter.standing"
        [ test "a creature with hit points and no holding condition is fighting" <|
            \_ ->
                standingAt 10 [ "Prone", "Frightened" ]
                    |> Expect.equal (Just Encounter.Fighting)
        , test "each holding condition holds it, whatever its case" <|
            \_ ->
                [ "Unconscious", "incapacitated", "PARALYZED", "Petrified" ]
                    |> List.map (\name -> standingAt 10 [ name ])
                    |> Expect.equal (List.repeat 4 (Just Encounter.Held))
        , test "0 hit points is down, holding condition or not" <|
            \_ ->
                ( standingAt 0 [], standingAt 0 [ "Paralyzed" ] )
                    |> Expect.equal ( Just Encounter.Down, Just Encounter.Down )
        , test "three failed death saves is down" <|
            \_ ->
                List.head Seed.initialEncounter.creatures
                    |> Maybe.map
                        (\c ->
                            Encounter.standing
                                { c | currentHp = 5, deathSaves = DeathSaves.addFailures 3 DeathSaves.empty }
                        )
                    |> Expect.equal (Just Encounter.Down)
        ]



-- ── ENTRY ────────────────────────────────────────────────────────────────────


suite : Test
suite =
    describe "Encounter (pure rules engine)"
        [ deathSavesSuite
        , turnLifecycleSuite
        , exhaustionSuite
        , standingSuite
        ]
