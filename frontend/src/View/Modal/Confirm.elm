module View.Modal.Confirm exposing (view)

{-| Two-step confirmation for Reset and Clear.

Both wipe combat state, so the trigger only stages the action
and this asks before anything is touched. A modal rather than a
drawer panel: it is the one interruption the GM has to answer
before doing anything else, which is what the modal tier is
for. The confirm button keeps the colour of the button that
staged it, so the visual association survives the trip.

-}

import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Model exposing (Model, PendingControl(..), Surface(..))
import Msg exposing (Msg(..))
import Ui.ModalChrome exposing (ModalChrome)
import View.Modal


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceConfirm pending) ->
            prompt model.modalChrome pending

        _ ->
            text ""


prompt : ModalChrome -> PendingControl -> Html Msg
prompt chrome pending =
    let
        ( message, confirmLabel, confirmClass ) =
            case pending of
                PendingReset ->
                    ( "Reset every creature's HP to full and clear all conditions / status?"
                    , "Reset"
                    , "action-btn action-btn--orange"
                    )

                PendingClear ->
                    ( "Remove every creature and reset round to 1?"
                    , "Clear"
                    , "action-btn action-btn--red"
                    )
    in
    View.Modal.view
        { close = EncounterControlCancel
        , noOp = NoOp
        , title = confirmLabel
        , extraClass = "modal--confirm"
        , chrome = chrome
        , body =
            [ div [ class "control-confirm" ]
                [ p [ class "control-confirm__msg" ] [ text message ]
                , div [ class "control-confirm__actions" ]
                    [ button
                        [ class "action-btn control-confirm__btn"
                        , onClick EncounterControlCancel
                        ]
                        [ text "Cancel" ]
                    , button
                        [ class (confirmClass ++ " control-confirm__btn")
                        , onClick EncounterControlConfirm
                        ]
                        [ text confirmLabel ]
                    ]
                ]
            ]
        }
