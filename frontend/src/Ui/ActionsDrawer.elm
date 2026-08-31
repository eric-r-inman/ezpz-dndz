module Ui.ActionsDrawer exposing (ActionsDrawerUi, fresh, title)

{-| State of the panel the Actions column slides open.

This is not a `Surface` variant, and won't become one: the
drawer is the frame the editors are headed for, so a drawer that
closed whenever an editor opened would be self-defeating. It
sits beside `surface` for the same reason `Ui.QueuePanels` does.

The target is all the drawer knows about its contents so far —
the buttons carry no destination yet, so there is nothing else
to record.

@docs ActionsDrawerUi, fresh, title

-}

import Msg exposing (ActionsDrawerTarget(..))


type alias ActionsDrawerUi =
    { target : ActionsDrawerTarget
    }


fresh : ActionsDrawerTarget -> ActionsDrawerUi
fresh target =
    { target = target
    }


{-| What the drawer calls itself in its header. Kept apart from
the button faces, which carry glyphs and, for XP, a live number.
-}
title : ActionsDrawerTarget -> String
title target =
    case target of
        DrawerManageHp ->
            "Manage HP"

        DrawerStatus ->
            "Status"

        DrawerCondition ->
            "Condition"

        DrawerSaveChain ->
            "Save Chain"

        DrawerInitiative ->
            "Initiative"

        DrawerReplace ->
            "Replace"

        DrawerDuplicate ->
            "Duplicate"

        DrawerDifficulty ->
            "Difficulty"

        DrawerTreasure ->
            "Treasure"

        DrawerXp ->
            "XP"

        DrawerQuickAdd ->
            "Quick Add"

        DrawerSave ->
            "Save"

        DrawerLoad ->
            "Load"

        DrawerNextTurn ->
            "Next Turn"

        DrawerReset ->
            "Reset"

        DrawerClear ->
            "Clear"

        DrawerRoll ->
            "Dice Roller"

        DrawerCompendiumOpen ->
            "Compendium"

        DrawerCompendiumRandom ->
            "Random Encounter"
