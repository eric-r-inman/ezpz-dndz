module Ui.Recording exposing
    ( RecordingMeta, RecordingState(..)
    , decodeMeta
    , fresh
    )

{-| Session recorder UI state.

The recorder is intentionally tiny: one button in the AppBar that
cycles through `RecordingIdle` → `RecordingPreparing` →
`RecordingActive` → `RecordingUploading` → `RecordingIdle`. All
state lives on the model — there's no modal, no list view yet
(see `View.Modal.Recording` and `Update.Recording` for the v0.5
expansion).

The audio capture itself happens in JS via `MediaRecorder`. Elm
fires `Ports.startRecording` / `Ports.stopRecording` and listens
for state-change messages on `Ports.recordingState`.

@docs RecordingMeta, RecordingState
@docs decodeMeta
@docs fresh

-}

import Json.Decode as D


{-| Where the button is in the cycle.

  - `RecordingIdle` — default, button reads "🎙 Record".
  - `RecordingPreparing` — `getUserMedia` in flight (mic permission
    prompt is up); button reads "⏳ Preparing…" so a slow prompt
    doesn't look frozen.
  - `RecordingActive` — capturing. `elapsedMs` ticks at ~1Hz so
    the button can show "⏺ Stop · 02:34".
  - `RecordingUploading` — multipart upload in flight; button
    reads "⏳ Uploading…" and the click handler is suppressed
    so the GM can't double-fire.
  - `RecordingFailed` — last attempt errored; the message renders
    as a small inline strip + the button returns to Idle so a
    second click retries.

-}
type RecordingState
    = RecordingIdle
    | RecordingPreparing
    | RecordingActive { elapsedMs : Int }
    | RecordingUploading
    | RecordingFailed String


{-| Metadata for one stored recording — mirrors
`RecordingMeta` on the server side. Used to surface the toast
message after a successful upload ("Recording saved — 5.2 MB").
-}
type alias RecordingMeta =
    { id : String
    , filename : String
    , mime : String
    , sizeBytes : Int
    , createdAtMs : Int
    }


fresh : RecordingState
fresh =
    RecordingIdle


decodeMeta : D.Decoder RecordingMeta
decodeMeta =
    D.map5 RecordingMeta
        (D.field "id" D.string)
        (D.field "filename" D.string)
        (D.field "mime" D.string)
        (D.field "size_bytes" D.int)
        (D.field "created_at_ms" D.int)
