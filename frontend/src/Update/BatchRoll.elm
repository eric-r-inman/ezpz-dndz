module Update.BatchRoll exposing (landed)

{-| Rolls one event fired together, routed to where each one lands.
-}

import Dice
import Model exposing (Model)
import Msg exposing (BatchRoll(..), Msg)
import Update.Condition
import Update.HpChange
import Update.SaveChain


{-| Lands each roll of a batch in turn, the way it would land alone.
-}
landed : List ( BatchRoll, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
landed rolls model =
    List.foldl
        (\( for, roll ) ( current, cmds ) ->
            Tuple.mapSecond (\cmd -> cmd :: cmds) (landOne for roll current)
        )
        ( model, [] )
        rolls
        |> Tuple.mapSecond Cmd.batch


landOne : BatchRoll -> Dice.Roll -> Model -> ( Model, Cmd Msg )
landOne for roll model =
    case for of
        FreshHpRoll kind target ->
            Update.HpChange.freshRollLanded kind target roll model

        SetHpRoll target ->
            Update.HpChange.manualRollLanded target roll model

        ConditionSaveRoll bearer id dc ->
            Update.Condition.saveLanded bearer id dc roll model

        AreaSaveRoll bearer id ->
            Update.SaveChain.areaSaveLanded bearer id roll model
