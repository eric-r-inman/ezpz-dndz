module Update.SpellList exposing (close, open)

{-| Open / close handlers for the read-only Spell List modal.

The modal carries no editable state — the body re-renders from
`model.encounter` + `model.compendium.db` on every open — so
these handlers just flip the modal slot.

@docs close, open

-}

import Model exposing (Model, Surface(..))
import Msg exposing (Msg)


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | surface = Just SurfaceSpellList }, Cmd.none )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )
