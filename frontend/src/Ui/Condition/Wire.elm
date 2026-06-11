module Ui.Condition.Wire exposing
    ( decodePresets, encodePresets
    , encodePreset, decodePreset
    )

{-| JSON wire format for the user-named condition presets that
back the Save / Load row in the Add-Condition modal.

The dict is persisted to `localStorage.conditionPresets` on every
mutation by the update-loop wrapper in `Main`, and read back at
boot via the `localConditionPresets` init flag. The shape is a
flat object whose keys are the user's preset names and whose
values are the per-preset body — `Ui.Condition.ConditionPreset`.

Anonymous and authenticated sessions both round-trip through this
same localStorage path today; if a server-side store is added
later the same encoders/decoders are reusable for that payload
since the body shape doesn't depend on session state.

@docs decodePresets, encodePresets
@docs encodePreset, decodePreset

-}

import Dict exposing (Dict)
import Encounter
import Json.Decode as D
import Json.Encode as E
import Msg exposing (DurationKind(..))
import Ui.Condition exposing (ConditionPreset, SaveToEndUi)


encodePresets : Dict String ConditionPreset -> E.Value
encodePresets presets =
    presets
        |> Dict.toList
        |> List.map (\( name, body ) -> ( name, encodePreset body ))
        |> E.object


{-| Decode the server's preset payload. The `/api/condition-presets`
endpoint returns JSON `null` when the user has never saved a preset
(see the handler doc in =crates/server/src/condition\_presets.rs=), so
the decoder accepts null as the empty dict; otherwise it expects the
flat-object shape that `encodePresets` writes.
-}
decodePresets : D.Decoder (Dict String ConditionPreset)
decodePresets =
    D.oneOf
        [ D.null Dict.empty
        , D.dict decodePreset
        ]


encodePreset : ConditionPreset -> E.Value
encodePreset p =
    E.object
        [ ( "conditionName", E.string p.conditionName )
        , ( "customName", E.string p.customName )
        , ( "note", E.string p.note )
        , ( "durationKind", encodeDurationKind p.durationKind )
        , ( "untilPhase", encodeTurnPhase p.untilPhase )
        , ( "countdownTurnsText", E.string p.countdownTurnsText )
        , ( "countdownTurns", E.int p.countdownTurns )
        , ( "countdownPhase", encodeTurnPhase p.countdownPhase )
        , ( "saveToEnd", encodeMaybe encodeSaveToEnd p.saveToEnd )
        , ( "category", E.string p.category )
        ]


decodePreset : D.Decoder ConditionPreset
decodePreset =
    D.succeed ConditionPreset
        |> required "conditionName" D.string
        |> required "customName" D.string
        |> required "note" D.string
        |> required "durationKind" decodeDurationKind
        |> required "untilPhase" decodeTurnPhase
        |> required "countdownTurnsText" D.string
        |> required "countdownTurns" D.int
        |> required "countdownPhase" decodeTurnPhase
        |> required "saveToEnd" (D.nullable decodeSaveToEnd)
        |> optional "category" D.string ""


required : String -> D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
required name decoder =
    D.map2 (|>) (D.field name decoder)


{-| Decode a field, falling back to a default when the field is
absent or null. Used for the `category` field so presets saved
before the bundled-defaults pass round-trip cleanly with `""`.
-}
optional : String -> D.Decoder a -> a -> D.Decoder (a -> b) -> D.Decoder b
optional name decoder default =
    D.map2 (|>)
        (D.oneOf [ D.field name decoder, D.succeed default ])


encodeDurationKind : DurationKind -> E.Value
encodeDurationKind k =
    case k of
        DurKindManual ->
            E.string "manual"

        DurKindUntilTurn ->
            E.string "untilTurn"

        DurKindCountdown ->
            E.string "countdown"


decodeDurationKind : D.Decoder DurationKind
decodeDurationKind =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "manual" ->
                        D.succeed DurKindManual

                    "untilTurn" ->
                        D.succeed DurKindUntilTurn

                    "countdown" ->
                        D.succeed DurKindCountdown

                    other ->
                        D.fail ("Unknown duration kind: " ++ other)
            )


encodeTurnPhase : Encounter.TurnPhase -> E.Value
encodeTurnPhase phase =
    case phase of
        Encounter.AtBegin ->
            E.string "atBegin"

        Encounter.AtEnd ->
            E.string "atEnd"


decodeTurnPhase : D.Decoder Encounter.TurnPhase
decodeTurnPhase =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "atBegin" ->
                        D.succeed Encounter.AtBegin

                    "atEnd" ->
                        D.succeed Encounter.AtEnd

                    other ->
                        D.fail ("Unknown turn phase: " ++ other)
            )


encodeSaveToEnd : SaveToEndUi -> E.Value
encodeSaveToEnd s =
    E.object
        [ ( "ability", E.string s.ability )
        , ( "dcText", E.string s.dcText )
        , ( "dc", E.int s.dc )
        , ( "bonusText", E.string s.bonusText )
        , ( "bonus", E.int s.bonus )
        , ( "autoRoll", encodeAutoRoll s.autoRoll )
        ]


decodeSaveToEnd : D.Decoder SaveToEndUi
decodeSaveToEnd =
    D.map6 SaveToEndUi
        (D.field "ability" D.string)
        (D.field "dcText" D.string)
        (D.field "dc" D.int)
        (D.field "bonusText" D.string)
        (D.field "bonus" D.int)
        (D.field "autoRoll" decodeAutoRoll)


encodeAutoRoll : Encounter.AutoRollMode -> E.Value
encodeAutoRoll mode =
    case mode of
        Encounter.AutoRollManual ->
            E.string "manual"

        Encounter.AutoRollAtBegin ->
            E.string "atBegin"

        Encounter.AutoRollAtEnd ->
            E.string "atEnd"


decodeAutoRoll : D.Decoder Encounter.AutoRollMode
decodeAutoRoll =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "manual" ->
                        D.succeed Encounter.AutoRollManual

                    "atBegin" ->
                        D.succeed Encounter.AutoRollAtBegin

                    "atEnd" ->
                        D.succeed Encounter.AutoRollAtEnd

                    other ->
                        D.fail ("Unknown auto-roll mode: " ++ other)
            )


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null
