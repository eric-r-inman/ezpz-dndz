module Update.LogRow exposing (overflowReported, toggle)

{-| The fold on a log row.

@docs overflowReported, toggle

-}

import Dict
import Json.Decode as Decode
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


{-| Take the browser's account of which rows are clipped. A
payload that will not decode leaves the previous answer standing,
which costs a fold caret its accuracy until the next measurement
rather than wedging the log.
-}
overflowReported : Decode.Value -> Model -> ( Model, Cmd Msg )
overflowReported measured model =
    ( Decode.decodeValue (Decode.dict Decode.bool) measured
        |> Result.map
            (\rows ->
                { model
                    | overflowingLogRows =
                        rows
                            |> Dict.filter (\_ clipped -> clipped)
                            |> Dict.keys
                            |> Set.fromList
                }
            )
        |> Result.withDefault model
    , Cmd.none
    )
