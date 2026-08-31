module View.Page.Donate exposing (view)

{-| Donate page at `/donate`.

Currently an under-construction placeholder wrapped in the
standard workspace / panel chrome so it inherits the app's
layout and theming.

@docs view

-}

import Html exposing (Html, div, p, section, text)
import Html.Attributes exposing (class)


view : Html msg
view =
    div [ class "workspace" ]
        [ section [ class "panel panel--main panel--solo" ]
            [ div [ class "panel__header" ]
                [ div [ class "panel__title" ] [ text "Donate" ] ]
            , div [ class "panel__body" ]
                [ p [ class "empty" ]
                    [ text "This page is under construction. Thanks for thinking about supporting the project!" ]
                ]
            ]
        ]
