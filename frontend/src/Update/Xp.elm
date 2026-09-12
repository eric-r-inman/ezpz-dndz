module Update.Xp exposing (scopeSet)

{-| Which creatures the encounter's XP total counts.

The scope itself is not panel state — it outlives a fold, so it
lives on the model.

@docs scopeSet

-}

import Encounter.Xp exposing (XpScope)
import Model exposing (Model)
import Msg exposing (Msg)


{-| Picking a scope leaves the panel unfolded: the total it shows
is the reason to pick one, so folding on the pick would hide the
answer.
-}
scopeSet : XpScope -> Model -> ( Model, Cmd Msg )
scopeSet scope model =
    ( { model | xpScope = scope }, Cmd.none )
