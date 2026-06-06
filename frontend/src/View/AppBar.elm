module View.AppBar exposing (me, view)

{-| Top-of-page application bar (brand + nav links + ⚙ settings
popover) and the `/me` account view shown by `Route.Me`.

`me` is here rather than in a separate `View.Me` because it's the
only thing rendered for the `Me` route and shares the auth/identity
domain with the app-bar nav.

The settings popover is a controlled `<div>` (not native
`<details>`) because the global Esc + click-outside
subscriptions in `Main.subscriptions` need to close it
declaratively when open. Styling lives under `.app-settings`
in `style.css`; the row pattern (label + radio cluster) is
extensible — Density, Sound, etc. will plug in alongside the
Theme row when those preferences land.

-}

-- import Auth handled below; kept here to make the module exports
-- self-explanatory.

import Auth
import Html
    exposing
        ( Html
        , a
        , button
        , div
        , fieldset
        , h2
        , header
        , label
        , legend
        , nav
        , p
        , span
        , text
        )
import Html.Attributes as Attr exposing (attribute, class, href, name, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (MeStatus(..), Msg(..), Theme(..))
import Route exposing (Route(..))
import Ui.Recording exposing (RecordingState(..))
import View.Tooltips as Tooltips


view :
    { settingsOpen : Bool
    , theme : Theme
    , user : Maybe Auth.User
    , useCustomCardLayout : Bool
    , route : Route
    , recordingState : RecordingState
    }
    -> Html Msg
view cfg =
    header [ class "app-bar" ]
        [ -- Skip-to-main link: visually hidden until focused; lets
          -- keyboard users jump past the ~half-dozen tab stops in
          -- the AppBar nav.  Target is `#main`, which `Workspace`
          -- now sets on its `<main>` element.  CSS in style.css
          -- handles the focus-visible reveal.
          a
            [ class "app-bar__skip-link"
            , href "#main"
            ]
            [ text "Skip to main content" ]
        , div [ class "app-bar__brand" ]
            [ div [ class "app-bar__title" ] [ text "eZpZ-dndZ" ]
            , signInTagline cfg.user
            ]
        , nav [ class "app-bar__nav" ]
            [ -- Text-labelled nav items intentionally omit
              -- `Tooltips.attr` — the label is self-explanatory,
              -- and hover bubbles on every item turn the bar
              -- into noise.  Settings (⚙) keeps its tooltip
              -- because it's icon-only.
              a [ href "/" ] [ text "Encounter" ]
            , recordButton cfg.user cfg.recordingState

            -- Customize-card feature hidden for launch.  The
            -- supporting modules (`Card.Layout`, `View.Card.Custom`,
            -- `Update.CardEditor`, the modal, the editor UI) are
            -- still in the codebase but unreachable from the
            -- AppBar.  To re-enable, restore the two buttons
            -- below and re-instate the `useCustomCardLayout`
            -- branch in `View.Workspace.panelMain`.
            --
            -- , button
            --     [ class "app-bar__card-editor"
            --     , type_ "button"
            --     , onClick CardEditorOpen
            --     ]
            --     [ text "Customize card" ]
            -- , button
            --     [ class
            --         ("app-bar__card-editor"
            --             ++ (if cfg.useCustomCardLayout then
            --                     " app-bar__card-editor--active"
            --
            --                 else
            --                     ""
            --                )
            --         )
            --     , type_ "button"
            --     , onClick CustomCardLayoutToggle
            --     ]
            --     [ text
            --         (if cfg.useCustomCardLayout then
            --             "Custom: on"
            --
            --          else
            --             "Custom: off"
            --         )
            --     ]
            , userLink cfg.user cfg.route
            , a
                [ class "app-bar__about"
                , href "/about"
                ]
                [ text "About" ]
            , a
                [ class "app-bar__donate"
                , href "/donate"
                ]
                [ text "Donate" ]
            , settings cfg.settingsOpen cfg.theme
            ]
        ]


{-| Italic prompt sitting next to the brand. Only shown when the
session is anonymous — authenticated users have nothing to gain
from a "sign in" nudge. Per-theme colour comes from the
`--tagline-color` CSS variable in style.css, so adding a new
theme means setting the token, not editing this view.
-}
signInTagline : Maybe Auth.User -> Html msg
signInTagline maybeUser =
    case maybeUser of
        Just _ ->
            text ""

        Nothing ->
            span [ class "app-bar__tagline" ]
                [ text "Sign in to save your encounters and compendium changes." ]


{-| Identity slot in the AppBar.

  - Authenticated → display name link to `/me`.
  - Anonymous (any route except `/login`) → "Sign in" link to
    `/login`.
  - Anonymous AND already on `/login` → render nothing. The form
    on the page IS the sign-in affordance; an AppBar link back to
    the same route would look broken.

-}
userLink : Maybe Auth.User -> Route -> Html Msg
userLink maybeUser route =
    case maybeUser of
        Just user ->
            a
                [ class "app-bar__user"
                , href "/me"
                ]
                [ text user.displayName ]

        Nothing ->
            if route == Login then
                text ""

            else
                a
                    [ class "app-bar__user app-bar__user--anonymous"
                    , href "/login"
                    ]
                    [ text "Sign in" ]


{-| ⚙ button + popover. Wraps the popover in a `<div>` with
`stopPropagationOn "mousedown"` so a click _inside_ the popover
doesn't bubble up to the document-level "click-outside closes"
handler in `Main.subscriptions`. The trigger button itself
reports its open state via `aria-expanded` for screen readers.
-}
settings : Bool -> Theme -> Html Msg
settings isOpen theme =
    let
        wrapperClass =
            if isOpen then
                "app-settings app-settings--open"

            else
                "app-settings"
    in
    div
        [ class wrapperClass
        , stopPropagationOn "mousedown" (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class "app-settings__trigger"
            , type_ "button"
            , attribute "aria-haspopup" "dialog"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            , attribute "aria-label" "Open settings"
            , Tooltips.attr Tooltips.appBarSettings
            , onClick SettingsToggle
            ]
            [ text "⚙" ]
        , if isOpen then
            div
                [ class "app-settings__menu"
                , -- Settings popover holds a radio-group, not a
                  -- menubar of menuitems.  WAI-ARIA's `role="menu"`
                  -- semantics expect `menuitem` / `menuitemradio`
                  -- children, not `<input type="radio">`.  The
                  -- correct role for "a panel of settings" is
                  -- `dialog` or just no role at all — the trigger
                  -- already carries `aria-haspopup` + `aria-expanded`
                  -- which is enough metadata for SR clients.  We
                  -- use `region` + `aria-label` so the popover
                  -- shows up as a labelled landmark while the
                  -- inner radios keep their natural fieldset/legend
                  -- semantics.
                  attribute "role" "region"
                , attribute "aria-label" "Settings"
                ]
                [ themeRow theme
                ]

          else
            text ""
        ]


themeRow : Theme -> Html Msg
themeRow current =
    fieldset [ class "app-settings__row" ]
        [ legend [ class "app-settings__row-label" ] [ text "Theme" ]
        , div [ class "app-settings__radio-group" ]
            [ themeRadio current Modern "Modern" ""
            , themeRadio current Dark "Dark" ""
            , themeRadio current Auto "Auto" ""
            , themeRadio current Accessible "Accessible" "(alpha)"
            ]
        ]


{-| A single theme option in the settings popover. `badge` is
rendered as a muted suffix next to the label when non-empty —
used to mark the Accessible theme as `(alpha)`. Pass `""` for
no badge.
-}
themeRadio : Theme -> Theme -> String -> String -> Html Msg
themeRadio current value labelText badge =
    label [ class "app-settings__radio" ]
        [ Html.input
            [ type_ "radio"
            , name "theme"
            , Attr.checked (current == value)
            , onClick (PreferencesThemeSet value)
            ]
            []
        , text labelText
        , if String.isEmpty badge then
            text ""

          else
            span [ class "app-settings__radio-badge" ] [ text (" " ++ badge) ]
        ]


{-| Session-recorder button (the first plugin's UI surface).
Cycles `🎙 Record → ⏺ Stop · mm:ss → ⏳ Uploading…`. Disabled
when the user is anonymous because the upload endpoint is
auth-gated; the tooltip explains why.
-}
recordButton : Maybe Auth.User -> RecordingState -> Html Msg
recordButton maybeUser state =
    let
        signedIn =
            maybeUser /= Nothing

        ( label_, cls, disabledNow ) =
            case ( signedIn, state ) of
                ( False, _ ) ->
                    ( "🎙 Record"
                    , "app-bar__record app-bar__record--disabled"
                    , True
                    )

                ( True, RecordingIdle ) ->
                    ( "🎙 Record"
                    , "app-bar__record"
                    , False
                    )

                ( True, RecordingPreparing ) ->
                    ( "⏳ Preparing…"
                    , "app-bar__record app-bar__record--preparing"
                    , True
                    )

                ( True, RecordingActive { elapsedMs } ) ->
                    ( "⏺ Stop · " ++ formatElapsed elapsedMs
                    , "app-bar__record app-bar__record--active"
                    , False
                    )

                ( True, RecordingUploading ) ->
                    ( "⏳ Uploading…"
                    , "app-bar__record app-bar__record--uploading"
                    , True
                    )

                ( True, RecordingFailed _ ) ->
                    ( "🎙 Record"
                    , "app-bar__record app-bar__record--failed"
                    , False
                    )

        tooltip =
            if not signedIn then
                "Sign in to record sessions"

            else
                case state of
                    RecordingIdle ->
                        "Start recording this session"

                    RecordingPreparing ->
                        "Waiting for microphone permission"

                    RecordingActive _ ->
                        "Stop recording and upload"

                    RecordingUploading ->
                        "Uploading recording…"

                    RecordingFailed reason ->
                        "Last attempt failed: " ++ reason ++ " — click to retry"
    in
    button
        [ class cls
        , type_ "button"
        , Attr.disabled disabledNow
        , Tooltips.attr tooltip
        , attribute "aria-label" tooltip
        , onClick RecordingToggleClicked
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


me : MeStatus -> Html Msg
me status =
    case status of
        Loading ->
            p [ class "empty" ] [ text "Loading…" ]

        Failed ->
            p [ class "empty" ] [ text "Failed to load user information." ]

        Loaded info ->
            div []
                [ h2 [] [ text info.name ]
                , p []
                    [ text
                        ("Authentication: "
                            ++ (if info.authEnabled then
                                    "enabled"

                                else
                                    "disabled"
                               )
                        )
                    ]
                ]
