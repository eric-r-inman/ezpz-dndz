module Update.Recording exposing
    ( stateReceived
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
import Json.Decode as D
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ports
import Ui.Recording as Recording exposing (RecordingMeta, RecordingState(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Toast


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
            in
            Update.Toast.push ToastSuccess
                message
                { model | recordingState = RecordingIdle }

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
