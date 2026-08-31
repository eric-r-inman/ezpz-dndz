module View.PanelActions exposing (view)

{-| Far-left pane: a single column of the workspace's triggers.

No button leads anywhere yet — every one of them slides the same
empty drawer open, so the shape of that interaction can be seen
before the editors are moved into it. The column is a proposal,
weighed against today's placements before the winner is wired
and the loser dropped (see =tasks.org=).

-}

import Encounter exposing (Encounter)
import Encounter.Xp as Xp exposing (XpScope)
import Html exposing (Html, button, div, h3, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (ActionsDrawerTarget(..), Msg(..))
import Ui.ActionsDrawer exposing (ActionsDrawerUi)
import Ui.Compendium exposing (CompendiumDb(..))
import View.Card


view : Encounter -> CompendiumDb -> XpScope -> Maybe ActionsDrawerUi -> Html Msg
view enc db xpScope drawer =
    let
        trigger cls target label =
            let
                showing =
                    Maybe.map .target drawer == Just target
            in
            button
                [ class
                    (View.Card.editorTriggerClass (cls ++ " panel-actions__btn")
                        showing
                    )
                , type_ "button"
                , onClick (ActionsDrawerToggle target)
                , attribute "aria-expanded"
                    (if showing then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text label ]
    in
    section [ class "panel panel--actions" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Actions" ] ]
        , div [ class "panel__body panel__body--actions" ]
            [ trigger "action-btn action-btn--manage-hp" DrawerManageHp "Manage HP"
            , trigger "action-btn action-btn--blue" DrawerStatus "Status"
            , trigger "action-btn action-btn--condition" DrawerCondition "Condition"
            , trigger "action-btn action-btn--save-chain" DrawerSaveChain "Save Chain"
            , trigger "action-btn action-btn--blue" DrawerInitiative "Initiative"
            , trigger "action-btn action-btn--orange" DrawerReplace "Replace"
            , trigger "action-btn action-btn--orange" DrawerDuplicate "Duplicate"

            -- A trigger with no button of its own elsewhere takes
            -- the neutral face; every other one keeps the colour
            -- and glyph it wears where it lives now.
            , trigger "action-btn" DrawerDifficulty "Difficulty"
            , trigger "action-btn" DrawerTreasure "Treasure"
            , trigger "action-btn" DrawerXp (xpLabel enc db xpScope)
            , trigger "action-btn action-btn--blue" DrawerQuickAdd "➕ Quick Add"
            , trigger "action-btn action-btn--blue" DrawerSave "💾 Save"
            , trigger "action-btn action-btn--blue" DrawerLoad "📁 Load"

            -- Before combat starts this button reads "Run
            -- Encounter" instead; an unwired column has no round
            -- to read, so it shows the in-combat face.
            , trigger "action-btn action-btn--green" DrawerNextTurn "⏭ Next Turn"
            , trigger "action-btn action-btn--orange" DrawerReset "⟲ Reset"
            , trigger "action-btn action-btn--red" DrawerClear "🗑 Clear"
            , trigger "action-btn action-btn--green" DrawerRoll "🎲 Roll"
            , heading "Compendium"
            , trigger "action-btn action-btn--blue" DrawerCompendiumOpen "📖 Open"
            , trigger "action-btn action-btn--blue" DrawerCompendiumRandom "🎲 Random"
            ]
        ]


{-| The title bar's XP total, restated on the column's own face.
The scope comes from the selector that stays up there, so the
two readouts can't disagree.
-}
xpLabel : Encounter -> CompendiumDb -> XpScope -> String
xpLabel enc db scope =
    case db of
        CompendiumDbLoaded loaded ->
            Xp.formatThousands (Xp.totalsFor scope enc loaded).total ++ " XP"

        _ ->
            "— XP"


heading : String -> Html msg
heading label =
    h3 [ class "panel-actions__heading" ] [ text label ]
