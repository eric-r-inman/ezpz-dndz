module View.PanelDrawer exposing (Panel(..), current, isOpen, view)

{-| The Actions column's panel: a second workspace column
holding whatever the column last opened.

One panel shows at a time. Its candidates are spread across
several model fields, so `current` spells the precedence out
rather than letting it fall out of whichever field happened to
be set; `Update.PanelDrawer.soleOpen` keeps them from being set
at once, and this order decides what shows if they ever are.

`current` is also what the Actions column rings its open button
against, so the ring can't disagree with what the drawer is
rendering.

@docs Panel, current, isOpen, view

-}

import Html exposing (Html, text)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import View.Inline.Condition
import View.Inline.Duplicate
import View.Inline.HpChange
import View.Inline.Initiative
import View.Inline.Replace
import View.Inline.SaveChain
import View.Inline.Status
import View.Panel
import View.Panel.Confirm
import View.Panel.CrCalculator
import View.Panel.Dice
import View.Panel.Load
import View.Panel.QuickAdd
import View.Panel.RandomEncounter
import View.Panel.Save
import View.Panel.StatBlock
import View.Panel.Treasure
import View.Panel.Xp


type Panel
    = PanelHpChange
    | PanelStatus
    | PanelCondition
    | PanelSaveChain
    | PanelInitiative
    | PanelReplace
    | PanelDuplicate
    | PanelDifficulty
    | PanelTreasure
    | PanelXp
    | PanelQuickAdd
    | PanelSave
    | PanelLoad
    | PanelDice
    | PanelRandomEncounter
    | PanelConfirm
    | PanelStatBlock
    | PanelNone


current : Model -> Panel
current model =
    case ( model.pendingControl, Maybe.andThen surfacePanel model.surface ) of
        ( Just _, _ ) ->
            PanelConfirm

        ( Nothing, Just panel ) ->
            panel

        ( Nothing, Nothing ) ->
            if model.dice.open then
                PanelDice

            else if model.xpFilterOpen then
                PanelXp

            else if model.panelCreaturePin /= Nothing then
                PanelStatBlock

            else
                PanelNone


{-| Card-inline editors and the surfaces still wearing modal
chrome answer `Nothing`, so they leave the drawer showing
whatever it had. The variants answered here are the ones
`Model.isDrawerSurface` accepts — the two lists have to move
together.
-}
surfacePanel : Surface -> Maybe Panel
surfacePanel surface =
    case surface of
        SurfaceHpChange _ ->
            Just PanelHpChange

        SurfaceStatus _ ->
            Just PanelStatus

        SurfaceCondition _ ->
            Just PanelCondition

        SurfaceSaveChain _ ->
            Just PanelSaveChain

        SurfaceInitiative _ ->
            Just PanelInitiative

        SurfaceReplace _ ->
            Just PanelReplace

        SurfaceDuplicate _ ->
            Just PanelDuplicate

        SurfaceCrCalculator _ ->
            Just PanelDifficulty

        SurfaceTreasure _ ->
            Just PanelTreasure

        SurfaceQuickAdd _ ->
            Just PanelQuickAdd

        SurfaceSave _ ->
            Just PanelSave

        SurfaceLoad _ ->
            Just PanelLoad

        SurfaceRandomEncounter _ ->
            Just PanelRandomEncounter

        _ ->
            Nothing


isOpen : Model -> Bool
isOpen model =
    current model /= PanelNone


view : Model -> Html Msg
view model =
    let
        selectedCount =
            List.length (List.filter .selected model.encounter.creatures)

        -- Manage HP and Save Chain still choose their scope with
        -- a checkbox, so their strip has to name the selection
        -- when it is ticked; the button-scoped editors always
        -- name their own target.
        scopedLabel targetName applyToSelected =
            if applyToSelected && selectedCount > 0 then
                "Target: Selected (" ++ String.fromInt selectedCount ++ ")"

            else
                "Target: " ++ targetName

        editor title subtitle close body =
            View.Panel.view
                { close = close
                , title = title
                , subtitle = Just subtitle
                , extraClass = "panel-drawer--editor"
                , body = [ body ]
                }
    in
    case ( current model, model.surface ) of
        ( PanelConfirm, _ ) ->
            case model.pendingControl of
                Just pending ->
                    View.Panel.Confirm.view pending

                Nothing ->
                    text ""

        ( PanelHpChange, Just (SurfaceHpChange ui) ) ->
            editor "Manage HP"
                (scopedLabel ui.target ui.applyToSelected)
                HpChangeClose
                (View.Inline.HpChange.view selectedCount model.hpChangeLog ui)

        ( PanelStatus, Just (SurfaceStatus ui) ) ->
            editor "Status"
                ("Target: " ++ ui.target)
                StatusClose
                (View.Inline.Status.view selectedCount ui)

        ( PanelCondition, Just (SurfaceCondition ui) ) ->
            editor "Condition"
                ("Target: " ++ ui.target)
                ConditionClose
                (View.Inline.Condition.view
                    { creatureNames = List.map .name model.encounter.creatures
                    , selectedCount = selectedCount
                    , presets = model.conditionPresets
                    , log = model.conditionLog
                    }
                    ui
                )

        ( PanelSaveChain, Just (SurfaceSaveChain ui) ) ->
            editor "Save Chain"
                (scopedLabel ui.target ui.applyToSelected)
                SaveChainClose
                (View.Inline.SaveChain.view
                    { presets = model.saveChainPresets
                    , selectedCount = selectedCount
                    , log = model.saveChainLog
                    }
                    ui
                )

        ( PanelInitiative, Just (SurfaceInitiative ui) ) ->
            editor "Initiative"
                ("Target: " ++ ui.target)
                InitiativeClose
                (View.Inline.Initiative.view selectedCount ui)

        ( PanelReplace, Just (SurfaceReplace ui) ) ->
            editor "Replace"
                ("Target: " ++ ui.target)
                ReplaceClose
                (View.Inline.Replace.view model.compendium.db
                    selectedCount
                    model.replaceLog
                    ui
                )

        ( PanelDuplicate, Just (SurfaceDuplicate ui) ) ->
            editor "Duplicate"
                ("Target: " ++ ui.target)
                DuplicateClose
                (View.Inline.Duplicate.view selectedCount model.duplicateLog ui)

        ( PanelDifficulty, _ ) ->
            View.Panel.CrCalculator.view model

        ( PanelTreasure, _ ) ->
            View.Panel.Treasure.view model

        ( PanelQuickAdd, _ ) ->
            View.Panel.QuickAdd.view model

        ( PanelSave, _ ) ->
            View.Panel.Save.view model

        ( PanelLoad, _ ) ->
            View.Panel.Load.view model

        ( PanelRandomEncounter, _ ) ->
            View.Panel.RandomEncounter.view model

        ( PanelDice, _ ) ->
            View.Panel.Dice.view model.hpChangeLog model.dice

        ( PanelXp, _ ) ->
            View.Panel.Xp.view model.encounter model.compendium.db model.xpScope

        ( PanelStatBlock, _ ) ->
            case model.panelCreaturePin of
                Just pin ->
                    View.Panel.StatBlock.view model.compendium.db pin

                Nothing ->
                    text ""

        ( PanelNone, _ ) ->
            text ""

        -- `current` and the surface agree by construction; this
        -- arm exists only because the compiler pairs them
        -- independently.
        _ ->
            text ""
