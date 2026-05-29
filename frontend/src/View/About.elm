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
                [ h1 [ class "about-page__title" ] [ text "eZpZ-dndZ" ]
                , p [ class "about-page__tagline" ]
                    [ text "...is a free browser-based combat tracker and monster compendium. It is based on encounter rules in the DnD System Reference Document 5.2.1, May 2025." ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "What it does" ]
                    , ul []
                        [ li [] [ text "Tracks initiative, HP, conditions, combat turns, and everything else a GM needs to run DnD 2025 combat." ]
                        , li [] [ text "Contains all SRD 5.2.1 monster stat blocks, and lets you add, edit, group, and roll creature instances into the combat queue." ]
                        , li [] [ text "Rolls dice, sets timers, and much more." ]
                        , li [] [ text "Remembers your encounters between sessions." ]
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Data persistence" ]
                    , p []
                        [ text "Anonymous users: your encounters, creature states, dice logs, and compendium data live in your browser's local storage (if your browser allows it), so your data can persist between sessions. You can also save your encounters and compendium to your local device (recommended), which will create a save file that can you can load into the app. Signed-in users: save your encounters and compendiums to the eZpZ-dndZ cloud, keeping your data safe and ready to pick up again in the next session." ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Beta Version" ]
                    , p []
                        [ text "eZpZ-dndZ is in beta development; use at your own risk. Your saved data could be wiped or rendered unusable without warning. Help me improve eZpZ-dndZ by providing feedback about your experience using the app. I welcome bug reports and ideas for improvement."
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Source & license" ]
                    , p []
                        [ text "Do not enter or upload copyrighted content that you are not licensed to use. If you'd like to run your own local version of eZpZ-dndZ, the full source is available under PolyForm Strict 1.0.0, where applicable. See the "
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
