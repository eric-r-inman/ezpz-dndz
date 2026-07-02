module SaveChainTest exposing (suite)

{-| Behavior tests for the pure bits of Encounter.SaveChain.
The `applyOutcome` end-to-end integration lives naturally in
manual QA — those tests need a full Encounter fixture; here we
lock in the arithmetic helpers and the "empty chain" detector
the modal uses to disable the Apply buttons.
-}

import Encounter.SaveChain as SaveChain exposing (HpEffect(..))
import Expect
import Test exposing (Test, describe, test)


halfSuite : Test
halfSuite =
    describe "halfFailDamage"
        [ test "rounds down" <|
            \_ -> SaveChain.halfFailDamage 9 |> Expect.equal 4
        , test "zero stays zero" <|
            \_ -> SaveChain.halfFailDamage 0 |> Expect.equal 0
        , test "negative clamps to zero" <|
            \_ -> SaveChain.halfFailDamage -6 |> Expect.equal 0
        , test "even splits cleanly" <|
            \_ -> SaveChain.halfFailDamage 20 |> Expect.equal 10
        ]


emptyDetectorSuite : Test
emptyDetectorSuite =
    describe "isEffectivelyEmpty"
        [ test "true for a fresh chain" <|
            \_ ->
                SaveChain.empty
                    |> SaveChain.isEffectivelyEmpty
                    |> Expect.equal True
        , test "false when the fail side deals damage" <|
            \_ ->
                let
                    base =
                        SaveChain.empty

                    fail =
                        base.onFail
                in
                { base | onFail = { fail | hp = DealDamage 8 } }
                    |> SaveChain.isEffectivelyEmpty
                    |> Expect.equal False
        , test "false when the fail side applies a condition" <|
            \_ ->
                let
                    base =
                        SaveChain.empty

                    fail =
                        base.onFail
                in
                { base | onFail = { fail | conditionName = "Blinded" } }
                    |> SaveChain.isEffectivelyEmpty
                    |> Expect.equal False
        , test "false when the success side does something (edge case)" <|
            \_ ->
                let
                    base =
                        SaveChain.empty

                    success =
                        base.onSuccess
                in
                { base | onSuccess = { success | hp = HalfFailDamage } }
                    |> SaveChain.isEffectivelyEmpty
                    |> Expect.equal False
        , test "whitespace-only condition name is treated as empty" <|
            \_ ->
                let
                    base =
                        SaveChain.empty

                    fail =
                        base.onFail
                in
                { base | onFail = { fail | conditionName = "   " } }
                    |> SaveChain.isEffectivelyEmpty
                    |> Expect.equal True
        ]


suite : Test
suite =
    describe "Encounter.SaveChain (pure helpers)"
        [ halfSuite, emptyDetectorSuite ]
