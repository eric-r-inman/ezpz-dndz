module Update.ActionsDrawer exposing (toggle)

{-| Open / close handler for the panel the Actions column slides
open.

Clicking the button that is already showing folds the drawer
away; clicking any other re-aims it without closing first. That
is the same open/openFor split the docked editors use, collapsed
into one branch because the drawer holds nothing worth
preserving across a re-aim yet.

@docs toggle

-}

import Model exposing (Model)
import Msg exposing (ActionsDrawerTarget, Msg)
import Ui.ActionsDrawer


toggle : ActionsDrawerTarget -> Model -> ( Model, Cmd Msg )
toggle target model =
    ( { model
        | actionsDrawer =
            if Maybe.map .target model.actionsDrawer == Just target then
                Nothing

            else
                Just (Ui.ActionsDrawer.fresh target)
      }
    , Cmd.none
    )
