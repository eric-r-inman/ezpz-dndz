module Encounter.Treasure.TableWire exposing
    ( decodeTable
    , encodeTable
    )

{-| Wire codec for the singular per-user `TreasureTable`.

The JSON shape mirrors the Elm record:

    { "individualBrackets": { "1to4": [...rows], ... }
    , "hoardBrackets":      { "1to4": [...rows], ... }
    , "gems":               { "50gp": ["Bloodstone", ...], ... }
    , "art":                { "25gp": ["Silver ewer", ...], ... }
    , "magic":              { "A": ["Potion of Healing", ...], ... }
    }

Row entries are full records (weights + coin formulas + the
optional gem/art/magic sub-roll specs); the codec round-trips
those tuples through `{ "count": ..., "faces": ..., ... }` JSON
objects so they stay readable in a database or backup.

-}

import Dict exposing (Dict)
import Encounter.Treasure exposing (TreasureTable)
import Encounter.Treasure.Tables
    exposing
        ( ArtTier(..)
        , GemTier(..)
        , HoardEntry
        , IndividualEntry
        , MagicTable(..)
        )
import Json.Decode as D
import Json.Encode as E



-- ── ENCODE ──────────────────────────────────────────────────────────────────


encodeTable : TreasureTable -> E.Value
encodeTable table =
    E.object
        [ ( "individualBrackets", encodeDictList encodeIndividualEntry table.individualBrackets )
        , ( "hoardBrackets", encodeDictList encodeHoardEntry table.hoardBrackets )
        , ( "gems", encodeDictList E.string table.gems )
        , ( "art", encodeDictList E.string table.art )
        , ( "magic", encodeDictList E.string table.magic )
        , ( "mundane", E.list encodeFlatItem table.mundane )
        , ( "mundaneRoll", encodeBracketSpec table.mundaneRoll )
        , ( "weapons", E.list encodeFlatItem table.weapons )
        , ( "weaponsRoll", encodeBracketSpec table.weaponsRoll )
        , ( "armor", E.list encodeFlatItem table.armor )
        , ( "armorRoll", encodeBracketSpec table.armorRoll )
        ]


encodeFlatItem : { item | name : String, valueGp : Int } -> E.Value
encodeFlatItem item =
    E.object
        [ ( "name", E.string item.name )
        , ( "valueGp", E.int item.valueGp )
        ]


encodeBracketSpec : Dict String ( Int, Int ) -> E.Value
encodeBracketSpec dict =
    Dict.toList dict
        |> List.map
            (\( k, ( count, faces ) ) ->
                ( k
                , E.object
                    [ ( "count", E.int count )
                    , ( "faces", E.int faces )
                    ]
                )
            )
        |> E.object


encodeDictList : (a -> E.Value) -> Dict String (List a) -> E.Value
encodeDictList encodeItem dict =
    Dict.toList dict
        |> List.map (\( k, items ) -> ( k, E.list encodeItem items ))
        |> E.object


encodeIndividualEntry : IndividualEntry -> E.Value
encodeIndividualEntry row =
    E.object
        [ ( "weight", E.int row.weight )
        , ( "copper", encodeMaybe encodeCoinFormula row.copper )
        , ( "silver", encodeMaybe encodeCoinFormula row.silver )
        , ( "electrum", encodeMaybe encodeCoinFormula row.electrum )
        , ( "gold", encodeMaybe encodeCoinFormula row.gold )
        , ( "platinum", encodeMaybe encodeCoinFormula row.platinum )
        ]


encodeHoardEntry : HoardEntry -> E.Value
encodeHoardEntry row =
    E.object
        [ ( "weight", E.int row.weight )
        , ( "copper", encodeMaybe encodeCoinFormula row.copper )
        , ( "silver", encodeMaybe encodeCoinFormula row.silver )
        , ( "electrum", encodeMaybe encodeCoinFormula row.electrum )
        , ( "gold", encodeMaybe encodeCoinFormula row.gold )
        , ( "platinum", encodeMaybe encodeCoinFormula row.platinum )
        , ( "gems", encodeMaybe (encodeSpec gemTierWire) row.gems )
        , ( "art", encodeMaybe (encodeSpec artTierWire) row.art )
        , ( "magic", encodeMaybe (encodeSpec magicTableWire) row.magic )
        ]


encodeCoinFormula : ( Int, Int, Int ) -> E.Value
encodeCoinFormula ( count, faces, mult ) =
    E.object
        [ ( "count", E.int count )
        , ( "faces", E.int faces )
        , ( "mult", E.int mult )
        ]


encodeSpec : (tier -> String) -> ( Int, Int, tier ) -> E.Value
encodeSpec tierToWire ( count, faces, tier ) =
    E.object
        [ ( "count", E.int count )
        , ( "faces", E.int faces )
        , ( "tier", E.string (tierToWire tier) )
        ]


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null



-- ── DECODE ──────────────────────────────────────────────────────────────────


{-| Decode a saved treasure table. The five legacy fields come
through `D.map5`, then the six new opt-in-category fields fold
in via `andThen` since elm/json caps `map` at 8 (5 + 6 > 8).
Each new field is missing-field tolerant so tables saved before
the Mundane / Weapons / Armor categories load cleanly with the
bundled defaults — that way a one-time upgrade doesn't have to
mass-mutate everyone's saved tables.
-}
decodeTable : D.Decoder TreasureTable
decodeTable =
    D.map5
        (\individualBrackets hoardBrackets gems art magic ->
            { individualBrackets = individualBrackets
            , hoardBrackets = hoardBrackets
            , gems = gems
            , art = art
            , magic = magic
            , mundane = []
            , mundaneRoll = Dict.empty
            , weapons = []
            , weaponsRoll = Dict.empty
            , armor = []
            , armorRoll = Dict.empty
            }
        )
        (D.field "individualBrackets" (decodeDictList decodeIndividualEntry))
        (D.field "hoardBrackets" (decodeDictList decodeHoardEntry))
        (D.field "gems" (decodeDictList D.string))
        (D.field "art" (decodeDictList D.string))
        (D.field "magic" (decodeDictList D.string))
        |> D.andThen
            (\partial ->
                D.map3
                    (\mundane weapons armor ->
                        { partial
                            | mundane = Tuple.first mundane
                            , mundaneRoll = Tuple.second mundane
                            , weapons = Tuple.first weapons
                            , weaponsRoll = Tuple.second weapons
                            , armor = Tuple.first armor
                            , armorRoll = Tuple.second armor
                        }
                    )
                    (decodeFlatCategory "mundane")
                    (decodeFlatCategory "weapons")
                    (decodeFlatCategory "armor")
            )


decodeFlatCategory : String -> D.Decoder ( List { name : String, valueGp : Int }, Dict String ( Int, Int ) )
decodeFlatCategory baseName =
    D.map2 Tuple.pair
        (D.oneOf
            [ D.field baseName (D.list decodeFlatItem)
            , D.succeed []
            ]
        )
        (D.oneOf
            [ D.field (baseName ++ "Roll") (D.dict decodeBracketSpec)
            , D.succeed Dict.empty
            ]
        )


decodeFlatItem : D.Decoder { name : String, valueGp : Int }
decodeFlatItem =
    D.map2 (\name value -> { name = name, valueGp = value })
        (D.field "name" D.string)
        (D.field "valueGp" D.int)


decodeBracketSpec : D.Decoder ( Int, Int )
decodeBracketSpec =
    D.map2 Tuple.pair
        (D.field "count" D.int)
        (D.field "faces" D.int)


decodeDictList : D.Decoder a -> D.Decoder (Dict String (List a))
decodeDictList itemDecoder =
    D.dict (D.list itemDecoder)


decodeIndividualEntry : D.Decoder IndividualEntry
decodeIndividualEntry =
    D.map6 IndividualEntry
        (D.field "weight" D.int)
        (decodeOptionalField "copper" decodeCoinFormula)
        (decodeOptionalField "silver" decodeCoinFormula)
        (decodeOptionalField "electrum" decodeCoinFormula)
        (decodeOptionalField "gold" decodeCoinFormula)
        (decodeOptionalField "platinum" decodeCoinFormula)


decodeHoardEntry : D.Decoder HoardEntry
decodeHoardEntry =
    D.map6
        (\weight copper silver electrum gold platinum ->
            { weight = weight
            , copper = copper
            , silver = silver
            , electrum = electrum
            , gold = gold
            , platinum = platinum
            }
        )
        (D.field "weight" D.int)
        (decodeOptionalField "copper" decodeCoinFormula)
        (decodeOptionalField "silver" decodeCoinFormula)
        (decodeOptionalField "electrum" decodeCoinFormula)
        (decodeOptionalField "gold" decodeCoinFormula)
        (decodeOptionalField "platinum" decodeCoinFormula)
        |> D.andThen
            (\base ->
                D.map3
                    (\gems art magic ->
                        { weight = base.weight
                        , copper = base.copper
                        , silver = base.silver
                        , electrum = base.electrum
                        , gold = base.gold
                        , platinum = base.platinum
                        , gems = gems
                        , art = art
                        , magic = magic
                        }
                    )
                    (decodeOptionalField "gems" (decodeSpec gemTierDecoder))
                    (decodeOptionalField "art" (decodeSpec artTierDecoder))
                    (decodeOptionalField "magic" (decodeSpec magicTableDecoder))
            )


decodeOptionalField : String -> D.Decoder a -> D.Decoder (Maybe a)
decodeOptionalField name inner =
    D.oneOf
        [ D.field name (D.nullable inner)
        , D.succeed Nothing
        ]


decodeCoinFormula : D.Decoder ( Int, Int, Int )
decodeCoinFormula =
    D.map3 (\a b c -> ( a, b, c ))
        (D.field "count" D.int)
        (D.field "faces" D.int)
        (D.field "mult" D.int)


decodeSpec : D.Decoder tier -> D.Decoder ( Int, Int, tier )
decodeSpec tierDecoder =
    D.map3 (\a b c -> ( a, b, c ))
        (D.field "count" D.int)
        (D.field "faces" D.int)
        (D.field "tier" tierDecoder)



-- ── TIER / TABLE WIRE TOKENS ───────────────────────────────────────────────


gemTierWire : GemTier -> String
gemTierWire t =
    case t of
        Gem10gp ->
            "10gp"

        Gem50gp ->
            "50gp"

        Gem100gp ->
            "100gp"

        Gem500gp ->
            "500gp"

        Gem1000gp ->
            "1000gp"

        Gem5000gp ->
            "5000gp"


gemTierDecoder : D.Decoder GemTier
gemTierDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "10gp" ->
                        D.succeed Gem10gp

                    "50gp" ->
                        D.succeed Gem50gp

                    "100gp" ->
                        D.succeed Gem100gp

                    "500gp" ->
                        D.succeed Gem500gp

                    "1000gp" ->
                        D.succeed Gem1000gp

                    "5000gp" ->
                        D.succeed Gem5000gp

                    other ->
                        D.fail ("Unknown gem tier: " ++ other)
            )


artTierWire : ArtTier -> String
artTierWire t =
    case t of
        Art25gp ->
            "25gp"

        Art250gp ->
            "250gp"

        Art750gp ->
            "750gp"

        Art2500gp ->
            "2500gp"

        Art7500gp ->
            "7500gp"


artTierDecoder : D.Decoder ArtTier
artTierDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "25gp" ->
                        D.succeed Art25gp

                    "250gp" ->
                        D.succeed Art250gp

                    "750gp" ->
                        D.succeed Art750gp

                    "2500gp" ->
                        D.succeed Art2500gp

                    "7500gp" ->
                        D.succeed Art7500gp

                    other ->
                        D.fail ("Unknown art tier: " ++ other)
            )


magicTableWire : MagicTable -> String
magicTableWire t =
    case t of
        TableA ->
            "A"

        TableB ->
            "B"

        TableC ->
            "C"

        TableD ->
            "D"

        TableE ->
            "E"

        TableF ->
            "F"

        TableG ->
            "G"

        TableH ->
            "H"

        TableI ->
            "I"


magicTableDecoder : D.Decoder MagicTable
magicTableDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "A" ->
                        D.succeed TableA

                    "B" ->
                        D.succeed TableB

                    "C" ->
                        D.succeed TableC

                    "D" ->
                        D.succeed TableD

                    "E" ->
                        D.succeed TableE

                    "F" ->
                        D.succeed TableF

                    "G" ->
                        D.succeed TableG

                    "H" ->
                        D.succeed TableH

                    "I" ->
                        D.succeed TableI

                    other ->
                        D.fail ("Unknown magic-item table: " ++ other)
            )
