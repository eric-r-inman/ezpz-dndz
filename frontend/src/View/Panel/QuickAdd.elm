module View.Panel.QuickAdd exposing (view)

{-| Quick Add panel — one-click "drop a creature into the
encounter" picker.

Top: a single sort-toggle button (Alphabetical ↔ Challenge
Rating). Bottom: a scrollable list of every compendium creature
with `<name> ··· <CR>`. Clicking any row dispatches
`QuickAddPick id` and closes the panel.

The compendium's full-featured browser (search, filter, edit,
count) lives at `View.Page.Compendium`; this is the
lightweight sibling for the common case.

Renders nothing when the panel isn't open.

-}

import Compendium
import Html exposing (Html, button, div, input, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.QuickAdd as QuickAddUi exposing (QuickAddSort(..), QuickAddUi)
import View.Panel
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceQuickAdd ui) ->
            let
                title =
                    case ui.replaceTarget of
                        Just oldName ->
                            "Replace " ++ oldName ++ " with…"

                        Nothing ->
                            "Quick Add"
            in
            View.Panel.view
                { close = QuickAddClose
                , title = title
                , titleLead = Nothing
                , subtitle = Nothing
                , extraClass = "panel-drawer--quick-add"
                , body =
                    [ controlsRow ui
                    , listSection ui model
                    ]
                }

        _ ->
            text ""


{-| Top row of the Quick Add panel: name-search input on the
left, sort toggle on the right. The search input filters the
list in real time via `Compendium.search`, which already powers
the full Compendium browser, so the matching surface is
consistent (name / race / source / CR).
-}
controlsRow : QuickAddUi -> Html Msg
controlsRow ui =
    let
        ( label, tooltip ) =
            case ui.sort of
                SortAlpha ->
                    ( "Sort: A → Z", Tooltips.quickAddSortToCr )

                SortByCr ->
                    ( "Sort: CR ↑", Tooltips.quickAddSortToAlpha )
    in
    div [ class "quick-add__controls-row" ]
        [ input
            [ class "quick-add__search"
            , type_ "search"
            , placeholder "🔍 Search…"
            , value ui.searchText
            , onInput QuickAddSearchChanged
            , attribute "aria-label" "Filter Quick Add by name"
            ]
            []
        , button
            [ class "action-btn action-btn--blue quick-add__sort-toggle"
            , onClick QuickAddSortToggle
            , Tooltips.attr tooltip
            ]
            [ text label ]
        ]


listSection : QuickAddUi -> Model -> Html Msg
listSection ui model =
    let
        ( creatureRowsHtml, trailingMessage ) =
            case model.compendium.db of
                CompendiumDbLoading ->
                    ( [], Just "Loading the compendium…" )

                CompendiumDbFailed _ ->
                    ( [], Just "Couldn't load the compendium." )

                CompendiumDbLoaded db ->
                    let
                        filteredDb =
                            Compendium.search ui.searchText db

                        sortedDb =
                            case ui.sort of
                                SortAlpha ->
                                    Compendium.sortByName filteredDb

                                SortByCr ->
                                    Compendium.sortByCr filteredDb

                        creatures =
                            Compendium.toList sortedDb

                        searchActive =
                            not (String.isEmpty (String.trim ui.searchText))
                    in
                    if List.isEmpty creatures then
                        if searchActive then
                            ( [], Just ("No matches for \"" ++ String.trim ui.searchText ++ "\".") )

                        else
                            ( [], Just "Your compendium is empty." )

                    else
                        ( List.map row creatures, Nothing )

        trailingHtml =
            case trailingMessage of
                Just msg ->
                    [ empty msg ]

                Nothing ->
                    []
    in
    -- Placeholder row is always the first <li> in the list,
    -- regardless of compendium state.  When the creature list
    -- is empty (loading / failed / search-no-match / empty
    -- compendium) the empty-state message follows the list so
    -- the placeholder row stays reachable.
    div []
        (ul [ class "quick-add__list" ]
            (placeholderRow :: creatureRowsHtml)
            :: trailingHtml
        )


{-| Standing "Placeholder" entry at the top of the Quick Add
list. Clicking it appends a stub combatant via the same rules
as the queue-bottom "+" button (Initiative 0, HP 1/1, AC 10,
`Placeholder N` name). Styled distinctly (italic + sticky to
the top of the scroll view) so it reads as an action, not a
compendium creature.
-}
placeholderRow : Html Msg
placeholderRow =
    li
        [ class "quick-add__row quick-add__row--placeholder"
        , onClick QuickAddPickPlaceholder
        , Tooltips.attr "Add a Placeholder N stub (Initiative 0, HP 1/1, AC 10)"
        , attribute "role" "button"
        , attribute "tabindex" "0"
        , attribute "aria-label" "Add placeholder"
        ]
        [ span [ class "quick-add__name" ] [ text "Placeholder" ]
        , span [ class "quick-add__cr" ] [ text "+" ]
        ]


row : Compendium.Creature -> Html Msg
row c =
    li
        [ class "quick-add__row"
        , onClick (QuickAddPick c.id)
        , Tooltips.attr (Tooltips.quickAddCreatureRow c.name)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ span [ class "quick-add__name" ] [ text c.name ]
        , span [ class "quick-add__cr" ] [ text (crLabel c.challengeRating) ]
        ]


{-| Render the CR string with a "CR" prefix so a row reads
"Goblin CR 1/4" rather than "Goblin 1/4". Empty CR (rare)
falls back to a muted dash so the column stays aligned.
-}
crLabel : String -> String
crLabel raw =
    if String.isEmpty (String.trim raw) then
        "—"

    else
        "CR " ++ raw


empty : String -> Html Msg
empty message =
    p [ class "quick-add__empty" ] [ text message ]
