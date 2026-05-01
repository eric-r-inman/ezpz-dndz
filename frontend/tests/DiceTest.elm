module DiceTest exposing (suite)

{-| Parser-focused tests for the Dice domain. Covers the
notation forms the JS roller accepted (standard / compound /
damage-tagged / stat-block-average wrap).
-}

import Dice
import Expect
import Test exposing (Test, describe, test)


parserSuite : Test
parserSuite =
    describe "Dice.parse"
        [ test "1d6 parses to a single positive die group, no constant" <|
            \_ ->
                case Dice.parse "1d6" of
                    Ok expr ->
                        Expect.all
                            [ \_ -> List.length expr.dice |> Expect.equal 1
                            , \_ -> expr.constant |> Expect.equal 0
                            , \_ -> expr.damageType |> Expect.equal Nothing
                            ]
                            ()

                    Err _ ->
                        Expect.fail "expected 1d6 to parse"
        , test "2d8+3 parses with constant 3" <|
            \_ ->
                case Dice.parse "2d8+3" of
                    Ok expr ->
                        expr.constant |> Expect.equal 3

                    Err _ ->
                        Expect.fail "expected 2d8+3 to parse"
        , test "compound 1d8 + 2d6 parses to two groups" <|
            \_ ->
                case Dice.parse "1d8 + 2d6" of
                    Ok expr ->
                        List.length expr.dice |> Expect.equal 2

                    Err _ ->
                        Expect.fail "expected compound to parse"
        , test "damage-tagged expression captures the type" <|
            \_ ->
                case Dice.parse "2d6+3 fire damage" of
                    Ok expr ->
                        expr.damageType
                            |> Expect.equal (Just "fire")

                    Err _ ->
                        Expect.fail "expected damage-tagged to parse"
        , test "stat-block-average wrap '7 (1d8 + 3)' strips the leading number" <|
            \_ ->
                case Dice.parse "7 (1d8 + 3)" of
                    Ok expr ->
                        Expect.all
                            [ \_ -> List.length expr.dice |> Expect.equal 1
                            , \_ -> expr.constant |> Expect.equal 3
                            ]
                            ()

                    Err _ ->
                        Expect.fail "expected stat-block average to parse"
        , test "garbage input returns Err" <|
            \_ ->
                case Dice.parse "not a roll" of
                    Ok _ ->
                        Expect.fail "expected garbage input to fail"

                    Err _ ->
                        Expect.pass
        ]


suite : Test
suite =
    describe "Dice (pure parser + types)"
        [ parserSuite ]
