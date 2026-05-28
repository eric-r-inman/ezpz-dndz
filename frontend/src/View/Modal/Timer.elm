module View.Modal.Timer exposing (view)

{-| Card row 3 timer-setup modal. The GM picks a turn count
(1..99) and a phase (begin/end of bearer's turn). Apply writes
the timer; Cancel discards.
-}

import Html exposing (Html, button, div, input, text)
import Html.Attributes as Attr exposing (autofocus, class, for, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Util.Keyboard
import View.Modal
import View.PhaseToggle


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalTimerSetup ui) ->
            View.Modal.view
                { close = TimerSetupCancel
                , noOp = NoOp
                , title = "Timer — " ++ ui.target
                , extraClass = "modal--timer"
                , chrome = model.modalChrome
                , body =
                    [ div [ class "cond-row" ]
                        [ Html.label [ for "timer-turns-input" ]
                            [ text "Lasts" ]
                        , input
                            [ id "timer-turns-input"
                            , class "cond-input cond-input--narrow"
                            , type_ "number"
                            , Attr.min "1"
                            , Attr.max "99"
                            , value ui.turnsText
                            , autofocus True
                            , onInput TimerSetupTurnsChanged
                            , Html.Events.on "keydown" (Util.Keyboard.enterKey TimerSetupApply)
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
                            , Html.Events.on "keydown" (Util.Keyboard.enterKey TimerSetupApply)
                            ]
                            []
                        ]
                    , div [ class "cond-section__caption" ]
                        [ text "When it reaches 0 the card flashes a 0 and the page plays a ping. Click × on the timer to dismiss." ]
                    , div [ class "note-edit__buttons" ]
                        [ button
                            [ class "action-btn action-btn--green"
                            , onClick TimerSetupApply
                            ]
                            [ text "Start Timer" ]
                        , button
                            [ class "action-btn"
                            , onClick TimerSetupCancel
                            ]
                            [ text "Cancel" ]
                        ]
                    ]
                }

        _ ->
            text ""
