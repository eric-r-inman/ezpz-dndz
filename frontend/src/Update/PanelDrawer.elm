module Update.PanelDrawer exposing
    ( foldNewest, toggleCollapse, togglePin
    , dragStart, dragOver, drop, dragEnd
    , foldAll, showPinned, showHpChange
    )

{-| Drawer-wide handlers that belong to no single panel.

@docs foldNewest, toggleCollapse, togglePin
@docs dragStart, dragOver, drop, dragEnd
@docs foldAll, showPinned, showHpChange

-}

import Effects
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Update.Dice


{-| Fold one panel's body away, or open it back up. The panel
stays in the stack either way, so a folded editor keeps what the
GM typed — unless expanding re-aims it, which
`Model.reaimStale` explains.
-}
toggleCollapse : Int -> Model -> ( Model, Cmd Msg )
toggleCollapse index model =
    let
        expanding =
            Model.drawerPanelAt index model
                |> Maybe.map .collapsed
                |> Maybe.withDefault False
    in
    if expanding then
        ( Model.toggleCollapsedAt index model
            |> (Model.reaimStale >> markRead index >> ackHpLog index)
        , Cmd.none
        )

    else
        ( Model.toggleCollapsedAt index model, Cmd.none )


{-| Hold a panel at the top of the column, or release it. Either
way it moves: to the bottom of the pinned block when pinning, to
the top of the rest when releasing.
-}
togglePin : Int -> Model -> ( Model, Cmd Msg )
togglePin index model =
    ( Model.togglePinnedAt index model, Cmd.none )


foldAll : Model -> ( Model, Cmd Msg )
foldAll model =
    ( Model.foldAllDrawer model, Cmd.none )


{-| The editors the GM keeps closest, and nothing else: the pinned
panels unfold, every other panel folds, and the pinned region goes
back to its top.
-}
showPinned : Model -> ( Model, Cmd Msg )
showPinned model =
    ( refold (Model.unfoldPinnedOnly model.preferences.profile) model
    , Effects.scrollDrawerPinnedToTop
    )


{-| Manage HP and nothing else: it unfolds, whatever the profile
hides, every other panel folds, and the column scrolls to it.
-}
showHpChange : Model -> ( Model, Cmd Msg )
showHpChange model =
    let
        next =
            refold Model.unfoldHpChangeOnly model
    in
    ( next, Effects.scrollDrawerTo Model.hpChangeLens next )


{-| Fold and unfold the stack's panels the way `arrange` sets them.
A panel this unfolds gets what unfolding it by hand gives it, as
`toggleCollapse` does.
-}
refold : (List Model.DrawerPanel -> List Model.DrawerPanel) -> Model -> Model
refold arrange model =
    let
        arranged =
            arrange model.drawer

        unfolded =
            List.map2 (\before after -> before.collapsed && not after.collapsed)
                model.drawer
                arranged
                |> List.indexedMap Tuple.pair
                |> List.filter Tuple.second
                |> List.map Tuple.first
    in
    List.foldl (\index -> markRead index >> ackHpLog index)
        (Model.reaimStale { model | drawer = arranged })
        unfolded


{-| Esc means "dismiss what I am looking at", which
`Model.newestShowing` names.
-}
foldNewest : Model -> ( Model, Cmd Msg )
foldNewest model =
    Model.newestShowing model
        |> Maybe.map (\( i, _ ) -> ( Model.collapseAt i model, Cmd.none ))
        |> Maybe.withDefault ( model, Cmd.none )


{-| Expanding the HP editor shows whatever the log already held,
so those entries are spent as far as the flash is concerned.
-}
ackHpLog : Int -> Model -> Model
ackHpLog index model =
    case Maybe.map .surface (Model.drawerPanelAt index model) of
        Just (SurfaceHpChange _) ->
            Model.ackHpLog model

        _ ->
            model


{-| Expanding the roller puts its history on screen, so that is
what clears the unread mark.
-}
markRead : Int -> Model -> Model
markRead index model =
    case Maybe.map .surface (Model.drawerPanelAt index model) of
        Just SurfaceDice ->
            Update.Dice.markRead model

        _ ->
            model


{-| A heading row picked up: remember where it came from.
-}
dragStart : Int -> Model -> ( Model, Cmd Msg )
dragStart index model =
    ( { model | drawerDrag = Just { from = index, over = Nothing } }
    , Cmd.none
    )


{-| The pointer crossed a slot. The cue goes on the slot the
panel would actually take, not the one under the pointer, so a
drag across the pinned boundary shows the snap coming rather than
springing it at the drop.
-}
dragOver : Int -> Model -> ( Model, Cmd Msg )
dragOver index model =
    ( { model
        | drawerDrag =
            Maybe.map
                (\d ->
                    { d | over = Just (Model.drawerDropIndex d.from index model.drawer) }
                )
                model.drawerDrag
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
