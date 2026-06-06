module Update.Recording exposing
    ( recordingsClose
    , recordingsDeleteCancel
    , recordingsDeleteConfirm
    , recordingsDeleteRequested
    , recordingsDeleteResponse
    , recordingsListLoaded
    , recordingsOpen
    , stateReceived
    , toggleClicked
    )

{-| Session recorder update branches.

The recorder is intentionally tiny — one button cycles through
the states. This module owns:

  - `toggleClicked` — the AppBar button. Dispatches
    `Ports.startRecording` when idle, `Ports.stopRecording`
    when active. No-op while a transition (Preparing /
    Uploading) is in flight so a double-click can't crash the
    JS side.
  - `stateReceived` — JS notifies Elm of state changes via
    `Ports.recordingState`. Decodes the wire payload and
    updates `model.recordingState`, pushing a toast when an
    upload completes (success) or fails.

The JS side handles `MediaRecorder`, `getUserMedia`, and the
multipart upload to `POST /api/recording/upload`. Elm here is
pure rules: which transitions are legal, which toasts to fire,
what to render.

-}

import Auth
import Http
import Json.Decode as D
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ports
import Ui.Recording as Recording
    exposing
        ( ConfirmAction(..)
        , RecordingMeta
        , RecordingState(..)
        , RecordingsListState(..)
        , RecordingsUi
        )
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


{-| Click on the recorder button. State-machine semantics:

  - Idle → ask JS to start (modal mic prompt etc.)
  - Active → ask JS to stop + upload
  - Preparing → no-op (waiting for the user to allow mic)
  - Uploading → no-op (don't fire-and-forget twice)
  - Failed → reset to Idle on next click for a clean retry

-}
toggleClicked : Model -> ( Model, Cmd Msg )
toggleClicked model =
    -- Server upload is auth-gated.  Mirror the gate client-side
    -- so a tap-while-anonymous doesn't fire a request that 401s.
    if not (Auth.isAuthenticated model.auth) then
        ( model, Cmd.none )

    else
        case model.recordingState of
            RecordingIdle ->
                ( { model | recordingState = RecordingPreparing }
                , Ports.startRecording ()
                )

            RecordingActive _ ->
                ( { model | recordingState = RecordingUploading }
                , Ports.stopRecording ()
                )

            RecordingFailed _ ->
                ( { model | recordingState = RecordingIdle }, Cmd.none )

            RecordingPreparing ->
                ( model, Cmd.none )

            RecordingUploading ->
                ( model, Cmd.none )


{-| `Ports.recordingState` payload arrives. Wire shape:

    { "state": "preparing" }
    { "state": "recording", "elapsedMs": 12345 }
    { "state": "uploading" }
    { "state": "done",  "meta": { id, filename, mime, size_bytes, created_at_ms } }
    { "state": "error", "message": "Microphone denied" }

Decode failures are silently absorbed — a malformed message from
JS shouldn't crash the app loop.

-}
stateReceived : D.Value -> Model -> ( Model, Cmd Msg )
stateReceived raw model =
    case D.decodeValue stateDecoder raw of
        Ok (Incoming RecordingPreparing) ->
            ( { model | recordingState = RecordingPreparing }, Cmd.none )

        Ok (Incoming (RecordingActive ticks)) ->
            ( { model | recordingState = RecordingActive ticks }, Cmd.none )

        Ok (Incoming RecordingUploading) ->
            ( { model | recordingState = RecordingUploading }, Cmd.none )

        Ok (Done meta) ->
            let
                friendlySize =
                    formatSize meta.sizeBytes

                message =
                    "Recording saved — " ++ friendlySize

                modelWithMeta =
                    { model | recordingState = RecordingIdle }
                        |> prependToOpenList meta
            in
            Update.Toast.push ToastSuccess message modelWithMeta

        Ok (Failed reason) ->
            Update.Toast.push ToastError
                ("Recording failed: " ++ reason)
                { model | recordingState = RecordingFailed reason }

        Ok (Incoming (RecordingFailed reason)) ->
            -- Defensive: we don't expect JS to ever fire a
            -- "failed" through the Incoming branch, but if it
            -- does, route it the same way.
            Update.Toast.push ToastError
                ("Recording failed: " ++ reason)
                { model | recordingState = RecordingFailed reason }

        Ok (Incoming RecordingIdle) ->
            ( { model | recordingState = RecordingIdle }, Cmd.none )

        Err _ ->
            ( model, Cmd.none )



-- ── decoders ──────────────────────────────────────────────────────────────


type Incoming
    = Incoming RecordingState
    | Done RecordingMeta
    | Failed String


stateDecoder : D.Decoder Incoming
stateDecoder =
    D.field "state" D.string
        |> D.andThen
            (\name ->
                case name of
                    "preparing" ->
                        D.succeed (Incoming RecordingPreparing)

                    "recording" ->
                        D.field "elapsedMs" D.int
                            |> D.map (\ms -> Incoming (RecordingActive { elapsedMs = ms }))

                    "uploading" ->
                        D.succeed (Incoming RecordingUploading)

                    "idle" ->
                        D.succeed (Incoming RecordingIdle)

                    "done" ->
                        D.field "meta" Recording.decodeMeta
                            |> D.map Done

                    "error" ->
                        D.field "message" D.string
                            |> D.map Failed

                    other ->
                        D.fail ("Unknown recording state: " ++ other)
            )


formatSize : Int -> String
formatSize bytes =
    if bytes < 1024 * 1024 then
        let
            kb =
                toFloat bytes / 1024
        in
        formatFloat kb 1 ++ " KB"

    else
        let
            mb =
                toFloat bytes / (1024 * 1024)
        in
        formatFloat mb 1 ++ " MB"


formatFloat : Float -> Int -> String
formatFloat n decimals =
    let
        scale =
            10 ^ decimals

        rounded =
            toFloat (round (n * toFloat scale)) / toFloat scale
    in
    String.fromFloat rounded



-- ── Recordings modal ─────────────────────────────────────────────────────


withRecordingsUi : (RecordingsUi -> RecordingsUi) -> Model -> Model
withRecordingsUi =
    Model.mapModal Model.recordingsLens


{-| Open the Recordings modal. Always kicks off the list fetch
so the GM sees the freshest server state — recordings can be
created from another tab too.
-}
recordingsOpen : Model -> ( Model, Cmd Msg )
recordingsOpen model =
    ( { model
        | modal = Just (ModalRecordings Recording.freshRecordings)
      }
    , if Auth.isAuthenticated model.auth then
        Recording.listCmd RecordingsListLoaded

      else
        Cmd.none
    )


recordingsClose : Model -> ( Model, Cmd Msg )
recordingsClose model =
    ( { model | modal = Nothing }, Cmd.none )


recordingsListLoaded :
    Result Http.Error (List RecordingMeta)
    -> Model
    -> ( Model, Cmd Msg )
recordingsListLoaded result model =
    let
        next =
            case result of
                Ok metas ->
                    RecordingsLoaded metas

                Err err ->
                    RecordingsFailed (Util.Http.errorToString err)
    in
    ( withRecordingsUi (\ui -> { ui | saves = next }) model, Cmd.none )


recordingsDeleteRequested :
    { id : String, filename : String }
    -> Model
    -> ( Model, Cmd Msg )
recordingsDeleteRequested target model =
    ( withRecordingsUi
        (\ui -> { ui | confirm = Just (ConfirmDelete target), error = Nothing })
        model
    , Cmd.none
    )


recordingsDeleteCancel : Model -> ( Model, Cmd Msg )
recordingsDeleteCancel model =
    ( withRecordingsUi (\ui -> { ui | confirm = Nothing }) model, Cmd.none )


recordingsDeleteConfirm : Model -> ( Model, Cmd Msg )
recordingsDeleteConfirm model =
    case model.modal of
        Just (ModalRecordings ui) ->
            case ui.confirm of
                Just (ConfirmDelete target) ->
                    ( withRecordingsUi
                        (\u ->
                            { u
                                | busy = True
                                , confirm = Nothing
                                , error = Nothing
                            }
                        )
                        model
                    , Recording.deleteCmd
                        (RecordingsDeleteResponse target.id)
                        target.id
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


recordingsDeleteResponse :
    String
    -> Result Http.Error ()
    -> Model
    -> ( Model, Cmd Msg )
recordingsDeleteResponse id result model =
    case result of
        Ok () ->
            ( withRecordingsUi
                (\ui ->
                    { ui
                        | busy = False
                        , saves = dropFromList id ui.saves
                    }
                )
                model
            , Cmd.none
            )

        Err err ->
            ( withRecordingsUi
                (\ui ->
                    { ui
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


dropFromList : String -> RecordingsListState -> RecordingsListState
dropFromList id state =
    case state of
        RecordingsLoaded metas ->
            RecordingsLoaded (List.filter (\m -> m.id /= id) metas)

        _ ->
            state


{-| When a `done` payload arrives while the Recordings modal is
open, slot the new entry at the top of its list so the GM sees
their fresh recording without having to close + reopen.
-}
prependToOpenList : RecordingMeta -> Model -> Model
prependToOpenList meta model =
    case model.modal of
        Just (ModalRecordings ui) ->
            let
                newSaves =
                    case ui.saves of
                        RecordingsLoaded metas ->
                            RecordingsLoaded (meta :: metas)

                        _ ->
                            -- List was loading or failed; the open
                            -- + fetch sequence will reconcile.
                            ui.saves
            in
            { model | modal = Just (ModalRecordings { ui | saves = newSaves }) }

        _ ->
            model
