module Update.PanelDrawer exposing (clearCreature, toggleCollapse)

{-| Drawer-wide handlers that belong to no single panel.

@docs clearCreature, toggleCollapse

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
