module Update.PanelDrawer exposing (clearCreature)

{-| Drawer-wide handlers that belong to no single panel.

@docs clearCreature

-}

import Model exposing (Model)
import Msg exposing (Msg)


{-| Close the stat-block panel, unpinning its creature.
-}
clearCreature : Model -> ( Model, Cmd Msg )
clearCreature model =
    ( Model.closeDrawer Model.statBlockLens model, Cmd.none )
