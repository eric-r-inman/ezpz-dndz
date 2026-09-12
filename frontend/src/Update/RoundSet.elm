module Update.RoundSet exposing (apply, close, open, setToOne, textChanged)

{-| Update branches for the round-setter modal.

Setting the round is a correction, not a turn advance, so none
of the lifecycle hooks fire. The GM is fixing a number they
mis-clicked, and the fight's state should not move under them.

@docs apply, close, open, setToOne, textChanged

-}

import Model exposing (Model)
import Msg exposing (Msg)
import Ui.RoundSet


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model
        | surface =
            Just (Model.SurfaceRoundSet (Ui.RoundSet.fresh model.encounter.round))
      }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


textChanged : String -> Model -> ( Model, Cmd Msg )
textChanged text model =
    ( Model.mapSurface Model.roundSetLens (\ui -> { ui | roundText = text }) model
    , Cmd.none
    )


setToOne : Model -> ( Model, Cmd Msg )
setToOne model =
    ( setRound 1 model, Cmd.none )


{-| Commit the typed value. Anything below round 1 — or
unparseable — is a no-op rather than an error: the field is
pre-filled with the current round, so there is always a sane
value to fall back to.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    ( case model.surface of
        Just (Model.SurfaceRoundSet ui) ->
            ui.roundText
                |> String.trim
                |> String.toInt
                |> Maybe.andThen
                    (\n ->
                        if n >= 1 then
                            Just (setRound n model)

                        else
                            Nothing
                    )
                |> Maybe.withDefault model

        _ ->
            model
    , Cmd.none
    )


setRound : Int -> Model -> Model
setRound round model =
    let
        enc =
            model.encounter
    in
    { model | encounter = { enc | round = round }, surface = Nothing }
