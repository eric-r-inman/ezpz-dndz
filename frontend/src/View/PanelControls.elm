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
import Json.Decode as Decode
import Model exposing (PendingControl(..))
import Msg exposing (ControlMenu(..), Msg(..), SaveDestination(..))
import Ui.Dice exposing (DiceUi)
import View.Tooltips as Tooltips


view : DiceUi -> Maybe PendingControl -> Int -> Bool -> Maybe ControlMenu -> Html Msg
view dice pendingControl round rosterDirty controlMenu =
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
                    buttonGrid round rosterDirty controlMenu
            ]
        ]


buttonGrid : Int -> Bool -> Maybe ControlMenu -> Html Msg
buttonGrid round rosterDirty controlMenu =
    div [ class "btn-grid btn-grid--two-rows" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick QuickAddOpen
            , title Tooltips.quickAddButton
            ]
            [ text "➕ Quick Add" ]
        , saveMenu rosterDirty (controlMenu == Just SaveControlMenu)
        , loadMenu (controlMenu == Just LoadControlMenu)
        , turnOrRunButton round
        , button
            [ class "action-btn action-btn--orange"
            , onClick EncounterReset
            , title Tooltips.reset
            ]
            [ span [ class "btn-glyph" ] [ text "⟲" ]
            , text " Reset"
            ]
        , button
            [ class "action-btn action-btn--red"
            , onClick EncounterClear
            , title Tooltips.clear
            ]
            [ text "🗑 Clear" ]
        ]


{-| Save split-button + popover dropdown. The trigger toggles the
popover; menu items dispatch `SaveOpen` with the chosen
destination. The wrapper stops `mousedown` propagation so a click
inside the menu doesn't bubble to the document-level
"click-outside closes" handler in `Main.subscriptions`.

`rosterDirty` lights the trigger yellow when the encounter has
unsaved changes — same dirty-highlight behavior as the old plain
Save button.

-}
saveMenu : Bool -> Bool -> Html Msg
saveMenu rosterDirty isOpen =
    let
        triggerClass =
            if rosterDirty then
                "action-btn action-btn--blue action-btn--dirty control-menu__trigger"

            else
                "action-btn action-btn--blue control-menu__trigger"

        wrapperClass =
            if isOpen then
                "control-menu control-menu--open"

            else
                "control-menu"

        triggerTitle =
            if rosterDirty then
                Tooltips.saveButtonDirty

            else
                Tooltips.saveButton
    in
    div
        [ class wrapperClass
        , Html.Events.stopPropagationOn "mousedown"
            (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class triggerClass
            , onClick (ControlMenuToggle SaveControlMenu)
            , title triggerTitle
            , attribute "aria-haspopup" "menu"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            ]
            [ text "💾 Save ▾" ]
        , if isOpen then
            div
                [ class "control-menu__list"
                , attribute "role" "menu"
                ]
                [ button
                    [ class "control-menu__item"
                    , onClick (SaveOpen SaveDestinationServer)
                    , attribute "role" "menuitem"
                    ]
                    [ text "To Server" ]
                , button
                    [ class "control-menu__item"
                    , onClick (SaveOpen SaveDestinationDevice)
                    , attribute "role" "menuitem"
                    ]
                    [ text "To Device" ]
                ]

          else
            text ""
        ]


{-| Load split-button + popover dropdown. Mirrors `saveMenu`.
"From Server" opens the existing Load modal; "From Device"
fires the file-picker (`LoadFromDeviceClick`).
-}
loadMenu : Bool -> Html Msg
loadMenu isOpen =
    let
        wrapperClass =
            if isOpen then
                "control-menu control-menu--open"

            else
                "control-menu"
    in
    div
        [ class wrapperClass
        , Html.Events.stopPropagationOn "mousedown"
            (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class "action-btn action-btn--blue control-menu__trigger"
            , onClick (ControlMenuToggle LoadControlMenu)
            , title Tooltips.loadButton
            , attribute "aria-haspopup" "menu"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            ]
            [ text "📁 Load ▾" ]
        , if isOpen then
            div
                [ class "control-menu__list"
                , attribute "role" "menu"
                ]
                [ button
                    [ class "control-menu__item"
                    , onClick LoadOpen
                    , attribute "role" "menuitem"
                    ]
                    [ text "From Server" ]
                , button
                    [ class "control-menu__item"
                    , onClick LoadFromDeviceClick
                    , attribute "role" "menuitem"
                    ]
                    [ text "From Device" ]
                ]

          else
            text ""
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
            , title Tooltips.runEncounter
            ]
            [ text "▶ Run Encounter" ]

    else
        button
            [ class "action-btn action-btn--green"
            , onClick NextTurn
            , title Tooltips.nextTurn
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
                , title Tooltips.lastRollTotal
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
