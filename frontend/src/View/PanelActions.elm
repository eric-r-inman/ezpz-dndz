module View.PanelActions exposing (view)

{-| Far-left column: the workspace's encounter-scoped triggers,
most of them opening a panel in the drawer beside it.

Whichever trigger's surface is showing wears the shared
editor-open ring, so the column says where it came from.

-}

import Encounter
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Model exposing (Model, PendingControl(..), Surface(..))
import Msg exposing (Msg(..))
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
        [ -- The encounter's own controls sit above the grid with
          -- no panel around them: they act on the encounter
          -- rather than opening anything.
          div [ class "actions-column__controls" ]
            [ div [ class "actions-column__pair" ]
                [ headerTrigger
                    (model.surface == Just (SurfaceConfirm PendingReset))
                    EncounterReset
                    Tooltips.reset
                    "⏮"
                , turnTrigger enc.activeName
                ]
            ]

        -- At icon size the triggers read as a keypad, so they
        -- share one grid.
        , div [ class "actions-column__grid" ]
            [ rollTrigger (Model.drawerHas Model.diceLens model) model.dice
            , trigger (showing Model.hpChangeLens)
                (HpChangeOpen target)
                Tooltips.manageHp
                "💜"
            , trigger (showing Model.statusLens)
                (StatusOpen target)
                Tooltips.statusEditor
                "❗"
            , trigger (showing Model.conditionLens)
                (ConditionOpenNew target)
                Tooltips.applyCondition
                "🌀"
            , trigger (showing Model.saveChainLens)
                (SaveChainOpen target)
                Tooltips.saveChain
                "🍀"
            , trigger (showing Model.initiativeLens)
                (InitiativeOpen target)
                Tooltips.initiativeManager
                "🏁"
            , trigger (showing Model.duplicateLens)
                (DuplicateOpen target)
                Tooltips.queueDuplicate
                "👥"
            , trigger (showing Model.replaceLens)
                (ReplaceOpen target)
                Tooltips.queueReplace
                "🔄"
            , trigger (showing Model.crCalculatorLens)
                CrCalculatorOpen
                Tooltips.difficultyButton
                "⚖️"
            , trigger (showing Model.treasureLens)
                TreasureOpen
                Tooltips.treasureButton
                "💰"
            , trigger (showing Model.xpLens)
                XpFilterToggle
                (Tooltips.xpFilterTotal
                    (View.Panel.Xp.label enc model.compendium.db model.xpScope)
                )
                "🏅"
            , trigger (showing Model.saveLoadLens)
                SaveLoadOpen
                (saveTip model)
                (saveLabel model)
            , trigger (model.surface == Just (SurfaceConfirm PendingClear))
                EncounterClear
                Tooltips.clear
                "🗑️"
            , trigger False
                CompendiumOpen
                Tooltips.panelOpenCompendium
                "📚"
            , trigger (showing Model.quickAddLens)
                QuickAddOpen
                Tooltips.quickAddButton
                "＋"
            , trigger (showing Model.randomEncounterLens)
                RandomEncounterOpen
                Tooltips.panelRandomEncounter
                "🎰"
            ]
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
        headerTrigger
            False
            EncounterRun
            Tooltips.runEncounter
            "▶"

    else
        headerTrigger
            False
            NextTurn
            Tooltips.nextTurn
            "⏭"


rollTrigger : Bool -> DiceUi -> Html Msg
rollTrigger open dice =
    triggerWithClass
        (if dice.unread then
            " dice-roll-btn--unread"

         else
            ""
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
        "🎲"


{-| Unsaved roster changes ride the label, not the button's
border. A border cue here is indistinguishable from the ring
every trigger wears while its panel is open, so a bordered
trigger reads as a panel that will not close.
-}
saveLabel : Model -> String
saveLabel model =
    if Encounter.rosterDirty model.encounter model.savedSnapshot then
        "💾•"

    else
        "💾"


saveTip : Model -> String
saveTip model =
    if Encounter.rosterDirty model.encounter model.savedSnapshot then
        Tooltips.saveButtonDirty

    else
        Tooltips.saveButton


{-| A trigger in the controls block's paired row: sized to
share that row rather than fill the column's width.
-}
headerTrigger : Bool -> Msg -> String -> String -> Html Msg
headerTrigger showing openMsg tip label =
    button
        [ class
            (View.Card.editorTriggerClass
                "action-btn panel-actions__header-btn"
                showing
            )
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


{-| One grid trigger. The glyph is the only label, so the
tooltip text doubles as the accessible name — nothing else in
the button says what it opens.
-}
trigger : Bool -> Msg -> String -> String -> Html Msg
trigger =
    triggerWithClass ""


{-| A trigger carrying a state class of its own, for the one
that marks unread rolls.
-}
triggerWithClass : String -> Bool -> Msg -> String -> String -> Html Msg
triggerWithClass extraClass showing openMsg tip glyph =
    button
        [ class
            (View.Card.editorTriggerClass
                ("action-btn panel-actions__btn" ++ extraClass)
                showing
            )
        , type_ "button"
        , onClick openMsg
        , Tooltips.attr
            (if showing then
                Tooltips.inlineEditCancel

             else
                tip
            )
        , attribute "aria-label" tip
        , attribute "aria-expanded"
            (if showing then
                "true"

             else
                "false"
            )
        ]
        [ text glyph ]
