module View.Inline.Timer exposing (view)

{-| Timer setup as an inline card expansion. The GM picks a turn
count (1..99) and a phase (begin/end of bearer's turn). Start
Timer writes the timer; Escape or re-clicking the trigger
discards.

Mirrors the per-surface preset pattern from
`View.Inline.Condition`: a footer Save/Load row backed by
`Model.timerPresets`.

-}

import Dict exposing (Dict)
import Html exposing (Html, button, div, input, text)
import Html.Attributes as Attr exposing (attribute, autofocus, class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (Msg(..))
import Ui.Timer exposing (TimerPreset, TimerSetupUi)
import Util.Keyboard
import View.PhaseToggle
import View.Tooltips as Tooltips


view : Dict String TimerPreset -> TimerSetupUi -> Html Msg
view presets ui =
    div [ class "creature-card__inline" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "timer-turns-input" ]
                [ text "Timer lasts" ]
            , input
                [ id "timer-turns-input"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "99"
                , value ui.turnsText
                , autofocus True
                , onInput TimerSetupTurnsChanged
                , on "keydown" (Util.Keyboard.enterKey TimerSetupApply)
                ]
                []
            , Html.label [] [ text "turns, ticking at" ]
            , View.PhaseToggle.view "timer-phase" ui.phase TimerSetupPhaseSet
            , Html.label [] [ text "of the bearer's turn" ]
            ]
        , div [ class "cond-row" ]
            [ Html.label [ for "timer-note-input" ]
                [ text "Label" ]
            , input
                [ id "timer-note-input"
                , class "cond-input"
                , type_ "text"
                , Attr.maxlength 10
                , Attr.placeholder "optional (10 chars)"
                , value ui.note
                , onInput TimerSetupNoteChanged
                , on "keydown" (Util.Keyboard.enterKey TimerSetupApply)
                ]
                []
            ]
        , div [ class "cond-section__caption" ]
            [ text "When it reaches 0 the card flashes a 0 and the page plays a ping. Click × on the timer to dismiss." ]
        , footer ui presets
        ]


footer : TimerSetupUi -> Dict String TimerPreset -> Html Msg
footer ui presets =
    div [ class "cond-footer" ]
        [ div [ class "cond-footer__presets" ]
            [ presetSaveControl ui
            , presetLoadControl ui presets
            ]
        , div [ class "note-edit__buttons" ]
            [ button
                [ class "action-btn action-btn--green"
                , onClick TimerSetupApply
                ]
                [ text "Start Timer" ]

            -- No Cancel button: Escape and re-clicking the
            -- ⏱ button both cancel.
            ]
        ]


presetSaveControl : TimerSetupUi -> Html Msg
presetSaveControl ui =
    case ui.pendingSaveName of
        Nothing ->
            button
                [ class "action-btn cond-footer__save"
                , onClick TimerPresetSaveStart
                , Tooltips.attr "Save this configuration as a named preset"
                ]
                [ text "Save" ]

        Just typed ->
            let
                trimmed =
                    String.trim typed

                canSaveName =
                    not (String.isEmpty trimmed)
            in
            div [ class "cond-footer__save-row" ]
                [ input
                    [ class "cond-input cond-footer__save-input"
                    , type_ "text"
                    , value typed
                    , placeholder "Name this preset"
                    , autofocus True
                    , onInput TimerPresetSaveNameChanged
                    , on "keydown" (enterKeyDecoder TimerPresetSaveSubmit)
                    ]
                    []
                , button
                    [ class "action-btn action-btn--green"
                    , onClick TimerPresetSaveSubmit
                    , disabled (not canSaveName)
                    , Tooltips.attr "Save preset"
                    ]
                    [ text "Save" ]
                , button
                    [ class "action-btn"
                    , onClick TimerPresetSaveCancel
                    , Tooltips.attr "Cancel"
                    ]
                    [ text "Cancel" ]
                ]


enterKeyDecoder : Msg -> Decode.Decoder Msg
enterKeyDecoder msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                if key == "Enter" then
                    Decode.succeed msg

                else
                    Decode.fail "ignored key"
            )


presetLoadControl : TimerSetupUi -> Dict String TimerPreset -> Html Msg
presetLoadControl ui presets =
    let
        names =
            -- Case-insensitive alphabetical so "Bless" and "bless"
            -- don't get sorted into different ranges of the list.
            Dict.keys presets
                |> List.sortBy String.toLower

        empty =
            List.isEmpty names
    in
    div
        [ class "cond-footer__load-wrap"
        , stopPropagationOn "mousedown" (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class "action-btn cond-footer__load"
            , onClick TimerPresetLoadMenuToggle
            , disabled empty
            , attribute "aria-haspopup" "listbox"
            , attribute "aria-expanded"
                (if ui.loadMenuOpen then
                    "true"

                 else
                    "false"
                )
            , Tooltips.attr
                (if empty then
                    "No saved presets yet — click Save first"

                 else
                    "Load a saved preset"
                )
            ]
            [ text "Load ▾" ]
        , if ui.loadMenuOpen && not empty then
            div
                [ class "cond-footer__load-menu"
                , attribute "role" "listbox"
                ]
                (List.map presetMenuItem names)

          else
            text ""
        ]


presetMenuItem : String -> Html Msg
presetMenuItem name =
    div [ class "cond-footer__load-item" ]
        [ button
            [ class "cond-footer__load-item-name"
            , onClick (TimerPresetLoad name)
            , Tooltips.attr ("Load preset: " ++ name)
            , attribute "role" "option"
            ]
            [ text name ]
        , button
            [ class "cond-footer__load-item-delete"
            , stopPropagationOn "click"
                (Decode.succeed ( TimerPresetDelete name, True ))
            , Tooltips.attr ("Delete preset: " ++ name)
            , attribute "aria-label" ("Delete preset " ++ name)
            ]
            [ text "×" ]
        ]
