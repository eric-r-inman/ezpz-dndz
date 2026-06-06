module View.PanelDetail exposing (view)

{-| Right pane: compendium toolbar + the pinned-creature stat
block.

The stat-block area has four states (in priority order):

  - Pinned creature found by id → render the matched entry via
    `View.StatBlock.view` (clickable inline dice and all).
  - Pinned creature found by name fallback → same renderer.
    This catches the case where an old saved encounter's
    `creatureId` is no longer in the bundled compendium — we
    still find the right stat block by display name so the
    panel doesn't silently revert to a placeholder.
  - Pinned creature exists but the compendium can't resolve it
    (still loading, or no match by id or name) → render an
    empty-state message naming the creature. The previous
    behaviour fell through to a hardcoded "Brakka, Ogre Brute"
    mock which read as if the panel were stuck on the wrong
    creature.
  - Nothing pinned → render a friendly "click a creature name"
    hint. No more bundled mock.

-}

import Auth
import Compendium
import Encounter.Roster
import Html exposing (Html, a, button, div, p, section, text)
import Html.Attributes as Attr exposing (attribute, class, href, target, title, type_)
import Html.Events exposing (onClick)
import Model exposing (Model, PanelPin)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Recording exposing (RecordingState(..))
import View.StatBlock
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    section [ class "panel panel--detail" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Compendium" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid compendium-toolbar" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumOpen
                    , Tooltips.attr Tooltips.panelOpenCompendium
                    ]
                    [ text "📖 Open" ]
                , recordButton (Auth.isAuthenticated model.auth) model.recordingState
                ]
            , statBlock model
            ]
        ]


{-| Session-recorder button (the first plugin's UI surface).
Replaces the old `⚔️ CR Calculator` slot in this panel because
the CR Calculator is already reachable via the _Difficulty_
button in the encounter title bar.

Click semantics differ by state so the toolbar stays a
quick-access affordance:

  - **Idle / Failed** — opens the Recordings modal (which has
    its own large record-now button and the list of past
    sessions).
  - **Active** — stops + uploads directly without opening the
    modal so a recording can be ended fast.
  - **Preparing / Uploading** — disabled.

Anonymous users see the disabled idle pill with a sign-in
tooltip; the modal's auth-aware empty state explains how to
unlock it.

-}
recordButton : Bool -> RecordingState -> Html Msg
recordButton signedIn state =
    let
        ( label_, modifier, disabledNow ) =
            case ( signedIn, state ) of
                ( False, _ ) ->
                    ( "🎙 Recordings"
                    , " action-btn--record-disabled"
                    , True
                    )

                ( True, RecordingIdle ) ->
                    ( "🎙 Recordings", "", False )

                ( True, RecordingPreparing ) ->
                    ( "⏳ Preparing…"
                    , " action-btn--record-preparing"
                    , True
                    )

                ( True, RecordingActive { elapsedMs } ) ->
                    ( "⏺ Stop · " ++ formatElapsed elapsedMs
                    , " action-btn--record-active"
                    , False
                    )

                ( True, RecordingUploading ) ->
                    ( "⏳ Uploading…"
                    , " action-btn--record-uploading"
                    , True
                    )

                ( True, RecordingFailed _ ) ->
                    ( "🎙 Recordings"
                    , " action-btn--record-failed"
                    , False
                    )

        tooltip =
            if not signedIn then
                "Sign in to record sessions"

            else
                case state of
                    RecordingIdle ->
                        "Open the Recordings panel"

                    RecordingPreparing ->
                        "Waiting for microphone permission"

                    RecordingActive _ ->
                        "Stop recording and upload"

                    RecordingUploading ->
                        "Uploading recording…"

                    RecordingFailed reason ->
                        "Last attempt failed: " ++ reason

        clickMsg =
            case state of
                RecordingActive _ ->
                    RecordingToggleClicked

                _ ->
                    RecordingsOpen
    in
    button
        [ class ("action-btn action-btn--blue" ++ modifier)
        , type_ "button"
        , Attr.disabled disabledNow
        , Tooltips.attr tooltip
        , attribute "aria-label" tooltip
        , onClick clickMsg
        ]
        [ text label_ ]


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


statBlock : Model -> Html Msg
statBlock model =
    case model.panelCreaturePin of
        Just pin ->
            case resolvePin pin model.compendium.db of
                Just creature ->
                    pinnedStatBlock creature

                Nothing ->
                    notFound pin model.compendium.db

        Nothing ->
            emptyState


resolvePin : PanelPin -> CompendiumDb -> Maybe Compendium.Creature
resolvePin pin db =
    case db of
        CompendiumDbLoaded loaded ->
            case Compendium.find pin.id loaded of
                Just c ->
                    Just c

                Nothing ->
                    -- Encounter creatures named like "Adult Blue
                    -- Dragon 2" come from `uniqueInstanceName`,
                    -- which suffixes a numeric instance index.
                    -- Strip it before the name lookup so duplicates
                    -- still match the canonical compendium entry.
                    Compendium.findByName (Encounter.Roster.instanceBaseName pin.name) loaded

        _ ->
            Nothing


pinnedStatBlock : Compendium.Creature -> Html Msg
pinnedStatBlock creature =
    div [ class "panel-statblock" ]
        [ a
            [ class "panel-statblock__open"
            , href ("/compendium/creatures/" ++ creature.id)
            , target "_blank"
            , attribute "rel" "noopener"
            , Tooltips.attr Tooltips.panelStatBlockNewWindow
            , attribute "aria-label" "Open in new window"
            ]
            [ text "↗" ]
        , View.StatBlock.view RollFromStatBlock AbilitySaveOpen View.StatBlock.TagIconTooltip creature
        ]


notFound : PanelPin -> CompendiumDb -> Html Msg
notFound pin db =
    let
        message =
            case db of
                CompendiumDbLoading ->
                    "Loading the compendium…"

                CompendiumDbFailed _ ->
                    "Couldn't load the compendium."

                CompendiumDbLoaded _ ->
                    "\"" ++ pin.name ++ "\" isn't in your compendium yet."
    in
    div [ class "panel-statblock panel-statblock--empty" ]
        [ p [ class "empty" ] [ text message ] ]


emptyState : Html Msg
emptyState =
    div [ class "panel-statblock panel-statblock--empty" ]
        [ p [ class "empty" ]
            [ text "Click a creature's name on a card to pin its stat block here." ]
        ]
