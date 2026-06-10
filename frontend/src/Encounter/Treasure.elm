module Encounter.Treasure exposing
    ( ArtItem, Coins, GemItem, MagicItem
    , Bracket(..), Kind(..), TreasureRoll
    , bracketFor, bracketIndex, bracketLabel, bracketOptions
    , emptyCoins
    , generate
    , kindLabel, kindOptions
    , suggestedBracket
    , totalArtValue, totalCoinValueGp, totalGemValue
    , Category(..), CoinFormulas, CreatureContribution, RowSource, TreasureTable, artNamesFor, bracketWire, bundledTable, categoryLabel, clearCoin, gemNamesFor, generateRerollCategory, hoardRowsFor, individualRowsFor, magicNamesFor, removeArt, removeGem, removeMagic, setArtNames, setGemNames, setMagicNames
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

import Dict exposing (Dict)
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


{-| Wire-friendly slug for one bracket. Stable identifier used
both in the wire codec and as the key into `TreasureTable`'s
per-bracket Dicts.
-}
bracketWire : Bracket -> String
bracketWire b =
    case b of
        B1to4 ->
            "1to4"

        B5to10 ->
            "5to10"

        B11to16 ->
            "11to16"

        B17plus ->
            "17plus"


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
            "Sum (all Enemies)"

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
    , source : Maybe RowSource
    , contributions : List CreatureContribution
    }


{-| One enemy creature's contribution to a `Sum (all Enemies)`
roll. Each creature gets its own row in the bracket's table,
rolls its own coin formula, and the totals are summed into
`TreasureRoll.coins`. The per-creature breakdown surfaces in
the modal under the "By creature" accordion so the GM can see
who's carrying what — useful for "you defeated three of the
five; here's what's on them" calls.

Hoard rolls leave `contributions` empty since they represent
a single shared stash rather than per-creature pockets.

-}
type alias CreatureContribution =
    { creatureName : String
    , coins : Coins
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


{-| Drop the gem at `index` from the rolled list.
-}
removeGem : Int -> TreasureRoll -> TreasureRoll
removeGem index roll =
    { roll | gems = dropIndex index roll.gems }


{-| Drop the art object at `index` from the rolled list.
-}
removeArt : Int -> TreasureRoll -> TreasureRoll
removeArt index roll =
    { roll | art = dropIndex index roll.art }


{-| Drop the magic item at `index` from the rolled list.
-}
removeMagic : Int -> TreasureRoll -> TreasureRoll
removeMagic index roll =
    { roll | magic = dropIndex index roll.magic }


{-| Zero out one denomination on the coin stack. `wire` is the
denomination key matching the view's slug ("copper", "silver",
"electrum", "gold", "platinum"). Unknown keys are a no-op.
-}
clearCoin : String -> TreasureRoll -> TreasureRoll
clearCoin wire roll =
    let
        c =
            roll.coins

        nextCoins =
            case wire of
                "copper" ->
                    { c | copper = 0 }

                "silver" ->
                    { c | silver = 0 }

                "electrum" ->
                    { c | electrum = 0 }

                "gold" ->
                    { c | gold = 0 }

                "platinum" ->
                    { c | platinum = 0 }

                _ ->
                    c
    in
    { roll | coins = nextCoins }


dropIndex : Int -> List a -> List a
dropIndex idx xs =
    xs
        |> List.indexedMap Tuple.pair
        |> List.filter (\( i, _ ) -> i /= idx)
        |> List.map Tuple.second


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



-- ── TREASURE TABLE ───────────────────────────────────────────────────────────


{-| The singular per-user treasure table. Encapsulates every
piece of editable treasure data: individual + hoard rows by
bracket, plus gem / art / magic name lists per tier.

Out of the box, the user's table is a copy of
[`bundledTable`](#bundledTable) — a faithful SRD 5.1 default.
Edits are persisted server-side (or to localStorage for
anonymous sessions) under a single per-user singleton; there's
no list of named tables, no separate "custom" rolls.

The dict-keyed shape (bracket / tier wires as String keys) is
verbose but makes the editor + wire codec mechanical, since
adding a new bracket or tier becomes a one-line addition with
no record-type surgery.

-}
type alias TreasureTable =
    { individualBrackets : Dict String (List IndividualEntry)
    , hoardBrackets : Dict String (List HoardEntry)
    , gems : Dict String (List String)
    , art : Dict String (List String)
    , magic : Dict String (List String)
    }


{-| Default treasure table — the bundled SRD lists from
[`Encounter.Treasure.Tables`](Encounter-Treasure-Tables)
materialised into the editable shape. A first-boot user (no
saved table on the server) gets this as their working copy.
-}
bundledTable : TreasureTable
bundledTable =
    { individualBrackets =
        Dict.fromList
            (List.map (\b -> ( bracketWire b, Tables.individualEntries (bracketIndex b) ))
                bracketOptions
            )
    , hoardBrackets =
        Dict.fromList
            (List.map (\b -> ( bracketWire b, Tables.hoardEntries (bracketIndex b) ))
                bracketOptions
            )
    , gems =
        Dict.fromList
            (List.map (\t -> ( gemTierKey t, Tables.gems t ))
                gemTierAll
            )
    , art =
        Dict.fromList
            (List.map (\t -> ( artTierKey t, Tables.artObjects t ))
                artTierAll
            )
    , magic =
        Dict.fromList
            (List.map (\t -> ( magicTableKey t, Tables.magicItems t ))
                magicTableAll
            )
    }


gemTierAll : List GemTier
gemTierAll =
    [ Tables.Gem10gp
    , Tables.Gem50gp
    , Tables.Gem100gp
    , Tables.Gem500gp
    , Tables.Gem1000gp
    , Tables.Gem5000gp
    ]


artTierAll : List ArtTier
artTierAll =
    [ Tables.Art25gp
    , Tables.Art250gp
    , Tables.Art750gp
    , Tables.Art2500gp
    , Tables.Art7500gp
    ]


magicTableAll : List MagicTable
magicTableAll =
    [ Tables.TableA
    , Tables.TableB
    , Tables.TableC
    , Tables.TableD
    , Tables.TableE
    , Tables.TableF
    , Tables.TableG
    , Tables.TableH
    , Tables.TableI
    ]


{-| Stable string key for a GemTier — the wire field name and
the Dict key. Matches the gp denomination so the editor can
display the same string as a section header.
-}
gemTierKey : GemTier -> String
gemTierKey t =
    case t of
        Tables.Gem10gp ->
            "10gp"

        Tables.Gem50gp ->
            "50gp"

        Tables.Gem100gp ->
            "100gp"

        Tables.Gem500gp ->
            "500gp"

        Tables.Gem1000gp ->
            "1000gp"

        Tables.Gem5000gp ->
            "5000gp"


artTierKey : ArtTier -> String
artTierKey t =
    case t of
        Tables.Art25gp ->
            "25gp"

        Tables.Art250gp ->
            "250gp"

        Tables.Art750gp ->
            "750gp"

        Tables.Art2500gp ->
            "2500gp"

        Tables.Art7500gp ->
            "7500gp"


magicTableKey : MagicTable -> String
magicTableKey =
    Tables.magicTableLabel


{-| Resolve the individual-treasure rows for one CR bracket from
the user's table. Falls back to `[]` if the table's missing the
bracket — shouldn't happen for tables seeded from
[`bundledTable`](#bundledTable), but the empty list keeps the
generator total.
-}
individualRowsFor : Bracket -> TreasureTable -> List IndividualEntry
individualRowsFor bracket table =
    Dict.get (bracketWire bracket) table.individualBrackets
        |> Maybe.withDefault []


hoardRowsFor : Bracket -> TreasureTable -> List HoardEntry
hoardRowsFor bracket table =
    Dict.get (bracketWire bracket) table.hoardBrackets
        |> Maybe.withDefault []


gemNamesFor : GemTier -> TreasureTable -> List String
gemNamesFor tier table =
    Dict.get (gemTierKey tier) table.gems
        |> Maybe.withDefault []


artNamesFor : ArtTier -> TreasureTable -> List String
artNamesFor tier table =
    Dict.get (artTierKey tier) table.art
        |> Maybe.withDefault []


magicNamesFor : MagicTable -> TreasureTable -> List String
magicNamesFor magicTable table =
    Dict.get (magicTableKey magicTable) table.magic
        |> Maybe.withDefault []


{-| Editor mutation: replace one tier's gem name list.
-}
setGemNames : GemTier -> List String -> TreasureTable -> TreasureTable
setGemNames tier names table =
    { table | gems = Dict.insert (gemTierKey tier) names table.gems }


setArtNames : ArtTier -> List String -> TreasureTable -> TreasureTable
setArtNames tier names table =
    { table | art = Dict.insert (artTierKey tier) names table.art }


setMagicNames : MagicTable -> List String -> TreasureTable -> TreasureTable
setMagicNames magicTable names table =
    { table | magic = Dict.insert (magicTableKey magicTable) names table.magic }



-- ── GENERATOR ────────────────────────────────────────────────────────────────


{-| Roll fresh treasure for the chosen kind + bracket against
the supplied table. Callers thread `model.userTreasureTable` (or
`bundledTable` for a fresh boot) so edits to the user's table
take effect immediately on the next roll.

`enemyNames` is the list of non-PC, non-placeholder creature
names tagged as enemies in the current encounter. Individual
rolls (now relabeled "Sum (all Enemies)") roll the bracket's
table ONCE PER ENEMY and sum the coins, so adding three more
kobolds tripled the take. Hoard rolls ignore the list — a
single shared stash doesn't scale with party size.

-}
generate : Kind -> Bracket -> TreasureTable -> List String -> Random.Generator TreasureRoll
generate kind bracket table enemyNames =
    case kind of
        Individual ->
            generateIndividualSum bracket table enemyNames

        Hoard ->
            generateHoard bracket table


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
generateRerollCategory :
    TreasureTable
    -> List String
    -> TreasureRoll
    -> Category
    -> Random.Generator TreasureRoll
generateRerollCategory table enemyNames currentRoll category =
    case currentRoll.source of
        Just source ->
            generateRerollFromSource table currentRoll source category

        Nothing ->
            generate currentRoll.kind currentRoll.bracket table enemyNames


generateRerollFromSource :
    TreasureTable
    -> TreasureRoll
    -> RowSource
    -> Category
    -> Random.Generator TreasureRoll
generateRerollFromSource table currentRoll source category =
    let
        scaffold =
            emptyRollFor currentRoll.kind currentRoll.bracket
    in
    case category of
        CoinsCategory ->
            rollCoinsFromFormulas source.coinFormulas
                |> Random.map (\coins -> { scaffold | coins = coins })

        GemsCategory ->
            rollGems table source.gemsSpec
                |> Random.map (\gems -> { scaffold | gems = gems })

        ArtCategory ->
            rollArt table source.artSpec
                |> Random.map (\art -> { scaffold | art = art })

        MagicCategory ->
            rollMagic table source.magicSpec
                |> Random.map (\magic -> { scaffold | magic = magic })


{-| Helper: blank scaffold roll used to carry one category's
slice through to the merge handler.
-}
emptyRollFor : Kind -> Bracket -> TreasureRoll
emptyRollFor kind bracket =
    { kind = kind
    , bracket = bracket
    , coins = emptyCoins
    , gems = []
    , art = []
    , magic = []
    , source = Nothing
    , contributions = []
    }


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


{-| Sum-of-enemies Individual roll. Rolls the bracket's
individual table independently for each enemy name in
`enemyNames`, sums the coins, and exposes the per-creature
breakdown through `TreasureRoll.contributions` so the modal
can show who's carrying what.

`source = Nothing` because the sum draws from many rows; a
per-category re-roll can't faithfully use the "same spec"
trick, so it falls back to a fresh full sum (which is what
the GM almost certainly wants anyway).

Empty `enemyNames` yields a zero-coin roll — no enemies in
the encounter, no pockets to loot.

-}
generateIndividualSum :
    Bracket
    -> TreasureTable
    -> List String
    -> Random.Generator TreasureRoll
generateIndividualSum bracket table enemyNames =
    let
        rows =
            individualRowsFor bracket table
    in
    sequenceList (List.map (rollOneEnemy rows) enemyNames)
        |> Random.map
            (\contributions ->
                { kind = Individual
                , bracket = bracket
                , coins = sumContributions contributions
                , gems = []
                , art = []
                , magic = []
                , source = Nothing
                , contributions = contributions
                }
            )


rollOneEnemy : List IndividualEntry -> String -> Random.Generator CreatureContribution
rollOneEnemy rows name =
    weightedPick rows emptyIndividualRow
        |> Random.andThen
            (\row ->
                rollIndividualCoins row
                    |> Random.map
                        (\coins ->
                            { creatureName = name
                            , coins = coins
                            }
                        )
            )


sumContributions : List CreatureContribution -> Coins
sumContributions =
    List.foldl (\c acc -> addCoins acc c.coins) emptyCoins


addCoins : Coins -> Coins -> Coins
addCoins a b =
    { copper = a.copper + b.copper
    , silver = a.silver + b.silver
    , electrum = a.electrum + b.electrum
    , gold = a.gold + b.gold
    , platinum = a.platinum + b.platinum
    }


sequenceList : List (Random.Generator a) -> Random.Generator (List a)
sequenceList gens =
    case gens of
        [] ->
            Random.constant []

        head :: rest ->
            head
                |> Random.andThen
                    (\h ->
                        sequenceList rest
                            |> Random.map (\tail -> h :: tail)
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


generateHoard : Bracket -> TreasureTable -> Random.Generator TreasureRoll
generateHoard bracket table =
    let
        rows =
            hoardRowsFor bracket table
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
                        , source = Just (sourceFromHoard row)
                        , contributions = []
                        }
                    )
                    (rollHoardCoins row)
                    (rollGems table row.gems)
                    (rollArt table row.art)
                    (rollMagic table row.magic)
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


rollGems : TreasureTable -> Maybe ( Int, Int, GemTier ) -> Random.Generator (List GemItem)
rollGems table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (gemNamesFor tier table)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , valueGp = Tables.gemTierValue tier
                                        }
                                    )
                                )
                    )


rollArt : TreasureTable -> Maybe ( Int, Int, ArtTier ) -> Random.Generator (List ArtItem)
rollArt table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (artNamesFor tier table)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , valueGp = Tables.artTierValue tier
                                        }
                                    )
                                )
                    )


rollMagic : TreasureTable -> Maybe ( Int, Int, MagicTable ) -> Random.Generator (List MagicItem)
rollMagic table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, magicTable ) ->
            rollDiceTimes count faces
                |> Random.andThen
                    (\n ->
                        pickN n (magicNamesFor magicTable table)
                            |> Random.map
                                (List.map
                                    (\name ->
                                        { name = name
                                        , rarity = Tables.magicTableRarity magicTable
                                        , table = magicTable
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
