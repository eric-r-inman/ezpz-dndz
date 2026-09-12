module View.Modal.Confirm exposing (view)

{-| Two-step confirmation for an action that cannot be undone.

The trigger only stages the action and this asks before anything
is touched. A modal rather than a drawer panel: it is the one
interruption the GM has to answer before doing anything else,
which is what the modal tier is for. The confirm button keeps the
colour of the button that staged it, so the visual association
survives the trip.

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
        -- The title carries the verb and its scope; the button
        -- carries the verb alone, so it reads as the answer to
        -- the question above it.
        spec =
            case pending of
                PendingReset ->
                    { message = "Reset every creature's HP to full and clear all conditions / status?"
                    , title = "Reset Encounter"
                    , confirmLabel = "Reset"
                    , confirmClass = "action-btn action-btn--orange"
                    , confirm = EncounterControlConfirm
                    , cancel = EncounterControlCancel
                    }

                PendingClear ->
                    { message = "Remove every creature and reset round to 1?"
                    , title = "Clear Encounter"
                    , confirmLabel = "Clear"
                    , confirmClass = "action-btn action-btn--red"
                    , confirm = EncounterControlConfirm
                    , cancel = EncounterControlCancel
                    }
    in
    View.Modal.view
        { close = spec.cancel
        , noOp = NoOp
        , title = spec.title
        , extraClass = "modal--confirm"
        , chrome = chrome
        , body =
            [ div [ class "control-confirm" ]
                [ p [ class "control-confirm__msg" ] [ text spec.message ]
                , div [ class "control-confirm__actions" ]
                    [ button
                        [ class "action-btn control-confirm__btn"
                        , onClick spec.cancel
                        ]
                        [ text "Cancel" ]
                    , button
                        [ class (spec.confirmClass ++ " control-confirm__btn")
                        , onClick spec.confirm
                        ]
                        [ text spec.confirmLabel ]
                    ]
                ]
            ]
        }
