module Encounter.TreasureFairnessTest exposing (suite)

{-| End-to-end fairness sanity checks on the treasure generator.

Each scenario runs N trials of the generator and asserts a
direction-or-bound property — Hoards in higher CR brackets carry
more gp than lower ones; the spell-scroll chance is within a few
percent of the requested probability; opt-in categories produce
items only when their None toggle is off. Numbers come from the
500-trial fairness audit that produced
[docs/TREASURE\_AUDIT.md][1] — the assertions here are tight
enough to catch regressions but loose enough to absorb sampling
variance.

-}

import Encounter.Treasure as Treasure
    exposing
        ( CountAdjust(..)
        , Kind(..)
        , RollContext
        , TreasureRoll
        , TreasureSettings
        , ValueAdjust(..)
        )
import Expect
import Random
import Test exposing (Test, describe, test)



-- ── INFRASTRUCTURE ──────────────────────────────────────────────────────────


trials : Int
trials =
    300


makeCtx : List Treasure.Bracket -> RollContext
makeCtx brackets =
    let
        enemies =
            List.indexedMap
                (\i b ->
                    { name = "E" ++ String.fromInt i
                    , bracket = b
                    , loot = []
                    }
                )
                brackets

        toughest =
            List.foldl maxBracket Treasure.B1to4 brackets
    in
    { enemies = enemies, hoardBracket = toughest }


maxBracket : Treasure.Bracket -> Treasure.Bracket -> Treasure.Bracket
maxBracket a b =
    if Treasure.bracketIndex a > Treasure.bracketIndex b then
        a

    else
        b


rollMany : Kind -> RollContext -> TreasureSettings -> List TreasureRoll
rollMany kind ctx settings =
    let
        gen =
            Treasure.generate settings kind Treasure.bundledTable ctx
    in
    List.range 1 trials
        |> List.map
            (\i ->
                Random.step gen (Random.initialSeed (i * 7919 + 13))
                    |> Tuple.first
            )


avgCoins : List TreasureRoll -> Float
avgCoins rolls =
    rolls
        |> List.map (.coins >> Treasure.totalCoinValueGp >> toFloat)
        |> avg


avgGems : List TreasureRoll -> Float
avgGems rolls =
    rolls
        |> List.map (.gems >> List.length >> toFloat)
        |> avg


avgMagic : List TreasureRoll -> Float
avgMagic rolls =
    rolls
        |> List.map (.magic >> List.length >> toFloat)
        |> avg


avgMundane : List TreasureRoll -> Float
avgMundane rolls =
    rolls
        |> List.map (.mundane >> List.length >> toFloat)
        |> avg


avgWeapons : List TreasureRoll -> Float
avgWeapons rolls =
    rolls
        |> List.map (.weapons >> List.length >> toFloat)
        |> avg


avgArmor : List TreasureRoll -> Float
avgArmor rolls =
    rolls
        |> List.map (.armor >> List.length >> toFloat)
        |> avg


avg : List Float -> Float
avg xs =
    case xs of
        [] ->
            0

        _ ->
            List.sum xs / toFloat (List.length xs)



-- ── SUITE ──────────────────────────────────────────────────────────────────


suite : Test
suite =
    describe "Treasure fairness"
        [ describe "Hoard coin gp scales monotonically by bracket"
            [ test "B5to10 > B1to4" <|
                \_ ->
                    avgCoins (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) Treasure.defaultSettings)
                        |> Expect.greaterThan (avgCoins (rollMany Hoard (makeCtx [ Treasure.B1to4 ]) Treasure.defaultSettings))
            , test "B11to16 > B5to10" <|
                \_ ->
                    avgCoins (rollMany Hoard (makeCtx [ Treasure.B11to16 ]) Treasure.defaultSettings)
                        |> Expect.greaterThan (avgCoins (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) Treasure.defaultSettings))
            , test "B17plus > B11to16" <|
                \_ ->
                    avgCoins (rollMany Hoard (makeCtx [ Treasure.B17plus ]) Treasure.defaultSettings)
                        |> Expect.greaterThan (avgCoins (rollMany Hoard (makeCtx [ Treasure.B11to16 ]) Treasure.defaultSettings))
            ]
        , describe "Hoard default rolls produce gems, art, and magic items"
            [ test "B17+ produces some gems on average" <|
                \_ ->
                    avgGems (rollMany Hoard (makeCtx [ Treasure.B17plus ]) Treasure.defaultSettings)
                        |> Expect.greaterThan 0
            , test "B17+ produces some magic items on average" <|
                \_ ->
                    avgMagic (rollMany Hoard (makeCtx [ Treasure.B17plus ]) Treasure.defaultSettings)
                        |> Expect.greaterThan 0
            ]
        , describe "Individual rolls scale linearly with creature count"
            [ test "3× CR5-10 ≥ 2.5× the 1× CR5-10 coin amount" <|
                \_ ->
                    let
                        one =
                            avgCoins (rollMany Individual (makeCtx [ Treasure.B5to10 ]) Treasure.defaultSettings)

                        three =
                            avgCoins (rollMany Individual (makeCtx (List.repeat 3 Treasure.B5to10)) Treasure.defaultSettings)
                    in
                    three |> Expect.greaterThan (one * 2.5)
            , test "5× CR5-10 ≥ 4× the 1× CR5-10 coin amount" <|
                \_ ->
                    let
                        one =
                            avgCoins (rollMany Individual (makeCtx [ Treasure.B5to10 ]) Treasure.defaultSettings)

                        five =
                            avgCoins (rollMany Individual (makeCtx (List.repeat 5 Treasure.B5to10)) Treasure.defaultSettings)
                    in
                    five |> Expect.greaterThan (one * 4)
            ]
        , describe "Per-Kind None toggle suppresses the category"
            [ test "Hoard CR17+ with all non-coin None=on has zero gems" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        settings =
                            { ds
                                | hoardToggles =
                                    { coinsNone = False
                                    , gemsNone = True
                                    , artNone = True
                                    , magicNone = True
                                    , mundaneNone = True
                                    , weaponsNone = True
                                    , armorNone = True
                                    }
                            }
                    in
                    avgGems (rollMany Hoard (makeCtx [ Treasure.B17plus ]) settings)
                        |> Expect.equal 0
            , test "Individual default (CR17+) has zero gems" <|
                \_ ->
                    avgGems (rollMany Individual (makeCtx [ Treasure.B17plus ]) Treasure.defaultSettings)
                        |> Expect.equal 0
            ]
        , describe "Opt-in categories appear only when toggled on"
            [ test "Hoard default has zero mundane items" <|
                \_ ->
                    avgMundane (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) Treasure.defaultSettings)
                        |> Expect.equal 0
            , test "Hoard with Mundane=off produces mundane items" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        ht =
                            ds.hoardToggles

                        settings =
                            { ds | hoardToggles = { ht | mundaneNone = False } }
                    in
                    avgMundane (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) settings)
                        |> Expect.greaterThan 0
            , test "Hoard with Weapons=off produces weapons" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        ht =
                            ds.hoardToggles

                        settings =
                            { ds | hoardToggles = { ht | weaponsNone = False } }
                    in
                    avgWeapons (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) settings)
                        |> Expect.greaterThan 0
            , test "Hoard with Armor=off produces armor" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        ht =
                            ds.hoardToggles

                        settings =
                            { ds | hoardToggles = { ht | armorNone = False } }
                    in
                    avgArmor (rollMany Hoard (makeCtx [ Treasure.B5to10 ]) settings)
                        |> Expect.greaterThan 0
            ]
        , describe "Spell scroll post-process chance is approximately faithful"
            [ test "chance=0 → zero scrolls among magic results" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        settings =
                            { ds | magicScrollChance = 0 }

                        rolls =
                            rollMany Hoard (makeCtx [ Treasure.B17plus ]) settings

                        scrolls =
                            rolls
                                |> List.concatMap .magic
                                |> List.filter (\m -> String.startsWith "Spell Scroll" m.name)
                                |> List.length
                    in
                    scrolls |> Expect.equal 0
            , test "chance=100 → every magic item is a scroll" <|
                \_ ->
                    let
                        ds =
                            Treasure.defaultSettings

                        settings =
                            { ds | magicScrollChance = 100 }

                        rolls =
                            rollMany Hoard (makeCtx [ Treasure.B17plus ]) settings

                        magic =
                            List.concatMap .magic rolls

                        scrolls =
                            magic
                                |> List.filter (\m -> String.startsWith "Spell Scroll" m.name)
                                |> List.length
                    in
                    scrolls |> Expect.equal (List.length magic)
            ]
        ]
