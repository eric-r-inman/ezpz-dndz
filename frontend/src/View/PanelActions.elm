module View.PanelActions exposing (view)

{-| Far-left pane: a single column of the encounter toolbar's
editor triggers.

The buttons carry no handlers — the column is here to be judged
against the toolbar before either is wired (see =tasks.org=).

-}

import Html exposing (Html, button, div, section, text)
import Html.Attributes exposing (class, type_)


view : Html msg
view =
    section [ class "panel panel--actions" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Actions" ] ]
        , div [ class "panel__body panel__body--actions" ]
            [ trigger "action-btn action-btn--manage-hp" "Manage HP"
            , trigger "action-btn action-btn--blue" "Status"
            , trigger "action-btn action-btn--condition" "Condition"
            , trigger "action-btn action-btn--save-chain" "Save Chain"
            , trigger "action-btn action-btn--blue" "Initiative"
            , trigger "action-btn action-btn--orange" "Replace"
            , trigger "action-btn action-btn--orange" "Duplicate"
            ]
        ]


trigger : String -> String -> Html msg
trigger cls label =
    button
        [ class (cls ++ " panel-actions__btn")
        , type_ "button"
        ]
        [ text label ]
