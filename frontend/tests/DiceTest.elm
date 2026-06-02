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


scannerSuite : Test
scannerSuite =
    describe "Dice.scan"
        [ test "extracts a `+7 to hit` attack-roll segment with its modifier" <|
            \_ ->
                let
                    typical =
                        "Melee Weapon Attack: +7 to hit, reach 5 ft., one target. Hit: 9 (1d10 + 4) slashing damage."

                    attacks =
                        Dice.scan typical
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink shown mod ->
                                            Just ( shown, mod )

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ ( "+7 to hit", 7 ) ]
        , test "negative attack modifier (-1 to hit) parses with sign preserved" <|
            \_ ->
                let
                    attacks =
                        Dice.scan "Old Bones: -1 to hit, reach 5 ft."
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink _ mod ->
                                            Just mod

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ -1 ]
        , test "damage-roll DiceLink still scans alongside an AttackLink in the same line" <|
            \_ ->
                let
                    segs =
                        Dice.scan "Bite: +6 to hit. Hit: 8 (1d8 + 4) piercing damage."

                    hasAttack =
                        List.any
                            (\s ->
                                case s of
                                    Dice.AttackLink _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                            segs

                    hasDice =
                        List.any
                            (\s ->
                                case s of
                                    Dice.DiceLink _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                            segs
                in
                ( hasAttack, hasDice ) |> Expect.equal ( True, True )
        , test "plain prose like '+5 bonus to checks' does NOT become an AttackLink" <|
            \_ ->
                let
                    attacks =
                        Dice.scan "Adds +5 bonus to checks; no to-hit involved."
                            |> List.filter
                                (\s ->
                                    case s of
                                        Dice.AttackLink _ _ ->
                                            True

                                        _ ->
                                            False
                                )
                in
                attacks |> Expect.equal []
        , test "SRD 5.2.1 `Melee Attack Roll: +4` is captured as one AttackLink" <|
            \_ ->
                let
                    -- The user's actual stat block, verbatim.
                    rend =
                        "Rend. Melee Attack Roll: +4, reach 5 ft. 7 (1d10 + 2) Slashing damage."

                    attacks =
                        Dice.scan rend
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink shown mod ->
                                            Just ( shown, mod )

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ ( "Melee Attack Roll: +4", 4 ) ]
        , test "`Ranged Attack Roll: +N` works the same way" <|
            \_ ->
                let
                    attacks =
                        Dice.scan "Bow. Ranged Attack Roll: +9, range 80/320 ft. 8 (1d8 + 4) Piercing damage."
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink shown mod ->
                                            Just ( shown, mod )

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ ( "Ranged Attack Roll: +9", 9 ) ]
        , test "`Melee or Ranged Attack Roll: +N` captures the combined qualifier" <|
            \_ ->
                let
                    attacks =
                        Dice.scan "Toss. Melee or Ranged Attack Roll: +7, reach 5 ft. or range 20/60 ft."
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink shown mod ->
                                            Just ( shown, mod )

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ ( "Melee or Ranged Attack Roll: +7", 7 ) ]
        , test "redundant `: +17 to hit` tail is consumed into the same single AttackLink" <|
            \_ ->
                let
                    attacks =
                        Dice.scan "Slam. Melee Attack Roll: +17 to hit, reach 10 ft. 21 (3d8 + 8) Bludgeoning damage."
                            |> List.filterMap
                                (\segment ->
                                    case segment of
                                        Dice.AttackLink shown _ ->
                                            Just shown

                                        _ ->
                                            Nothing
                                )
                in
                attacks |> Expect.equal [ "Melee Attack Roll: +17 to hit" ]
        , test "SRD-format AttackLink and damage DiceLink coexist on a single action line" <|
            \_ ->
                let
                    segs =
                        Dice.scan "Rend. Melee Attack Roll: +4, reach 5 ft. 7 (1d10 + 2) Slashing damage."

                    hasAttack =
                        List.any
                            (\s ->
                                case s of
                                    Dice.AttackLink _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                            segs

                    hasDice =
                        List.any
                            (\s ->
                                case s of
                                    Dice.DiceLink _ _ ->
                                        True

                                    _ ->
                                        False
                            )
                            segs
                in
                ( hasAttack, hasDice ) |> Expect.equal ( True, True )
        ]


suite : Test
suite =
    describe "Dice (pure parser + types)"
        [ parserSuite
        , scannerSuite
        ]
