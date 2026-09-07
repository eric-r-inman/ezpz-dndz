module Update.LogRow exposing (toggle)

{-| The fold on a log row.

@docs toggle

-}

import Model exposing (Model)
import Msg exposing (Msg)
import Set


toggle : String -> Model -> ( Model, Cmd Msg )
toggle key model =
    ( { model
        | expandedLogRows =
            if Set.member key model.expandedLogRows then
                Set.remove key model.expandedLogRows

            else
                Set.insert key model.expandedLogRows
      }
    , Cmd.none
    )
