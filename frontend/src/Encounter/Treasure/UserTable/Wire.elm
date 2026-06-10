module Encounter.Treasure.UserTable.Wire exposing
    ( encodeTables, decodeTables
    , encodeTable, decodeTable
    )

{-| Wire codec for the per-user user-authored treasure-table
list.

The shape that crosses the wire / lands in localStorage is:

    {
      "tables": [
        {
          "id": "ut-1717280000-123",
          "name": "Pirate Cove",
          "entries": [
            { "label": "Smoking Censer", "weight": 2, "gpValue": 25, "rarity": "rare" },
            ...
          ]
        }
      ]
    }

A top-level object (rather than a bare array) leaves room to
grow the wrapper later (versioning, settings) without another
backward-compat shim.

@docs encodeTables, decodeTables
@docs encodeTable, decodeTable

-}

import Encounter.Treasure.Tables exposing (Rarity(..))
import Encounter.Treasure.UserTable exposing (Entry, UserTable)
import Json.Decode as D
import Json.Encode as E



-- ── ENCODE ──────────────────────────────────────────────────────────────────


encodeTables : List UserTable -> E.Value
encodeTables tables =
    E.object [ ( "tables", E.list encodeTable tables ) ]


encodeTable : UserTable -> E.Value
encodeTable table =
    E.object
        [ ( "id", E.string table.id )
        , ( "name", E.string table.name )
        , ( "entries", E.list encodeEntry table.entries )
        ]


encodeEntry : Entry -> E.Value
encodeEntry entry =
    E.object
        [ ( "label", E.string entry.label )
        , ( "weight", E.int entry.weight )
        , ( "gpValue", maybe E.int entry.gpValue )
        , ( "rarity", maybe (rarityWire >> E.string) entry.rarity )
        ]


maybe : (a -> E.Value) -> Maybe a -> E.Value
maybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null


rarityWire : Rarity -> String
rarityWire r =
    case r of
        Common ->
            "common"

        Uncommon ->
            "uncommon"

        Rare ->
            "rare"

        VeryRare ->
            "very-rare"

        Legendary ->
            "legendary"



-- ── DECODE ──────────────────────────────────────────────────────────────────


{-| Decode the wire shape into a table list. Accepts both the
wrapper `{"tables": [...]}` and a bare array — the server
returns `null` when the user has nothing saved, which Decode
catches at the call site (the runtime supplies `[]` then).
-}
decodeTables : D.Decoder (List UserTable)
decodeTables =
    D.oneOf
        [ D.field "tables" (D.list decodeTable)
        , D.list decodeTable
        ]


decodeTable : D.Decoder UserTable
decodeTable =
    D.map3 UserTable
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "entries" (D.list decodeEntry))


decodeEntry : D.Decoder Entry
decodeEntry =
    D.map4 Entry
        (D.field "label" D.string)
        (D.oneOf [ D.field "weight" D.int, D.succeed 1 ])
        (D.oneOf
            [ D.field "gpValue" (D.nullable D.int)
            , D.succeed Nothing
            ]
        )
        (D.oneOf
            [ D.field "rarity" (D.nullable rarityDecoder)
            , D.succeed Nothing
            ]
        )


rarityDecoder : D.Decoder Rarity
rarityDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "common" ->
                        D.succeed Common

                    "uncommon" ->
                        D.succeed Uncommon

                    "rare" ->
                        D.succeed Rare

                    "very-rare" ->
                        D.succeed VeryRare

                    "legendary" ->
                        D.succeed Legendary

                    other ->
                        D.fail ("Unknown rarity: " ++ other)
            )
