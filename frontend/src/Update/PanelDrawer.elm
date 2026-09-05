module Update.PanelDrawer exposing (clearCreature, dragEnd, dragOver, dragStart, drop, toggleCollapse)

{-| Drawer-wide handlers that belong to no single panel.

@docs clearCreature, dragEnd, dragOver, dragStart, drop, toggleCollapse

-}

import Model exposing (Model)
import Msg exposing (Msg)


{-| Close the stat-block panel, unpinning its creature.
-}
clearCreature : Model -> ( Model, Cmd Msg )
clearCreature model =
    ( Model.closeDrawer Model.statBlockLens model, Cmd.none )


{-| Fold one panel's body away, or open it back up. The panel
stays in the stack either way, so a folded editor keeps whatever
the GM had typed into it.
-}
toggleCollapse : Int -> Model -> ( Model, Cmd Msg )
toggleCollapse index model =
    ( Model.toggleCollapsedAt index model, Cmd.none )


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
