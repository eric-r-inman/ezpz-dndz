module Update.Timer exposing
    ( apply
    , cancel
    , dismiss
    , noteChanged
    , open
    , phaseSet
    , presetDelete
    , presetLoad
    , presetLoadMenuClose
    , presetLoadMenuToggle
    , presetSaveCancel
    , presetSaveNameChanged
    , presetSaveStart
    , presetSaveSubmit
    , turnsChanged
    )

{-| Update branches for the per-creature countdown timer (card row
3 ⏱). The timer is a ringer: it counts down at the chosen phase
boundary and rings once when it hits zero, after which the GM can
dismiss it.
-}

import Dict
import Encounter exposing (TurnPhase)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Timer as TimerUi exposing (TimerSetupUi)


withTimerSetup : (TimerSetupUi -> TimerSetupUi) -> Model -> Model
withTimerSetup =
    Model.mapSurface Model.timerLens


open : String -> Model -> ( Model, Cmd Msg )
open name model =
    ( { model | surface = Just (SurfaceTimerSetup (TimerUi.fresh name)) }
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


{-| Free-form short label the GM can attach to the timer to
remember what's ticking down (e.g. "Bless", "Rage", "Slow").
Capped at 10 chars to keep the card-row pill compact; the input
itself sets `maxlength` so we don't need to truncate here.
-}
noteChanged : String -> Model -> ( Model, Cmd Msg )
noteChanged text model =
    ( withTimerSetup (\u -> { u | note = String.left 10 text }) model
    , Cmd.none
    )


apply : Model -> ( Model, Cmd Msg )
apply model =
    case model.surface of
        Just (SurfaceTimerSetup ui) ->
            let
                newTimer =
                    { remaining = ui.turns
                    , phase = ui.phase
                    , ringing = False
                    , note = String.trim ui.note
                    }
            in
            ( { model
                | encounter =
                    Encounter.mapCreature ui.target
                        (\c -> { c | timer = Just newTimer })
                        model.encounter
                , surface = Nothing
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | surface = Nothing }, Cmd.none )


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



-- ── PRESETS ──────────────────────────────────────────────────────────────


{-| Mirror of `Update.Condition.presetSaveStart` / etc. — see
those for the shared semantics. The timer flavour stores its
dict at `Model.timerPresets` and persists to
`localStorage.timerPresets` via the wrapper in `Main`.
-}
presetSaveStart : Model -> ( Model, Cmd Msg )
presetSaveStart model =
    ( withTimerSetup
        (\u -> { u | pendingSaveName = Just "", loadMenuOpen = False })
        model
    , Cmd.none
    )


presetSaveNameChanged : String -> Model -> ( Model, Cmd Msg )
presetSaveNameChanged text model =
    ( withTimerSetup (\u -> { u | pendingSaveName = Just text }) model
    , Cmd.none
    )


presetSaveCancel : Model -> ( Model, Cmd Msg )
presetSaveCancel model =
    ( withTimerSetup (\u -> { u | pendingSaveName = Nothing }) model
    , Cmd.none
    )


presetSaveSubmit : Model -> ( Model, Cmd Msg )
presetSaveSubmit model =
    case model.surface of
        Just (SurfaceTimerSetup ui) ->
            let
                trimmed =
                    Maybe.withDefault "" ui.pendingSaveName
                        |> String.trim
            in
            if String.isEmpty trimmed then
                ( model, Cmd.none )

            else
                let
                    preset =
                        TimerUi.toPreset ui

                    newPresets =
                        Dict.insert trimmed preset model.timerPresets
                in
                ( { model | timerPresets = newPresets }
                    |> withTimerSetup
                        (\u ->
                            { u
                                | pendingSaveName = Nothing
                                , loadedPresetName = Just trimmed
                            }
                        )
                , Cmd.none
                )

        _ ->
            ( model, Cmd.none )


presetLoadMenuToggle : Model -> ( Model, Cmd Msg )
presetLoadMenuToggle model =
    ( withTimerSetup
        (\u ->
            { u
                | loadMenuOpen = not u.loadMenuOpen
                , pendingSaveName = Nothing
            }
        )
        model
    , Cmd.none
    )


presetLoadMenuClose : Model -> ( Model, Cmd Msg )
presetLoadMenuClose model =
    ( withTimerSetup (\u -> { u | loadMenuOpen = False }) model
    , Cmd.none
    )


presetLoad : String -> Model -> ( Model, Cmd Msg )
presetLoad name model =
    case Dict.get name model.timerPresets of
        Just preset ->
            ( withTimerSetup (TimerUi.applyPreset name preset) model
            , Cmd.none
            )

        Nothing ->
            ( withTimerSetup (\u -> { u | loadMenuOpen = False }) model
            , Cmd.none
            )


presetDelete : String -> Model -> ( Model, Cmd Msg )
presetDelete name model =
    let
        newPresets =
            Dict.remove name model.timerPresets
    in
    ( { model | timerPresets = newPresets }
        |> withTimerSetup
            (\u ->
                if u.loadedPresetName == Just name then
                    { u | loadedPresetName = Nothing }

                else
                    u
            )
    , Cmd.none
    )
