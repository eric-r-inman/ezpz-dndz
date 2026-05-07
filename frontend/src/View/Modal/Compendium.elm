module View.Modal.Compendium exposing (view)

{-| Read-only browser for the creature library. Two-column layout:
filterable + sortable list on the left, full stat block on the
right. The right pane has an action bar with the "Add to
Encounter" handoff plus per-creature edit / duplicate / delete.
-}

import Compendium
import Html exposing (Html, a, button, div, input, label, option, p, span, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, href, id, placeholder, selected, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg
    exposing
        ( CompendiumSort(..)
        , Msg(..)
        )
import Set exposing (Set)
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumDb(..)
        , CompendiumUi
        , PendingAction(..)
        )
import Update.Compendium.Browser
import View.Modal
import View.StatBlock


view : CompendiumUi -> List String -> Html Msg
view ui encounterIds =
    if not ui.open then
        text ""

    else
        View.Modal.view
            { close = CompendiumClose
            , noOp = NoOp
            , title = "📚 Compendium"
            , extraClass = "modal--compendium"
            , body =
                [ filterBar ui
                , bulkBanner ui
                , body ui encounterIds
                ]
            }


{-| Count how many encounter creatures point at the given
compendium id. Used both by the "Added" filter and the
right-pane "[N] in Encounter" readout.
-}
encounterInstancesOf : String -> List String -> Int
encounterInstancesOf compendiumId encounterIds =
    List.foldl
        (\id acc ->
            if id == compendiumId then
                acc + 1

            else
                acc
        )
        0
        encounterIds


bulkBanner : CompendiumUi -> Html Msg
bulkBanner ui =
    case ( ui.pending, ui.bulkError ) of
        ( Just PendingReset, _ ) ->
            confirmBanner
                { message =
                    "Reset to bundled? Every custom creature will be discarded "
                        ++ "and the library returned to the original 5 creatures."
                , confirmLabel = "Reset"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Just (PendingImport _ count), _ ) ->
            confirmBanner
                { message =
                    "Import "
                        ++ String.fromInt count
                        ++ " creatures? This REPLACES the entire current library."
                , confirmLabel = "Replace library"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Just (PendingDelete _ displayName), _ ) ->
            confirmBanner
                { message =
                    "Delete \""
                        ++ displayName
                        ++ "\" from the compendium? This cannot be undone."
                , confirmLabel = "Delete"
                , danger = True
                , busy = ui.bulkBusy
                }

        ( Nothing, Just err ) ->
            div [ class "compendium__bulk-error" ] [ text err ]

        ( Nothing, Nothing ) ->
            text ""


confirmBanner :
    { message : String, confirmLabel : String, danger : Bool, busy : Bool }
    -> Html Msg
confirmBanner cfg =
    div [ class "compendium__bulk-confirm" ]
        [ span [ class "compendium__bulk-confirm-msg" ] [ text cfg.message ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumPendingCancel
            , disabled cfg.busy
            ]
            [ text "Cancel" ]
        , button
            [ class
                (if cfg.danger then
                    "action-btn action-btn--red"

                 else
                    "action-btn action-btn--green"
                )
            , onClick CompendiumPendingConfirm
            , disabled cfg.busy
            ]
            [ text
                (if cfg.busy then
                    "Working…"

                 else
                    cfg.confirmLabel
                )
            ]
        ]


filterBar : CompendiumUi -> Html Msg
filterBar ui =
    div [ class "compendium__filter-bar" ]
        [ input
            [ class "compendium__search"
            , id Update.Compendium.Browser.searchId
            , type_ "search"
            , placeholder "🔍 Search by name, race, source, CR… (press / to focus)"
            , value ui.searchText
            , onInput CompendiumSearchChanged
            , attribute "aria-label" "Search compendium"
            ]
            []
        , div [ class "compendium__kind-filters" ]
            (addedFilter ui.showOnlyAdded
                :: List.map (kindFilter ui.kindFilter)
                    [ Compendium.Player, Compendium.Enemy, Compendium.Npc ]
            )
        , sortPicker ui.sort
        , newButton
        , pasteButton
        , bulkButtons
        ]


{-| Toggle button that narrows the visible list to creatures
already in the encounter. Visually styled like the kind-filter
chips so the row reads as one filter cluster — but distinct
because it filters on encounter membership rather than creature
kind.
-}
addedFilter : Bool -> Html Msg
addedFilter active =
    button
        [ class
            ("compendium__kind-filter compendium__kind-filter--added"
                ++ (if active then
                        " compendium__kind-filter--active"

                    else
                        ""
                   )
            )
        , onClick CompendiumAddedToggle
        , title
            (if active then
                "Showing only creatures with instances in the encounter — click to clear"

             else
                "Show only creatures that have instances in the current encounter"
            )
        , attribute "aria-pressed"
            (if active then
                "true"

             else
                "false"
            )
        ]
        [ text "Added" ]


kindFilter : Set String -> Compendium.CreatureKind -> Html Msg
kindFilter active kind =
    let
        key =
            CompendiumUi.kindToString kind

        isActive =
            -- An empty filter set means "show all kinds"; the chip
            -- appears active in that case so the GM sees the default
            -- isn't filtering anything out.
            Set.isEmpty active || Set.member key active
    in
    button
        [ class
            ("compendium__kind-filter"
                ++ (if isActive then
                        " compendium__kind-filter--active"

                    else
                        ""
                   )
            )
        , onClick (CompendiumKindToggled kind)
        , attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ text (CompendiumUi.creatureKindLabel kind) ]


sortPicker : CompendiumSort -> Html Msg
sortPicker current =
    let
        opt sort label_ =
            option
                [ value (sortToString sort)
                , selected (sort == current)
                ]
                [ text label_ ]
    in
    Html.select
        [ class "compendium__sort"
        , onInput sortFromInput
        , attribute "aria-label" "Sort compendium"
        ]
        [ opt SortName "A–Z"
        , opt SortCr "By CR"
        , opt SortRecency "Newest first"
        ]


sortToString : CompendiumSort -> String
sortToString s =
    case s of
        SortName ->
            "name"

        SortCr ->
            "cr"

        SortRecency ->
            "recency"


sortFromInput : String -> Msg
sortFromInput raw =
    case raw of
        "cr" ->
            CompendiumSortChanged SortCr

        "recency" ->
            CompendiumSortChanged SortRecency

        _ ->
            CompendiumSortChanged SortName


body : CompendiumUi -> List String -> Html Msg
body ui encounterIds =
    case ui.db of
        CompendiumDbLoading ->
            skeleton

        CompendiumDbFailed _ ->
            div [ class "compendium__placeholder compendium__placeholder--error" ]
                [ text "Couldn't load the compendium. Check the server logs." ]

        CompendiumDbLoaded _ ->
            twoColumn ui encounterIds


skeleton : Html Msg
skeleton =
    div [ class "compendium__columns" ]
        [ div [ class "compendium__list" ]
            (List.repeat 8 skeletonRow)
        , div [ class "compendium__detail compendium__detail--skeleton" ]
            [ div [ class "skeleton-block skeleton-block--title" ] []
            , div [ class "skeleton-block" ] []
            , div [ class "skeleton-block" ] []
            , div [ class "skeleton-block skeleton-block--short" ] []
            ]
        ]


skeletonRow : Html Msg
skeletonRow =
    div [ class "compendium__row compendium__row--skeleton" ]
        [ div [ class "skeleton-block skeleton-block--title" ] []
        , div [ class "skeleton-block skeleton-block--short" ] []
        ]


twoColumn : CompendiumUi -> List String -> Html Msg
twoColumn ui encounterIds =
    let
        baseVisible =
            CompendiumUi.compendiumVisible ui

        -- "Added" filter narrows the visible list to only
        -- creatures that already have at least one instance in
        -- the encounter.  When off, no further filtering.
        visible =
            if ui.showOnlyAdded then
                List.filter
                    (\c -> List.member c.id encounterIds)
                    baseVisible

            else
                baseVisible

        totalCount =
            case ui.db of
                CompendiumDbLoaded db ->
                    Compendium.count db

                _ ->
                    0
    in
    div [ class "compendium__columns" ]
        [ list ui totalCount visible encounterIds
        , detail ui visible encounterIds
        ]


list :
    CompendiumUi
    -> Int
    -> List Compendium.Creature
    -> List String
    -> Html Msg
list ui totalCount visible encounterIds =
    if List.isEmpty visible then
        if totalCount == 0 then
            div [ class "compendium__list compendium__list--empty" ]
                [ p [] [ text "Your compendium is empty." ]
                , p [ class "compendium__empty-hint" ]
                    [ text "Try "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumEditNew
                        ]
                        [ text "creating one" ]
                    , text ", "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumPasteOpen
                        ]
                        [ text "pasting a stat block" ]
                    , text ", or "
                    , button
                        [ class "compendium__empty-link"
                        , onClick CompendiumImportClick
                        ]
                        [ text "importing a JSON file" ]
                    , text "."
                    ]
                ]

        else
            div [ class "compendium__list compendium__list--empty" ]
                [ p [] [ text "No creatures match the current filters." ]
                , p [ class "compendium__empty-hint" ]
                    [ text (String.fromInt totalCount ++ " creatures hidden — try clearing the search or kind filters.") ]
                ]

    else
        div [ class "compendium__list" ]
            (List.map (listItem ui.selectedId encounterIds) visible)


listItem : Maybe String -> List String -> Compendium.Creature -> Html Msg
listItem selectedId encounterIds c =
    let
        isSelected =
            selectedId == Just c.id

        inEncounter =
            List.member c.id encounterIds

        rowClass =
            "compendium__row"
                ++ (if isSelected then
                        " compendium__row--selected"

                    else
                        ""
                   )
                ++ (" compendium__row--" ++ CompendiumUi.kindToString c.kind)
    in
    button
        [ class rowClass
        , onClick (CompendiumSelect c.id)
        , attribute "aria-pressed"
            (if isSelected then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "compendium__row-name" ]
            [ text c.name
            , if inEncounter then
                span
                    [ class "compendium__row-in-enc"
                    , title "This creature has at least one instance in the encounter"
                    , attribute "aria-label" "in encounter"
                    ]
                    []

              else
                text ""
            ]
        , span [ class "compendium__row-meta" ]
            [ text (rowMetaLine c) ]
        ]


rowMetaLine : Compendium.Creature -> String
rowMetaLine c =
    let
        bits =
            List.filter (not << String.isEmpty)
                [ CompendiumUi.creatureKindLabel c.kind
                , c.race
                , "AC " ++ String.fromInt c.armorClass
                , "HP " ++ String.fromInt c.maxHp
                , crLabel c.challengeRating
                ]
    in
    String.join " · " bits


crLabel : String -> String
crLabel cr =
    if String.isEmpty cr then
        ""

    else
        "CR " ++ cr


detail : CompendiumUi -> List Compendium.Creature -> List String -> Html Msg
detail ui visible encounterIds =
    let
        chosen =
            ui.selectedId
                |> Maybe.andThen (\id -> List.filter (\c -> c.id == id) visible |> List.head)
    in
    case chosen of
        Just creature ->
            div [ class "compendium__detail" ]
                [ actionBar creature
                    (encounterInstancesOf creature.id encounterIds)
                , View.StatBlock.view RollFromStatBlock AbilitySaveOpen creature
                ]

        Nothing ->
            div [ class "compendium__detail compendium__detail--empty" ]
                [ text "Select a creature on the left to see its stat block." ]


{-| Right-pane action bar for the selected creature. Replaces
the old Count input with a read-only "[N] in Encounter" badge so
the GM can see at a glance how many instances of this creature
are already in the queue. Each click of "Add to Encounter"
spawns one fresh instance; the modal stays open across adds.
-}
actionBar : Compendium.Creature -> Int -> Html Msg
actionBar creature inEncounter =
    let
        badgeClass =
            if inEncounter > 0 then
                "compendium__in-encounter compendium__in-encounter--present"

            else
                "compendium__in-encounter"
    in
    div [ class "compendium__action-bar" ]
        [ span
            [ class badgeClass
            , title "Instances of this creature already in the encounter"
            ]
            [ text (String.fromInt inEncounter ++ " in Encounter") ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumAddToQueue creature.id)
            , title "Roll initiative and add to the encounter queue"
            ]
            [ text "➕ Add to Encounter" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditExisting
            , title "Edit this creature"
            ]
            [ text "✏️ Edit" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditDuplicate
            , title "Duplicate this creature in the compendium"
            ]
            [ text "📋 Duplicate" ]
        , button
            [ class "action-btn action-btn--red compendium__delete-btn"
            , onClick (CompendiumDeleteFromBrowser creature.id creature.name)
            , title "Delete this creature from the compendium"
            , attribute "aria-label" "Delete creature"
            ]
            [ text "🗑" ]
        ]


newButton : Html Msg
newButton =
    button
        [ class "action-btn action-btn--green compendium__new-btn"
        , onClick CompendiumEditNew
        , title "Create a new creature from scratch"
        ]
        [ text "➕ New Creature" ]


pasteButton : Html Msg
pasteButton =
    button
        [ class "action-btn action-btn--blue"
        , onClick CompendiumPasteOpen
        , title "Paste a 5e stat block to import"
        ]
        [ text "📋 Paste Stat Block" ]


{-| Cluster of bulk operations on the right edge of the filter
bar: Import / Export / Reset to Bundled. Export is a plain anchor
with `download` so the browser handles it natively (no Cmd needed).
Import + Reset both go through the destructive-confirm banner
before firing.
-}
bulkButtons : Html Msg
bulkButtons =
    div [ class "compendium__bulk-cluster" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumImportClick
            , title "Import a creature library JSON file (replaces the current library)"
            ]
            [ text "📥 Import" ]
        , a
            [ class "action-btn action-btn--blue"
            , href "/api/compendium/export"
            , attribute "download" "compendium.json"
            , title "Download the entire library as JSON"
            ]
            [ text "📤 Export" ]
        , button
            [ class "action-btn action-btn--red"
            , onClick CompendiumResetClick
            , title "Reset the library to the bundled creature set"
            ]
            [ text "↺ Reset" ]
        ]
