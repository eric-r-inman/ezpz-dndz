module Update.SpellList exposing (close, open)

{-| Open / close handlers for the read-only Spell List modal.

The modal carries no editable state — the body re-renders from
`model.encounter` + `model.compendium.db` on every open — so
these handlers just flip the modal slot.

@docs close, open

-}

import Model exposing (Modal(..), Model)
import Msg exposing (Msg)


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just ModalSpellList }, Cmd.none )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )
