module Update.Xp exposing (filterClose, filterToggle, scopeSet)

{-| Which creatures the encounter's XP total counts, and whether
the panel that picks is open.

The scope itself is not panel state — the title bar's readout
reads it whether or not the panel is showing — so it lives on
the model beside the open flag rather than inside it.

@docs filterClose, filterToggle, scopeSet

-}

import Encounter.Xp exposing (XpScope)
import Model exposing (Model)
import Msg exposing (Msg)


{-| Picking a scope leaves the panel open: the total it shows is
the reason to pick one, so closing on the pick would hide the
answer.
-}
scopeSet : XpScope -> Model -> ( Model, Cmd Msg )
scopeSet scope model =
    ( { model | xpScope = scope }, Cmd.none )


filterToggle : Model -> ( Model, Cmd Msg )
filterToggle model =
    ( { model | xpFilterOpen = not model.xpFilterOpen }, Cmd.none )


filterClose : Model -> ( Model, Cmd Msg )
filterClose model =
    ( { model | xpFilterOpen = False }, Cmd.none )
