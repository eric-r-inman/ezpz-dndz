module View.PanelDrawer exposing (view)

{-| The editor column: the encounter's own controls above a
stack holding every panel, oldest-first, so a newly opened one
appears below the ones already up.

Each drawer variant renders through `panelFor`; adding a panel
means a lens in `Model`, an arm here, and — if the drawer boots
with it — an entry in `Model.defaultDrawer`.

@docs view

-}

import Effects
import Encounter
import Html exposing (Html, button, div, text)
import Html.Attributes as Attr exposing (class)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode
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
import View.Panel.QuickAdd
import View.Panel.RandomEncounter
import View.Panel.SaveLoad
import View.Panel.Treasure
import View.Panel.Xp
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    div [ class "drawer-column" ]
        [ encounterControls model
        , stack model
        ]


{-| The encounter's own controls, above the editors they sit
with. They stay put when the stack folds away: advancing the
turn is the one thing a GM does every round, and it should not
need the editors unfolded first.
-}
encounterControls : Model -> Html Msg
encounterControls model =
    div [ class "drawer-controls" ]
        [ div [ class "drawer-controls__tools" ]
            [ controlButton "action-btn action-btn--plain"
                CompendiumOpen
                Tooltips.panelOpenCompendium
                "📚"
            , controlButton "action-btn action-btn--plain"
                DiceRollerOpen
                Tooltips.panelOpenDiceRoller
                "🎲"
            , View.Panel.Dice.recentBadges model.dice.history model.dice.rollBadgeOverride
            ]
        , div [ class "drawer-controls__encounter" ]
            [ controlButton "action-btn action-btn--red"
                EncounterClear
                Tooltips.clear
                "🗑️"
            , controlButton "action-btn action-btn--orange"
                EncounterReset
                Tooltips.reset
                "⏮"
            , turnControl model.encounter.activeName
            ]
        ]


{-| An empty active creature is the pre-combat sentinel: the
queue is set up but combat hasn't started, so the button starts
it rather than advancing it.
-}
turnControl : String -> Html Msg
turnControl activeName =
    if String.isEmpty activeName then
        controlButton "action-btn action-btn--green drawer-controls__btn--wide"
            EncounterRun
            Tooltips.runEncounter
            "▶"

    else
        controlButton "action-btn action-btn--green drawer-controls__btn--wide"
            NextTurn
            Tooltips.nextTurn
            "⏭"


controlButton : String -> Msg -> String -> String -> Html Msg
controlButton cls msg tip glyph =
    button
        [ class (cls ++ " drawer-controls__btn")
        , Attr.type_ "button"
        , onClick msg
        , Tooltips.attr tip
        , Attr.attribute "aria-label" tip
        ]
        [ text glyph ]


stack : Model -> Html Msg
stack model =
    case model.drawer of
        [] ->
            text ""

        panels ->
            -- Keyed by surface so a reorder moves DOM nodes
            -- instead of rewriting every panel in place, which
            -- would drop focus and replay the mount animation.
            Html.Keyed.node "div"
                [ class "drawer-stack", Attr.id Effects.drawerStackId ]
                (List.indexedMap
                    (\index panel ->
                        ( Model.surfaceKey panel.surface, panelFor model index panel )
                    )
                    panels
                )


{-| The slot the dragged panel would land in wears the drop cue.
That is not always the one under the pointer — a drag across the
pinned boundary clamps, and the cue shows where it clamps to.
-}
slotClass : Int -> Maybe Model.DragState -> String
slotClass index drag =
    if Maybe.map .over drag == Just (Just index) then
        "drawer-stack__slot drawer-stack__slot--drop"

    else
        "drawer-stack__slot"


panelFor : Model -> Int -> Model.DrawerPanel -> Html Msg
panelFor model index panel =
    let
        header =
            { collapsed = panel.collapsed
            , toggle = DrawerCollapseToggle index
            , foldAll = DrawerFoldAll

            -- The heading row is the drag handle; the body keeps
            -- its clicks and selections to itself.
            , dragAttrs =
                [ Attr.draggable "true"
                , Html.Events.on "dragstart"
                    (Decode.succeed (DrawerDragStart index))
                , Html.Events.on "dragend"
                    (Decode.succeed DrawerDragEnd)
                ]
            , pinned = panel.pinned
            , pinToggle = DrawerPinToggle index
            }

        selectedCount =
            List.length (List.filter .selected model.encounter.creatures)

        selectedHasPlaceholder =
            model.encounter.creatures
                |> List.filter .selected
                |> List.any .isPlaceholder

        -- Whether the editor's current target or selection includes
        -- a placeholder stub. These five editors act on a creature's
        -- real stats, which a placeholder doesn't have yet — the
        -- panel warns rather than silently doing nothing.
        placeholderWarning targetName =
            Encounter.isPlaceholderName model.encounter targetName
                || selectedHasPlaceholder

        -- Manage HP and Save Chain still choose their scope with
        -- a checkbox, so their strip has to name the selection
        -- when it is ticked; the button-scoped editors always
        -- name their own target.
        scopedLabel targetName applyToSelected =
            if applyToSelected && selectedCount > 0 then
                "Target: Selected (" ++ String.fromInt selectedCount ++ ")"

            else
                "Target: " ++ targetName

        editor title subtitle body =
            editorTagged title Nothing subtitle body

        editorTagged title trail subtitle body =
            View.Panel.view
                { title = title
                , titleTrail = trail
                , subtitle = Just subtitle
                , header = header
                , extraClass = "panel-drawer--editor"
                , body = [ body ]
                }

        wrap body =
            -- The id rides a wrapper rather than the panel itself
            -- so scroll-into-view can address a panel without every
            -- panel module having to carry an id through its config.
            -- The wrapper is also the drop target: `dragover` must
            -- be preventDefault-ed or the browser never allows the
            -- drop at all.
            div
                [ class (slotClass index model.drawerDrag)
                , Attr.id (Effects.drawerPanelId index)
                , Html.Events.preventDefaultOn "dragover"
                    (Decode.succeed ( DrawerDragOver index, True ))
                , Html.Events.preventDefaultOn "drop"
                    (Decode.succeed ( DrawerDrop index, True ))
                ]
                [ body ]
    in
    wrap <|
        case panel.surface of
            SurfaceHpChange ui ->
                editor "Manage HP"
                    (scopedLabel ui.target ui.applyToSelected)
                    (View.Inline.HpChange.view
                        { selectedCount = selectedCount
                        , placeholderWarning = placeholderWarning ui.target
                        , log = model.hpChangeLog
                        , logOpen = model.hpLogOpen
                        , setOpen = model.hpSetOpen
                        , flashedSeq = model.flashedHpLogSeq
                        , expanded = model.expandedLogRows
                        }
                        ui
                    )

            SurfaceStatus ui ->
                editor "Status"
                    ("Target: " ++ ui.target)
                    (View.Inline.Status.view selectedCount (placeholderWarning ui.target) ui)

            SurfaceCondition ui ->
                editor "Condition/Effect"
                    ("Target: " ++ ui.target)
                    (View.Inline.Condition.view
                        { creatureNames = List.map .name model.encounter.creatures
                        , selectedCount = selectedCount
                        , placeholderWarning = placeholderWarning ui.target
                        , presets = model.conditionPresets
                        , log = model.conditionLog
                        , logOpen = model.conditionLogOpen
                        , expanded = model.expandedLogRows
                        }
                        ui
                    )

            SurfaceSaveChain ui ->
                editorTagged "Save Chain"
                    (Just View.Panel.betaTag)
                    (scopedLabel ui.target ui.applyToSelected)
                    (View.Inline.SaveChain.view
                        { presets = model.saveChainPresets
                        , selectedCount = selectedCount
                        , placeholderWarning = placeholderWarning ui.target
                        , log = model.saveChainLog
                        , logOpen = model.saveChainLogOpen
                        , creatureNames = List.map .name model.encounter.creatures
                        }
                        ui
                    )

            SurfaceInitiative ui ->
                editor "Initiative"
                    ("Target: " ++ ui.target)
                    (View.Inline.Initiative.view selectedCount ui)

            SurfaceReplace ui ->
                editor "Replace"
                    ("Target: " ++ ui.target)
                    (View.Inline.Replace.view model.compendium.db
                        selectedCount
                        model.replaceLog
                        ui
                    )

            SurfaceDuplicate ui ->
                editor "Duplicate"
                    ("Target: " ++ ui.target)
                    (View.Inline.Duplicate.view selectedCount (placeholderWarning ui.target) model.duplicateLog ui)

            SurfaceCrCalculator _ ->
                View.Panel.CrCalculator.view header model

            SurfaceTreasure _ ->
                View.Panel.Treasure.view header model

            SurfaceQuickAdd _ ->
                View.Panel.QuickAdd.view header model

            SurfaceSaveLoad _ ->
                View.Panel.SaveLoad.view header model

            SurfaceRandomEncounter _ ->
                View.Panel.RandomEncounter.view header model

            SurfaceDice ->
                View.Panel.Dice.view header
                    { hpChangeLog = model.hpChangeLog
                    , expanded = model.expandedLogRows
                    , flashedRollSeq = model.flashedRollSeq
                    }
                    model.dice

            SurfaceXp ->
                View.Panel.Xp.view header model.encounter model.compendium.db model.xpScope

            -- Modal and card-inline variants never enter the stack —
            -- their Update modules write `model.surface`, and the
            -- drawer's own Update modules are the stack's only
            -- writers.
            _ ->
                text ""
