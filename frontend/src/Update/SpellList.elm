module Update.SpellList exposing (close, open)

{-| Open / close handlers for the read-only spell-list panel.

The panel carries no editable state — the body re-renders from
`model.encounter` + `model.compendium.db` on every open — so
these handlers just flip the surface slot.

@docs close, open

-}

import Model exposing (Model, Surface(..))
import Msg exposing (Msg)


{-| The strip's scroll button toggles: clicking it while the
panel is open folds it away.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    ( case model.surface of
        Just SurfaceSpellList ->
            { model | surface = Nothing }

        _ ->
            { model | surface = Just SurfaceSpellList }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )
