module Update.Notice exposing (alreadyHasCondition, dismiss)

{-| The modal that says why something was not applied.

It carries its own message text rather than a tag, since nothing
but the modal reads it and a sentence is clearer at the call site
than a constructor the reader has to look up.

@docs alreadyHasCondition, dismiss

-}

import Model exposing (Model)
import Msg exposing (Msg)


{-| What the modal says when a creature already carries the
condition the GM is applying.
-}
alreadyHasCondition : String
alreadyHasCondition =
    "The creature already has this condition"


dismiss : Model -> ( Model, Cmd Msg )
dismiss model =
    ( { model | surface = Nothing }, Cmd.none )
