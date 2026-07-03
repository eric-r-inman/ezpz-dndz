module Encounter.Wire exposing
    ( SavedEncounterMeta
    , decodeEncounter, encodeEncounter
    , fetchEncounterCmd, persistEncounterCmd
    , listSavesCmd, getSaveCmd, putSaveCmd, deleteSaveCmd, renameSaveCmd
    , LocalEncounterSave, decodeLocalEncounterSaves, decodeTreasureSettings, encodeLocalEncounterSaves, encodeTreasureSettings, localSaveToMeta
    )

{-| JSON encoders / decoders for `Encounter` and its referenced
types, plus the HTTP commands that talk to `/api/encounter` (the
single auto-saved live encounter) and `/api/encounter/saves` (the
user-named save files behind the Save / Load modal).

The wire format is whatever round-trips through these encoders —
the server stores the body opaquely (`serde_json::Value`), so
shape changes here don't require a server-side migration as long
as you handle the legacy shape on the decoder side.

The field names mirror the Elm record fields (camelCase) rather
than the Rust-side compendium convention (snake\_case) because
the server doesn't re-model this schema.

@docs SavedEncounterMeta
@docs decodeEncounter, encodeEncounter
@docs fetchEncounterCmd, persistEncounterCmd
@docs listSavesCmd, getSaveCmd, putSaveCmd, deleteSaveCmd, renameSaveCmd

-}

import Dict exposing (Dict)
import Encounter
    exposing
        ( AutoRollMode(..)
        , Condition
        , Cover(..)
        , Creature
        , DeathSaves
        , Duration(..)
        , Encounter
        , SaveNotice
        , SaveToEnd
        , Timer
        , TurnPhase(..)
        , TurnTarget(..)
        )
import Encounter.Treasure
import Encounter.Treasure.Tables
import Http
import Json.Decode as D
import Json.Encode as E
import Set exposing (Set)
import Util.Http



-- ── HTTP COMMANDS ────────────────────────────────────────────────────────────


{-| `GET /api/encounter` — load whatever was last persisted, if
anything. Result is `Result Http.Error (Maybe Encounter)`:

  - `Ok (Just enc)` — server had a saved encounter, decoded
    cleanly. Caller should replace its in-memory encounter.
  - `Ok Nothing` — server returned `null` (nothing saved). Caller
    should keep the empty default.
  - `Err _` — network / decode failure. Caller should keep the
    empty default and surface the error if appropriate.

-}
fetchEncounterCmd :
    (Result Http.Error (Maybe Encounter) -> msg)
    -> Cmd msg
fetchEncounterCmd toMsg =
    Http.get
        { url = "/api/encounter"
        , expect =
            Http.expectJson toMsg
                (D.oneOf
                    [ D.null Nothing
                    , D.map Just decodeEncounter
                    ]
                )
        }


{-| `PUT /api/encounter` — replace the persisted encounter with
the given one. The response body echoes the JSON we sent; we
only care about success / failure for the toast / retry path.
-}
persistEncounterCmd :
    (Result Http.Error () -> msg)
    -> Encounter
    -> Cmd msg
persistEncounterCmd toMsg encounter =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/encounter"
        , body = Http.jsonBody (encodeEncounter encounter)
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }



-- ── NAMED SAVES ──────────────────────────────────────────────────────────────


{-| Server-side metadata for one named save: name + timestamps
(no body). Used by the Save / Load modal listings.
-}
type alias SavedEncounterMeta =
    { name : String
    , createdAt : Int
    , updatedAt : Int
    }


decodeSavedEncounterMeta : D.Decoder SavedEncounterMeta
decodeSavedEncounterMeta =
    D.map3 SavedEncounterMeta
        (D.field "name" D.string)
        (D.field "created_at" D.int)
        (D.field "updated_at" D.int)


{-| `GET /api/encounter/saves` — list named saves (metadata only).
-}
listSavesCmd : (Result Http.Error (List SavedEncounterMeta) -> msg) -> Cmd msg
listSavesCmd toMsg =
    Http.get
        { url = "/api/encounter/saves"
        , expect = Http.expectJson toMsg (D.list decodeSavedEncounterMeta)
        }


{-| `GET /api/encounter/saves/:name` — fetch one save's body.
The server response wraps the encounter in
`{ name, encounter, created_at, updated_at }`; we project down
to just the encounter here so callers don't have to.
-}
getSaveCmd :
    (Result Http.Error Encounter -> msg)
    -> String
    -> Cmd msg
getSaveCmd toMsg name =
    Http.get
        { url = "/api/encounter/saves/" ++ Util.Http.urlPathSegment name
        , expect =
            Http.expectJson toMsg
                (D.field "encounter" decodeEncounter)
        }


{-| `PUT /api/encounter/saves/:name(?overwrite=true)` — create or
replace a named save. When `overwrite` is False the server
returns 409 if the name already exists; when True it upserts.
-}
putSaveCmd :
    (Result Http.Error () -> msg)
    -> { name : String, overwrite : Bool }
    -> Encounter
    -> Cmd msg
putSaveCmd toMsg opts encounter =
    let
        suffix =
            if opts.overwrite then
                "?overwrite=true"

            else
                ""
    in
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/encounter/saves/" ++ Util.Http.urlPathSegment opts.name ++ suffix
        , body = Http.jsonBody (encodeEncounter encounter)
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `DELETE /api/encounter/saves/:name`.
-}
deleteSaveCmd : (Result Http.Error () -> msg) -> String -> Cmd msg
deleteSaveCmd toMsg name =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/encounter/saves/" ++ Util.Http.urlPathSegment name
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


{-| `POST /api/encounter/saves/:name/rename` — body
`{ "new_name": "<new>" }`.
-}
renameSaveCmd :
    (Result Http.Error () -> msg)
    -> { from : String, to : String }
    -> Cmd msg
renameSaveCmd toMsg opts =
    Http.post
        { url = "/api/encounter/saves/" ++ Util.Http.urlPathSegment opts.from ++ "/rename"
        , body =
            Http.jsonBody
                (E.object [ ( "new_name", E.string opts.to ) ])
        , expect = Http.expectWhatever toMsg
        }



-- ── ENCODE ───────────────────────────────────────────────────────────────────


encodeEncounter : Encounter -> E.Value
encodeEncounter enc =
    E.object
        [ ( "creatures", E.list encodeCreature enc.creatures )
        , ( "activeName", E.string enc.activeName )
        , ( "round", E.int enc.round )
        , ( "treasure", encodeMaybe encodeTreasureRoll enc.treasure )
        , ( "treasureSettings", encodeTreasureSettings enc.treasureSettings )
        ]


encodeTreasureSettings : Encounter.Treasure.TreasureSettings -> E.Value
encodeTreasureSettings s =
    E.object
        [ ( "coinsCount", E.string (Encounter.Treasure.countAdjustWire s.coinsCount) )
        , ( "gemsCount", E.string (Encounter.Treasure.countAdjustWire s.gemsCount) )
        , ( "gemsValue", E.string (Encounter.Treasure.valueAdjustWire s.gemsValue) )
        , ( "artCount", E.string (Encounter.Treasure.countAdjustWire s.artCount) )
        , ( "artValue", E.string (Encounter.Treasure.valueAdjustWire s.artValue) )
        , ( "magicCount", E.string (Encounter.Treasure.countAdjustWire s.magicCount) )
        , ( "magicValue", E.string (Encounter.Treasure.valueAdjustWire s.magicValue) )
        , ( "mundaneCount", E.string (Encounter.Treasure.countAdjustWire s.mundaneCount) )
        , ( "weaponsCount", E.string (Encounter.Treasure.countAdjustWire s.weaponsCount) )
        , ( "armorCount", E.string (Encounter.Treasure.countAdjustWire s.armorCount) )
        , ( "hoardToggles", encodeToggles s.hoardToggles )
        , ( "individualToggles", encodeToggles s.individualToggles )
        , ( "magicScrollChance", E.int s.magicScrollChance )
        ]


encodeToggles : Encounter.Treasure.CategoryToggles -> E.Value
encodeToggles t =
    E.object
        [ ( "coinsNone", E.bool t.coinsNone )
        , ( "gemsNone", E.bool t.gemsNone )
        , ( "artNone", E.bool t.artNone )
        , ( "magicNone", E.bool t.magicNone )
        , ( "mundaneNone", E.bool t.mundaneNone )
        , ( "weaponsNone", E.bool t.weaponsNone )
        , ( "armorNone", E.bool t.armorNone )
        ]


{-| Decode the 17-field settings record. `D.map` caps at 8, so
the record assembles via a `succeed |> andMap |> andMap` pipeline.
Every field decoder is missing-field tolerant so old saves load
with safe defaults.
-}
decodeTreasureSettings : D.Decoder Encounter.Treasure.TreasureSettings
decodeTreasureSettings =
    D.succeed Encounter.Treasure.TreasureSettings
        |> andMap (decodeCountField "coinsCount")
        |> andMap (decodeCountField "gemsCount")
        |> andMap (decodeValueField "gemsValue")
        |> andMap (decodeCountField "artCount")
        |> andMap (decodeValueField "artValue")
        |> andMap (decodeCountField "magicCount")
        |> andMap (decodeValueField "magicValue")
        |> andMap (decodeCountField "mundaneCount")
        |> andMap (decodeCountField "weaponsCount")
        |> andMap (decodeCountField "armorCount")
        |> andMap (decodeTogglesField "hoardToggles" decodeLegacyHoardToggles)
        |> andMap (decodeTogglesField "individualToggles" (D.succeed Encounter.Treasure.defaultIndividualToggles))
        |> andMap (decodeIntField "magicScrollChance" 15)


decodeTogglesField :
    String
    -> D.Decoder Encounter.Treasure.CategoryToggles
    -> D.Decoder Encounter.Treasure.CategoryToggles
decodeTogglesField name fallback =
    D.oneOf
        [ D.field name decodeToggles
        , fallback
        ]


decodeToggles : D.Decoder Encounter.Treasure.CategoryToggles
decodeToggles =
    D.map7 Encounter.Treasure.CategoryToggles
        (decodeBoolField "coinsNone" False)
        (decodeBoolField "gemsNone" False)
        (decodeBoolField "artNone" False)
        (decodeBoolField "magicNone" False)
        (decodeBoolField "mundaneNone" True)
        (decodeBoolField "weaponsNone" True)
        (decodeBoolField "armorNone" True)


{-| Read the pre-split flat None fields. Used as the fallback
decoder for `hoardToggles` so a save written before the
per-Kind toggle refactor doesn't suddenly forget what the GM
had on or off — those flat fields were the Hoard knobs.
-}
decodeLegacyHoardToggles : D.Decoder Encounter.Treasure.CategoryToggles
decodeLegacyHoardToggles =
    D.map7 Encounter.Treasure.CategoryToggles
        (decodeBoolField "coinsNone" False)
        (decodeBoolField "gemsNone" False)
        (decodeBoolField "artNone" False)
        (decodeBoolField "magicNone" False)
        (decodeBoolField "mundaneNone" True)
        (decodeBoolField "weaponsNone" True)
        (decodeBoolField "armorNone" True)


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


decodeCountField : String -> D.Decoder Encounter.Treasure.CountAdjust
decodeCountField name =
    D.oneOf
        [ D.field name D.string |> D.map Encounter.Treasure.countAdjustFromWire
        , D.succeed Encounter.Treasure.CountNormal
        ]


decodeValueField : String -> D.Decoder Encounter.Treasure.ValueAdjust
decodeValueField name =
    D.oneOf
        [ D.field name D.string |> D.map Encounter.Treasure.valueAdjustFromWire
        , D.succeed Encounter.Treasure.ValueNormal
        ]


decodeBoolField : String -> Bool -> D.Decoder Bool
decodeBoolField name fallback =
    D.oneOf
        [ D.field name D.bool
        , D.succeed fallback
        ]


decodeIntField : String -> Int -> D.Decoder Int
decodeIntField name fallback =
    D.oneOf
        [ D.field name D.int
        , D.succeed fallback
        ]


{-| Decode the encounter's `treasure` field. Accepts two shapes
so saved encounters from earlier builds still load:

  - Current: the raw `TreasureRoll` JSON.
  - Legacy: `{ "roll": TreasureRoll, "recipients": {...} }` or
    `{ "roll": ..., "distributed": [...] }` — the old wrapper
    shape from the now-removed party-loot-ledger feature. We
    just unwrap to the inner `roll` and drop the recipient data.

-}
decodeTreasureField : D.Decoder Encounter.Treasure.TreasureRoll
decodeTreasureField =
    D.oneOf
        [ D.field "roll" decodeTreasureRoll
        , decodeTreasureRoll
        ]


encodeTreasureRoll : Encounter.Treasure.TreasureRoll -> E.Value
encodeTreasureRoll roll =
    E.object
        [ ( "kind", E.string (treasureKindWire roll.kind) )
        , ( "bracket", E.string (treasureBracketWire roll.bracket) )
        , ( "coins", encodeCoins roll.coins )
        , ( "gems", E.list encodeGemItem roll.gems )
        , ( "art", E.list encodeArtItem roll.art )
        , ( "magic", E.list encodeMagicItem roll.magic )
        , ( "mundane", E.list encodeFlatItem roll.mundane )
        , ( "weapons", E.list encodeFlatItem roll.weapons )
        , ( "armor", E.list encodeFlatItem roll.armor )
        , ( "source", encodeMaybe encodeRowSource roll.source )
        , ( "contributions", E.list encodeContribution roll.contributions )
        , ( "loot", E.list E.string roll.loot )
        ]


decodeTreasureRoll : D.Decoder Encounter.Treasure.TreasureRoll
decodeTreasureRoll =
    D.map8
        (\kind bracket coins gems art magic source contributions ->
            { kind = kind
            , bracket = bracket
            , coins = coins
            , gems = gems
            , art = art
            , magic = magic
            , source = source
            , contributions = contributions

            -- Placeholders so the record type-checks; the andThen
            -- below replaces them with decoded lists (or keeps `[]`
            -- if the field is missing on legacy rolls).  `D.map9+`
            -- doesn't exist in elm/json so the standard workaround
            -- is a partial in `D.map8` plus an `andThen` to slot in
            -- the remaining fields.
            , mundane = []
            , weapons = []
            , armor = []
            , loot = []
            }
        )
        (D.field "kind" treasureKindDecoder)
        (D.field "bracket" treasureBracketDecoder)
        (D.field "coins" decodeCoins)
        (D.field "gems" (D.list decodeGemItem))
        (D.field "art" (D.list decodeArtItem))
        (D.field "magic" (D.list decodeMagicItem))
        -- Pre-source rolls (saved before the row's originating
        -- formulas were tracked) decode `source = Nothing`; the
        -- re-roll-category path falls back to picking a fresh
        -- row in that case.  Legacy "custom" field is just
        -- ignored.
        (D.oneOf
            [ D.field "source" (D.nullable decodeRowSource)
            , D.succeed Nothing
            ]
        )
        -- Pre-sum rolls (saved before the per-creature
        -- contributions breakdown landed) decode as `[]`.
        (D.oneOf
            [ D.field "contributions" (D.list decodeContribution)
            , D.succeed []
            ]
        )
        |> D.andThen
            (\partial ->
                D.oneOf
                    [ D.field "loot" (D.list D.string)
                        |> D.map (\loot -> { partial | loot = loot })
                    , D.succeed partial
                    ]
            )
        |> D.andThen
            (\partial ->
                D.map3
                    (\mundane weapons armor ->
                        { partial | mundane = mundane, weapons = weapons, armor = armor }
                    )
                    (decodeFlatList "mundane")
                    (decodeFlatList "weapons")
                    (decodeFlatList "armor")
            )


encodeFlatItem : { item | name : String, valueGp : Int } -> E.Value
encodeFlatItem item =
    E.object
        [ ( "name", E.string item.name )
        , ( "valueGp", E.int item.valueGp )
        ]


decodeFlatList : String -> D.Decoder (List { name : String, valueGp : Int })
decodeFlatList name =
    D.oneOf
        [ D.field name (D.list decodeFlatItem)
        , D.succeed []
        ]


decodeFlatItem : D.Decoder { name : String, valueGp : Int }
decodeFlatItem =
    D.map2 (\name value -> { name = name, valueGp = value })
        (D.field "name" D.string)
        (D.field "valueGp" D.int)


encodeContribution : Encounter.Treasure.CreatureContribution -> E.Value
encodeContribution c =
    E.object
        [ ( "creatureName", E.string c.creatureName )
        , ( "coins", encodeCoins c.coins )
        , ( "gems", E.list encodeGemItem c.gems )
        , ( "art", E.list encodeArtItem c.art )
        , ( "magic", E.list encodeMagicItem c.magic )
        , ( "mundane", E.list encodeFlatItem c.mundane )
        , ( "weapons", E.list encodeFlatItem c.weapons )
        , ( "armor", E.list encodeFlatItem c.armor )
        , ( "loot", E.list E.string c.loot )
        , ( "bracket", E.string (treasureBracketWire c.bracket) )
        ]


decodeContribution : D.Decoder Encounter.Treasure.CreatureContribution
decodeContribution =
    D.map5
        (\creatureName coins gems loot bracket ->
            { creatureName = creatureName
            , coins = coins
            , gems = gems

            -- Filled by the andThen below.  Legacy contributions
            -- decoded before the non-coin Individual roll feature
            -- get [] for the new fields.
            , art = []
            , magic = []
            , mundane = []
            , weapons = []
            , armor = []
            , loot = loot
            , bracket = bracket
            }
        )
        (D.field "creatureName" D.string)
        (D.field "coins" decodeCoins)
        (D.oneOf
            [ D.field "gems" (D.list decodeGemItem)
            , D.succeed []
            ]
        )
        (D.oneOf
            [ D.field "loot" (D.list D.string)
            , D.succeed []
            ]
        )
        (D.oneOf
            [ D.field "bracket" treasureBracketDecoder
            , D.succeed Encounter.Treasure.B1to4
            ]
        )
        |> D.andThen
            (\partial ->
                D.map5
                    (\art magic mundane weapons armor ->
                        { partial
                            | art = art
                            , magic = magic
                            , mundane = mundane
                            , weapons = weapons
                            , armor = armor
                        }
                    )
                    (D.oneOf
                        [ D.field "art" (D.list decodeArtItem), D.succeed [] ]
                    )
                    (D.oneOf
                        [ D.field "magic" (D.list decodeMagicItem), D.succeed [] ]
                    )
                    (D.oneOf
                        [ D.field "mundane" (D.list decodeFlatItem), D.succeed [] ]
                    )
                    (D.oneOf
                        [ D.field "weapons" (D.list decodeFlatItem), D.succeed [] ]
                    )
                    (D.oneOf
                        [ D.field "armor" (D.list decodeFlatItem), D.succeed [] ]
                    )
            )


encodeRowSource : Encounter.Treasure.RowSource -> E.Value
encodeRowSource source =
    E.object
        [ ( "coinFormulas", encodeCoinFormulas source.coinFormulas )
        , ( "gemsSpec", encodeMaybe (encodeSpec gemTierWire) source.gemsSpec )
        , ( "artSpec", encodeMaybe (encodeSpec artTierWire) source.artSpec )
        , ( "magicSpec", encodeMaybe (encodeSpec magicTableWire) source.magicSpec )
        ]


decodeRowSource : D.Decoder Encounter.Treasure.RowSource
decodeRowSource =
    D.map4
        (\coinFormulas gemsSpec artSpec magicSpec ->
            { coinFormulas = coinFormulas
            , gemsSpec = gemsSpec
            , artSpec = artSpec
            , magicSpec = magicSpec
            }
        )
        (D.field "coinFormulas" decodeCoinFormulas)
        (D.oneOf
            [ D.field "gemsSpec" (D.nullable (decodeSpec gemTierDecoder))
            , D.succeed Nothing
            ]
        )
        (D.oneOf
            [ D.field "artSpec" (D.nullable (decodeSpec artTierDecoder))
            , D.succeed Nothing
            ]
        )
        (D.oneOf
            [ D.field "magicSpec" (D.nullable (decodeSpec magicTableDecoder))
            , D.succeed Nothing
            ]
        )


encodeCoinFormulas : Encounter.Treasure.CoinFormulas -> E.Value
encodeCoinFormulas formulas =
    E.object
        [ ( "copper", encodeMaybe encodeCoinFormula formulas.copper )
        , ( "silver", encodeMaybe encodeCoinFormula formulas.silver )
        , ( "electrum", encodeMaybe encodeCoinFormula formulas.electrum )
        , ( "gold", encodeMaybe encodeCoinFormula formulas.gold )
        , ( "platinum", encodeMaybe encodeCoinFormula formulas.platinum )
        ]


decodeCoinFormulas : D.Decoder Encounter.Treasure.CoinFormulas
decodeCoinFormulas =
    D.map5
        (\cp sp ep gp pp ->
            { copper = cp
            , silver = sp
            , electrum = ep
            , gold = gp
            , platinum = pp
            }
        )
        (decodeOptionalField "copper" decodeCoinFormula)
        (decodeOptionalField "silver" decodeCoinFormula)
        (decodeOptionalField "electrum" decodeCoinFormula)
        (decodeOptionalField "gold" decodeCoinFormula)
        (decodeOptionalField "platinum" decodeCoinFormula)


decodeOptionalField : String -> D.Decoder a -> D.Decoder (Maybe a)
decodeOptionalField name inner =
    D.oneOf
        [ D.field name (D.nullable inner)
        , D.succeed Nothing
        ]


encodeCoinFormula : ( Int, Int, Int ) -> E.Value
encodeCoinFormula ( count, faces, mult ) =
    E.object
        [ ( "count", E.int count )
        , ( "faces", E.int faces )
        , ( "mult", E.int mult )
        ]


decodeCoinFormula : D.Decoder ( Int, Int, Int )
decodeCoinFormula =
    D.map3 (\a b c -> ( a, b, c ))
        (D.field "count" D.int)
        (D.field "faces" D.int)
        (D.field "mult" D.int)


encodeSpec : (tier -> String) -> ( Int, Int, tier ) -> E.Value
encodeSpec tierToWire ( count, faces, tier ) =
    E.object
        [ ( "count", E.int count )
        , ( "faces", E.int faces )
        , ( "tier", E.string (tierToWire tier) )
        ]


decodeSpec : D.Decoder tier -> D.Decoder ( Int, Int, tier )
decodeSpec tierDecoder =
    D.map3 (\a b c -> ( a, b, c ))
        (D.field "count" D.int)
        (D.field "faces" D.int)
        (D.field "tier" tierDecoder)


gemTierWire : Encounter.Treasure.Tables.GemTier -> String
gemTierWire t =
    case t of
        Encounter.Treasure.Tables.Gem10gp ->
            "10gp"

        Encounter.Treasure.Tables.Gem50gp ->
            "50gp"

        Encounter.Treasure.Tables.Gem100gp ->
            "100gp"

        Encounter.Treasure.Tables.Gem500gp ->
            "500gp"

        Encounter.Treasure.Tables.Gem1000gp ->
            "1000gp"

        Encounter.Treasure.Tables.Gem5000gp ->
            "5000gp"


gemTierDecoder : D.Decoder Encounter.Treasure.Tables.GemTier
gemTierDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "10gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem10gp

                    "50gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem50gp

                    "100gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem100gp

                    "500gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem500gp

                    "1000gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem1000gp

                    "5000gp" ->
                        D.succeed Encounter.Treasure.Tables.Gem5000gp

                    other ->
                        D.fail ("Unknown gem tier: " ++ other)
            )


artTierWire : Encounter.Treasure.Tables.ArtTier -> String
artTierWire t =
    case t of
        Encounter.Treasure.Tables.Art25gp ->
            "25gp"

        Encounter.Treasure.Tables.Art250gp ->
            "250gp"

        Encounter.Treasure.Tables.Art750gp ->
            "750gp"

        Encounter.Treasure.Tables.Art2500gp ->
            "2500gp"

        Encounter.Treasure.Tables.Art7500gp ->
            "7500gp"


artTierDecoder : D.Decoder Encounter.Treasure.Tables.ArtTier
artTierDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "25gp" ->
                        D.succeed Encounter.Treasure.Tables.Art25gp

                    "250gp" ->
                        D.succeed Encounter.Treasure.Tables.Art250gp

                    "750gp" ->
                        D.succeed Encounter.Treasure.Tables.Art750gp

                    "2500gp" ->
                        D.succeed Encounter.Treasure.Tables.Art2500gp

                    "7500gp" ->
                        D.succeed Encounter.Treasure.Tables.Art7500gp

                    other ->
                        D.fail ("Unknown art tier: " ++ other)
            )


treasureKindWire : Encounter.Treasure.Kind -> String
treasureKindWire k =
    case k of
        Encounter.Treasure.Individual ->
            "individual"

        Encounter.Treasure.Hoard ->
            "hoard"


treasureKindDecoder : D.Decoder Encounter.Treasure.Kind
treasureKindDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "individual" ->
                        D.succeed Encounter.Treasure.Individual

                    "hoard" ->
                        D.succeed Encounter.Treasure.Hoard

                    other ->
                        D.fail ("Unknown treasure kind: " ++ other)
            )


treasureBracketWire : Encounter.Treasure.Bracket -> String
treasureBracketWire b =
    case b of
        Encounter.Treasure.B1to4 ->
            "1to4"

        Encounter.Treasure.B5to10 ->
            "5to10"

        Encounter.Treasure.B11to16 ->
            "11to16"

        Encounter.Treasure.B17plus ->
            "17plus"


treasureBracketDecoder : D.Decoder Encounter.Treasure.Bracket
treasureBracketDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "1to4" ->
                        D.succeed Encounter.Treasure.B1to4

                    "5to10" ->
                        D.succeed Encounter.Treasure.B5to10

                    "11to16" ->
                        D.succeed Encounter.Treasure.B11to16

                    "17plus" ->
                        D.succeed Encounter.Treasure.B17plus

                    other ->
                        D.fail ("Unknown treasure bracket: " ++ other)
            )


encodeCoins : Encounter.Treasure.Coins -> E.Value
encodeCoins c =
    E.object
        [ ( "copper", E.int c.copper )
        , ( "silver", E.int c.silver )
        , ( "electrum", E.int c.electrum )
        , ( "gold", E.int c.gold )
        , ( "platinum", E.int c.platinum )
        ]


decodeCoins : D.Decoder Encounter.Treasure.Coins
decodeCoins =
    D.map5
        (\cp sp ep gp pp ->
            { copper = cp
            , silver = sp
            , electrum = ep
            , gold = gp
            , platinum = pp
            }
        )
        (D.field "copper" D.int)
        (D.field "silver" D.int)
        (D.field "electrum" D.int)
        (D.field "gold" D.int)
        (D.field "platinum" D.int)


encodeGemItem : Encounter.Treasure.GemItem -> E.Value
encodeGemItem g =
    E.object [ ( "name", E.string g.name ), ( "valueGp", E.int g.valueGp ) ]


decodeGemItem : D.Decoder Encounter.Treasure.GemItem
decodeGemItem =
    D.map2 Encounter.Treasure.GemItem
        (D.field "name" D.string)
        (D.field "valueGp" D.int)


encodeArtItem : Encounter.Treasure.ArtItem -> E.Value
encodeArtItem a =
    E.object [ ( "name", E.string a.name ), ( "valueGp", E.int a.valueGp ) ]


decodeArtItem : D.Decoder Encounter.Treasure.ArtItem
decodeArtItem =
    D.map2 Encounter.Treasure.ArtItem
        (D.field "name" D.string)
        (D.field "valueGp" D.int)


encodeMagicItem : Encounter.Treasure.MagicItem -> E.Value
encodeMagicItem m =
    E.object
        [ ( "name", E.string m.name )
        , ( "rarity", E.string (rarityWire m.rarity) )
        , ( "table", E.string (magicTableWire m.table) )
        ]


decodeMagicItem : D.Decoder Encounter.Treasure.MagicItem
decodeMagicItem =
    D.map3 Encounter.Treasure.MagicItem
        (D.field "name" D.string)
        (D.field "rarity" rarityDecoder)
        -- Older treasure rolls (pre-table-letter) decode with a
        -- TableA fallback.  TableA is "Common consumables" so the
        -- fallback at least implies the right tier order.
        (D.oneOf
            [ D.field "table" magicTableDecoder
            , D.succeed Encounter.Treasure.Tables.TableA
            ]
        )


magicTableWire : Encounter.Treasure.Tables.MagicTable -> String
magicTableWire t =
    case t of
        Encounter.Treasure.Tables.TableA ->
            "A"

        Encounter.Treasure.Tables.TableB ->
            "B"

        Encounter.Treasure.Tables.TableC ->
            "C"

        Encounter.Treasure.Tables.TableD ->
            "D"

        Encounter.Treasure.Tables.TableE ->
            "E"

        Encounter.Treasure.Tables.TableF ->
            "F"

        Encounter.Treasure.Tables.TableG ->
            "G"

        Encounter.Treasure.Tables.TableH ->
            "H"

        Encounter.Treasure.Tables.TableI ->
            "I"


magicTableDecoder : D.Decoder Encounter.Treasure.Tables.MagicTable
magicTableDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "A" ->
                        D.succeed Encounter.Treasure.Tables.TableA

                    "B" ->
                        D.succeed Encounter.Treasure.Tables.TableB

                    "C" ->
                        D.succeed Encounter.Treasure.Tables.TableC

                    "D" ->
                        D.succeed Encounter.Treasure.Tables.TableD

                    "E" ->
                        D.succeed Encounter.Treasure.Tables.TableE

                    "F" ->
                        D.succeed Encounter.Treasure.Tables.TableF

                    "G" ->
                        D.succeed Encounter.Treasure.Tables.TableG

                    "H" ->
                        D.succeed Encounter.Treasure.Tables.TableH

                    "I" ->
                        D.succeed Encounter.Treasure.Tables.TableI

                    other ->
                        D.fail ("Unknown magic-item table: " ++ other)
            )


rarityWire : Encounter.Treasure.Tables.Rarity -> String
rarityWire r =
    case r of
        Encounter.Treasure.Tables.Common ->
            "common"

        Encounter.Treasure.Tables.Uncommon ->
            "uncommon"

        Encounter.Treasure.Tables.Rare ->
            "rare"

        Encounter.Treasure.Tables.VeryRare ->
            "very-rare"

        Encounter.Treasure.Tables.Legendary ->
            "legendary"


rarityDecoder : D.Decoder Encounter.Treasure.Tables.Rarity
rarityDecoder =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "common" ->
                        D.succeed Encounter.Treasure.Tables.Common

                    "uncommon" ->
                        D.succeed Encounter.Treasure.Tables.Uncommon

                    "rare" ->
                        D.succeed Encounter.Treasure.Tables.Rare

                    "very-rare" ->
                        D.succeed Encounter.Treasure.Tables.VeryRare

                    "legendary" ->
                        D.succeed Encounter.Treasure.Tables.Legendary

                    other ->
                        D.fail ("Unknown magic-item rarity: " ++ other)
            )


encodeCreature : Creature -> E.Value
encodeCreature c =
    E.object
        [ ( "name", E.string c.name )
        , ( "kind", E.string c.kind )
        , ( "initiative", E.int c.initiative )
        , ( "initiativeBonus", E.int c.initiativeBonus )
        , ( "currentHp", E.int c.currentHp )
        , ( "maxHp", E.int c.maxHp )
        , ( "originalMaxHp", E.int c.originalMaxHp )
        , ( "tempHp", E.int c.tempHp )
        , ( "armorClass", E.int c.armorClass )
        , ( "speed", E.int c.speed )
        , ( "conditions", E.list encodeCondition c.conditions )
        , ( "saveNotices", E.list encodeSaveNotice c.saveNotices )
        , ( "selected", E.bool c.selected )
        , ( "cover", encodeCover c.cover )
        , ( "concentrating", E.bool c.concentrating )
        , ( "hiding", E.bool c.hiding )
        , ( "dodging", E.bool c.dodging )
        , ( "flying", E.bool c.flying )
        , ( "flyHeight", E.int c.flyHeight )
        , ( "bloodied", E.bool c.bloodied )
        , ( "deathSaves", encodeDeathSaves c.deathSaves )
        , ( "acceptingDeathSaves", E.bool c.acceptingDeathSaves )
        , ( "reactionUsed", E.bool c.reactionUsed )
        , ( "rechargeAbilities", E.list encodeRechargeAbility c.rechargeAbilities )
        , ( "readied", E.bool c.readied )
        , ( "inactive", E.bool c.inactive )
        , ( "note", E.string c.note )
        , ( "memo", E.string c.memo )
        , ( "timer", encodeMaybe encodeTimer c.timer )
        , ( "creatureId", encodeMaybe E.string c.creatureId )
        , ( "legendaryActionsCount", E.int c.legendaryActionsCount )
        , ( "legendaryActionsLairBonus", E.int c.legendaryActionsLairBonus )
        , ( "legendaryActionsUsed", encodeIntSet c.legendaryActionsUsed )
        , ( "legendaryResistanceCount", E.int c.legendaryResistanceCount )
        , ( "legendaryResistanceLairBonus", E.int c.legendaryResistanceLairBonus )
        , ( "legendaryResistanceUsed", encodeIntSet c.legendaryResistanceUsed )
        , ( "isPlaceholder", E.bool c.isPlaceholder )
        , ( "creatureKind", E.string c.creatureKind )
        , ( "race", E.string c.race )
        , ( "alignment", E.string c.alignment )
        , ( "surprised", E.bool c.surprised )
        , ( "hasSpecialReactions", E.bool c.hasSpecialReactions )
        ]


encodeIntSet : Set Int -> E.Value
encodeIntSet s =
    E.list E.int (Set.toList s)


encodeCondition : Condition -> E.Value
encodeCondition cond =
    E.object
        [ ( "id", E.int cond.id )
        , ( "name", E.string cond.name )
        , ( "note", E.string cond.note )
        , ( "duration", encodeDuration cond.duration )
        , ( "saveToEnd", encodeMaybe encodeSaveToEnd cond.saveToEnd )
        ]


encodeDuration : Duration -> E.Value
encodeDuration d =
    case d of
        DurationManual ->
            E.object [ ( "kind", E.string "manual" ) ]

        DurationUntilTurn phase target name ->
            E.object
                [ ( "kind", E.string "untilTurn" )
                , ( "phase", encodeTurnPhase phase )
                , ( "target", encodeTurnTarget target )
                , ( "name", E.string name )
                ]

        DurationCountdown phase remaining skipNext ->
            E.object
                [ ( "kind", E.string "countdown" )
                , ( "phase", encodeTurnPhase phase )
                , ( "remaining", E.int remaining )
                , ( "skipNextTick", E.bool skipNext )
                ]


encodeTurnPhase : TurnPhase -> E.Value
encodeTurnPhase p =
    case p of
        AtBegin ->
            E.string "atBegin"

        AtEnd ->
            E.string "atEnd"


encodeTurnTarget : TurnTarget -> E.Value
encodeTurnTarget t =
    case t of
        OnCurrentTurn ->
            E.string "current"

        OnNextTurn ->
            E.string "next"


encodeSaveToEnd : SaveToEnd -> E.Value
encodeSaveToEnd s =
    E.object
        [ ( "ability", E.string s.ability )
        , ( "dc", E.int s.dc )
        , ( "bonus", E.int s.bonus )
        , ( "autoRoll", encodeAutoRoll s.autoRoll )
        ]


encodeAutoRoll : AutoRollMode -> E.Value
encodeAutoRoll a =
    case a of
        AutoRollManual ->
            E.string "manual"

        AutoRollAtBegin ->
            E.string "atBegin"

        AutoRollAtEnd ->
            E.string "atEnd"


encodeSaveNotice : SaveNotice -> E.Value
encodeSaveNotice n =
    E.object
        [ ( "id", E.int n.id )
        , ( "conditionName", E.string n.conditionName )
        , ( "turnsRemaining", E.int n.turnsRemaining )
        ]


encodeCover : Cover -> E.Value
encodeCover c =
    case c of
        NoCover ->
            E.string "none"

        HalfCover ->
            E.string "half"

        ThreeQuartersCover ->
            E.string "threeQuarters"

        FullCover ->
            E.string "full"


encodeDeathSaves : DeathSaves -> E.Value
encodeDeathSaves d =
    E.object
        [ ( "successes", E.int d.successes )
        , ( "failures", E.int d.failures )
        ]


encodeRechargeAbility : Encounter.RechargeAbility -> E.Value
encodeRechargeAbility r =
    E.object
        [ ( "name", E.string r.name )
        , ( "low", E.int r.low )
        , ( "high", E.int r.high )
        , ( "ready", E.bool r.ready )
        , ( "awaitingRoll", E.bool r.awaitingRoll )
        ]


encodeTimer : Timer -> E.Value
encodeTimer t =
    E.object
        [ ( "remaining", E.int t.remaining )
        , ( "phase", encodeTurnPhase t.phase )
        , ( "ringing", E.bool t.ringing )
        , ( "note", E.string t.note )
        ]


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null



-- ── DECODE ───────────────────────────────────────────────────────────────────


{-| Tiny pipeline helper so a 25-field record decoder doesn't
need an `andMap` chain. Same trick used in `Compendium.elm`.
-}
required : String -> D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
required name dec =
    D.map2 (|>) (D.field name dec)


optional : String -> D.Decoder a -> a -> D.Decoder (a -> b) -> D.Decoder b
optional name dec default =
    D.map2 (|>)
        (D.oneOf
            [ D.field name dec
            , D.field name (D.null default)
            , D.succeed default
            ]
        )


{-| Like [`optional`](#optional) but accepts either of two field
names. `current` wins when both are present; `legacy` is the
old name, kept on the read path so encounters saved before a
rename still decode without a migration script. Used today by
the `readied` field (was `holding` until the 2014-vs-2024
terminology cleanup).
-}
optionalEither : String -> String -> D.Decoder a -> a -> D.Decoder (a -> b) -> D.Decoder b
optionalEither current legacy dec default =
    D.map2 (|>)
        (D.oneOf
            [ D.field current dec
            , D.field current (D.null default)
            , D.field legacy dec
            , D.field legacy (D.null default)
            , D.succeed default
            ]
        )


{-| Map the old `hasLegendaryActions : Bool` / `hasLegendaryResistance : Bool`
fields onto the new count-typed fields. A `True` legacy flag
becomes 3 (the historical default for both LA and LR per 5e
norms); a `False` flag becomes 0 (no column).
-}
boolToLegacyCount : Bool -> Int
boolToLegacyCount b =
    if b then
        3

    else
        0


decodeEncounter : D.Decoder Encounter
decodeEncounter =
    D.map5
        (\creatures activeName round treasure treasureSettings ->
            { creatures = creatures
            , activeName = activeName
            , round = round
            , treasure = treasure
            , treasureSettings = treasureSettings
            }
        )
        (D.field "creatures" (D.list decodeCreature))
        (D.field "activeName" D.string)
        (D.field "round" D.int)
        (D.oneOf
            [ D.field "treasure" (D.nullable decodeTreasureField)
            , D.succeed Nothing
            ]
        )
        -- Saved encounters from before this commit didn't carry
        -- roll knobs; default to all-Normal.
        (D.oneOf
            [ D.field "treasureSettings" decodeTreasureSettings
            , D.succeed Encounter.Treasure.defaultSettings
            ]
        )


decodeCreature : D.Decoder Creature
decodeCreature =
    D.succeed
        (\name kind initiative initiativeBonus currentHp maxHp originalMaxHpMaybe tempHp armorClass speed conditions saveNotices selected cover concentrating hiding dodging flying flyHeight bloodied deathSaves acceptingDeathSaves reactionUsed rechargeAbilities readied inactive note memo timer creatureId laCount laLairBonus laUsed lrCount lrLairBonus lrUsed isPlaceholder creatureKind race alignment surprised hasSpecialReactions ->
            { name = name
            , kind = kind
            , initiative = initiative
            , initiativeBonus = initiativeBonus
            , currentHp = currentHp
            , maxHp = maxHp
            , originalMaxHp = Maybe.withDefault maxHp originalMaxHpMaybe
            , tempHp = tempHp
            , armorClass = armorClass
            , speed = speed
            , conditions = conditions
            , saveNotices = saveNotices
            , selected = selected
            , cover = cover
            , concentrating = concentrating
            , hiding = hiding
            , dodging = dodging
            , flying = flying
            , flyHeight = flyHeight
            , bloodied = bloodied
            , deathSaves = deathSaves
            , acceptingDeathSaves = acceptingDeathSaves
            , reactionUsed = reactionUsed
            , rechargeAbilities = rechargeAbilities
            , readied = readied
            , inactive = inactive
            , note = note
            , memo = memo
            , timer = timer
            , creatureId = creatureId
            , legendaryActionsCount = laCount
            , legendaryActionsLairBonus = laLairBonus
            , legendaryActionsUsed = laUsed
            , legendaryResistanceCount = lrCount
            , legendaryResistanceLairBonus = lrLairBonus
            , legendaryResistanceUsed = lrUsed
            , isPlaceholder = isPlaceholder
            , creatureKind = creatureKind
            , race = race
            , alignment = alignment
            , surprised = surprised
            , hasSpecialReactions = hasSpecialReactions
            }
        )
        |> required "name" D.string
        |> optional "kind" D.string ""
        |> required "initiative" D.int
        |> optional "initiativeBonus" D.int 0
        |> required "currentHp" D.int
        |> required "maxHp" D.int
        |> optional "originalMaxHp" (D.map Just D.int) Nothing
        |> optional "tempHp" D.int 0
        |> required "armorClass" D.int
        |> optional "speed" D.int 30
        |> optional "conditions" (D.list decodeCondition) []
        |> optional "saveNotices" (D.list decodeSaveNotice) []
        |> optional "selected" D.bool False
        |> optional "cover" decodeCover NoCover
        |> optional "concentrating" D.bool False
        |> optional "hiding" D.bool False
        |> optional "dodging" D.bool False
        |> optional "flying" D.bool False
        |> optional "flyHeight" D.int 0
        |> optional "bloodied" D.bool False
        |> optional "deathSaves" decodeDeathSaves { successes = 0, failures = 0 }
        |> optional "acceptingDeathSaves" D.bool False
        |> optional "reactionUsed" D.bool False
        |> optional "rechargeAbilities" (D.list decodeRechargeAbility) []
        |> optionalEither "readied" "holding" D.bool False
        |> optional "inactive" D.bool False
        |> optional "note" D.string ""
        |> optional "memo" D.string ""
        |> optional "timer" (D.nullable decodeTimer) Nothing
        |> optional "creatureId" (D.nullable D.string) Nothing
        -- Old encoder wrote `hasLegendaryActions : Bool`; the
        -- newer one writes a numeric count + lair bonus.
        -- Honor both shapes so saved encounters from the
        -- pre-count era still load — a `True` flag maps to a
        -- conservative 3-pip default, the count itself wins
        -- when present.
        |> optionalEither "legendaryActionsCount"
            "hasLegendaryActions"
            (D.oneOf [ D.int, D.bool |> D.map boolToLegacyCount ])
            0
        |> optional "legendaryActionsLairBonus" D.int 0
        |> optional "legendaryActionsUsed" decodeIntSet Set.empty
        |> optionalEither "legendaryResistanceCount"
            "hasLegendaryResistance"
            (D.oneOf [ D.int, D.bool |> D.map boolToLegacyCount ])
            0
        |> optional "legendaryResistanceLairBonus" D.int 0
        |> optional "legendaryResistanceUsed" decodeIntSet Set.empty
        |> optional "isPlaceholder" D.bool False
        |> optional "creatureKind" D.string "enemy"
        |> optional "race" D.string ""
        |> optional "alignment" D.string ""
        |> optional "surprised" D.bool False
        |> optional "hasSpecialReactions" D.bool False


decodeIntSet : D.Decoder (Set Int)
decodeIntSet =
    D.list D.int |> D.map Set.fromList


decodeCondition : D.Decoder Condition
decodeCondition =
    D.map5 Condition
        (D.field "id" D.int)
        (D.field "name" D.string)
        (D.oneOf [ D.field "note" D.string, D.succeed "" ])
        (D.field "duration" decodeDuration)
        (D.oneOf
            [ D.field "saveToEnd" (D.nullable decodeSaveToEnd)
            , D.succeed Nothing
            ]
        )


decodeDuration : D.Decoder Duration
decodeDuration =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "manual" ->
                        D.succeed DurationManual

                    "untilTurn" ->
                        D.map3 DurationUntilTurn
                            (D.field "phase" decodeTurnPhase)
                            (D.field "target" decodeTurnTarget)
                            (D.field "name" D.string)

                    "countdown" ->
                        D.map3 DurationCountdown
                            (D.field "phase" decodeTurnPhase)
                            (D.field "remaining" D.int)
                            (D.field "skipNextTick" D.bool)

                    other ->
                        D.fail ("Unknown duration kind: " ++ other)
            )


decodeTurnPhase : D.Decoder TurnPhase
decodeTurnPhase =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "atBegin" ->
                        D.succeed AtBegin

                    "atEnd" ->
                        D.succeed AtEnd

                    other ->
                        D.fail ("Unknown turn phase: " ++ other)
            )


decodeTurnTarget : D.Decoder TurnTarget
decodeTurnTarget =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "current" ->
                        D.succeed OnCurrentTurn

                    "next" ->
                        D.succeed OnNextTurn

                    other ->
                        D.fail ("Unknown turn target: " ++ other)
            )


decodeSaveToEnd : D.Decoder SaveToEnd
decodeSaveToEnd =
    D.map4 SaveToEnd
        (D.field "ability" D.string)
        (D.field "dc" D.int)
        (D.field "bonus" D.int)
        (D.field "autoRoll" decodeAutoRoll)


decodeAutoRoll : D.Decoder AutoRollMode
decodeAutoRoll =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "manual" ->
                        D.succeed AutoRollManual

                    "atBegin" ->
                        D.succeed AutoRollAtBegin

                    "atEnd" ->
                        D.succeed AutoRollAtEnd

                    other ->
                        D.fail ("Unknown auto-roll mode: " ++ other)
            )


decodeSaveNotice : D.Decoder SaveNotice
decodeSaveNotice =
    D.map3
        (\id conditionName turnsRemaining ->
            { id = id
            , conditionName = conditionName
            , turnsRemaining = turnsRemaining
            }
        )
        (D.field "id" D.int)
        (D.field "conditionName" D.string)
        (D.field "turnsRemaining" D.int)


decodeCover : D.Decoder Cover
decodeCover =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "none" ->
                        D.succeed NoCover

                    "half" ->
                        D.succeed HalfCover

                    "threeQuarters" ->
                        D.succeed ThreeQuartersCover

                    "full" ->
                        D.succeed FullCover

                    other ->
                        D.fail ("Unknown cover: " ++ other)
            )


decodeDeathSaves : D.Decoder DeathSaves
decodeDeathSaves =
    -- DeathSaves is a re-exported alias from Encounter.DeathSaves,
    -- so the constructor isn't directly callable. Build the
    -- record literal explicitly.
    D.map2 (\s f -> { successes = s, failures = f })
        (D.field "successes" D.int)
        (D.field "failures" D.int)


decodeRechargeAbility : D.Decoder Encounter.RechargeAbility
decodeRechargeAbility =
    D.map5
        (\name low high ready awaitingRoll ->
            { name = name
            , low = low
            , high = high
            , ready = ready
            , awaitingRoll = awaitingRoll
            }
        )
        (D.field "name" D.string)
        (D.field "low" D.int)
        (D.field "high" D.int)
        (D.field "ready" D.bool)
        -- `awaitingRoll` was added after `ready`; older saves
        -- and the server's bundle-versioned recharge entries
        -- both lack it, so default to False on decode.  Same
        -- effect as if the begin-of-turn hook had just fired
        -- and seen `ready = True`.
        (D.oneOf [ D.field "awaitingRoll" D.bool, D.succeed False ])


decodeTimer : D.Decoder Timer
decodeTimer =
    D.map4 Timer
        (D.field "remaining" D.int)
        (D.field "phase" decodeTurnPhase)
        (D.field "ringing" D.bool)
        (D.oneOf [ D.field "note" D.string, D.succeed "" ])



-- ── LOCAL (ANONYMOUS) NAMED SAVES ────────────────────────────────────────────
--
-- Anonymous sessions store named encounter saves in a single
-- localStorage dict keyed by name.  Each value carries the
-- encoded encounter plus created_at / updated_at millis so the
-- Save / Load modal listings can sort and display dates the
-- same way the server-backed flow does.


type alias LocalEncounterSave =
    { encounter : Encounter
    , createdAt : Int
    , updatedAt : Int
    }


{-| Project a dict entry down to the same metadata shape the
server returns from `GET /api/encounter/saves` so the Save / Load
modals can use one row renderer for both paths.
-}
localSaveToMeta : ( String, LocalEncounterSave ) -> SavedEncounterMeta
localSaveToMeta ( name, save ) =
    { name = name
    , createdAt = save.createdAt
    , updatedAt = save.updatedAt
    }


encodeLocalEncounterSave : LocalEncounterSave -> E.Value
encodeLocalEncounterSave save =
    E.object
        [ ( "encounter", encodeEncounter save.encounter )
        , ( "created_at", E.int save.createdAt )
        , ( "updated_at", E.int save.updatedAt )
        ]


decodeLocalEncounterSave : D.Decoder LocalEncounterSave
decodeLocalEncounterSave =
    D.map3 LocalEncounterSave
        (D.field "encounter" decodeEncounter)
        (D.field "created_at" D.int)
        (D.field "updated_at" D.int)


encodeLocalEncounterSaves : Dict String LocalEncounterSave -> E.Value
encodeLocalEncounterSaves dict =
    E.dict identity encodeLocalEncounterSave dict


decodeLocalEncounterSaves : D.Decoder (Dict String LocalEncounterSave)
decodeLocalEncounterSaves =
    D.dict decodeLocalEncounterSave
