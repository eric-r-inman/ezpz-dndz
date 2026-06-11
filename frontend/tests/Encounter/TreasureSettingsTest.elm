module Encounter.TreasureSettingsTest exposing (suite)

{-| Statistical sanity checks for the per-encounter "Tune your
rolls" knobs.

Each test runs the treasure generator many times under one
setting, runs it again under a contrasting setting, and asserts
the aggregate relationship is in the expected direction (e.g.
"More gems → average count is bigger"). The trial counts (200)
plus the bracketing structure of the bundled SRD tables make
the relationships robust — these aren't fuzz tests of a single
roll, they're tests of the generator's expected behavior under
the knobs.

The pivot point: the knobs are applied to dice counts and tier
indices BEFORE any randomness is consumed, so even though
individual rolls have noise, averages over a few hundred trials
should clearly separate Higher/Normal/Lower outcomes.

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


suite : Test
suite =
    describe "Treasure roll settings"
        [ describe "Coins Amount knob"
            [ test "More → average total coin value > Normal" <|
                \_ ->
                    avgCoinValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | coinsCount = CountMore }))
                        |> Expect.greaterThan (avgCoinValueAcross 200 Treasure.defaultSettings)
            , test "Fewer → average total coin value < Normal" <|
                \_ ->
                    avgCoinValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | coinsCount = CountFewer }))
                        |> Expect.lessThan (avgCoinValueAcross 200 Treasure.defaultSettings)
            ]
        , describe "Gems Count knob"
            [ test "More → average gem count > Normal" <|
                \_ ->
                    avgGemCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | gemsCount = CountMore }))
                        |> Expect.greaterThan (avgGemCountAcross 200 Treasure.defaultSettings)
            , test "Fewer → average gem count < Normal" <|
                \_ ->
                    avgGemCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | gemsCount = CountFewer }))
                        |> Expect.lessThan (avgGemCountAcross 200 Treasure.defaultSettings)
            ]
        , describe "Gems Value knob"
            [ test "Higher → average per-gem value > Normal" <|
                \_ ->
                    avgPerGemValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | gemsValue = ValueHigher }))
                        |> Expect.greaterThan (avgPerGemValueAcross 200 Treasure.defaultSettings)
            , test "Lower → average per-gem value < Normal" <|
                \_ ->
                    avgPerGemValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | gemsValue = ValueLower }))
                        |> Expect.lessThan (avgPerGemValueAcross 200 Treasure.defaultSettings)
            ]
        , describe "Art Count knob"
            [ test "More → average art count > Normal" <|
                \_ ->
                    avgArtCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | artCount = CountMore }))
                        |> Expect.greaterThan (avgArtCountAcross 200 Treasure.defaultSettings)
            , test "Fewer → average art count < Normal" <|
                \_ ->
                    avgArtCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | artCount = CountFewer }))
                        |> Expect.lessThan (avgArtCountAcross 200 Treasure.defaultSettings)
            ]
        , describe "Art Value knob"
            [ test "Higher → average per-art value > Normal" <|
                \_ ->
                    avgPerArtValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | artValue = ValueHigher }))
                        |> Expect.greaterThan (avgPerArtValueAcross 200 Treasure.defaultSettings)
            , test "Lower → average per-art value < Normal" <|
                \_ ->
                    avgPerArtValueAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | artValue = ValueLower }))
                        |> Expect.lessThan (avgPerArtValueAcross 200 Treasure.defaultSettings)
            ]
        , describe "Magic Count knob"
            [ test "More → average magic count > Normal" <|
                \_ ->
                    avgMagicCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | magicCount = CountMore }))
                        |> Expect.greaterThan (avgMagicCountAcross 200 Treasure.defaultSettings)
            , test "Fewer → average magic count < Normal" <|
                \_ ->
                    avgMagicCountAcross 200 (settingWith Treasure.defaultSettings (\s -> { s | magicCount = CountFewer }))
                        |> Expect.lessThan (avgMagicCountAcross 200 Treasure.defaultSettings)
            ]
        , describe "Default settings keep the generator behavior unchanged"
            [ test "Normal settings produce non-zero average coin value" <|
                \_ ->
                    avgCoinValueAcross 200 Treasure.defaultSettings
                        |> Expect.greaterThan 0
            , test "Normal settings produce non-zero average gem count" <|
                \_ ->
                    avgGemCountAcross 200 Treasure.defaultSettings
                        |> Expect.greaterThan 0
            ]
        , describe "Empty encounter short-circuits to empty roll"
            [ test "Hoard with no enemies produces no coins" <|
                \_ ->
                    rollEmptyEncounter Hoard
                        |> .coins
                        |> Treasure.totalCoinValueGp
                        |> Expect.equal 0
            , test "Hoard with no enemies produces no gems / art / magic" <|
                \_ ->
                    let
                        roll =
                            rollEmptyEncounter Hoard
                    in
                    ( List.length roll.gems, List.length roll.art, List.length roll.magic )
                        |> Expect.equal ( 0, 0, 0 )
            , test "Individual with no enemies produces empty contributions" <|
                \_ ->
                    rollEmptyEncounter Treasure.Individual
                        |> .contributions
                        |> Expect.equal []
            ]
        ]


{-| Run the generator under default settings with an explicitly
empty enemy list. Used to verify the "no enemies, no loot"
short-circuit on both Kinds.
-}
rollEmptyEncounter : Kind -> TreasureRoll
rollEmptyEncounter kind =
    let
        emptyCtx =
            { enemies = [], hoardBracket = Treasure.B17plus }

        gen =
            Treasure.generate Treasure.defaultSettings kind Treasure.bundledTable emptyCtx
    in
    Random.step gen (Random.initialSeed 1) |> Tuple.first



-- ── HELPERS ────────────────────────────────────────────────────────────────


{-| Pin the bracket to CR 17+ — its hoard table has two
gem tiers (1000gp, 5000gp), two art tiers (2500gp, 7500gp), and
three magic tables (C, D, E), so every value-shift knob has
headroom in both directions. Lower brackets float at the floor
on some tiers (bracket 2's art is single-tier Art25gp, so
ValueLower is a no-op there) and would mask the signal.

A single dummy enemy is needed in the list — the generator now
short-circuits empty-enemy rolls to an empty roll regardless of
kind, so without a placeholder the statistical assertions would
all see zero items.

-}
ctx : RollContext
ctx =
    { enemies = [ { name = "Dummy", bracket = Treasure.B17plus } ]
    , hoardBracket = Treasure.B17plus
    }


{-| Run the Hoard generator many times under one settings
config, with deterministic but distinct seeds, and return the
materialised rolls.
-}
rollMany : Int -> TreasureSettings -> List TreasureRoll
rollMany n settings =
    let
        gen =
            Treasure.generate settings Hoard Treasure.bundledTable ctx
    in
    List.range 1 n
        |> List.map
            (\i ->
                Random.step gen (Random.initialSeed i)
                    |> Tuple.first
            )


avgCoinValueAcross : Int -> TreasureSettings -> Float
avgCoinValueAcross n settings =
    rollMany n settings
        |> List.map (.coins >> Treasure.totalCoinValueGp >> toFloat)
        |> average


avgGemCountAcross : Int -> TreasureSettings -> Float
avgGemCountAcross n settings =
    rollMany n settings
        |> List.map (.gems >> List.length >> toFloat)
        |> average


avgPerGemValueAcross : Int -> TreasureSettings -> Float
avgPerGemValueAcross n settings =
    let
        allGems =
            rollMany n settings
                |> List.concatMap .gems
    in
    case allGems of
        [] ->
            0

        _ ->
            (List.map (.valueGp >> toFloat) allGems |> List.sum)
                / toFloat (List.length allGems)


avgArtCountAcross : Int -> TreasureSettings -> Float
avgArtCountAcross n settings =
    rollMany n settings
        |> List.map (.art >> List.length >> toFloat)
        |> average


avgPerArtValueAcross : Int -> TreasureSettings -> Float
avgPerArtValueAcross n settings =
    let
        allArt =
            rollMany n settings
                |> List.concatMap .art
    in
    case allArt of
        [] ->
            0

        _ ->
            (List.map (.valueGp >> toFloat) allArt |> List.sum)
                / toFloat (List.length allArt)


avgMagicCountAcross : Int -> TreasureSettings -> Float
avgMagicCountAcross n settings =
    rollMany n settings
        |> List.map (.magic >> List.length >> toFloat)
        |> average


average : List Float -> Float
average xs =
    case xs of
        [] ->
            0

        _ ->
            List.sum xs / toFloat (List.length xs)


{-| Helper: take the default settings and apply a transform.
Reads more cleanly at the call sites than re-stating all seven
fields per test.
-}
settingWith : TreasureSettings -> (TreasureSettings -> TreasureSettings) -> TreasureSettings
settingWith base fn =
    fn base
