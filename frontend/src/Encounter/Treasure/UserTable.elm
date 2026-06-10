module Encounter.Treasure.UserTable exposing
    ( UserTable, Entry, CustomRoll
    , empty, emptyEntry
    , generate
    , totalWeight
    , normalisedWeight
    )

{-| User-authored treasure tables — Phase D of the treasure
generator.

A `UserTable` is a named, weighted list of entries the GM
authors themselves. When the table is rolled, one entry is
picked by weight and surfaces as a `CustomRoll` row inside the
encounter's [`TreasureRoll`](Encounter-Treasure#TreasureRoll).
The roll participates in the same recipients ledger as the SRD
rolls — so "Iridescent Pearl → Alice" works exactly like a gem
row.

Custom tables are useful for recurring villain stashes (Pit
Fiend's hoard), thematic bundles (pirate cove loot, fey
trinket pouch), or quick lookups the SRD doesn't cover.

The schema is deliberately small — the goal is to make the
authoring experience light. If a future need calls for nested
sub-tables or formula-driven coin rolls, this is the place to
grow.

@docs UserTable, Entry, CustomRoll
@docs empty, emptyEntry
@docs generate
@docs totalWeight
@docs normalisedWeight

-}

import Encounter.Treasure.Tables exposing (Rarity)
import Random



-- ── TYPES ────────────────────────────────────────────────────────────────────


{-| One user-authored table. The `id` is a frontend-allocated
slug (timestamp-based) so cross-device round-trips don't
clobber tables that happen to share a name.
-}
type alias UserTable =
    { id : String
    , name : String
    , entries : List Entry
    }


{-| One row in a user table.

  - `label` — the human-readable thing the GM gets ("Iridescent
    Pearl", "Smoking Censer of Bahamut").
  - `weight` — relative pick weight, default 1. Zero entries are
    skipped at roll time.
  - `gpValue` — optional gp tag the row prints next to the
    label ("(50gp)"). Lets gems / coins show their worth without
    forcing the GM to fill it in.
  - `rarity` — optional rarity tag, prints as "(rare)" etc.
    Lets magic-item rows match the SRD aesthetic.

The label is the only required field — everything else is
flavor.

-}
type alias Entry =
    { label : String
    , weight : Int
    , gpValue : Maybe Int
    , rarity : Maybe Rarity
    }


{-| One materialised roll from a user table. Pinned to the
sourcing table by id + name so the modal can render a
"Custom: Pirate Cove" provenance line and the user-table picker
can show which table it came from in the recipients ledger.
-}
type alias CustomRoll =
    { sourceTableId : String
    , sourceTableName : String
    , label : String
    , gpValue : Maybe Int
    , rarity : Maybe Rarity
    }



-- ── CONSTRUCTORS ────────────────────────────────────────────────────────────


{-| Fresh blank table for the editor's "New table" affordance.
The caller is responsible for assigning a unique `id`.
-}
empty : String -> UserTable
empty id =
    { id = id, name = "", entries = [] }


emptyEntry : Entry
emptyEntry =
    { label = "", weight = 1, gpValue = Nothing, rarity = Nothing }



-- ── GENERATION ──────────────────────────────────────────────────────────────


{-| Roll one entry from the table, weighted by `weight`. Returns
`Nothing` when the table has no entries with positive weight —
the modal handles that by suppressing the row and surfacing the
empty-table state to the GM.
-}
generate : UserTable -> Random.Generator (Maybe CustomRoll)
generate table =
    let
        livening =
            List.filter (\e -> e.weight > 0 && not (String.isEmpty (String.trim e.label))) table.entries
    in
    case livening of
        [] ->
            Random.constant Nothing

        first :: rest ->
            Random.weighted
                ( toFloat first.weight, first )
                (List.map (\e -> ( toFloat e.weight, e )) rest)
                |> Random.map
                    (\entry ->
                        Just
                            { sourceTableId = table.id
                            , sourceTableName = table.name
                            , label = entry.label
                            , gpValue = entry.gpValue
                            , rarity = entry.rarity
                            }
                    )



-- ── DISPLAY HELPERS ─────────────────────────────────────────────────────────


totalWeight : UserTable -> Int
totalWeight table =
    List.foldl (\e acc -> acc + max 0 e.weight) 0 table.entries


{-| Express one entry's weight as a percentage of the table
total (rounded to the nearest integer). Returns 0 for empty
tables so the editor can show "0%" cleanly when the GM removes
the last entry.
-}
normalisedWeight : Entry -> UserTable -> Int
normalisedWeight entry table =
    let
        total =
            totalWeight table
    in
    if total <= 0 then
        0

    else
        round (toFloat (max 0 entry.weight) * 100 / toFloat total)
