module Update.StatBlock exposing (minimize, show, toggle)

{-| The stat block that unfolds under a creature's card.

@docs minimize, show, toggle

-}

import Effects
import Model exposing (Model)
import Msg exposing (Msg)
import Set


{-| Open the block from somewhere other than its card — a strip or
list naming the creature — so the card is brought into view as
well; opened from off-screen, it would otherwise land nowhere the
GM is looking.
-}
show : String -> Model -> ( Model, Cmd Msg )
show name model =
    ( open name model, Effects.scrollActiveIntoView name )


{-| The card's own name click: unfold the block, or fold it away
again.
-}
toggle : String -> Model -> ( Model, Cmd Msg )
toggle name model =
    ( if Set.member name model.openStatBlocks then
        close name model

      else
        open name model
    , Cmd.none
    )


minimize : String -> Model -> ( Model, Cmd Msg )
minimize name model =
    ( close name model, Cmd.none )


open : String -> Model -> Model
open name model =
    { model | openStatBlocks = Set.insert name model.openStatBlocks }


close : String -> Model -> Model
close name model =
    { model | openStatBlocks = Set.remove name model.openStatBlocks }
