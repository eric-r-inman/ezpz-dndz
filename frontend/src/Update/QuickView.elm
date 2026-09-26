module Update.QuickView exposing (toggle, toggleEnemiesOnly)

{-| Open / close and filter handlers for the quick view beside the
queue. The column re-renders from `model.encounter`, so each
handler only flips a flag.

@docs toggle, toggleEnemiesOnly

-}

import Model exposing (Model)
import Msg exposing (Msg)


toggle : Model -> ( Model, Cmd Msg )
toggle model =
    let
        quickView =
            model.quickView
    in
    ( { model | quickView = { quickView | open = not quickView.open } }, Cmd.none )


toggleEnemiesOnly : Model -> ( Model, Cmd Msg )
toggleEnemiesOnly model =
    let
        quickView =
            model.quickView
    in
    ( { model | quickView = { quickView | enemiesOnly = not quickView.enemiesOnly } }, Cmd.none )
