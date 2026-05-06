module Update.Timer exposing
    ( apply
    , cancel
    , dismiss
    , open
    , phaseSet
    , turnsChanged
    )

{-| Update branches for the per-creature countdown timer (card row
3 ⏱). The timer is a ringer: it counts down at the chosen phase
boundary and rings once when it hits zero, after which the GM can
dismiss it.
-}

import Encounter exposing (TurnPhase)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg)
import Ui.Timer as TimerUi exposing (TimerSetupUi)


withTimerSetup : (TimerSetupUi -> TimerSetupUi) -> Model -> Model
withTimerSetup =
    Model.mapModal Model.timerLens


open : String -> Model -> ( Model, Cmd Msg )
open name model =
    ( { model | modal = Just (ModalTimerSetup (TimerUi.fresh name)) }
    , Cmd.none
    )


turnsChanged : String -> Model -> ( Model, Cmd Msg )
turnsChanged text model =
    ( withTimerSetup
        (\u ->
            { u
                | turnsText = text
                , turns =
                    String.toInt (String.trim text)
                        |> Maybe.map (Basics.max 1 >> Basics.min 99)
                        |> Maybe.withDefault u.turns
            }
        )
        model
    , Cmd.none
    )


phaseSet : TurnPhase -> Model -> ( Model, Cmd Msg )
phaseSet phase model =
    ( withTimerSetup (\u -> { u | phase = phase }) model, Cmd.none )


apply : Model -> ( Model, Cmd Msg )
apply model =
    case model.modal of
        Just (ModalTimerSetup ui) ->
            let
                newTimer =
                    { remaining = ui.turns
                    , phase = ui.phase
                    , ringing = False
                    }
            in
            ( { model
                | encounter =
                    Encounter.mapCreature ui.target
                        (\c -> { c | timer = Just newTimer })
                        model.encounter
                , modal = Nothing
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | modal = Nothing }, Cmd.none )


{-| Dismiss whether ringing or still counting; the GM gets to cancel
a timer mid-flight if combat ends early or they set the wrong
creature.
-}
dismiss : String -> Model -> ( Model, Cmd Msg )
dismiss name model =
    ( { model
        | encounter =
            Encounter.mapCreature name (\c -> { c | timer = Nothing }) model.encounter
      }
    , Cmd.none
    )
