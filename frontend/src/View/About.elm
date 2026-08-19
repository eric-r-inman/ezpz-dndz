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

import Html exposing (Html, a, div, h1, h2, h3, li, p, section, text, ul)
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
                        , li [] [ text "Rolls dice, sets timers, tracks difficulty, trawls treasure tables." ]
                        , li [] [ text "Remembers your encounters between sessions." ]
                        , li [] [ text "And much more!" ]
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Data persistence" ]
                    , p []
                        [ text "Your encounters, creature states, dice logs, and compendium data live in your browser's local storage (if your browser allows it), so your data can persist between sessions. You can also save your encounters and compendium to your local device, or our server for signed-in users, which will create a save file that can you can load anytime." ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Beta Version" ]
                    , p []
                        [ text "eZpZ-dndZ is in beta development; use at your own risk. Your saved data could be wiped or rendered unusable without warning. Help me improve eZpZ-dndZ by providing feedback about your experience using the service. I welcome bug reports and ideas for improvement."
                        ]
                    ]
                , section [ class "about-page__section" ]
                    [ h2 [] [ text "Source & license" ]
                    , p []
                        [ text "This website is a personal project based on SRD 5.2.1 rules. I have no relationship with WoTC or any associated corporation, and I make no claims to any of their intellectual property. Do not use this app to store or upload copyrighted content that you are not licensed to use in this way. If you'd like to run your own local version of eZpZ-dndZ, the full source is available under PolyForm Strict 1.0.0 where applicable. See the "
                        , a
                            [ href "https://github.com/eric-r-inman/ezpz-dndz"
                            , target "_blank"
                            , rel "noopener noreferrer"
                            ]
                            [ text "GitHub repository" ]
                        , text " for the full code. The app is in early beta testing, and may be unreliable at this stage."
                        ]
                    ]
                , betaFeaturesSection
                , upcomingSection
                ]
            ]
        ]


upcomingSection : Html msg
upcomingSection =
    section [ class "about-page__section" ]
        [ h2 [] [ text "Next major features/updates" ]
        , ul []
            [ li [] [ text "Hotkey mapping for quick navigation and most-used buttons." ]
            , li [] [ text "\"Hide\" controls for less-used features and buttons." ]
            , li [] [ text "UI re-do (not a huge priority while I'm still nailing down the features)." ]
            ]
        ]


betaFeaturesSection : Html msg
betaFeaturesSection =
    section [ class "about-page__section" ]
        [ h2 [] [ text "Beta features" ]
        , p []
            [ text "The following features are under development, but working. Results may change as development progresses. Features are SRD 5.2.1 compliant." ]
        , h3 [] [ text "Encounter Queue" ]
        , p []
            [ text "Tracks the round, turn, and important stats for all creatures in the encounter queue. Populate with creatures from the Compendium, or add placeholders (for example, to represent players' positions). Controls are in the upper right Encounter Controls pane. Your encounters can be saved/loaded to/from your local device or the eZpZ-dndZ server." ]
        , h3 [] [ text "Creature Cards" ]
        , p []
            [ text "Information block for creatures in the encounter queue. Easily manage initiative order, hit points, conditions/effects, statuses (such as cover), legendary actions, timers, notes, and more. Hover-text describes what each clickable element does." ]
        , h3 [] [ text "Treasure Roller" ]
        , p []
            [ text "Roll treasure for enemies in the active encounter queue. Optional controls for tweaking the results to your liking: adjust \"Tune your rolls\" first, but for more control \"Edit treasure tables\". Opened via the Treasure button in the status bar of the encounter queue." ]
        , p []
            [ text "\"Boss\" rolls work well for enemies with true lair hoards. \"Individual\" rolls make sense for enemies with pockets & pouches (for example, goblins)." ]
        , h3 [] [ text "Dice Roller" ]
        , p []
            [ text "The \"Roll\" button in the Encounter Controls pane title bar opens the standalone dice roller, which accepts formula or manual values. The dice roller also serves as an auto-roller for stat block rolls (ability checks, saving throws, actions). It's wired into creature cards too, for initiative rolls, healing, damage, and falling damage. The last 4 roll results are shown next to the Roll button, and the last 30 rolls are recorded in the dice roller window." ]
        , h3 [] [ text "Stat Block" ]
        , p []
            [ text "The Compendium panel on the Encounter page shows the pinned stat block of the creature you select by clicking its name in a creature card, or by selecting it in the Compendium (see Compendium below). Abilities, saving throws, and actions are clickable for generating an auto-roll using the dice roller." ]
        , h3 [] [ text "Compendium" ]
        , p []
            [ text "The Compendium contains the database of creatures, creature groups, and lore groupings used to build encounters. Open the Compendium by clicking \"Open\" in the lower right Compendium pane." ]
        , p []
            [ text "The Compendium comes bundled with all SRD creatures, which cannot be edited or deleted. You'll need to duplicate a bundled creature, import a creature, or create a creature, in order to edit that creature." ]
        , p [] [ text "Notable Compendium features include:" ]
        , ul []
            [ li [] [ text "A parser for importing a pasted-in stat block (tested with raw cut-&-pasted stat blocks from popular websites; results may vary)" ]
            , li [] [ text "Import/export your Compendium to your local device or the eZpZ-dndZ server" ]
            , li [] [ text "Creature groups for easy adding to the encounter queue later" ]
            , li [] [ text "Lore groupings for the random encounter generator" ]
            , li [] [ text "Sorting options" ]
            ]
        , h3 [] [ text "Random Encounter" ]
        , p []
            [ text "Tunable encounter generator, using creatures from the Compendium. Opened via the Random Encounter button in the lower right Compendium pane." ]
        , p []
            [ text "Setting any of the Random Encounter constraints will drastically reduce the types of creatures that get generated; broaden your parameters if you're not seeing as much creature variety as you're hoping for." ]
        , p []
            [ text "The Lore grouping toggle pulls from a table that makes certain creatures more likely to spawn together. You can view the bundled Lore groupings, or create/edit your own (sign in first), via the Compendium." ]
        , h3 [] [ text "Difficulty Calculator" ]
        , p []
            [ text "Uses SRD guidelines to calculate the difficulty of the current encounter. Opened via the Difficulty button in the status bar of the encounter queue." ]
        ]
