module Ui.Recording exposing
    ( RecordingState(..), RecordingMeta
    , RecordingsUi, RecordingsListState(..), ConfirmAction(..)
    , freshState, freshRecordings, decodeMeta
    , listCmd, deleteCmd
    )

{-| Session recorder UI state — both the per-frame "is there a
recording in flight" pulse on the toolbar button, and the modal
that lists / downloads / deletes past recordings.

The two pieces live in this module together because they share
the wire shape (`RecordingMeta`) and the typical user flow goes
button → modal → list → record / download / delete and back.

@docs RecordingState, RecordingMeta
@docs RecordingsUi, RecordingsListState, ConfirmAction
@docs freshState, freshRecordings, decodeMeta
@docs listCmd, deleteCmd

-}

import Http
import Json.Decode as D



-- ── PER-BUTTON STATE (the toolbar pulse) ──────────────────────────────────


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


freshState : RecordingState
freshState =
    RecordingIdle



-- ── SHARED METADATA (server wire shape) ───────────────────────────────────


{-| Metadata for one stored recording — mirrors `RecordingMeta`
in `crates/server/src/recording/store.rs`. Used by the modal's
list rows and by the post-upload toast.
-}
type alias RecordingMeta =
    { id : String
    , filename : String
    , mime : String
    , sizeBytes : Int
    , createdAtMs : Int
    }


decodeMeta : D.Decoder RecordingMeta
decodeMeta =
    D.map5 RecordingMeta
        (D.field "id" D.string)
        (D.field "filename" D.string)
        (D.field "mime" D.string)
        (D.field "size_bytes" D.int)
        (D.field "created_at_ms" D.int)



-- ── MODAL STATE (the Recordings list) ─────────────────────────────────────


{-| State the Recordings modal carries while open. Mirrors the
shape of the Save / Load modals so the view code can reuse the
existing `.save-modal__*` CSS scaffolding for the list rows +
confirm banner.
-}
type alias RecordingsUi =
    { saves : RecordingsListState
    , busy : Bool
    , error : Maybe String
    , confirm : Maybe ConfirmAction
    }


type RecordingsListState
    = RecordingsLoading
    | RecordingsLoaded (List RecordingMeta)
    | RecordingsFailed String


type ConfirmAction
    = ConfirmDelete { id : String, filename : String }


freshRecordings : RecordingsUi
freshRecordings =
    { saves = RecordingsLoading
    , busy = False
    , error = Nothing
    , confirm = Nothing
    }



-- ── HTTP commands ─────────────────────────────────────────────────────────


{-| `GET /api/recording` — list the current user's recordings,
newest-first. Server is auth-gated so this only succeeds for
signed-in users; anonymous callers get a 401 which the
view-layer error banner surfaces as a sign-in nudge.
-}
listCmd : (Result Http.Error (List RecordingMeta) -> msg) -> Cmd msg
listCmd toMsg =
    Http.get
        { url = "/api/recording"
        , expect = Http.expectJson toMsg (D.list decodeMeta)
        }


{-| `DELETE /api/recording/:id`. The server removes both the
audio file and the index entry; the response carries no body
(204 No Content on success).
-}
deleteCmd : (Result Http.Error () -> msg) -> String -> Cmd msg
deleteCmd toMsg id =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/recording/" ++ id
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
