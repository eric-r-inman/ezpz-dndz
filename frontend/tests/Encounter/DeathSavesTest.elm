module Encounter.DeathSavesTest exposing (suite)

{-| Behavior tests for `Encounter.DeathSaves` — the pure 5e
death-save tracker. Locks in:

  - `empty` as the zeroed reset value (used on heal-to-positive
    and nat-20 revive by the HP-change engine)
  - `addSuccesses` / `addFailures` increment independently and
    clamp to 0..3 (a natural 1 is `addFailures 2`)
  - the derived states: 3 successes → stable, 3 failures → dead,
    and dead wins over stable when both counts are maxed

The nat-20 "revive at 1 HP" rule lives in the HP-change engine,
not in this value object, so it is out of scope here.

-}

import Encounter.DeathSaves as DeathSaves
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Encounter.DeathSaves"
        [ emptySuite
        , mutationSuite
        , clampSuite
        , derivedStateSuite
        ]



-- ── empty / reset ────────────────────────────────────────────────────────


emptySuite : Test
emptySuite =
    describe "empty"
        [ test "starts at zero successes and zero failures" <|
            \_ ->
                DeathSaves.empty
                    |> Expect.equal { successes = 0, failures = 0 }
        , test "resetting a dying creature to empty clears both derived states" <|
            \_ ->
                let
                    -- 2 successes / 2 failures, then the GM heals the
                    -- creature — the HP-change engine swaps in `empty`.
                    reset =
                        DeathSaves.empty
                            |> DeathSaves.addSuccesses 2
                            |> DeathSaves.addFailures 2
                            |> always DeathSaves.empty
                in
                ( DeathSaves.isStable reset, DeathSaves.isDead reset )
                    |> Expect.equal ( False, False )
        ]



-- ── mutations ────────────────────────────────────────────────────────────


mutationSuite : Test
mutationSuite =
    describe "addSuccesses / addFailures"
        [ test "addSuccesses 1 bumps successes and leaves failures alone" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addSuccesses 1
                    |> Expect.equal { successes = 1, failures = 0 }
        , test "addFailures 1 bumps failures and leaves successes alone" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 1
                    |> Expect.equal { successes = 0, failures = 1 }
        , test "natural 1 (addFailures 2) takes a fresh tracker to two failures" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 2
                    |> .failures
                    |> Expect.equal 2
        , test "natural 1 at two failures kills (2 + 2 clamps to 3, isDead)" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 2
                    |> DeathSaves.addFailures 2
                    |> Expect.all
                        [ .failures >> Expect.equal 3
                        , DeathSaves.isDead >> Expect.equal True
                        ]
        , test "negative n removes a pip (GM mis-click undo)" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addSuccesses 2
                    |> DeathSaves.addSuccesses -1
                    |> .successes
                    |> Expect.equal 1
        ]



-- ── clamping ─────────────────────────────────────────────────────────────


clampSuite : Test
clampSuite =
    describe "clamping to 0..3"
        [ test "successes cap at 3 even for a large n" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addSuccesses 5
                    |> .successes
                    |> Expect.equal 3
        , test "adding to a maxed count is idempotent" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 3
                    |> DeathSaves.addFailures 1
                    |> .failures
                    |> Expect.equal 3
        , test "removing below zero clamps at 0" <|
            \_ ->
                DeathSaves.empty
                    |> DeathSaves.addFailures 1
                    |> DeathSaves.addFailures -5
                    |> .failures
                    |> Expect.equal 0
        ]



-- ── derived states ───────────────────────────────────────────────────────


derivedStateSuite : Test
derivedStateSuite =
    describe "isStable / isDead"
        [ test "three successes with fewer than three failures → stable" <|
            \_ ->
                { successes = 3, failures = 2 }
                    |> DeathSaves.isStable
                    |> Expect.equal True
        , test "two successes is NOT stable" <|
            \_ ->
                { successes = 2, failures = 0 }
                    |> DeathSaves.isStable
                    |> Expect.equal False
        , test "three failures → dead; two failures is not" <|
            \_ ->
                ( DeathSaves.isDead { successes = 0, failures = 3 }
                , DeathSaves.isDead { successes = 0, failures = 2 }
                )
                    |> Expect.equal ( True, False )
        , test "dead wins over stable when both counts are maxed" <|
            \_ ->
                let
                    -- 3/3 can't arise from legal play in sequence, but
                    -- the GM can click pips freely; the tracker must
                    -- resolve the conflict as dead-not-stable.
                    both =
                        { successes = 3, failures = 3 }
                in
                ( DeathSaves.isStable both, DeathSaves.isDead both )
                    |> Expect.equal ( False, True )
        , test "fresh tracker is neither stable nor dead" <|
            \_ ->
                ( DeathSaves.isStable DeathSaves.empty
                , DeathSaves.isDead DeathSaves.empty
                )
                    |> Expect.equal ( False, False )
        ]
