module Encounter.Treasure exposing
    ( ArtItem, Coins, GemItem, MagicItem
    , Bracket(..), Kind(..), TreasureRoll
    , bracketFor, bracketIndex, bracketLabel, bracketOptions
    , emptyCoins
    , generate
    , kindLabel, kindOptions
    , suggestedBracket
    , totalArtValue, totalCoinValueGp, totalGemValue
    , Category(..), CoinFormulas, RowSource, appendCustom, categoryLabel, emptyRoll, generateRerollCategory, removeCustom
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
import Encounter.Treasure.UserTable as UserTable
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
    { name : String, rarity : Rarity, table : MagicTable }


type alias TreasureRoll =
    { kind : Kind
    , bracket : Bracket
    , coins : Coins
    , gems : List GemItem
    , art : List ArtItem
    , magic : List MagicItem
    , custom : List UserTable.CustomRoll
    , source : Maybe RowSource
    }


{-| The originating SRD row's formulas, stashed alongside the
materialised roll so per-category re-rolls can use the SAME
dice spec as the original. Without this, "re-roll just gems"
would pick a fresh table row and use its gems slice — which
might be empty (if the new row has no gems) or wildly off-tier
(50gp → 5000gp).

Coin formulas are tuples `(count, faces, multiplier)`; the gem
/ art / magic specs are `Maybe (count, faces, tier)` — `Nothing`
means the originating row didn't include that category.

`Nothing` on `TreasureRoll.source` means the roll was loaded
from an encounter saved before this field existed; the
re-roll path falls back to picking a fresh row in that case.

-}
type alias RowSource =
    { coinFormulas : CoinFormulas
    , gemsSpec : Maybe ( Int, Int, GemTier )
    , artSpec : Maybe ( Int, Int, ArtTier )
    , magicSpec : Maybe ( Int, Int, MagicTable )
    }


type alias CoinFormulas =
    { copper : Maybe ( Int, Int, Int )
    , silver : Maybe ( Int, Int, Int )
    , electrum : Maybe ( Int, Int, Int )
    , gold : Maybe ( Int, Int, Int )
    , platinum : Maybe ( Int, Int, Int )
    }


sourceFromIndividual : IndividualEntry -> RowSource
sourceFromIndividual row =
    { coinFormulas =
        { copper = row.copper
        , silver = row.silver
        , electrum = row.electrum
        , gold = row.gold
        , platinum = row.platinum
        }
    , gemsSpec = Nothing
    , artSpec = Nothing
    , magicSpec = Nothing
    }


sourceFromHoard : HoardEntry -> RowSource
sourceFromHoard row =
    { coinFormulas =
        { copper = row.copper
        , silver = row.silver
        , electrum = row.electrum
        , gold = row.gold
        , platinum = row.platinum
        }
    , gemsSpec = row.gems
    , artSpec = row.art
    , magicSpec = row.magic
    }


{-| Blank roll seeded from the current Kind + Bracket. Used when
the GM hits a user-table roll on a fresh modal — there's no SRD
result to merge into, so we synthesise an empty one to carry the
custom row.
-}
emptyRoll : Kind -> Bracket -> TreasureRoll
emptyRoll kind bracket =
    { kind = kind
    , bracket = bracket
    , coins = emptyCoins
    , gems = []
    , art = []
    , magic = []
    , custom = []
    , source = Nothing
    }


{-| Append one user-table result onto the existing custom rows.
-}
appendCustom : UserTable.CustomRoll -> TreasureRoll -> TreasureRoll
appendCustom row roll =
    { roll | custom = roll.custom ++ [ row ] }


{-| Drop the custom row at `index` (0-based). Out-of-range
indices are a no-op so the update handler doesn't need defensive
bounds-checking.
-}
removeCustom : Int -> TreasureRoll -> TreasureRoll
removeCustom index roll =
    { roll
        | custom =
            roll.custom
                |> List.indexedMap Tuple.pair
                |> List.filter (\( i, _ ) -> i /= index)
                |> List.map Tuple.second
    }


{-| Which sub-section of the treasure the GM is asking to
re-roll. Single-category re-rolls leave the other three
sections untouched — useful when the magic item came up wildly
off-theme but the rest of the loot is good.
-}
type Category
    = CoinsCategory
    | GemsCategory
    | ArtCategory
    | MagicCategory


categoryLabel : Category -> String
categoryLabel c =
    case c of
        CoinsCategory ->
            "coins"

        GemsCategory ->
            "gems"

        ArtCategory ->
            "art"

        MagicCategory ->
            "magic"


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


{-| Re-roll just one category of the existing roll, using the
ORIGINATING row's spec. Re-rolling gems uses the same
`(count, faces, tier)` the original row gave, so the gem tier
and count distribution stay consistent — only the specific
stone names change.

Returns a partial `TreasureRoll` where only the requested
category's slice is populated; the caller's update handler
merges that slice into the current roll, leaving the other
three sections untouched.

Falls back to a fresh full-row generate when the current roll
has no `source` data — encounters saved before the
source-tracking field existed take this path so the ↻ icons
still do something useful.

-}
generateRerollCategory : TreasureRoll -> Category -> Random.Generator TreasureRoll
generateRerollCategory currentRoll category =
    case currentRoll.source of
        Just source ->
            generateRerollFromSource currentRoll source category

        Nothing ->
            generate currentRoll.kind currentRoll.bracket


generateRerollFromSource :
    TreasureRoll
    -> RowSource
    -> Category
    -> Random.Generator TreasureRoll
generateRerollFromSource currentRoll source category =
    let
        scaffold =
            emptyRoll currentRoll.kind currentRoll.bracket
    in
    case category of
        CoinsCategory ->
            rollCoinsFromFormulas source.coinFormulas
                |> Random.map (\coins -> { scaffold | coins = coins })

        GemsCategory ->
            rollGems source.gemsSpec
                |> Random.map (\gems -> { scaffold | gems = gems })

        ArtCategory ->
            rollArt source.artSpec
                |> Random.map (\art -> { scaffold | art = art })

        MagicCategory ->
            rollMagic source.magicSpec
                |> Random.map (\magic -> { scaffold | magic = magic })


rollCoinsFromFormulas : CoinFormulas -> Random.Generator Coins
rollCoinsFromFormulas formulas =
    rollIndividualCoins
        { weight = 0
        , copper = formulas.copper
        , silver = formulas.silver
        , electrum = formulas.electrum
        , gold = formulas.gold
        , platinum = formulas.platinum
        }


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
                        , custom = []
                        , source = Just (sourceFromIndividual row)
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
                        , custom = []
                        , source = Just (sourceFromHoard row)
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
                                        , table = table
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
