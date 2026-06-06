module View.Modal.Recordings exposing (view)

{-| Recordings modal — the second piece of the session-recorder
plugin.

Layout, top to bottom:

  - Status / record button: a big affordance that mirrors the
    state of the toolbar button. Idle → "● Record session";
    Active → "⏺ Stop · mm:ss" with the same red pulse the
    toolbar uses; Preparing / Uploading render as muted busy
    pills. Anonymous users see a sign-in nudge instead.
  - Inline confirm banner when a delete is pending.
  - Inline error banner when a list / delete request fails.
  - The list of saved recordings — newest-first row of
    `filename · date · size · ⬇ download · 🗑 delete`.
    Empty state: friendly "no recordings yet" prompt.
  - Close row.

-}

import Auth
import Html exposing (Html, a, button, div, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, disabled, download, href, type_)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Recording
    exposing
        ( ConfirmAction(..)
        , RecordingMeta
        , RecordingState(..)
        , RecordingsListState(..)
        , RecordingsUi
        )
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalRecordings ui) ->
            View.Modal.view
                { close = RecordingsClose
                , noOp = NoOp
                , title = "Recordings"
                , extraClass = "modal--recordings"
                , chrome = model.modalChrome
                , body =
                    [ recordControl model.auth model.recordingState
                    , confirmBanner ui
                    , errorBanner ui
                    , savesSection model.auth ui
                    , closeRow
                    ]
                }

        _ ->
            text ""



-- ── record control ───────────────────────────────────────────────────────


recordControl : Auth.AuthState -> RecordingState -> Html Msg
recordControl auth state =
    if not (Auth.isAuthenticated auth) then
        div [ class "recordings__hero" ]
            [ p [ class "recordings__hero-hint" ]
                [ text "Sign in to record sessions and store them on the eZpZ-dndZ server." ]
            ]

    else
        let
            ( label_, modifier, disabledNow ) =
                case state of
                    RecordingIdle ->
                        ( "● Record session"
                        , ""
                        , False
                        )

                    RecordingPreparing ->
                        ( "⏳ Preparing…"
                        , " recordings__hero-btn--busy"
                        , True
                        )

                    RecordingActive { elapsedMs } ->
                        ( "⏺ Stop · " ++ formatElapsed elapsedMs
                        , " recordings__hero-btn--active"
                        , False
                        )

                    RecordingUploading ->
                        ( "⏳ Uploading…"
                        , " recordings__hero-btn--busy"
                        , True
                        )

                    RecordingFailed _ ->
                        ( "● Record session"
                        , " recordings__hero-btn--failed"
                        , False
                        )

            caption =
                case state of
                    RecordingIdle ->
                        "Click to start.  Audio uploads when you stop."

                    RecordingPreparing ->
                        "Waiting for microphone permission…"

                    RecordingActive _ ->
                        "Recording.  Click stop to upload."

                    RecordingUploading ->
                        "Uploading to the server…"

                    RecordingFailed reason ->
                        "Last attempt failed: " ++ reason
        in
        div [ class "recordings__hero" ]
            [ button
                [ class ("recordings__hero-btn" ++ modifier)
                , type_ "button"
                , disabled disabledNow
                , onClick RecordingToggleClicked
                ]
                [ text label_ ]
            , p [ class "recordings__hero-caption" ] [ text caption ]
            ]


formatElapsed : Int -> String
formatElapsed elapsedMs =
    let
        totalSec =
            elapsedMs // 1000

        mins =
            totalSec // 60

        secs =
            modBy 60 totalSec

        pad n =
            if n < 10 then
                "0" ++ String.fromInt n

            else
                String.fromInt n
    in
    pad mins ++ ":" ++ pad secs



-- ── confirm / error banners ───────────────────────────────────────────────


confirmBanner : RecordingsUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmDelete target) ->
            div [ class "save-modal__confirm" ]
                [ p [ class "save-modal__confirm-msg" ]
                    [ text ("Delete \"" ++ target.filename ++ "\"? This cannot be undone.") ]
                , div [ class "save-modal__confirm-actions" ]
                    [ button
                        [ class "action-btn action-btn--red"
                        , onClick RecordingsDeleteConfirm
                        , disabled ui.busy
                        ]
                        [ text "Delete" ]
                    , button
                        [ class "action-btn"
                        , onClick RecordingsDeleteCancel
                        , disabled ui.busy
                        ]
                        [ text "Cancel" ]
                    ]
                ]

        Nothing ->
            text ""


errorBanner : RecordingsUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "save-modal__error" ] [ text err ]

        Nothing ->
            text ""



-- ── saves list ────────────────────────────────────────────────────────────


savesSection : Auth.AuthState -> RecordingsUi -> Html Msg
savesSection auth ui =
    if not (Auth.isAuthenticated auth) then
        text ""

    else
        case ui.saves of
            RecordingsLoading ->
                div [ class "save-modal__list-empty" ]
                    [ text "Loading recordings…" ]

            RecordingsFailed _ ->
                div [ class "save-modal__list-empty" ]
                    [ text "No recordings yet." ]

            RecordingsLoaded [] ->
                div [ class "save-modal__list-empty" ]
                    [ text "No recordings yet — click ● to start your first one." ]

            RecordingsLoaded metas ->
                div [ class "save-modal__list-wrap" ]
                    [ p [ class "save-modal__list-title" ] [ text "Saved sessions" ]
                    , ul [ class "save-modal__list recordings__list" ]
                        (List.map (recordingRow ui.busy) metas)
                    ]


recordingRow : Bool -> RecordingMeta -> Html Msg
recordingRow isBusy meta =
    li [ class "save-modal__row-item recordings__row" ]
        [ div [ class "recordings__row-text" ]
            [ span [ class "recordings__row-name" ] [ text meta.filename ]
            , span [ class "recordings__row-meta" ]
                [ text (formatDate meta.createdAtMs ++ " · " ++ formatSize meta.sizeBytes) ]
            ]
        , div [ class "save-modal__row-actions recordings__row-actions" ]
            [ a
                [ class "icon-btn"
                , href ("/api/recording/" ++ meta.id)
                , download meta.filename
                , Tooltips.attr "Download recording"
                , attribute "aria-label" ("Download " ++ meta.filename)
                ]
                [ text "⬇" ]
            , button
                [ class "icon-btn icon-btn--danger"
                , disabled isBusy
                , onClick
                    (RecordingsDeleteRequested
                        { id = meta.id, filename = meta.filename }
                    )
                , Tooltips.attr "Delete recording"
                , attribute "aria-label" ("Delete " ++ meta.filename)
                ]
                [ text "🗑" ]
            ]
        ]



-- ── formatters ────────────────────────────────────────────────────────────


{-| Human-friendly file size: `47 KB`, `5.2 MB`.
-}
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


{-| Rough ISO-style timestamp: `2026-06-05 17:32`. Server sends
unix ms; we extract date components by integer arithmetic so we
don't have to pull in the whole `Time` module for one display
helper. The math handles the Gregorian leap-year rules through


-}
formatDate : Int -> String
formatDate ms =
    let
        secs =
            ms // 1000

        days =
            secs // 86400

        secOfDay =
            modBy 86400 secs

        hour =
            secOfDay // 3600

        minute =
            modBy 3600 secOfDay // 60

        ( y, m, d ) =
            epochDaysToYmd days

        pad n =
            if n < 10 then
                "0" ++ String.fromInt n

            else
                String.fromInt n
    in
    String.fromInt y
        ++ "-"
        ++ pad m
        ++ "-"
        ++ pad d
        ++ " "
        ++ pad hour
        ++ ":"
        ++ pad minute


{-| Days-since-1970 → `(year, month, day)`. Standard civil-from-
days algorithm; correct through 2099 and beyond.
-}
epochDaysToYmd : Int -> ( Int, Int, Int )
epochDaysToYmd days =
    let
        shifted =
            days + 719468

        era =
            shifted // 146097

        doe =
            shifted - era * 146097

        yoe =
            (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365

        y =
            yoe + era * 400

        doy =
            doe - (365 * yoe + yoe // 4 - yoe // 100)

        mp =
            (5 * doy + 2) // 153

        d =
            doy - (153 * mp + 2) // 5 + 1

        m =
            if mp < 10 then
                mp + 3

            else
                mp - 9

        finalY =
            if m <= 2 then
                y + 1

            else
                y
    in
    ( finalY, m, d )


closeRow : Html Msg
closeRow =
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn"
            , onClick RecordingsClose
            ]
            [ text "Close" ]
        ]
