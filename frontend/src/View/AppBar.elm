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
        , text
        )
import Html.Attributes as Attr exposing (attribute, class, href, name, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (MeStatus(..), Msg(..), Theme(..))
import View.Tooltips as Tooltips


view : Bool -> Theme -> Html Msg
view _ _ =
    -- The ⚙ settings popover (light/dark/auto theme switcher) is
    -- temporarily hidden from the nav while the light theme gets
    -- more polish.  All the supporting code below — `settings`,
    -- `themeRow`, `themeRadio`, the PreferencesThemeSet wiring —
    -- stays in place so re-enabling is a one-line change in `nav`.
    -- The two parameters stay on the signature so callers in
    -- Main.elm don't have to be edited; they're passed through
    -- but ignored here for now.
    header [ class "app-bar" ]
        [ div [ class "app-bar__brand" ]
            [ div [ class "app-bar__title" ] [ text "eZpZ-dndZ" ]
            ]
        , nav [ class "app-bar__nav" ]
            [ a [ href "/" ] [ text "Encounter" ]
            , a [ href "/me" ] [ text "Me" ]
            , a [ href "/scalar" ] [ text "API" ]
            ]
        ]


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
            , attribute "aria-haspopup" "menu"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            , attribute "aria-label" "Open settings"
            , Attr.title Tooltips.appBarSettings
            , onClick SettingsToggle
            ]
            [ text "⚙" ]
        , if isOpen then
            div
                [ class "app-settings__menu"
                , attribute "role" "menu"
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
            [ themeRadio current Light "Light"
            , themeRadio current Dark "Dark"
            , themeRadio current Auto "Auto"
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
