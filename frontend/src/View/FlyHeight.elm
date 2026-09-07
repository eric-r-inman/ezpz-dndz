module View.FlyHeight exposing (Controls, view)

{-| The flight-height widget, parameterised on its messages so the
Status editor's draft and a card's creature can share it — the
messages are the whole difference between the two.

@docs Controls, view

-}

import Html exposing (Html, button, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


type alias Controls =
    { height : Int
    , up : Msg
    , down : Msg
    , fall : Msg
    }


view : Controls -> Html Msg
view c =
    span [ class "fly-height" ]
        [ button
            [ class "fly-height__btn"
            , onClick c.up
            , Tooltips.attr Tooltips.flyHeightUp
            , attribute "aria-label" "Increase flight height by 5 feet"
            ]
            [ text "▲" ]
        , span [ class "fly-height__value" ]
            [ text (String.fromInt c.height) ]
        , button
            [ class "fly-height__btn"
            , onClick c.down
            , Tooltips.attr Tooltips.flyHeightDown
            , attribute "aria-label" "Decrease flight height by 5 feet"
            ]
            [ text "▼" ]
        , span [ class "fly-height__unit" ] [ text "ft" ]
        , button
            [ class "icon-btn icon-btn--sm fly-height__fall"
            , onClick c.fall
            , Tooltips.attr Tooltips.fallDamage
            , attribute "aria-label" "Roll falling damage"
            ]
            [ text "↯" ]
        ]
