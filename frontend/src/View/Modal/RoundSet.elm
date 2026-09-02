module View.Modal.RoundSet exposing (view)

{-| Round-setter: correct the round counter without advancing
the fight.

A fight starting over is the common reason to reach for this,
so it gets a shortcut of its own.

-}

import Html exposing (Html, button, div, input, text)
import Html.Attributes as Attr exposing (class, id, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Ui.ModalChrome exposing (ModalChrome)
import Ui.RoundSet exposing (RoundSetUi)
import Util.Keyboard
import View.Modal


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceRoundSet ui) ->
            body model.modalChrome ui

        _ ->
            text ""


body : ModalChrome -> RoundSetUi -> Html Msg
body chrome ui =
    View.Modal.view
        { close = RoundSetClose
        , noOp = NoOp
        , title = "Set Round"
        , extraClass = "modal--round-set"
        , chrome = chrome
        , body =
            [ div [ class "note-edit__buttons note-edit__buttons--start" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick RoundSetToOne
                    ]
                    [ text "Set to 1" ]
                ]
            , div [ class "cond-divider" ] []
            , div [ class "cond-row" ]
                [ Html.label [ Attr.for "round-set-input" ] [ text "Round:" ]
                , input
                    [ id "round-set-input"
                    , class "cond-input cond-input--w20"
                    , type_ "number"
                    , Attr.min "0"
                    , Attr.max "9999"
                    , value ui.roundText
                    , Attr.autofocus True
                    , onInput RoundSetTextChanged
                    , Html.Events.on "keydown" (Util.Keyboard.enterKey RoundSetApply)
                    ]
                    []
                , button
                    [ class "action-btn action-btn--green"
                    , onClick RoundSetApply
                    ]
                    [ text "Set" ]
                ]
            ]
        }
