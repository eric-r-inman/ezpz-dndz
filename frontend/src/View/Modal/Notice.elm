module View.Modal.Notice exposing (view)

{-| A refusal the GM has to read before carrying on.

Distinct from a toast, which says what happened and slides away:
this says what did not happen, and the work the GM asked for is
still sitting in the form behind it.

@docs view

-}

import Html exposing (Html, button, div, p, text)
import Html.Attributes exposing (class)
import Html.Events exposing (onClick)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Ui.ModalChrome exposing (ModalChrome)
import View.Modal


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceNotice message) ->
            body model.modalChrome message

        _ ->
            text ""


body : ModalChrome -> String -> Html Msg
body chrome message =
    View.Modal.view
        { close = NoticeDismiss
        , noOp = NoOp
        , title = "Not applied"
        , extraClass = "modal--confirm"
        , chrome = chrome
        , body =
            [ div [ class "control-confirm" ]
                [ p [ class "control-confirm__msg" ] [ text message ]
                , div [ class "control-confirm__actions" ]
                    [ button
                        [ class "action-btn control-confirm__btn"
                        , onClick NoticeDismiss
                        ]
                        [ text "OK" ]
                    ]
                ]
            ]
        }
