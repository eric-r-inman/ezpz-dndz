module View.PanelActions exposing (view)

{-| Far-left pane: a single column of the workspace's triggers.

The buttons carry no handlers — the column is a proposal,
weighed against today's placements before the winner is wired
and the loser dropped (see =tasks.org=).

-}

import Html exposing (Html, button, div, h3, section, text)
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

            -- A trigger with no button of its own elsewhere takes
            -- the neutral face; every other one keeps the colour
            -- and glyph it wears where it lives now.
            , trigger "action-btn" "Difficulty"
            , trigger "action-btn" "Treasure"
            , trigger "action-btn action-btn--blue" "➕ Quick Add"
            , trigger "action-btn action-btn--blue" "💾 Save"
            , trigger "action-btn action-btn--blue" "📁 Load"

            -- Before combat starts this button reads "Run
            -- Encounter" instead; an unwired column has no round
            -- to read, so it shows the in-combat face.
            , trigger "action-btn action-btn--green" "⏭ Next Turn"
            , trigger "action-btn action-btn--orange" "⟲ Reset"
            , trigger "action-btn action-btn--red" "🗑 Clear"
            , trigger "action-btn action-btn--green" "🎲 Roll"
            , heading "Compendium"
            , trigger "action-btn action-btn--blue" "📖 Open"
            , trigger "action-btn action-btn--blue" "🎲 Random"
            ]
        ]


heading : String -> Html msg
heading label =
    h3 [ class "panel-actions__heading" ] [ text label ]


trigger : String -> String -> Html msg
trigger cls label =
    button
        [ class (cls ++ " panel-actions__btn")
        , type_ "button"
        ]
        [ text label ]
