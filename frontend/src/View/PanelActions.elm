module View.PanelActions exposing (view)

{-| Far-left column: the workspace's encounter-scoped triggers,
grouped by what they act on, most of them opening a panel in
the drawer beside it.

Whichever trigger's surface is showing wears the shared
editor-open ring, so the column says where it came from.

-}

import Encounter
import Html exposing (Html, button, div, section, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Model exposing (Model, PendingControl(..), Surface(..))
import Msg exposing (Msg(..), SaveDestination(..))
import Ui.Dice exposing (DiceUi)
import View.Card
import View.Panel.Xp
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    let
        enc =
            model.encounter

        -- Every editor aims at the active creature, falling back
        -- to the top of the queue before combat starts; their
        -- own "apply to selected" buttons cover the rest.
        target =
            if String.isEmpty enc.activeName then
                enc.creatures
                    |> List.head
                    |> Maybe.map .name
                    |> Maybe.withDefault ""

            else
                enc.activeName

        showing lens =
            Model.drawerHas lens model
    in
    div [ class "actions-column" ]
        [ -- The encounter's own controls sit above the grouped
          -- triggers with no panel around them: they belong to
          -- no one creature or reference, so a heading would
          -- have to invent a category for them.
          div [ class "actions-column__controls" ]
            [ div [ class "actions-column__pair" ]
                [ headerTrigger "action-btn action-btn--orange"
                    (model.surface == Just (SurfaceConfirm PendingReset))
                    EncounterReset
                    Tooltips.reset
                    "⏮"
                , turnTrigger enc.activeName
                ]
            , rollTrigger (Model.drawerHas Model.diceLens model) model.dice
            , diceTotals model.dice
            ]
        , group "Compendium"
            [ trigger "action-btn action-btn--blue"
                False
                CompendiumOpen
                Tooltips.panelOpenCompendium
                "Open"
            , trigger "action-btn action-btn--blue"
                (showing Model.quickAddLens)
                QuickAddOpen
                Tooltips.quickAddButton
                "Quick Add"
            , trigger "action-btn action-btn--blue"
                (showing Model.randomEncounterLens)
                RandomEncounterOpen
                Tooltips.panelRandomEncounter
                "Random"
            ]
        , group "Encounter"
            [ trigger "action-btn"
                (showing Model.crCalculatorLens)
                CrCalculatorOpen
                Tooltips.difficultyButton
                "Difficulty"
            , trigger "action-btn"
                (showing Model.treasureLens)
                TreasureOpen
                Tooltips.treasureButton
                "Treasure"
            , trigger "action-btn"
                (showing Model.xpLens)
                XpFilterToggle
                Tooltips.xpFilter
                (View.Panel.Xp.label enc model.compendium.db model.xpScope)
            , trigger (saveClass model)
                (showing Model.saveLens)
                (SaveOpen SaveDestinationServer)
                (saveTip model)
                "Save"
            , trigger "action-btn action-btn--blue"
                (showing Model.loadLens)
                LoadOpen
                Tooltips.loadButton
                "Load"
            , trigger "action-btn action-btn--red"
                (model.surface == Just (SurfaceConfirm PendingClear))
                EncounterClear
                Tooltips.clear
                "Clear"
            ]
        , group "Creature"
            [ trigger "action-btn action-btn--manage-hp"
                (showing Model.hpChangeLens)
                (HpChangeOpen target)
                Tooltips.manageHp
                "HP"
            , trigger "action-btn action-btn--blue"
                (showing Model.statusLens)
                (StatusOpen target)
                Tooltips.statusEditor
                "Status"
            , trigger "action-btn action-btn--condition"
                (showing Model.conditionLens)
                (ConditionOpenNew target)
                Tooltips.applyCondition
                "Condition"
            , trigger "action-btn action-btn--save-chain"
                (showing Model.saveChainLens)
                (SaveChainOpen target)
                Tooltips.saveChain
                "Save Chain"
            , trigger "action-btn action-btn--blue"
                (showing Model.initiativeLens)
                (InitiativeOpen target)
                Tooltips.initiativeManager
                "Initiative"
            , trigger "action-btn action-btn--orange"
                (showing Model.duplicateLens)
                (DuplicateOpen target)
                Tooltips.queueDuplicate
                "Duplicate"
            , trigger "action-btn action-btn--orange"
                (showing Model.replaceLens)
                (ReplaceOpen target)
                Tooltips.queueReplace
                "Replace"
            ]
        ]


{-| One titled block of triggers. The heading is the block's
own panel header, so the groups read as peers of the drawer
panels beside them.
-}
group : String -> List (Html Msg) -> Html Msg
group heading triggers =
    section [ class "panel" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text heading ] ]
        , div [ class "panel__body panel__body--actions" ] triggers
        ]


{-| An empty active creature is the pre-combat sentinel: the
queue is set up but combat hasn't started, so the button starts
it rather than advancing it. Only the glyph changes — the
column has no room for a label, and the tooltip carries the
distinction.
-}
turnTrigger : String -> Html Msg
turnTrigger activeName =
    if String.isEmpty activeName then
        headerTrigger "action-btn action-btn--green"
            False
            EncounterRun
            Tooltips.runEncounter
            "▶"

    else
        headerTrigger "action-btn action-btn--green"
            False
            NextTurn
            Tooltips.nextTurn
            "⏭"


rollTrigger : Bool -> DiceUi -> Html Msg
rollTrigger open dice =
    trigger
        (if dice.unread then
            "action-btn action-btn--green dice-roll-btn dice-roll-btn--unread"

         else
            "action-btn action-btn--green"
        )
        open
        (if open then
            CloseDice

         else
            OpenDice
        )
        (if dice.unread then
            Tooltips.rollDiceUnread

         else
            Tooltips.rollDice
        )
        "🎲 Roll"


{-| The last roll's total plus the three before it, oldest
first, so the run reads left to right into the newest. Sits
under the Roll button rather than inside the roller: the point
is to be readable from across the table with nothing open.
-}
diceTotals : DiceUi -> Html Msg
diceTotals dice =
    case dice.history.entries of
        [] ->
            text ""

        newest :: older ->
            div [ class "dice-totals" ]
                ((older
                    |> List.take 3
                    |> List.reverse
                    |> List.map
                        (\r ->
                            span [ class "dice-previous-total" ]
                                [ text (String.fromInt r.total) ]
                        )
                 )
                    ++ [ span
                            [ class
                                (if dice.flashLatest then
                                    "dice-last-total dice-last-total--flash"

                                 else
                                    "dice-last-total"
                                )
                            , Tooltips.attr Tooltips.lastRollTotal
                            ]
                            [ text (String.fromInt newest.total) ]
                       ]
                )


{-| Save lights up yellow while the encounter has changes the
last save didn't capture.
-}
saveClass : Model -> String
saveClass model =
    if Encounter.rosterDirty model.encounter model.savedSnapshot then
        "action-btn action-btn--blue action-btn--dirty"

    else
        "action-btn action-btn--blue"


saveTip : Model -> String
saveTip model =
    if Encounter.rosterDirty model.encounter model.savedSnapshot then
        Tooltips.saveButtonDirty

    else
        Tooltips.saveButton


{-| A trigger in the controls block's paired row: sized to
share that row rather than fill the column's width.
-}
headerTrigger : String -> Bool -> Msg -> String -> String -> Html Msg
headerTrigger cls showing openMsg tip label =
    button
        [ class (View.Card.editorTriggerClass (cls ++ " panel-actions__header-btn") showing)
        , type_ "button"
        , onClick openMsg
        , Tooltips.attr tip
        , attribute "aria-label" tip
        , attribute "aria-expanded"
            (if showing then
                "true"

             else
                "false"
            )
        ]
        [ text label ]


trigger : String -> Bool -> Msg -> String -> String -> Html Msg
trigger cls showing openMsg tip label =
    button
        [ class (View.Card.editorTriggerClass (cls ++ " panel-actions__btn") showing)
        , type_ "button"
        , onClick openMsg
        , Tooltips.attr
            (if showing then
                Tooltips.inlineEditCancel

             else
                tip
            )
        , attribute "aria-expanded"
            (if showing then
                "true"

             else
                "false"
            )
        ]
        [ text label ]
