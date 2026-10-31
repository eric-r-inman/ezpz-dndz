module Update.Notice exposing (alreadyHasCondition, dismiss)

{-| The modal that says why something was not applied.

It carries its own message text rather than a tag, since nothing
but the modal reads it and a sentence is clearer at the call site
than a constructor the reader has to look up.

@docs alreadyHasCondition, dismiss

-}

import Model exposing (Model)
import Msg exposing (Msg)
import Util.Number
import Util.Text


{-| What the modal says when every creature the GM aimed at
already carries the condition.
-}
alreadyHasCondition : List String -> String -> String
alreadyHasCondition holders condition =
    Util.Text.andList holders
        ++ Util.Number.pluralize " already has " " already have " (List.length holders)
        ++ condition
        ++ "."


dismiss : Model -> ( Model, Cmd Msg )
dismiss model =
    ( { model | surface = Nothing }, Cmd.none )
