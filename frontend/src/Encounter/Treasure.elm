module Encounter.Treasure exposing
    ( ArtItem, Coins, GemItem, MagicItem
    , Bracket(..), Kind(..), TreasureRoll
    , bracketFor, bracketIndex, bracketLabel, bracketOptions
    , emptyCoins
    , generate
    , kindLabel, kindOptions
    , suggestedBracket
    , totalArtValue, totalCoinValueGp, totalGemValue
    , ArmorItem, Category(..), CoinFormulas, CountAdjust(..), CreatureContribution, EnemyInfo, MundaneItem, RollContext, RowSource, TreasureSettings, TreasureTable, ValueAdjust(..), WeaponItem, armorItemsFor, armorRollFor, artNamesFor, bracketFromWire, bracketWire, bundledTable, categoryLabel, clearCoin, countAdjustFromWire, countAdjustWire, defaultSettings, gemNamesFor, generateRerollCategory, hoardRowsFor, individualRowsFor, magicNamesFor, mundaneItemsFor, mundaneRollFor, removeArmorItem, removeArt, removeGem, removeMagic, removeMundaneItem, removeWeaponItem, scrollSpellsFor, setArmorItems, setArmorRoll, setArtNames, setGemNames, setHoardRows, setIndividualRows, setMagicNames, setMundaneItems, setMundaneRoll, setScrollSpells, setWeaponsItems, setWeaponsRoll, totalArmorValue, totalMundaneValue, totalWeaponsValue, valueAdjustFromWire, valueAdjustWire, weaponsItemsFor, weaponsRollFor
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
import Encounter.Treasure.MundaneTables as MundaneTables
import Encounter.Treasure.ScrollSpells as ScrollSpells
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


{-| Inverse of `bracketWire`. Returns `Nothing` when the string
isn't one of the four stable slugs — callers in the editor treat
that as a no-op rather than guessing.
-}
bracketFromWire : String -> Maybe Bracket
bracketFromWire s =
    case s of
        "1to4" ->
            Just B1to4

        "5to10" ->
            Just B5to10

        "11to16" ->
            Just B11to16

        "17plus" ->
            Just B17plus

        _ ->
            Nothing


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
            "All (individual loot)"

        Hoard ->
            "Boss (lair hoard)"


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


{-| Mundane / Weapons / Armor share the same flat (name, gp)
shape — no tier abstraction, just a uniform pick from the user's
list. Aliases stay distinct so view code can dispatch on the
intended category without a tag field.
-}
type alias MundaneItem =
    { name : String, valueGp : Int }


type alias WeaponItem =
    { name : String, valueGp : Int }


type alias ArmorItem =
    { name : String, valueGp : Int }


type alias TreasureRoll =
    { kind : Kind
    , bracket : Bracket
    , coins : Coins
    , gems : List GemItem
    , art : List ArtItem
    , magic : List MagicItem
    , mundane : List MundaneItem
    , weapons : List WeaponItem
    , armor : List ArmorItem
    , source : Maybe RowSource
    , contributions : List CreatureContribution

    -- Aggregate of every enemy's pre-authored loot strings (one
    -- entry per item).  Surfaces in the Treasure modal as a
    -- dedicated "Loot" section with no gp values — these are
    -- DM-flavor item descriptions from the stat blocks, not
    -- table-rolled treasure.  Loot lands on the roll regardless
    -- of Kind: both individual sums and hoards aggregate every
    -- enemy's authored items, since "the lair contained the boss
    -- and minions, so their stuff is here too" reads the same way
    -- as "you defeated everyone, here's what was on them."
    , loot : List String
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
    , gems : List GemItem
    , loot : List String
    , bracket : Bracket
    }


{-| Context passed to the random Generator at roll time.

  - `enemies` — one entry per enemy creature in the encounter,
    each with its own per-CR bracket. Used by Sum rolls; the
    Generator rolls the right bracket's table independently for
    each entry and sums the coins.
  - `hoardBracket` — the bracket used by a Hoard roll, picked
    from the toughest enemy in the encounter (or `B1to4` when
    there are no enemies). Ignored by Sum rolls.

Replaces the old CR Bracket dropdown: the encounter already
knows what creatures are in it, so the GM doesn't have to pick
a bracket the modal could derive itself.

-}
type alias RollContext =
    { enemies : List EnemyInfo
    , hoardBracket : Bracket
    }


type alias EnemyInfo =
    { name : String
    , bracket : Bracket
    , loot : List String
    }


{-| Per-encounter roll-time knobs. Each knob is a coarse
"more/normal/fewer" or "higher/normal/lower" adjustment that
gets applied around the canonical treasure-table values at roll
time — the table itself stays untouched. Lets a GM say "this
chest skews to fewer-but-richer gems" without authoring custom
rows.

  - `*Count` axes multiply dice count by 1.5× / 1× / 0.5×
    (rounded, min 1).
  - `gemsValue` and `artValue` shift the tier up or down by one
    step (10gp ↔ 50gp ↔ 100gp ↔ 500gp ↔ 1000gp ↔ 5000gp; or
    25gp ↔ 250gp ↔ 750gp ↔ 2500gp ↔ 7500gp).
  - `magicValue` shifts the SRD table letter (A ↔ B ↔ … ↔ I).
  - `coinsCount` is a single Amount knob — Coins don't have a
    natural value axis distinct from their amount.

-}
type alias TreasureSettings =
    { coinsCount : CountAdjust
    , gemsCount : CountAdjust
    , gemsValue : ValueAdjust
    , artCount : CountAdjust
    , artValue : ValueAdjust
    , magicCount : CountAdjust
    , magicValue : ValueAdjust
    , mundaneCount : CountAdjust
    , weaponsCount : CountAdjust
    , armorCount : CountAdjust

    -- "None" toggles per category — when on, the category is
    -- skipped at roll time regardless of its Count knob.  Mundane
    -- / Weapons / Armor default to ON so the opt-in categories
    -- don't surprise GMs who upgrade and roll without changing
    -- settings; coins / gems / art / magic default to OFF.
    , coinsNone : Bool
    , gemsNone : Bool
    , artNone : Bool
    , magicNone : Bool
    , mundaneNone : Bool
    , weaponsNone : Bool
    , armorNone : Bool

    -- Post-process probability (0..100): for each rolled magic
    -- item, this is the chance the result gets swapped for a
    -- spell scroll at the same rarity, with a spell name picked
    -- from the user's scrollSpells list at the appropriate
    -- level.  0 disables the post-process entirely; defaults to
    -- 15 so scrolls appear naturally without dominating hoards.
    , magicScrollChance : Int
    }


type CountAdjust
    = CountFewer
    | CountNormal
    | CountMore


type ValueAdjust
    = ValueLower
    | ValueNormal
    | ValueHigher


defaultSettings : TreasureSettings
defaultSettings =
    { coinsCount = CountNormal
    , gemsCount = CountNormal
    , gemsValue = ValueNormal
    , artCount = CountNormal
    , artValue = ValueNormal
    , magicCount = CountNormal
    , magicValue = ValueNormal
    , mundaneCount = CountNormal
    , weaponsCount = CountNormal
    , armorCount = CountNormal
    , coinsNone = False
    , gemsNone = False
    , artNone = False
    , magicNone = False
    , mundaneNone = True
    , weaponsNone = True
    , armorNone = True
    , magicScrollChance = 15
    }


countAdjustWire : CountAdjust -> String
countAdjustWire a =
    case a of
        CountFewer ->
            "fewer"

        CountNormal ->
            "normal"

        CountMore ->
            "more"


countAdjustFromWire : String -> CountAdjust
countAdjustFromWire s =
    case s of
        "fewer" ->
            CountFewer

        "more" ->
            CountMore

        _ ->
            CountNormal


valueAdjustWire : ValueAdjust -> String
valueAdjustWire a =
    case a of
        ValueLower ->
            "lower"

        ValueNormal ->
            "normal"

        ValueHigher ->
            "higher"


valueAdjustFromWire : String -> ValueAdjust
valueAdjustFromWire s =
    case s of
        "lower" ->
            ValueLower

        "higher" ->
            ValueHigher

        _ ->
            ValueNormal


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


removeMundaneItem : Int -> TreasureRoll -> TreasureRoll
removeMundaneItem index roll =
    { roll | mundane = dropIndex index roll.mundane }


removeWeaponItem : Int -> TreasureRoll -> TreasureRoll
removeWeaponItem index roll =
    { roll | weapons = dropIndex index roll.weapons }


removeArmorItem : Int -> TreasureRoll -> TreasureRoll
removeArmorItem index roll =
    { roll | armor = dropIndex index roll.armor }


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
    | MundaneCategory
    | WeaponsCategory
    | ArmorCategory


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

        MundaneCategory ->
            "mundane"

        WeaponsCategory ->
            "weapons"

        ArmorCategory ->
            "armor"


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

    -- Opt-in categories: flat (name, gp) lists with a per-bracket
    -- (count, faces) dice that fires whenever the category's None
    -- toggle is off.  No tier abstraction — the item's gp value
    -- comes straight off the picked entry.
    , mundane : List MundaneItem
    , mundaneRoll : Dict String ( Int, Int )
    , weapons : List WeaponItem
    , weaponsRoll : Dict String ( Int, Int )
    , armor : List ArmorItem
    , armorRoll : Dict String ( Int, Int )

    -- Spell-name pool per scroll level, keyed by the level wire
    -- ("cantrip", "1st", "2nd", …, "9th").  The magic-result
    -- post-process picks uniformly from the list at the level
    -- matching the rolled rarity.
    , scrollSpells : Dict String (List String)
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
    , mundane = MundaneTables.bundledMundane
    , mundaneRoll = MundaneTables.bundledMundaneRollByBracket
    , weapons = MundaneTables.bundledWeapons
    , weaponsRoll = MundaneTables.bundledWeaponsRollByBracket
    , armor = MundaneTables.bundledArmor
    , armorRoll = MundaneTables.bundledArmorRollByBracket
    , scrollSpells =
        Dict.fromList
            (List.map
                (\l ->
                    ( ScrollSpells.scrollLevelWire l
                    , ScrollSpells.bundledScrollSpells l
                    )
                )
                ScrollSpells.scrollLevelAll
            )
    }


{-| Replace one level's spell-name list in the user's table.
The level wire key must be one of the slugs in
`ScrollSpells.scrollLevelWire` ("cantrip", "1st", …, "9th");
unknown keys insert under that key so a no-op call still
round-trips through the codec.
-}
setScrollSpells : ScrollSpells.ScrollLevel -> List String -> TreasureTable -> TreasureTable
setScrollSpells level names table =
    { table
        | scrollSpells =
            Dict.insert (ScrollSpells.scrollLevelWire level) names table.scrollSpells
    }


scrollSpellsFor : ScrollSpells.ScrollLevel -> TreasureTable -> List String
scrollSpellsFor level table =
    Dict.get (ScrollSpells.scrollLevelWire level) table.scrollSpells
        |> Maybe.withDefault []


mundaneItemsFor : TreasureTable -> List MundaneItem
mundaneItemsFor table =
    table.mundane


mundaneRollFor : Bracket -> TreasureTable -> ( Int, Int )
mundaneRollFor bracket table =
    Dict.get (bracketWire bracket) table.mundaneRoll
        |> Maybe.withDefault ( 1, 4 )


weaponsItemsFor : TreasureTable -> List WeaponItem
weaponsItemsFor table =
    table.weapons


weaponsRollFor : Bracket -> TreasureTable -> ( Int, Int )
weaponsRollFor bracket table =
    Dict.get (bracketWire bracket) table.weaponsRoll
        |> Maybe.withDefault ( 1, 2 )


armorItemsFor : TreasureTable -> List ArmorItem
armorItemsFor table =
    table.armor


armorRollFor : Bracket -> TreasureTable -> ( Int, Int )
armorRollFor bracket table =
    Dict.get (bracketWire bracket) table.armorRoll
        |> Maybe.withDefault ( 1, 2 )


setMundaneItems : List MundaneItem -> TreasureTable -> TreasureTable
setMundaneItems items table =
    { table | mundane = items }


setMundaneRoll : Bracket -> ( Int, Int ) -> TreasureTable -> TreasureTable
setMundaneRoll bracket spec table =
    { table | mundaneRoll = Dict.insert (bracketWire bracket) spec table.mundaneRoll }


setWeaponsItems : List WeaponItem -> TreasureTable -> TreasureTable
setWeaponsItems items table =
    { table | weapons = items }


setWeaponsRoll : Bracket -> ( Int, Int ) -> TreasureTable -> TreasureTable
setWeaponsRoll bracket spec table =
    { table | weaponsRoll = Dict.insert (bracketWire bracket) spec table.weaponsRoll }


setArmorItems : List ArmorItem -> TreasureTable -> TreasureTable
setArmorItems items table =
    { table | armor = items }


setArmorRoll : Bracket -> ( Int, Int ) -> TreasureTable -> TreasureTable
setArmorRoll bracket spec table =
    { table | armorRoll = Dict.insert (bracketWire bracket) spec table.armorRoll }


totalMundaneValue : List MundaneItem -> Int
totalMundaneValue =
    List.foldl (\m acc -> acc + m.valueGp) 0


totalWeaponsValue : List WeaponItem -> Int
totalWeaponsValue =
    List.foldl (\w acc -> acc + w.valueGp) 0


totalArmorValue : List ArmorItem -> Int
totalArmorValue =
    List.foldl (\a acc -> acc + a.valueGp) 0


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


{-| Editor mutation: replace one bracket's individual-treasure
rows wholesale. The editor parses inputs, builds the new row
list, and hands it here.
-}
setIndividualRows :
    Bracket
    -> List IndividualEntry
    -> TreasureTable
    -> TreasureTable
setIndividualRows bracket rows table =
    { table
        | individualBrackets =
            Dict.insert (bracketWire bracket) rows table.individualBrackets
    }


{-| Editor mutation: replace one bracket's hoard rows wholesale.
-}
setHoardRows : Bracket -> List HoardEntry -> TreasureTable -> TreasureTable
setHoardRows bracket rows table =
    { table
        | hoardBrackets =
            Dict.insert (bracketWire bracket) rows table.hoardBrackets
    }



-- ── GENERATOR ────────────────────────────────────────────────────────────────


{-| Roll fresh treasure for the chosen kind against the
supplied table, drawing per-creature CR brackets from the
context.

Sum rolls iterate `ctx.enemies` and roll each enemy's
matched bracket. Hoard rolls use `ctx.hoardBracket` (the
toughest enemy's bracket). The CR bracket is no longer
user-selectable — the encounter already knows which creatures
are present, so the right bracket falls out naturally.

`settings` wraps the rolls in coarse "more/fewer" + "higher/
lower" knobs (see [`TreasureSettings`](#TreasureSettings)).
Defaults to no-op when the GM hasn't tuned anything.

An empty enemy list short-circuits to an empty roll regardless
of `kind`: no enemies means no creatures to loot, no lair to
plunder. The modal still gets a `Just` treasure record so the
user sees "(no coins)" rather than the un-rolled empty state,
making it clear the click registered but the encounter had no
targets.

-}
generate : TreasureSettings -> Kind -> TreasureTable -> RollContext -> Random.Generator TreasureRoll
generate settings kind table ctx =
    if List.isEmpty ctx.enemies then
        Random.constant (emptyRollFor kind ctx.hoardBracket)

    else
        let
            aggregateLoot =
                List.concatMap .loot ctx.enemies
        in
        case kind of
            Individual ->
                generateIndividualSum settings table ctx.enemies

            Hoard ->
                generateHoard settings ctx.hoardBracket table
                    |> Random.map (\roll -> { roll | loot = aggregateLoot })


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
    TreasureSettings
    -> TreasureTable
    -> RollContext
    -> TreasureRoll
    -> Category
    -> Random.Generator TreasureRoll
generateRerollCategory settings table ctx currentRoll category =
    case currentRoll.source of
        Just source ->
            generateRerollFromSource settings table currentRoll source category

        Nothing ->
            generate settings currentRoll.kind table ctx


generateRerollFromSource :
    TreasureSettings
    -> TreasureTable
    -> TreasureRoll
    -> RowSource
    -> Category
    -> Random.Generator TreasureRoll
generateRerollFromSource settings table currentRoll source category =
    let
        scaffold =
            emptyRollFor currentRoll.kind currentRoll.bracket
    in
    case category of
        CoinsCategory ->
            rollCoinsFromFormulas settings source.coinFormulas
                |> Random.map (\coins -> { scaffold | coins = coins })

        GemsCategory ->
            rollGems settings table source.gemsSpec
                |> Random.map (\gems -> { scaffold | gems = gems })

        ArtCategory ->
            rollArt settings table source.artSpec
                |> Random.map (\art -> { scaffold | art = art })

        MagicCategory ->
            rollMagic settings table source.magicSpec
                |> Random.map (\magic -> { scaffold | magic = magic })

        MundaneCategory ->
            rollMundane settings currentRoll.bracket table
                |> Random.map (\mundane -> { scaffold | mundane = mundane })

        WeaponsCategory ->
            rollWeapons settings currentRoll.bracket table
                |> Random.map (\weapons -> { scaffold | weapons = weapons })

        ArmorCategory ->
            rollArmor settings currentRoll.bracket table
                |> Random.map (\armor -> { scaffold | armor = armor })


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
    , mundane = []
    , weapons = []
    , armor = []
    , source = Nothing
    , contributions = []
    , loot = []
    }


rollCoinsFromFormulas : TreasureSettings -> CoinFormulas -> Random.Generator Coins
rollCoinsFromFormulas settings formulas =
    rollIndividualCoins settings
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
    TreasureSettings
    -> TreasureTable
    -> List EnemyInfo
    -> Random.Generator TreasureRoll
generateIndividualSum settings table enemies =
    sequenceList (List.map (rollOneEnemy settings table) enemies)
        |> Random.map
            (\contributions ->
                { kind = Individual
                , bracket = highestContributionBracket contributions
                , coins = sumContributions contributions
                , gems = List.concatMap .gems contributions
                , art = []
                , magic = []
                , mundane = []
                , weapons = []
                , armor = []
                , source = Nothing
                , contributions = contributions
                , loot = List.concatMap .loot contributions
                }
            )


rollOneEnemy : TreasureSettings -> TreasureTable -> EnemyInfo -> Random.Generator CreatureContribution
rollOneEnemy settings table enemy =
    let
        rows =
            individualRowsFor enemy.bracket table
    in
    weightedPick rows emptyIndividualRow
        |> Random.andThen
            (\row ->
                rollIndividualCoins settings row
                    |> Random.andThen (maybeConvertGoldToGem settings table enemy)
            )
        |> Random.map (\c -> { c | loot = enemy.loot })


{-| Per-creature post-process: with some probability, swap some
of the rolled gold for a bracket-appropriate gem of equal value.
Models the SRD-isn't-very-explicit reality that creatures
carry pocket gems alongside their coin, without inflating the
encounter's total expected treasure value (the gem replaces gp
1-for-1).

Conversion only triggers when the creature has enough gold to
pay for the gem outright, so total value is exactly preserved.
Probability + tier pool are tuned to keep gems uncommon but
not vanishingly rare at the bracket's typical loot scale.

-}
maybeConvertGoldToGem :
    TreasureSettings
    -> TreasureTable
    -> EnemyInfo
    -> Coins
    -> Random.Generator CreatureContribution
maybeConvertGoldToGem settings table enemy coins =
    let
        affordableTiers =
            individualGemTiers enemy.bracket
                |> List.map (shiftGemTier settings.gemsValue)
                |> List.filter (\t -> coins.gold >= Tables.gemTierValue t)

        baseContribution =
            { creatureName = enemy.name
            , coins = coins
            , gems = []
            , loot = []
            , bracket = enemy.bracket
            }
    in
    case affordableTiers of
        [] ->
            Random.constant baseContribution

        first :: rest ->
            Random.weighted ( 70, False ) [ ( 30, True ) ]
                |> Random.andThen
                    (\shouldConvert ->
                        if shouldConvert then
                            convertOneGem table baseContribution first rest

                        else
                            Random.constant baseContribution
                    )


{-| Bracket-appropriate gem tiers for an individual-loot
conversion. Caps below the bracket's hoard-tier ceilings on
purpose — pocket gems shouldn't rival the lair stash.
-}
individualGemTiers : Bracket -> List GemTier
individualGemTiers bracket =
    case bracket of
        B1to4 ->
            [ Tables.Gem10gp, Tables.Gem50gp ]

        B5to10 ->
            [ Tables.Gem10gp, Tables.Gem50gp, Tables.Gem100gp ]

        B11to16 ->
            [ Tables.Gem100gp, Tables.Gem500gp ]

        B17plus ->
            [ Tables.Gem500gp, Tables.Gem1000gp ]


convertOneGem :
    TreasureTable
    -> CreatureContribution
    -> GemTier
    -> List GemTier
    -> Random.Generator CreatureContribution
convertOneGem table contribution firstTier restTiers =
    Random.uniform firstTier restTiers
        |> Random.andThen
            (\tier ->
                let
                    tierValue =
                        Tables.gemTierValue tier

                    names =
                        gemNamesFor tier table
                in
                case names of
                    [] ->
                        Random.constant contribution

                    n :: ns ->
                        Random.uniform n ns
                            |> Random.map
                                (\name ->
                                    let
                                        gem =
                                            { name = name, valueGp = tierValue }

                                        coins =
                                            contribution.coins

                                        reducedCoins =
                                            { coins | gold = coins.gold - tierValue }
                                    in
                                    { contribution
                                        | coins = reducedCoins
                                        , gems = [ gem ]
                                    }
                                )
            )


highestContributionBracket : List CreatureContribution -> Bracket
highestContributionBracket contributions =
    case contributions of
        [] ->
            B1to4

        head :: rest ->
            List.foldl
                (\c acc ->
                    if bracketIndex c.bracket > bracketIndex acc then
                        c.bracket

                    else
                        acc
                )
                head.bracket
                rest


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


rollIndividualCoins : TreasureSettings -> IndividualEntry -> Random.Generator Coins
rollIndividualCoins settings row =
    if settings.coinsNone then
        Random.constant emptyCoins

    else
        rollIndividualCoinsInner settings row


rollIndividualCoinsInner : TreasureSettings -> IndividualEntry -> Random.Generator Coins
rollIndividualCoinsInner settings row =
    let
        roll mFormula =
            case mFormula of
                Just ( count, faces, mult ) ->
                    adjustCount settings.coinsCount count
                        |> Random.andThen
                            (\adjusted ->
                                rollDiceTimes adjusted faces
                                    |> Random.map (\n -> n * mult)
                            )

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


generateHoard : TreasureSettings -> Bracket -> TreasureTable -> Random.Generator TreasureRoll
generateHoard settings bracket table =
    let
        rows =
            hoardRowsFor bracket table
    in
    weightedPick rows emptyHoardRow
        |> Random.andThen
            (\row ->
                -- Random.map only goes up to map5, so the seven
                -- category slices land via nested map5 + andThen
                -- pairs.  All three opt-in category generators
                -- short-circuit to [] when their None toggle is on
                -- (or when their item list is empty), so this is
                -- cheap when those toggles are off.
                Random.map5
                    (\coins gems art magic mundane ->
                        { coins = coins
                        , gems = gems
                        , art = art
                        , magic = magic
                        , mundane = mundane
                        }
                    )
                    (rollHoardCoins settings row)
                    (rollGems settings table row.gems)
                    (rollArt settings table row.art)
                    (rollMagic settings table row.magic)
                    (rollMundane settings bracket table)
                    |> Random.andThen
                        (\rolled ->
                            Random.map2
                                (\weapons armor ->
                                    { kind = Hoard
                                    , bracket = bracket
                                    , coins = rolled.coins
                                    , gems = rolled.gems
                                    , art = rolled.art
                                    , magic = rolled.magic
                                    , mundane = rolled.mundane
                                    , weapons = weapons
                                    , armor = armor
                                    , source = Just (sourceFromHoard row)
                                    , contributions = []

                                    -- Loot is layered onto the roll in
                                    -- `generate` after this returns (uses the
                                    -- caller's aggregated enemy loot list).
                                    , loot = []
                                    }
                                )
                                (rollWeapons settings bracket table)
                                (rollArmor settings bracket table)
                        )
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


rollHoardCoins : TreasureSettings -> HoardEntry -> Random.Generator Coins
rollHoardCoins settings row =
    rollIndividualCoins settings
        { weight = row.weight
        , copper = row.copper
        , silver = row.silver
        , electrum = row.electrum
        , gold = row.gold
        , platinum = row.platinum
        }


rollGems : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, GemTier ) -> Random.Generator (List GemItem)
rollGems settings table mSpec =
    if settings.gemsNone then
        Random.constant []

    else
        rollGemsInner settings table mSpec


rollGemsInner : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, GemTier ) -> Random.Generator (List GemItem)
rollGemsInner settings table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            let
                adjustedTier =
                    shiftGemTier settings.gemsValue tier
            in
            adjustCount settings.gemsCount count
                |> Random.andThen
                    (\adjustedCount ->
                        rollDiceTimes adjustedCount faces
                            |> Random.andThen
                                (\n ->
                                    pickN n (gemNamesFor adjustedTier table)
                                        |> Random.map
                                            (List.map
                                                (\name ->
                                                    { name = name
                                                    , valueGp = Tables.gemTierValue adjustedTier
                                                    }
                                                )
                                            )
                                )
                    )
                |> Random.andThen (splitGems table)


{-| Post-process for rolled hoard gems: with 25% probability per
gem, "split" a high-tier gem into N gems of the next tier down
where N is exactly the tier-value ratio. By construction the
total gp value is preserved.

  - 50gp → 5 × 10gp
  - 100gp → 2 × 50gp
  - 500gp → 5 × 100gp
  - 1000gp → 2 × 500gp
  - 5000gp → 5 × 1000gp

10gp gems can't split further. The replacement gem names are
drawn from the user's treasure table at the target tier so
edits to the gem lists carry through.

-}
splitGems : TreasureTable -> List GemItem -> Random.Generator (List GemItem)
splitGems table gems =
    sequenceList (List.map (maybeSplitOneGem table) gems)
        |> Random.map List.concat


maybeSplitOneGem : TreasureTable -> GemItem -> Random.Generator (List GemItem)
maybeSplitOneGem table gem =
    case splitTargetFor gem of
        Nothing ->
            Random.constant [ gem ]

        Just ( lowerTier, count ) ->
            Random.weighted ( 75, False ) [ ( 25, True ) ]
                |> Random.andThen
                    (\shouldSplit ->
                        if shouldSplit then
                            rollLowerGems table lowerTier count

                        else
                            Random.constant [ gem ]
                    )


{-| Map a gem to its (lower tier, count) split target — chosen
so count × lower\_tier\_value == gem\_value, preserving total gp.
-}
splitTargetFor : GemItem -> Maybe ( GemTier, Int )
splitTargetFor gem =
    case gem.valueGp of
        50 ->
            Just ( Tables.Gem10gp, 5 )

        100 ->
            Just ( Tables.Gem50gp, 2 )

        500 ->
            Just ( Tables.Gem100gp, 5 )

        1000 ->
            Just ( Tables.Gem500gp, 2 )

        5000 ->
            Just ( Tables.Gem1000gp, 5 )

        _ ->
            Nothing


rollLowerGems : TreasureTable -> GemTier -> Int -> Random.Generator (List GemItem)
rollLowerGems table tier count =
    let
        tierValue =
            Tables.gemTierValue tier

        names =
            gemNamesFor tier table
    in
    case names of
        [] ->
            Random.constant []

        first :: rest ->
            Random.list count (Random.uniform first rest)
                |> Random.map
                    (List.map
                        (\name ->
                            { name = name, valueGp = tierValue }
                        )
                    )


rollArt : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, ArtTier ) -> Random.Generator (List ArtItem)
rollArt settings table mSpec =
    if settings.artNone then
        Random.constant []

    else
        rollArtInner settings table mSpec


rollArtInner : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, ArtTier ) -> Random.Generator (List ArtItem)
rollArtInner settings table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, tier ) ->
            let
                adjustedTier =
                    shiftArtTier settings.artValue tier
            in
            adjustCount settings.artCount count
                |> Random.andThen
                    (\adjustedCount ->
                        rollDiceTimes adjustedCount faces
                            |> Random.andThen
                                (\n ->
                                    pickN n (artNamesFor adjustedTier table)
                                        |> Random.map
                                            (List.map
                                                (\name ->
                                                    { name = name
                                                    , valueGp = Tables.artTierValue adjustedTier
                                                    }
                                                )
                                            )
                                )
                    )


rollMagic : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, MagicTable ) -> Random.Generator (List MagicItem)
rollMagic settings table mSpec =
    if settings.magicNone then
        Random.constant []

    else
        rollMagicInner settings table mSpec
            |> Random.andThen (applyScrollPostProcess settings table)


{-| Post-process the magic-item list: for each item, roll d100
against `magicScrollChance`; if it hits, swap the item for a
"Spell Scroll (level): name" entry at the same rarity, with the
spell name drawn from the user's level-keyed scroll-spell list.
A chance of 0 short-circuits to the unchanged list. Items whose
spell-list is empty also pass through unchanged so the GM can
clear the list to opt out per-level.
-}
applyScrollPostProcess :
    TreasureSettings
    -> TreasureTable
    -> List MagicItem
    -> Random.Generator (List MagicItem)
applyScrollPostProcess settings table items =
    if settings.magicScrollChance <= 0 then
        Random.constant items

    else
        items
            |> List.map (maybeSwapForScroll settings table)
            |> sequenceList


maybeSwapForScroll :
    TreasureSettings
    -> TreasureTable
    -> MagicItem
    -> Random.Generator MagicItem
maybeSwapForScroll settings table item =
    Random.int 1 100
        |> Random.andThen
            (\roll ->
                if roll > settings.magicScrollChance then
                    Random.constant item

                else
                    pickScrollFor item table
                        |> Random.map (Maybe.withDefault item)
            )


pickScrollFor : MagicItem -> TreasureTable -> Random.Generator (Maybe MagicItem)
pickScrollFor item table =
    pickScrollLevelFor item.rarity
        |> Random.andThen
            (\level ->
                case scrollSpellsFor level table of
                    [] ->
                        -- GM cleared this level's list — opt-out.
                        Random.constant Nothing

                    first :: rest ->
                        Random.uniform first rest
                            |> Random.map
                                (\spellName ->
                                    Just
                                        { item
                                            | name =
                                                "Spell Scroll ("
                                                    ++ ScrollSpells.scrollLevelLabel level
                                                    ++ "): "
                                                    ++ spellName
                                        }
                                )
            )


{-| Map an item rarity to a scroll level (or a small distribution
when the rarity spans more than one level). Mapping mirrors the
DMG's rarity-to-scroll-level guidance.
-}
pickScrollLevelFor : Rarity -> Random.Generator ScrollSpells.ScrollLevel
pickScrollLevelFor rarity =
    case rarity of
        Tables.Common ->
            Random.uniform ScrollSpells.ScrollCantrip [ ScrollSpells.Scroll1st ]

        Tables.Uncommon ->
            Random.uniform ScrollSpells.Scroll2nd [ ScrollSpells.Scroll3rd ]

        Tables.Rare ->
            Random.uniform ScrollSpells.Scroll4th [ ScrollSpells.Scroll5th ]

        Tables.VeryRare ->
            Random.uniform ScrollSpells.Scroll6th
                [ ScrollSpells.Scroll7th, ScrollSpells.Scroll8th ]

        Tables.Legendary ->
            Random.constant ScrollSpells.Scroll9th


rollMagicInner : TreasureSettings -> TreasureTable -> Maybe ( Int, Int, MagicTable ) -> Random.Generator (List MagicItem)
rollMagicInner settings table mSpec =
    case mSpec of
        Nothing ->
            Random.constant []

        Just ( count, faces, magicTable ) ->
            let
                adjustedTable =
                    shiftMagicTable settings.magicValue magicTable
            in
            adjustCount settings.magicCount count
                |> Random.andThen
                    (\adjustedCount ->
                        rollDiceTimes adjustedCount faces
                            |> Random.andThen
                                (\n ->
                                    pickN n (magicNamesFor adjustedTable table)
                                        |> Random.map
                                            (List.map
                                                (\name ->
                                                    { name = name
                                                    , rarity = Tables.magicTableRarity adjustedTable
                                                    , table = adjustedTable
                                                    }
                                                )
                                            )
                                )
                    )


{-| Roll a flat (name, gp) category — the shared shape for
mundane / weapons / armor. When the None toggle is on, or the
item list is empty, returns the empty list without rolling.
-}
rollFlatCategory :
    Bool
    -> CountAdjust
    -> ( Int, Int )
    -> List { item | name : String, valueGp : Int }
    -> Random.Generator (List { item | name : String, valueGp : Int })
rollFlatCategory none countAdj ( count, faces ) items =
    if none || List.isEmpty items then
        Random.constant []

    else
        adjustCount countAdj count
            |> Random.andThen
                (\adjustedCount ->
                    rollDiceTimes adjustedCount faces
                        |> Random.andThen (\n -> pickItemsN n items)
                )


rollMundane : TreasureSettings -> Bracket -> TreasureTable -> Random.Generator (List MundaneItem)
rollMundane settings bracket table =
    rollFlatCategory settings.mundaneNone
        settings.mundaneCount
        (mundaneRollFor bracket table)
        (mundaneItemsFor table)


rollWeapons : TreasureSettings -> Bracket -> TreasureTable -> Random.Generator (List WeaponItem)
rollWeapons settings bracket table =
    rollFlatCategory settings.weaponsNone
        settings.weaponsCount
        (weaponsRollFor bracket table)
        (weaponsItemsFor table)


rollArmor : TreasureSettings -> Bracket -> TreasureTable -> Random.Generator (List ArmorItem)
rollArmor settings bracket table =
    rollFlatCategory settings.armorNone
        settings.armorCount
        (armorRollFor bracket table)
        (armorItemsFor table)


{-| Pick `n` items (with replacement, since the flat categories
have small lists where uniqueness isn't an SRD requirement).
Returns at most `n` items; when the list is empty, returns [].
-}
pickItemsN : Int -> List a -> Random.Generator (List a)
pickItemsN n items =
    case items of
        [] ->
            Random.constant []

        first :: _ ->
            Random.list n (Random.uniform first items)



-- ── SETTINGS → SPEC ADJUSTMENTS ─────────────────────────────────────────────


{-| Coarse multiplier on dice count.

  - **Fewer** = ⌊n/2⌋ for n ≥ 2. For single-die specs (n=1) the
    integer floor would either stay at 1 (no effect) or jump to
    0 (always-none) — neither matches the GM's intent. Instead
    we return a 50/50 Generator over {0, 1}, so a "Fewer Magic"
    roll on a 1d6 spec produces no items half the time and 1
    item the other half, averaging to "fewer" without
    eliminating the class outright.
  - **More** = n + max 1 ⌊n/2⌋. The `max 1` matters for single-die
    specs: a 1d-something would otherwise round to 1+0 == 1 with
    no effect, so we bump it to 2 instead. Every SRD magic-item
    spec uses 1d-something, so without this clamp the Magic
    Count knob would silently do nothing.

The `n ≤ 0` guard up front protects rows whose category was
already absent (no gem spec on this row, say) — those rolls
shouldn't suddenly grow items under "More".

-}
adjustCount : CountAdjust -> Int -> Random.Generator Int
adjustCount adj n =
    if n <= 0 then
        Random.constant 0

    else
        case adj of
            CountFewer ->
                if n == 1 then
                    Random.weighted ( 50, 0 ) [ ( 50, 1 ) ]

                else
                    Random.constant (n // 2)

            CountNormal ->
                Random.constant n

            CountMore ->
                Random.constant (n + max 1 (n // 2))


{-| Shift a gem tier up or down one step. Capped at the
extremes — `Higher` on the top tier is a no-op, same on the
floor for `Lower`.
-}
shiftGemTier : ValueAdjust -> GemTier -> GemTier
shiftGemTier adj tier =
    case adj of
        ValueNormal ->
            tier

        ValueLower ->
            case tier of
                Tables.Gem10gp ->
                    Tables.Gem10gp

                Tables.Gem50gp ->
                    Tables.Gem10gp

                Tables.Gem100gp ->
                    Tables.Gem50gp

                Tables.Gem500gp ->
                    Tables.Gem100gp

                Tables.Gem1000gp ->
                    Tables.Gem500gp

                Tables.Gem5000gp ->
                    Tables.Gem1000gp

        ValueHigher ->
            case tier of
                Tables.Gem10gp ->
                    Tables.Gem50gp

                Tables.Gem50gp ->
                    Tables.Gem100gp

                Tables.Gem100gp ->
                    Tables.Gem500gp

                Tables.Gem500gp ->
                    Tables.Gem1000gp

                Tables.Gem1000gp ->
                    Tables.Gem5000gp

                Tables.Gem5000gp ->
                    Tables.Gem5000gp


shiftArtTier : ValueAdjust -> ArtTier -> ArtTier
shiftArtTier adj tier =
    case adj of
        ValueNormal ->
            tier

        ValueLower ->
            case tier of
                Tables.Art25gp ->
                    Tables.Art25gp

                Tables.Art250gp ->
                    Tables.Art25gp

                Tables.Art750gp ->
                    Tables.Art250gp

                Tables.Art2500gp ->
                    Tables.Art750gp

                Tables.Art7500gp ->
                    Tables.Art2500gp

        ValueHigher ->
            case tier of
                Tables.Art25gp ->
                    Tables.Art250gp

                Tables.Art250gp ->
                    Tables.Art750gp

                Tables.Art750gp ->
                    Tables.Art2500gp

                Tables.Art2500gp ->
                    Tables.Art7500gp

                Tables.Art7500gp ->
                    Tables.Art7500gp


shiftMagicTable : ValueAdjust -> MagicTable -> MagicTable
shiftMagicTable adj t =
    case adj of
        ValueNormal ->
            t

        ValueLower ->
            case t of
                Tables.TableA ->
                    Tables.TableA

                Tables.TableB ->
                    Tables.TableA

                Tables.TableC ->
                    Tables.TableB

                Tables.TableD ->
                    Tables.TableC

                Tables.TableE ->
                    Tables.TableD

                Tables.TableF ->
                    Tables.TableE

                Tables.TableG ->
                    Tables.TableF

                Tables.TableH ->
                    Tables.TableG

                Tables.TableI ->
                    Tables.TableH

        ValueHigher ->
            case t of
                Tables.TableA ->
                    Tables.TableB

                Tables.TableB ->
                    Tables.TableC

                Tables.TableC ->
                    Tables.TableD

                Tables.TableD ->
                    Tables.TableE

                Tables.TableE ->
                    Tables.TableF

                Tables.TableF ->
                    Tables.TableG

                Tables.TableG ->
                    Tables.TableH

                Tables.TableH ->
                    Tables.TableI

                Tables.TableI ->
                    Tables.TableI



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
