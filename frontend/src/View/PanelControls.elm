module View.PanelControls exposing (view)

{-| Middle pane: encounter-control buttons (Add, Save, Load, Next
Turn, Reset, Clear) plus the always-visible dice-roll cluster
(latest-total readout, arrow, Roll button).

The Save / Load / Reset / Clear buttons are placeholders pending
their respective Msg handlers — they're rendered for layout but
don't fire anything yet.

-}

import Html exposing (Html, button, div, section, span, text)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Dice exposing (DiceUi)


view : DiceUi -> Html Msg
view dice =
    section [ class "panel panel--controls" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Encounter Controls" ]
            , div [ class "dice-roll-cluster" ]
                [ diceLastTotal dice
                , diceArrow dice
                , button
                    [ class
                        (if dice.unread then
                            "action-btn action-btn--green dice-roll-btn dice-roll-btn--unread"

                         else
                            "action-btn action-btn--green dice-roll-btn"
                        )
                    , onClick OpenDice
                    , title
                        (if dice.unread then
                            "Roll dice (new entries since last open)"

                         else
                            "Roll dice"
                        )
                    , attribute "aria-label" "Roll dice"
                    ]
                    [ text "🎲 Roll" ]
                ]
            ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid btn-grid--two-rows" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumOpen
                    , title "Browse the creature library"
                    ]
                    [ text "➕ Add Creature" ]
                , button [ class "action-btn action-btn--blue" ] [ text "💾 Save" ]
                , button [ class "action-btn action-btn--blue" ] [ text "📁 Load" ]
                , button
                    [ class "action-btn action-btn--green"
                    , onClick NextTurn
                    , title "Advance to the next creature in initiative order"
                    ]
                    [ text "⏭ Next Turn" ]
                , button [ class "action-btn action-btn--orange" ]
                    [ span [ class "btn-glyph" ] [ text "⟲" ]
                    , text " Reset"
                    ]
                , button [ class "action-btn action-btn--red" ] [ text "🗑 Clear" ]
                ]
            ]
        ]


{-| Latest dice-roll total displayed left of the Roll button. Bold
white integer (no formula, no source label) so the most recent
result is glanceable from across the table even with the modal
closed. Hidden when no rolls have landed yet.
-}
diceLastTotal : DiceUi -> Html Msg
diceLastTotal dice =
    case List.head dice.history.entries of
        Just roll ->
            span
                [ class "dice-last-total"
                , title "Last roll total"
                ]
                [ text (String.fromInt roll.total) ]

        Nothing ->
            text ""


{-| Left-facing arrow between the latest-total readout and the
Roll button, signalling that the number was emitted by the
roller. Hidden until at least one roll has landed so the
cluster isn't visually cluttered on first load.
-}
diceArrow : DiceUi -> Html Msg
diceArrow dice =
    if List.isEmpty dice.history.entries then
        text ""

    else
        span
            [ class "dice-arrow"
            , attribute "aria-hidden" "true"
            ]
            [ text "←" ]
