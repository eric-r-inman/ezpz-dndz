module View.Compendium.Pane exposing (chrome)

{-| Shared chrome for an editor occupying the compendium page's
detail pane — the space the selected stat block normally fills.
An editor here replaces the stat block rather than covering the
page, so the list stays browsable while it is open.

@docs chrome

-}

import Html exposing (Html, button, div, h3, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


chrome :
    { title : String
    , close : Msg
    , extraClass : String
    , body : List (Html Msg)
    }
    -> Html Msg
chrome config =
    section [ class ("compendium__editor-pane " ++ config.extraClass) ]
        [ div [ class "compendium__editor-pane-head" ]
            [ h3 [ class "compendium__editor-pane-title" ] [ text config.title ]
            , button
                [ class "compendium__editor-pane-close"
                , type_ "button"
                , onClick config.close
                , Tooltips.attr Tooltips.compendiumEditorClose
                , attribute "aria-label" Tooltips.compendiumEditorClose
                ]
                [ text "✕" ]
            ]
        , div [ class "compendium__editor-pane-body" ] config.body
        ]
