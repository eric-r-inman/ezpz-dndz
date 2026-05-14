module Encounter.Wire exposing
    ( SavedEncounterMeta
    , decodeEncounter, encodeEncounter
    , fetchEncounterCmd, persistEncounterCmd
    , listSavesCmd, getSaveCmd, putSaveCmd, deleteSaveCmd, renameSaveCmd
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
        ]


encodeCreature : Creature -> E.Value
encodeCreature c =
    E.object
        [ ( "name", E.string c.name )
        , ( "kind", E.string c.kind )
        , ( "initiative", E.int c.initiative )
        , ( "initiativeBonus", E.int c.initiativeBonus )
        , ( "currentHp", E.int c.currentHp )
        , ( "maxHp", E.int c.maxHp )
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
        , ( "holding", E.bool c.holding )
        , ( "inactive", E.bool c.inactive )
        , ( "note", E.string c.note )
        , ( "memo", E.string c.memo )
        , ( "timer", encodeMaybe encodeTimer c.timer )
        , ( "creatureId", encodeMaybe E.string c.creatureId )
        , ( "hasLegendaryActions", E.bool c.hasLegendaryActions )
        , ( "legendaryActionsUsed", encodeIntSet c.legendaryActionsUsed )
        , ( "hasLegendaryResistance", E.bool c.hasLegendaryResistance )
        , ( "legendaryResistanceUsed", encodeIntSet c.legendaryResistanceUsed )
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


decodeEncounter : D.Decoder Encounter
decodeEncounter =
    D.map3
        (\creatures activeName round ->
            { creatures = creatures
            , activeName = activeName
            , round = round
            }
        )
        (D.field "creatures" (D.list decodeCreature))
        (D.field "activeName" D.string)
        (D.field "round" D.int)


decodeCreature : D.Decoder Creature
decodeCreature =
    D.succeed
        (\name kind initiative initiativeBonus currentHp maxHp tempHp armorClass speed conditions saveNotices selected cover concentrating hiding dodging flying flyHeight bloodied deathSaves holding inactive note memo timer creatureId hasLA laUsed hasLR lrUsed ->
            { name = name
            , kind = kind
            , initiative = initiative
            , initiativeBonus = initiativeBonus
            , currentHp = currentHp
            , maxHp = maxHp
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
            , holding = holding
            , inactive = inactive
            , note = note
            , memo = memo
            , timer = timer
            , creatureId = creatureId
            , hasLegendaryActions = hasLA
            , legendaryActionsUsed = laUsed
            , hasLegendaryResistance = hasLR
            , legendaryResistanceUsed = lrUsed
            }
        )
        |> required "name" D.string
        |> optional "kind" D.string ""
        |> required "initiative" D.int
        |> optional "initiativeBonus" D.int 0
        |> required "currentHp" D.int
        |> required "maxHp" D.int
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
        |> optional "holding" D.bool False
        |> optional "inactive" D.bool False
        |> optional "note" D.string ""
        |> optional "memo" D.string ""
        |> optional "timer" (D.nullable decodeTimer) Nothing
        |> optional "creatureId" (D.nullable D.string) Nothing
        |> optional "hasLegendaryActions" D.bool False
        |> optional "legendaryActionsUsed" decodeIntSet Set.empty
        |> optional "hasLegendaryResistance" D.bool False
        |> optional "legendaryResistanceUsed" decodeIntSet Set.empty


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


decodeTimer : D.Decoder Timer
decodeTimer =
    D.map4 Timer
        (D.field "remaining" D.int)
        (D.field "phase" decodeTurnPhase)
        (D.field "ringing" D.bool)
        (D.oneOf [ D.field "note" D.string, D.succeed "" ])
