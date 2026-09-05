module View.PanelDrawer exposing (isOpen, view)

{-| The Actions column's drawer: a second workspace column
holding every open panel, stacked oldest-first so a newly
opened panel appears below the ones already up.

Each drawer variant renders through `panelFor`; adding a panel
means a lens in `Model`, an arm here, and an Esc mapping in
`Main.subscriptions`.

@docs isOpen, view

-}

import Effects
import Html exposing (Html, div, text)
import Html.Attributes as Attr exposing (class)
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
import View.Panel.CrCalculator
import View.Panel.Dice
import View.Panel.Load
import View.Panel.QuickAdd
import View.Panel.RandomEncounter
import View.Panel.Save
import View.Panel.StatBlock
import View.Panel.Treasure
import View.Panel.Xp


{-| Whether the column has anything to show. Also drives the
workspace's grid template, which carries no drawer track while
the stack is empty.
-}
isOpen : Model -> Bool
isOpen model =
    not (List.isEmpty model.drawer)


view : Model -> Html Msg
view model =
    case model.drawer of
        [] ->
            text ""

        panels ->
            div [ class "drawer-stack", Attr.id Effects.drawerStackId ]
                (List.indexedMap (panelFor model) panels)


panelFor : Model -> Int -> Model.DrawerPanel -> Html Msg
panelFor model index panel =
    let
        collapse =
            { collapsed = panel.collapsed
            , toggle = DrawerCollapseToggle index
            }

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
                , titleLead = Nothing
                , subtitle = Just subtitle
                , collapse = collapse
                , extraClass = "panel-drawer--editor"
                , body = [ body ]
                }

        wrap body =
            -- The id rides a wrapper rather than the panel itself
            -- so scroll-into-view can address a panel without every
            -- panel module having to carry an id through its config.
            div [ class "drawer-stack__slot", Attr.id (Effects.drawerPanelId index) ]
                [ body ]
    in
    wrap <|
        case panel.surface of
            SurfaceHpChange ui ->
                editor "Manage HP"
                    (scopedLabel ui.target ui.applyToSelected)
                    HpChangeClose
                    (View.Inline.HpChange.view selectedCount model.hpChangeLog ui)

            SurfaceStatus ui ->
                editor "Status"
                    ("Target: " ++ ui.target)
                    StatusClose
                    (View.Inline.Status.view selectedCount ui)

            SurfaceCondition ui ->
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

            SurfaceSaveChain ui ->
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

            SurfaceInitiative ui ->
                editor "Initiative"
                    ("Target: " ++ ui.target)
                    InitiativeClose
                    (View.Inline.Initiative.view selectedCount ui)

            SurfaceReplace ui ->
                editor "Replace"
                    ("Target: " ++ ui.target)
                    ReplaceClose
                    (View.Inline.Replace.view model.compendium.db
                        selectedCount
                        model.replaceLog
                        ui
                    )

            SurfaceDuplicate ui ->
                editor "Duplicate"
                    ("Target: " ++ ui.target)
                    DuplicateClose
                    (View.Inline.Duplicate.view selectedCount model.duplicateLog ui)

            SurfaceCrCalculator _ ->
                View.Panel.CrCalculator.view collapse model

            SurfaceTreasure _ ->
                View.Panel.Treasure.view collapse model

            SurfaceQuickAdd _ ->
                View.Panel.QuickAdd.view collapse model

            SurfaceSave _ ->
                View.Panel.Save.view collapse model

            SurfaceLoad _ ->
                View.Panel.Load.view collapse model

            SurfaceRandomEncounter _ ->
                View.Panel.RandomEncounter.view collapse model

            SurfaceDice ->
                View.Panel.Dice.view collapse model.hpChangeLog model.dice

            SurfaceXp ->
                View.Panel.Xp.view collapse model.encounter model.compendium.db model.xpScope

            SurfaceStatBlock pin ->
                View.Panel.StatBlock.view collapse model.compendium.db pin

            -- Modal and card-inline variants never enter the stack —
            -- their Update modules write `model.surface`, and the
            -- drawer's own Update modules are the stack's only
            -- writers.
            _ ->
                text ""
