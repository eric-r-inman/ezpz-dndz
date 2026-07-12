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

import Auth
import Html exposing (Html, button, div, p, section, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Model exposing (PendingControl(..))
import Msg exposing (ControlMenu(..), Msg(..), SaveDestination(..))
import Ui.Dice exposing (DiceUi)
import View.Tooltips as Tooltips


view : Auth.AuthState -> DiceUi -> Maybe PendingControl -> Int -> Bool -> Maybe ControlMenu -> Html Msg
view auth dice pendingControl round rosterDirty controlMenu =
    section [ class "panel panel--controls" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Encounter Controls" ]
            , div [ class "dice-roll-cluster" ]
                [ dicePreviousTotals dice
                , diceLastTotal dice
                , diceArrow dice
                , button
                    [ class
                        (if dice.unread then
                            "action-btn action-btn--green dice-roll-btn dice-roll-btn--unread"

                         else
                            "action-btn action-btn--green dice-roll-btn"
                        )
                    , onClick OpenDice
                    , Tooltips.attr
                        (if dice.unread then
                            Tooltips.rollDiceUnread

                         else
                            Tooltips.rollDice
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
                    buttonGrid auth round rosterDirty controlMenu
            ]
        ]


buttonGrid : Auth.AuthState -> Int -> Bool -> Maybe ControlMenu -> Html Msg
buttonGrid auth round rosterDirty controlMenu =
    div [ class "btn-grid btn-grid--two-rows" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick QuickAddOpen
            , Tooltips.attr Tooltips.quickAddButton
            ]
            [ text "➕ Quick Add" ]
        , saveMenu auth rosterDirty (controlMenu == Just SaveControlMenu)
        , loadMenu auth (controlMenu == Just LoadControlMenu)
        , turnOrRunButton round
        , button
            [ class "action-btn action-btn--orange"
            , onClick EncounterReset
            , Tooltips.attr Tooltips.reset
            ]
            [ span [ class "btn-glyph" ] [ text "⟲" ]
            , text " Reset"
            ]
        , button
            [ class "action-btn action-btn--red"
            , onClick EncounterClear
            , Tooltips.attr Tooltips.clear
            ]
            [ text "🗑 Clear" ]
        ]


{-| Save button. Single-click opens the Save modal which now
carries the Server / Device radio pair (matching the Compendium
Export pattern), so the previous split-button dropdown was
redundant.

`rosterDirty` lights the button yellow when the encounter has
unsaved changes — same dirty-highlight behaviour as before.

The default destination is `SaveDestinationServer` because that
maps to the user's primary storage (server when authenticated,
`localStorage` when anonymous); flipping to Device in the modal
remains one click.

-}
saveMenu : Auth.AuthState -> Bool -> Bool -> Html Msg
saveMenu _ rosterDirty _ =
    let
        triggerClass =
            if rosterDirty then
                "action-btn action-btn--blue action-btn--dirty"

            else
                "action-btn action-btn--blue"

        triggerTitle =
            if rosterDirty then
                Tooltips.saveButtonDirty

            else
                Tooltips.saveButton
    in
    button
        [ class triggerClass
        , onClick (SaveOpen SaveDestinationServer)
        , Tooltips.attr triggerTitle
        ]
        [ text "💾 Save" ]


{-| Load button. Mirrors `saveMenu`: single click opens the
Load modal whose own Server / Device radios cover what the
old dropdown used to.
-}
loadMenu : Auth.AuthState -> Bool -> Html Msg
loadMenu _ _ =
    button
        [ class "action-btn action-btn--blue"
        , onClick LoadOpen
        , Tooltips.attr Tooltips.loadButton
        ]
        [ text "📁 Load" ]


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
            , Tooltips.attr Tooltips.runEncounter
            ]
            [ text "▶ Run Encounter" ]

    else
        button
            [ class "action-btn action-btn--green"
            , onClick NextTurn
            , Tooltips.attr Tooltips.nextTurn
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
                    ( "Reset every creature's HP to full and clear all conditions / status?"
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
            let
                cls =
                    if dice.flashLatest then
                        "dice-last-total dice-last-total--flash"

                    else
                        "dice-last-total"
            in
            span
                [ class cls
                , Tooltips.attr Tooltips.lastRollTotal
                ]
                [ text (String.fromInt roll.total) ]

        Nothing ->
            text ""


{-| Up to three previous-roll totals rendered in muted text to
the LEFT of the current `diceLastTotal`, oldest-first so the
sequence reads naturally as `[older … newer] [current] ← Roll`.
Skips when there's no history beyond the current roll. The
muted colour comes from `--color-text-muted` so the row reads
as "context, not the headline."
-}
dicePreviousTotals : DiceUi -> Html Msg
dicePreviousTotals dice =
    let
        previous =
            dice.history.entries
                |> List.drop 1
                |> List.take 3
                |> List.reverse
    in
    if List.isEmpty previous then
        text ""

    else
        span [ class "dice-previous-totals" ]
            (List.map
                (\r ->
                    span [ class "dice-previous-total" ]
                        [ text (String.fromInt r.total) ]
                )
                previous
            )


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
