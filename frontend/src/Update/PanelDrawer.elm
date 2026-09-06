module Update.PanelDrawer exposing (clearCreature, columnToggle, dragEnd, dragOver, dragStart, drop, toggleCollapse)

{-| Drawer-wide handlers that belong to no single panel.

@docs clearCreature, columnToggle, dragEnd, dragOver, dragStart, drop, toggleCollapse

-}

import Encounter
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Condition
import Ui.Duplicate
import Ui.HpChange
import Ui.Initiative
import Ui.Replace
import Ui.SaveChain
import Ui.Status


{-| Close the stat-block panel, unpinning its creature.
-}
clearCreature : Model -> ( Model, Cmd Msg )
clearCreature model =
    ( Model.closeDrawer Model.statBlockLens model, Cmd.none )


{-| Fold one panel's body away, or open it back up. The panel
stays in the stack either way, so a folded editor keeps what the
GM typed — unless expanding re-aims it, which `aimAt` explains.
-}
toggleCollapse : Int -> Model -> ( Model, Cmd Msg )
toggleCollapse index model =
    let
        expanding =
            Model.drawerPanelAt index model
                |> Maybe.map .collapsed
                |> Maybe.withDefault False
    in
    ( Model.toggleCollapsedAt index model
        |> (if expanding then
                aimAt index

            else
                identity
           )
    , Cmd.none
    )


{-| A per-creature editor being expanded is aimed at the queue's
default target when it is aimed at nothing, or at a creature that
has since left. One already pointing somewhere real is left
alone, so a deliberate aim from a card survives a fold — but a
re-aim resets the editor, so a draft typed against a creature
that then left the queue does not.
-}
aimAt : Int -> Model -> Model
aimAt index model =
    let
        target =
            Encounter.defaultTarget model.encounter

        reaim wrap fresh aimed surface =
            if Encounter.hasCreature aimed model.encounter then
                surface

            else
                wrap (fresh target)
    in
    Model.mapSurfaceAt index
        (\surface ->
            case surface of
                SurfaceHpChange ui ->
                    reaim SurfaceHpChange Ui.HpChange.fresh ui.target surface

                SurfaceStatus ui ->
                    reaim SurfaceStatus Ui.Status.fresh ui.target surface

                SurfaceCondition ui ->
                    reaim SurfaceCondition Ui.Condition.fresh ui.target surface

                SurfaceSaveChain ui ->
                    reaim SurfaceSaveChain Ui.SaveChain.fresh ui.target surface

                SurfaceInitiative ui ->
                    reaim SurfaceInitiative Ui.Initiative.fresh ui.target surface

                SurfaceDuplicate ui ->
                    reaim SurfaceDuplicate Ui.Duplicate.fresh ui.target surface

                SurfaceReplace ui ->
                    reaim SurfaceReplace Ui.Replace.fresh ui.target surface

                _ ->
                    surface
        )
        model


{-| A heading row picked up: remember where it came from.
-}
dragStart : Int -> Model -> ( Model, Cmd Msg )
dragStart index model =
    ( { model | drawerDrag = Just { from = index, over = Nothing } }
    , Cmd.none
    )


{-| The pointer crossed a slot; that slot wears the drop cue.
-}
dragOver : Int -> Model -> ( Model, Cmd Msg )
dragOver index model =
    ( { model
        | drawerDrag =
            Maybe.map (\d -> { d | over = Just index }) model.drawerDrag
      }
    , Cmd.none
    )


{-| Dropped on a slot: commit the reorder and clear the drag.
-}
drop : Int -> Model -> ( Model, Cmd Msg )
drop index model =
    ( model.drawerDrag
        |> Maybe.map
            (\d ->
                Model.moveDrawerPanel d.from
                    index
                    { model | drawerDrag = Nothing }
            )
        |> Maybe.withDefault model
    , Cmd.none
    )


{-| The drag ended anywhere but a slot (dropped outside, or the
browser cancelled it): clear the cue without reordering.
-}
dragEnd : Model -> ( Model, Cmd Msg )
dragEnd model =
    ( { model | drawerDrag = Nothing }, Cmd.none )


{-| Fold the drawer column out of the layout, or back into it.
The panels keep their place in the stack, so this is a view of
the same work rather than a close.
-}
columnToggle : Model -> ( Model, Cmd Msg )
columnToggle model =
    ( { model | drawerCollapsed = not model.drawerCollapsed }, Cmd.none )
