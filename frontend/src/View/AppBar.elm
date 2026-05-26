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
import View.Tooltips as Tooltips


view :
    { settingsOpen : Bool
    , theme : Theme
    , user : Maybe Auth.User
    , useCustomCardLayout : Bool
    , route : Route
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
            ]
        , nav [ class "app-bar__nav" ]
            [ a [ href "/" ] [ text "Encounter" ]
            , button
                [ class "app-bar__card-editor"
                , type_ "button"
                , onClick CardEditorOpen
                , Tooltips.attr Tooltips.appBarCardEditor
                ]
                [ text "Customize card" ]
            , button
                [ class
                    ("app-bar__card-editor"
                        ++ (if cfg.useCustomCardLayout then
                                " app-bar__card-editor--active"

                            else
                                ""
                           )
                    )
                , type_ "button"
                , onClick CustomCardLayoutToggle
                , Tooltips.attr
                    (if cfg.useCustomCardLayout then
                        "Switch encounter cards back to the classic renderer"

                     else
                        "Use the custom card layout in the encounter (prototype: limited inline-edit)"
                    )
                ]
                [ text
                    (if cfg.useCustomCardLayout then
                        "Custom: on"

                     else
                        "Custom: off"
                    )
                ]
            , userLink cfg.user cfg.route
            , a
                [ class "app-bar__donate"
                , href "/donate"
                , Tooltips.attr Tooltips.appBarDonate
                ]
                [ text "Donate" ]
            , settings cfg.settingsOpen cfg.theme
            ]
        ]


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
                , Tooltips.attr Tooltips.appBarAccount
                ]
                [ text user.displayName ]

        Nothing ->
            if route == Login then
                text ""

            else
                a
                    [ class "app-bar__user app-bar__user--anonymous"
                    , href "/login"
                    , Tooltips.attr "Sign in or create an account to save encounters on the server."
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
            [ themeRadio current Modern "Modern"
            , themeRadio current Dark "Dark"
            , themeRadio current Auto "Auto"
            , themeRadio current Accessible "Accessible"
            ]
        ]


themeRadio : Theme -> Theme -> String -> Html Msg
themeRadio current value labelText =
    label [ class "app-settings__radio" ]
        [ Html.input
            [ type_ "radio"
            , name "theme"
            , Attr.checked (current == value)
            , onClick (PreferencesThemeSet value)
            ]
            []
        , text labelText
        ]


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
