module Encounter.Treasure exposing
    ( ArtItem, Coins, GemItem, MagicItem
    , Bracket(..), Kind(..), TreasureRoll
    , bracketFor, bracketIndex, bracketLabel, bracketOptions
    , emptyCoins
    , generate
    , kindLabel, kindOptions
    , suggestedBracket
    , totalArtValue, totalCoinValueGp, totalGemValue
    )

{-| Treasure-roll domain.

This module owns the rules side of the treasure generator: types,
the random `Generator` that produces a fresh roll, and the small
helpers the modal uses to display things ("how much is this stack
worth in gp?"). No `Html`, no `Update`, no UI state — those
live in `View.Modal.Treasure`, `Ui.Treasure`, and
`Update.Treasure` respectively.

The treasure flow:

  - **Bracket** is the CR band that drives table selection.
    Auto-suggested from the highest CR in the encounter; the GM
    can override.
  - **Kind** is Individual (pocket money from a single creature)
    or Hoard (lair stash with gems / art / magic items).
  - **Generator** walks the chosen table — picks a weighted row,
    rolls each coin formula, then rolls the gem / art / magic
    sub-tables when the hoard row indicates them.
  - **TreasureRoll** is the materialised result: coins, gems
    (each tagged with name + value), art objects (same), and
    magic items (name + rarity). The modal renders these flat;
    persistence pushes the whole record into the encounter.

@docs ArtItem, Coins, GemItem, MagicItem
@docs Bracket, Kind, TreasureRoll
@docs bracketFor, bracketIndex, bracketLabel, bracketOptions
@docs emptyCoins
@docs generate
@docs kindLabel, kindOptions
@docs suggestedBracket
@docs totalArtValue, totalCoinValueGp, totalGemValue

-}

import Encounter.Treasure.Tables as Tables
    exposing
        ( ArtTier
        , GemTier
        , HoardEntry
        , IndividualEntry
        , MagicTable
        , Rarity
        )
import Random



-- ── TYPES ────────────────────────────────────────────────────────────────────


{-| Which CR band a creature falls into. Maps to the row index
in `Encounter.Treasure.Tables.individualEntries` /
`hoardEntries`.
-}
type Bracket
    = B1to4
    | B5to10
    | B11to16
    | B17plus


bracketIndex : Bracket -> Int
bracketIndex b =
    case b of
        B1to4 ->
            0

        B5to10 ->
            1

        B11to16 ->
            2

        B17plus ->
            3


bracketLabel : Bracket -> String
bracketLabel b =
    case b of
        B1to4 ->
            "CR 0–4"

        B5to10 ->
            "CR 5–10"

        B11to16 ->
            "CR 11–16"

        B17plus ->
            "CR 17+"


bracketOptions : List Bracket
bracketOptions =
    [ B1to4, B5to10, B11to16, B17plus ]


{-| Pick a bracket from a CR float. Used by `suggestedBracket`
to walk the encounter and find the toughest monster's band.
-}
bracketFor : Float -> Bracket
bracketFor cr =
    if cr <= 4 then
        B1to4

    else if cr <= 10 then
        B5to10

    else if cr <= 16 then
        B11to16

    else
        B17plus


{-| Recommend the bracket of the toughest creature in the
encounter. Caller passes a list of CR floats (the lookup from
creature → CR float lives in the view / update layer that owns
the compendium handle, since this domain module deliberately
doesn't import `Compendium` to keep the dependency arrow one-
way). Defaults to `B1to4` for an empty list so the modal has
something sensible selected on first open.
-}
suggestedBracket : List Float -> Bracket
suggestedBracket challengeRatings =
    challengeRatings
        |> List.maximum
        |> Maybe.map bracketFor
        |> Maybe.withDefault B1to4


{-| Individual = one creature's pocket money. Hoard = the full
lair stash with gems + art + magic items.
-}
type Kind
    = Individual
    | Hoard


kindLabel : Kind -> String
kindLabel k =
    case k of
        Individual ->
            "Individual"

        Hoard ->
            "Hoard"


kindOptions : List Kind
kindOptions =
    [ Individual, Hoard ]


type alias Coins =
    { copper : Int
    , silver : Int
    , electrum : Int
    , gold : Int
    , platinum : Int
    }


emptyCoins : Coins
emptyCoins =
    { copper = 0, silver = 0, electrum = 0, gold = 0, platinum = 0 }


{-| Converted total value of a coin stack expressed in gp using
the standard 5e exchange rates: 1 pp = 10 gp, 1 ep = 5 sp = 0.5
gp, 10 sp = 1 gp, 100 cp = 1 gp.
-}
totalCoinValueGp : Coins -> Int
totalCoinValueGp c =
    c.platinum
        * 10
        + c.gold
        + (c.electrum // 2)
        + (c.silver // 10)
        + (c.copper // 100)


type alias GemItem =
    { name : String, valueGp : Int }


type alias ArtItem =
    { name : String, valueGp : Int }


type alias MagicItem =
    { name : String, rarity : Rarity }


type alias TreasureRoll =
    { kind : Kind
    , bracket : Bracket
    , coins : Coins
    , gems : List GemItem
    , art : List ArtItem
    , magic : List MagicItem
    }


totalGemValue : List GemItem -> Int
totalGemValue =
    List.foldl (\g acc -> acc + g.valueGp) 0


totalArtValue : List ArtItem -> Int
totalArtValue =
    List.foldl (\a acc -> acc + a.valueGp) 0



-- ── GENERATOR ────────────────────────────────────────────────────────────────


{-| Roll fresh treasure for the chosen kind + bracket. Pure
random — the caller threads the seed (or uses `Random.generate`
in the runtime) per usual Elm `Generator` convention.
-}
generate : Kind -> Bracket -> Random.Generator TreasureRoll
generate kind bracket =
    case kind of
        Individual ->
            generateIndividual bracket

        Hoard ->
            generateHoard bracket


generateIndividual : Bracket -> Random.Generator TreasureRoll
generateIndividual bracket =
    let
        rows =
            Tables.individualEntries (bracketIndex bracket)
    in
    weightedPick rows emptyIndividualRow
        |> Random.andThen
            (\row ->
                Random.map
                    (\coins ->
                        { kind = Individual
                        , bracket = bracket
                        , coins = coins
                        , gems = []
                        , art = []
                        , magic = []
                        }
                    )
                    (rollIndividualCoins row)
            )


emptyIndividualRow : IndividualEntry
emptyIndividualRow =
    { weight = 1
    , copper = Nothing
    , silver = Nothing
    , electrum = Nothing
    , gold = Nothing
    , platinum = Nothing
    }


rollIndividualCoins : IndividualEntry -> Random.Generator Coins
rollIndividualCoins row =
    let
        roll mFormula =
            case mFormula of
                Just ( count, faces, mult ) ->
                    rollDiceTimes count faces |> Random.map (\n -> n * mult)

                Nothing ->
                    Random.constant 0
    in
    Random.map5
        (\cp sp ep gp pp ->
            { copper = cp
            , silver = sp
            , electrum = ep
            , gold = gp
            , platinum = pp
            }
        )
        (roll row.copper)
        (roll row.silver)
        (roll row.electrum)
        (roll row.gold)
        (roll row.platinum)


generateHoard : Bracket -> Random.Generator TreasureRoll
generateHoard bracket =
    let
        rows =
            Tables.hoardEntries (bracketIndex bracket)
    in
    weightedPick rows emptyHoardRow
        |> Random.andThen
            (\row ->
                Random.map4
                    (\coins gems art magic ->
                        { kind = Hoard
                        , bracket = bracket
                        , coins = coins
                        , gems = gems
                        , art = art
                        , magic = magic
                        }
                    )
                    (rollHoardCoins row)
                    (rollGems row.gems)
                    (rollArt row.art)
                    (rollMagic row.magic)
            )


emptyHoardRow : HoardEntry
emptyHoardRow =
    { weight = 1
    , copper = Nothing
    , silver = Nothing
    , electrum = Nothing
    , gold = Nothing
    , platinum = Nothing
    , gems = Nothing
    , art = Nothing
    , magic = Nothing
    }


rollHoardCoins : HoardEntry -> Random.Generator Coins
rollHoardCoins row =
    rollIndividualCoins
        { weight = row.weight
        , copper = row.copper
        , silver = row.silver
        , electrum = row.electrum
        , gold = row.gold
        , platinum = row.platinum
        }


rollGems : Maybe ( Int, Int, GemTier ) -> Random.Generator (List GemItem)
rollGems mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (Tables.gems tier)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , valueGp = Tables.gemTierValue tier
                                        }
                                    )
                                )
                    )


rollArt : Maybe ( Int, Int, ArtTier ) -> Random.Generator (List ArtItem)
rollArt mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (Tables.artObjects tier)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , valueGp = Tables.artTierValue tier
                                        }
                                    )
                                )
                    )


rollMagic : Maybe ( Int, Int, MagicTable ) -> Random.Generator (List MagicItem)
rollMagic mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, table ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (Tables.magicItems table)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , rarity = Tables.magicTableRarity table
                                        }
                                    )
                                )
                    )



-- ── RANDOM HELPERS ───────────────────────────────────────────────────────────


{-| Sum N rolls of a dN. Empty range falls through to 0 so
formula-of-zero entries don't crash.
-}
rollDiceTimes : Int -> Int -> Random.Generator Int
rollDiceTimes count faces =
    if count <= 0 || faces <= 0 then
        Random.constant 0

    else
        Random.list count (Random.int 1 faces)
            |> Random.map List.sum


{-| Weighted pick from a list where each entry carries a
`weight` field. `fallback` is returned when the list is empty
(shouldn't happen for the SRD tables but keeps the type total).
-}
weightedPick :
    List { e | weight : Int }
    -> { e | weight : Int }
    -> Random.Generator { e | weight : Int }
weightedPick entries fallback =
    let
        totalWeight =
            List.sum (List.map .weight entries)
    in
    if totalWeight <= 0 then
        Random.constant fallback

    else
        Random.int 1 totalWeight
            |> Random.map (\target -> walkWeights target entries fallback)


walkWeights :
    Int
    -> List { e | weight : Int }
    -> { e | weight : Int }
    -> { e | weight : Int }
walkWeights remaining list fallback =
    case list of
        [] ->
            fallback

        head :: tail ->
            if remaining <= head.weight then
                head

            else
                walkWeights (remaining - head.weight) tail fallback


{-| Pick `n` items with replacement from `list`. Sampling
without replacement would feel more "loot-y" (no duplicates) but
the SRD tables allow duplicates and the simpler model lets
exotic stones pile up legibly.

An empty `list` produces `n` copies of the empty-table sentinel
`"—"` so the generator type stays total — in practice the SRD
tables are never empty, so this branch is reachable only via a
data bug.

-}
pickN : Int -> List String -> Random.Generator (List String)
pickN n list =
    case ( n, list ) of
        ( 0, _ ) ->
            Random.constant []

        ( _, [] ) ->
            Random.constant (List.repeat n "—")

        ( _, first :: rest ) ->
            Random.list n (Random.uniform first rest)
