module View.Page.NotFound exposing (view)

{-| 404 page for unrecognized routes.

Wrapped in the standard workspace / panel chrome so a bad URL
still lands somewhere that looks like the app rather than a
bare error string.

@docs view

-}

import Html exposing (Html, div, p, section, text)
import Html.Attributes exposing (class)


view : Html msg
view =
    div [ class "workspace" ]
        [ section [ class "panel panel--main" ]
            [ div [ class "panel__header" ]
                [ div [ class "panel__title" ] [ text "Not Found" ] ]
            , div [ class "panel__body" ]
                [ p [ class "empty" ]
                    [ text "The page you requested does not exist." ]
                ]
            ]
        ]
