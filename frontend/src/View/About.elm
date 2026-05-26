module View.About exposing (view)

{-| Static "About eZpZ-dndZ" page. Reachable from the AppBar nav.

Content is hand-curated rather than pulled from a data source —
the page rarely changes and the markup is small enough to read
linearly. Styling lives under `.about-page` in style.css; each
section uses semantic `<section>` + `<h2>` so screen readers can
navigate by heading and so the Accessible theme picks up its
usual heading-size bumps.

@docs view

-}

import Html exposing (Html, a, div, h1, h2, li, p, section, text, ul)
import Html.Attributes exposing (class, href, rel, target)


view : Html msg
view =
    div [ class "workspace workspace--standalone" ]
        [ section [ class "panel panel--standalone about-page" ]
            [ div [ class "panel__body about-page__body" ]
                [ h1 [ class "about-page__title" ] [ text "About eZpZ-dndZ" ]
                , p [ class "about-page__tagline" ]
                    [ text "A free, fast, browser-based combat tracker and monster compendium for fifth-edition Dungeons & Dragons." ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "What it does" ]
                    , ul []
                        [ li [] [ text "Tracks initiative, HP, conditions, death saves, and legendary actions for every creature in a fight." ]
                        , li [] [ text "Ships with the full SRD 5.1 monster compendium and lets you add, edit, group, and roll instances into the queue." ]
                        , li [] [ text "Rolls dice, plays out readied actions, fires timers across rounds, and remembers everything between sessions." ]
                        , li [] [ text "Splits puddings, spawns minions, manages cover, concentration, and the Dodge / Hide / Fly stances." ]
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Anonymous vs. signed-in" ]
                    , p []
                        [ text "Use it without an account — every encounter, custom card layout, dice log, and compendium edit lives in your browser's local storage. Sign in to save those things to the server instead, so you can pick up a fight from a different device or share the compendium with co-DMs at the same table." ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Accessibility" ]
                    , p []
                        [ text "The Accessible theme targets WCAG AAA contrast, scales every glyph up, replaces icon-only buttons with text, and pairs colour signals with shape or symbol. The whole app is keyboard-driveable, honours "
                        , Html.code [] [ text "prefers-reduced-motion" ]
                        , text ", and exposes ARIA labels on every interactive control."
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Source & license" ]
                    , p []
                        [ text "Source-available under PolyForm Strict 1.0.0 — read it, learn from it, run it for your own table. See the "
                        , a
                            [ href "https://github.com/eric-r-inman/ezpz-dndz"
                            , target "_blank"
                            , rel "noopener noreferrer"
                            ]
                            [ text "GitHub repository" ]
                        , text " for the full code and license text."
                        ]
                    ]
                ]
            ]
        ]
