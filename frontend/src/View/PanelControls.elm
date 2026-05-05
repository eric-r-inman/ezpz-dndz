module View.PanelControls exposing (view)

{-| Middle pane: encounter-control buttons (Add, Save, Load, Next
Turn, Reset, Clear) plus the always-visible dice-roll cluster
(latest-total readout, arrow, Roll button).

Save / Load open their respective modals; Reset reverts the
encounter to the last-saved snapshot (and forces round 1);
Clear empties the queue back to the default empty state.

When `pendingControl` is `Just`, the panel body swaps the button
grid for an inline confirmation banner so the GM can back out
of a Reset / Clear before any state is touched.

-}

import Html exposing (Html, button, div, p, section, span, text)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick)
import Model exposing (PendingControl(..))
import Msg exposing (Msg(..))
import Ui.Dice exposing (DiceUi)


view : DiceUi -> Maybe PendingControl -> Int -> Html Msg
view dice pendingControl round =
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
            [ case pendingControl of
                Just pending ->
                    confirmBanner pending

                Nothing ->
                    buttonGrid round
            ]
        ]


buttonGrid : Int -> Html Msg
buttonGrid round =
    div [ class "btn-grid btn-grid--two-rows" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick QuickAddOpen
            , title "Quick-add a creature from the compendium (alpha or CR sort)"
            ]
            [ text "➕ Quick Add" ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick SaveOpen
            , title "Save the encounter to the server or download to your device"
            ]
            [ text "💾 Save" ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick LoadOpen
            , title "Load a saved encounter from the server or your device"
            ]
            [ text "📁 Load" ]
        , turnOrRunButton round
        , button
            [ class "action-btn action-btn--orange"
            , onClick EncounterReset
            , title "Revert the encounter to its last-saved state and reset round counter to 1"
            ]
            [ span [ class "btn-glyph" ] [ text "⟲" ]
            , text " Reset"
            ]
        , button
            [ class "action-btn action-btn--red"
            , onClick EncounterClear
            , title "Remove every creature and reset round counter to 1"
            ]
            [ text "🗑 Clear" ]
        ]


{-| Round-0 is the pre-combat sentinel: the queue is set up but
combat hasn't started yet, so the green action button reads
"Run Encounter" and dispatches `EncounterRun` (which bumps round
to 1 and picks the highest-initiative creature as active).
Once combat is live, the button reverts to its normal "Next
Turn" function.
-}
turnOrRunButton : Int -> Html Msg
turnOrRunButton round =
    if round == 0 then
        button
            [ class "action-btn action-btn--green"
            , onClick EncounterRun
            , title "Begin combat — round 1, highest-initiative creature acts"
            ]
            [ text "▶ Run Encounter" ]

    else
        button
            [ class "action-btn action-btn--green"
            , onClick NextTurn
            , title "Advance to the next creature in initiative order"
            ]
            [ text "⏭ Next Turn" ]


{-| Inline confirmation strip rendered in place of the button
grid when a destructive control action is staged. The confirm
button keeps the same color as the original action button so
the visual association ("the orange button I clicked") survives
the swap.
-}
confirmBanner : PendingControl -> Html Msg
confirmBanner pending =
    let
        ( prompt, confirmLabel, confirmClass ) =
            case pending of
                PendingReset ->
                    ( "Reset the encounter to its last-saved state and round 1?"
                    , "Reset"
                    , "action-btn action-btn--orange"
                    )

                PendingClear ->
                    ( "Remove every creature and reset round to 1?"
                    , "Clear"
                    , "action-btn action-btn--red"
                    )
    in
    div [ class "control-confirm" ]
        [ p [ class "control-confirm__msg" ] [ text prompt ]
        , div [ class "control-confirm__actions" ]
            [ button
                [ class "action-btn"
                , onClick EncounterControlCancel
                ]
                [ text "Cancel" ]
            , button
                [ class confirmClass
                , onClick EncounterControlConfirm
                ]
                [ text confirmLabel ]
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
