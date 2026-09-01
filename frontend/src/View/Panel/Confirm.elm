module View.Panel.Confirm exposing (view)

{-| Two-step confirmation for Reset and Clear.

Both wipe combat state, so the column's button only stages the
action; the drawer asks before anything is touched. The confirm
button keeps the colour of the button that staged it, so the
visual association survives the trip across the workspace.

-}

import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Model exposing (PendingControl(..))
import Msg exposing (Msg(..))
import View.Panel


view : PendingControl -> Html Msg
view pending =
    let
        ( prompt, confirmLabel, confirmClass ) =
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
    View.Panel.view
        { close = EncounterControlCancel
        , title = confirmLabel
        , subtitle = Nothing
        , extraClass = "panel-drawer--confirm"
        , body =
            [ div [ class "control-confirm" ]
                [ p [ class "control-confirm__msg" ] [ text prompt ]
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
