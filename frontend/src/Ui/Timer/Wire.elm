module Ui.Timer.Wire exposing
    ( decodePresets, encodePresets
    , encodePreset, decodePreset
    )

{-| JSON wire format for the user-named timer presets that back
the Save / Load row in the Timer-setup modal.

Mirrors `Ui.Condition.Wire` in shape: a flat object keyed by the
preset name, persisted to `localStorage.timerPresets` and read
back at boot via the `localTimerPresets` init flag. Same dual-
session usage (anonymous + authenticated both round-trip through
localStorage today).

@docs decodePresets, encodePresets
@docs encodePreset, decodePreset

-}

import Dict exposing (Dict)
import Encounter
import Json.Decode as D
import Json.Encode as E
import Ui.Timer exposing (TimerPreset)


encodePresets : Dict String TimerPreset -> E.Value
encodePresets presets =
    presets
        |> Dict.toList
        |> List.map (\( name, body ) -> ( name, encodePreset body ))
        |> E.object


decodePresets : D.Decoder (Dict String TimerPreset)
decodePresets =
    D.dict decodePreset


encodePreset : TimerPreset -> E.Value
encodePreset p =
    E.object
        [ ( "turnsText", E.string p.turnsText )
        , ( "turns", E.int p.turns )
        , ( "phase", encodeTurnPhase p.phase )
        , ( "note", E.string p.note )
        ]


decodePreset : D.Decoder TimerPreset
decodePreset =
    D.map4 TimerPreset
        (D.field "turnsText" D.string)
        (D.field "turns" D.int)
        (D.field "phase" decodeTurnPhase)
        (D.field "note" D.string)


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
