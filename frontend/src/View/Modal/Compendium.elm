module View.Modal.Compendium exposing (pageBody, view)

{-| Read-only browser for the creature library. Two-column layout:
filterable + sortable list on the left, full stat block on the
right. The right pane has an action bar with the "Add to
Encounter" handoff plus per-creature edit / duplicate / delete.
-}

import Auth
import Compendium
import Compendium.Group
import Dict
import Encounter.RandomEncounter.Lore as Lore
import Html exposing (Html, button, div, h3, input, label, option, p, span, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, id, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as Decode
import Msg
    exposing
        ( CompendiumBulkMenu(..)
        , CompendiumSort(..)
        , Msg(..)
        , SaveDestination(..)
        )
import Set exposing (Set)
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumDb(..)
        , CompendiumUi
        , PendingAction(..)
        )
import Ui.ModalChrome exposing (ModalChrome)
import Update.Compendium.Browser
import View.AuthGate as AuthGate
import View.Modal
import View.StatBlock
import View.Tooltips as Tooltips


view : ModalChrome -> Auth.AuthState -> CompendiumUi -> List Lore.Group -> List String -> Html Msg
view chrome auth ui userLoreGroups encounterIds =
    if not ui.open then
        text ""

    else
        View.Modal.viewWithExtras
            { close = CompendiumClose
            , noOp = NoOp
            , title = "📚 Compendium"
            , extraClass = "modal--compendium"
            , chrome = chrome
            , body = pageBody auth ui userLoreGroups encounterIds
            }
            [ savedAsLabel ui.savedAs
            , button
                [ class "modal__open-in-tab"
                , Attr.type_ "button"
                , onClick CompendiumOpenInTab
                , Tooltips.attr Tooltips.compendiumOpenInTab
                , attribute "aria-label" "Open compendium in a new tab"
                ]
                [ text "↗" ]
            ]


{-| Title-bar tag identifying which compendium snapshot is in
view. `Nothing` means "the bundled SRD default plus whatever
this user has authored locally" — labelled with the project's
own name so the GM has an immediate cue that they're not
editing a named save.
-}
savedAsLabel : Maybe String -> Html Msg
savedAsLabel savedAs =
    let
        name =
            savedAs |> Maybe.withDefault "eZpZ-dndZ default"
    in
    span
        [ class "modal__title-meta" ]
        [ text ("From file: " ++ name) ]


{-| The compendium's body content — filter bar, actions bar,
bulk-confirm banner, and the main list/stat-block pane.
Exposed so [`View.Page.Compendium`](View-Page-Compendium) can
render the same UI as a full standalone page without the
modal chrome wrapper.
-}
pageBody : Auth.AuthState -> CompendiumUi -> List Lore.Group -> List String -> List (Html Msg)
pageBody auth ui userLoreGroups encounterIds =
    [ filterBar ui
    , actionsBar auth ui
    , bulkBanner ui
    , body auth ui userLoreGroups encounterIds
    ]


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
                , extra = Nothing
                }

        ( Just (PendingImport _ groups count), _ ) ->
            let
                groupNote =
                    case List.length groups of
                        0 ->
                            ""

                        n ->
                            " (plus "
                                ++ String.fromInt n
                                ++ " group"
                                ++ (if n == 1 then
                                        ""

                                    else
                                        "s"
                                   )
                                ++ ")"
            in
            confirmBanner
                { message =
                    "Import "
                        ++ String.fromInt count
                        ++ " creatures"
                        ++ groupNote
                        ++ "? This REPLACES the entire current library."
                , confirmLabel = "Replace library"
                , danger = True
                , busy = ui.bulkBusy
                , extra = Nothing
                }

        ( Just (PendingDelete _ displayName), _ ) ->
            let
                selectedCount =
                    Set.size ui.selectedIds

                -- "Delete Selected" only appears when 2+ creatures
                -- are checkbox-selected.  A single selection has the
                -- same effect as the regular Delete button, so we
                -- skip it to keep the banner uncluttered.
                extra =
                    if selectedCount > 1 then
                        Just
                            { label =
                                "Delete Selected ("
                                    ++ String.fromInt selectedCount
                                    ++ ")"
                            , msg = CompendiumDeleteSelected
                            , tooltip = Tooltips.compendiumDeleteSelected
                            }

                    else
                        Nothing
            in
            confirmBanner
                { message =
                    "Delete \""
                        ++ displayName
                        ++ "\" from the compendium? This cannot be undone."
                , confirmLabel = "Delete"
                , danger = True
                , busy = ui.bulkBusy
                , extra = extra
                }

        ( Nothing, Just err ) ->
            -- Pop-up notice with an OK button.  `CompendiumPendingCancel`
            -- already clears both `pending` and `bulkError`, so we
            -- reuse it as the dismiss handler.  The button takes
            -- the browser's default Space/Enter activation, so no
            -- extra keydown wiring is needed.
            div [ class "compendium__bulk-alert" ]
                [ p [ class "compendium__bulk-alert-msg" ] [ text err ]
                , button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumPendingCancel
                    ]
                    [ text "OK" ]
                ]

        ( Nothing, Nothing ) ->
            text ""


confirmBanner :
    { message : String
    , confirmLabel : String
    , danger : Bool
    , busy : Bool
    , extra : Maybe { label : String, msg : Msg, tooltip : String }
    }
    -> Html Msg
confirmBanner cfg =
    let
        extraButton =
            case cfg.extra of
                Just e ->
                    button
                        [ class "action-btn action-btn--red"
                        , onClick e.msg
                        , disabled cfg.busy
                        , Tooltips.attr e.tooltip
                        ]
                        [ text e.label ]

                Nothing ->
                    text ""
    in
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
        , extraButton
        ]


filterBar : CompendiumUi -> Html Msg
filterBar ui =
    div [ class "compendium__filter-bar" ]
        [ input
            [ class "compendium__search"
            , id Update.Compendium.Browser.searchId
            , type_ "search"
            , placeholder "Search by name, type, etc."
            , value ui.searchText
            , onInput CompendiumSearchChanged
            , attribute "aria-label" "Search compendium"
            ]
            []
        , div [ class "compendium__kind-filters" ]
            (addedFilter ui.showOnlyAdded
                :: List.map (kindFilter ui.kindFilter)
                    [ Compendium.Player, Compendium.Enemy, Compendium.Npc ]
                ++ [ groupsFilter ui.showGroups ]
            )
        , sortPicker ui.sort
        , tagPicker ui
        ]


{-| Second-row toolbar. Creation affordances (New Creature,
Paste Stat Block, Create Group, optional Create Group w/Selected)
sit on the left; the bulk-action cluster (Import / Export / Reset
/ Clear) stays on the right.

The Create Group buttons are wired to placeholder toasts in this
first pass while the Group store + modal land in follow-up
commits — see [feature: Group UI placeholders, follow-ups for
store + modal].

-}
actionsBar : Auth.AuthState -> CompendiumUi -> Html Msg
actionsBar auth ui =
    div [ class "compendium__actions-bar" ]
        [ div [ class "compendium__create-cluster" ]
            [ newButton
            , pasteButton
            , createGroupButton
            , if Set.isEmpty ui.selectedIds then
                text ""

              else
                createGroupFromSelectedButton ui
            ]
        , bulkButtons auth ui
        ]


createGroupButton : Html Msg
createGroupButton =
    button
        [ class "action-btn action-btn--condition"
        , onClick CompendiumGroupCreate
        , Tooltips.attr Tooltips.compendiumCreateGroup
        ]
        [ text "👥 Create Group" ]


createGroupFromSelectedButton : CompendiumUi -> Html Msg
createGroupFromSelectedButton ui =
    button
        [ class "action-btn action-btn--condition"
        , onClick CompendiumGroupCreateFromSelected
        , Tooltips.attr Tooltips.compendiumCreateGroupFromSelected
        ]
        [ text
            ("👥 Create Group w/Selected ("
                ++ String.fromInt (Set.size ui.selectedIds)
                ++ ")"
            )
        ]


{-| Show / hide groups chip — sits on the right of the kind
filters. Styled like the kind-filter chips so the row reads
as one filter cluster, but distinct because it toggles a
different axis (group visibility) rather than a creature kind.
-}
groupsFilter : Bool -> Html Msg
groupsFilter active =
    button
        [ class
            ("compendium__kind-filter compendium__kind-filter--groups"
                ++ (if active then
                        " compendium__kind-filter--active"

                    else
                        ""
                   )
            )
        , onClick CompendiumGroupsToggle
        , Tooltips.attr
            (if active then
                Tooltips.compendiumGroupsHide

             else
                Tooltips.compendiumGroupsShow
            )
        , attribute "aria-pressed"
            (if active then
                "true"

             else
                "false"
            )
        ]
        [ text "Groups" ]


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
        , Tooltips.attr
            (if active then
                Tooltips.compendiumAddedFilterOn

             else
                Tooltips.compendiumAddedFilterOff
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


{-| "Tag" filter dropdown to the right of A-Z. Two optgroups —
the full Habitat list first, then whatever user-authored tags
are in the loaded compendium. The user-tag optgroup is omitted
entirely when no creature carries a tag, which is the visible
expression of the "no separate tag DB" invariant.

Pairs with a × clear button that only appears when a filter is
active. The dropdown's first option ("Tag") would technically
clear the filter on its own, but it doesn't read as a clear
affordance — the explicit × is the discoverable path.

-}
tagPicker : CompendiumUi -> Html Msg
tagPicker ui =
    let
        currentWire =
            ui.tagFilter
                |> Maybe.map CompendiumUi.tagFilterToWire
                |> Maybe.withDefault ""

        opt wire label_ =
            option
                [ value wire, selected (wire == currentWire) ]
                [ text label_ ]

        habitatOpt h =
            opt
                (CompendiumUi.tagFilterToWire (CompendiumUi.TagFilterHabitat h))
                (Compendium.habitatLabel h)

        tagOpt t =
            opt
                (CompendiumUi.tagFilterToWire (CompendiumUi.TagFilterTag t))
                t

        userTags =
            CompendiumUi.userTagsInDb ui

        userTagsGroup =
            if List.isEmpty userTags then
                []

            else
                [ Html.optgroup [ attribute "label" "Tags" ]
                    (List.map tagOpt userTags)
                ]

        select_ =
            Html.select
                [ class "compendium__tag-filter"
                , onInput CompendiumTagFilterChanged
                , attribute "aria-label" "Filter compendium by tag"
                ]
                (opt "" "Tag"
                    :: Html.optgroup [ attribute "label" "Habitats" ]
                        (List.map habitatOpt Compendium.allHabitats)
                    :: userTagsGroup
                )

        clearButton =
            case ui.tagFilter of
                Just _ ->
                    [ button
                        [ class "compendium__tag-filter-clear"
                        , type_ "button"
                        , onClick (CompendiumTagFilterChanged "")
                        , Tooltips.attr Tooltips.compendiumClearTagFilter
                        , attribute "aria-label" Tooltips.compendiumClearTagFilter
                        ]
                        [ text "×" ]
                    ]

                Nothing ->
                    []
    in
    div [ class "compendium__tag-filter-group" ]
        (select_ :: clearButton)


body : Auth.AuthState -> CompendiumUi -> List Lore.Group -> List String -> Html Msg
body auth ui userLoreGroups encounterIds =
    case ui.db of
        CompendiumDbLoading ->
            skeleton

        CompendiumDbFailed _ ->
            div [ class "compendium__placeholder compendium__placeholder--error" ]
                [ text "Couldn't load the compendium. Check the server logs." ]

        CompendiumDbLoaded _ ->
            twoColumn auth ui userLoreGroups encounterIds


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


twoColumn : Auth.AuthState -> CompendiumUi -> List Lore.Group -> List String -> Html Msg
twoColumn auth ui userLoreGroups encounterIds =
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
        [ list auth ui totalCount visible userLoreGroups encounterIds ui.selectedIds
        , detail auth ui visible userLoreGroups encounterIds
        ]


list :
    Auth.AuthState
    -> CompendiumUi
    -> Int
    -> List Compendium.Creature
    -> List Lore.Group
    -> List String
    -> Set String
    -> Html Msg
list auth ui totalCount visible userLoreGroups encounterIds selectedIds =
    let
        groups =
            CompendiumUi.visibleGroups ui

        loreRows =
            loreSection auth ui userLoreGroups

        groupRows =
            List.concatMap (groupListItem ui) groups

        creatureRows =
            List.map (listItem ui.selectedId selectedIds encounterIds) visible
    in
    if List.isEmpty visible && List.isEmpty groups then
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
            (div [ class "compendium__lore-pane" ] loreRows
                :: groupRows
                ++ creatureRows
            )


{-| Render a group as a header row + (optional) expansion of its
entry rows. Returns a list because a single group can expand
into multiple rendered rows. Groups don't have bulk-selection
checkboxes — the GM operates on the group as a whole.

When the header is expanded, the child rows render the
underlying creature names + per-entry settings (count, minion
type) read-only. The GM can't bulk-select or pin those rows;
to change the group's contents they re-open the edit modal.

-}
groupListItem : CompendiumUi -> Compendium.Group.Group -> List (Html Msg)
groupListItem ui group =
    let
        isExpanded =
            Set.member group.id ui.expandedGroupIds

        isSelected =
            ui.selectedGroupId == Just group.id

        headerClass =
            "compendium__row compendium__row--group"
                ++ (if isSelected then
                        " compendium__row--selected"

                    else
                        ""
                   )

        totalCount =
            Compendium.Group.totalCreatureCount group

        header =
            div
                [ class headerClass
                , onClick (CompendiumGroupSelect group.id)
                , attribute "role" "button"
                , attribute "tabindex" "0"
                ]
                [ button
                    [ class "compendium__group-disclosure"
                    , onClickStopPropagation (CompendiumGroupExpandToggle group.id)
                    , attribute "aria-expanded"
                        (if isExpanded then
                            "true"

                         else
                            "false"
                        )
                    , attribute "aria-label" "Toggle group entries"
                    ]
                    [ text
                        (if isExpanded then
                            "▾"

                         else
                            "▸"
                        )
                    ]
                , div [ class "compendium__row-text" ]
                    [ span [ class "compendium__row-name" ]
                        [ text ("👥 " ++ group.name) ]
                    , span [ class "compendium__row-meta" ]
                        [ text
                            (String.fromInt totalCount
                                ++ " creature"
                                ++ (if totalCount == 1 then
                                        ""

                                    else
                                        "s"
                                   )
                                ++ " · "
                                ++ Compendium.Group.initiativeModeLabel
                                    group.initiativeMode
                            )
                        ]
                    ]
                ]

        creatureNameById creatureId =
            case ui.db of
                CompendiumDbLoaded db ->
                    Compendium.find creatureId db
                        |> Maybe.map .name
                        |> Maybe.withDefault "Unknown creature"

                _ ->
                    "Unknown creature"

        -- Apply the global filters + sort to the group's
        -- entries so the expanded view mirrors what the GM sees
        -- in the surrounding list.  Search text, kind filter,
        -- and tag filter all narrow which entries appear; sort
        -- decides their order.  Entries whose `creatureId` doesn't
        -- resolve in the loaded DB are dropped from the visible
        -- list (the GM can't usefully act on them anyway).
        visibleEntries =
            case ui.db of
                CompendiumDbLoaded db ->
                    filterAndSortGroupEntries ui db group.entries

                _ ->
                    group.entries

        entryRow entry =
            div [ class "compendium__row compendium__row--group-entry" ]
                [ div [ class "compendium__row-text" ]
                    [ span [ class "compendium__row-name" ]
                        [ text
                            (String.fromInt entry.count
                                ++ " × "
                                ++ creatureNameById entry.creatureId
                            )
                        ]
                    , case entry.minionType of
                        Compendium.Group.MinionNone ->
                            text ""

                        other ->
                            span [ class "compendium__row-meta" ]
                                [ text (Compendium.Group.minionTypeLabel other) ]
                    ]
                ]
    in
    if isExpanded then
        header :: List.map entryRow visibleEntries

    else
        [ header ]


{-| Apply the compendium browser's filters + sort to one group's
entries. Pipeline mirrors `CompendiumUi.compendiumVisible`: resolve
each entry to its underlying creature, drop entries whose creature
is missing from the DB, then narrow the resolved creatures through
the same `Compendium.search` / `filterByKind` / habitat-or-tag
filter stack used by the global list, and finally sort. Returns
the original entries (in DB-narrowed order) so the rendered row
keeps its `count` / `minionType` annotations.
-}
filterAndSortGroupEntries : CompendiumUi -> Compendium.Db -> List Compendium.Group.GroupEntry -> List Compendium.Group.GroupEntry
filterAndSortGroupEntries ui db entries =
    let
        -- Resolve each entry to (entry, creature) once so the
        -- filter + sort passes can read both halves without
        -- repeating the DB lookup.
        resolved =
            List.filterMap
                (\e ->
                    Compendium.find e.creatureId db
                        |> Maybe.map (\c -> ( e, c ))
                )
                entries

        kinds =
            CompendiumUi.kindFilterAsList ui.kindFilter

        passesKind c =
            List.isEmpty kinds || List.member c.kind kinds

        passesTagFilter c =
            case ui.tagFilter of
                Nothing ->
                    True

                Just (CompendiumUi.TagFilterHabitat h) ->
                    List.member h c.habitats

                Just (CompendiumUi.TagFilterTag t) ->
                    List.member t c.tags

        passesSearch c =
            -- `Compendium.search` is the canonical matcher; build a
            -- single-element Db so the same name / race / source /
            -- CR matching applies here as in the global list.
            Compendium.search ui.searchText (Compendium.fromList [ c ])
                |> Compendium.toList
                |> List.isEmpty
                |> not

        kept =
            List.filter
                (\( _, c ) ->
                    passesKind c
                        && passesTagFilter c
                        && passesSearch c
                )
                resolved
    in
    case ui.sort of
        SortName ->
            kept
                |> List.sortBy (\( _, c ) -> String.toLower c.name)
                |> List.map Tuple.first

        SortCr ->
            kept
                |> List.sortBy (\( _, c ) -> Compendium.crToFloat c.challengeRating)
                |> List.map Tuple.first

        SortRecency ->
            kept
                |> List.sortBy (\( _, c ) -> -c.createdAt)
                |> List.map Tuple.first


{-| Click handler that calls `Html.Events.stopPropagationOn` so
the inner disclosure button doesn't also fire the row's
`CompendiumGroupSelect` (which would shift the right pane).
-}
onClickStopPropagation : Msg -> Html.Attribute Msg
onClickStopPropagation msg =
    Html.Events.stopPropagationOn "click"
        (Decode.succeed ( msg, True ))


listItem : Maybe String -> Set String -> List String -> Compendium.Creature -> Html Msg
listItem selectedId selectedIds encounterIds c =
    let
        isSelected =
            selectedId == Just c.id

        isChecked =
            Set.member c.id selectedIds

        inEncounter =
            List.member c.id encounterIds

        rowClass =
            "compendium__row"
                ++ (if isSelected then
                        " compendium__row--selected"

                    else
                        ""
                   )
                ++ (if isChecked then
                        " compendium__row--checked"

                    else
                        ""
                   )
                ++ (" compendium__row--" ++ CompendiumUi.kindToString c.kind)
    in
    div
        [ class rowClass
        , onClick (CompendiumSelect c.id)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        , attribute "aria-pressed"
            (if isSelected then
                "true"

             else
                "false"
            )
        ]
        [ rowCheckbox c.id isChecked
        , div [ class "compendium__row-text" ]
            [ span [ class "compendium__row-name" ]
                [ text c.name
                , if inEncounter then
                    span
                        [ class "compendium__row-in-enc"
                        , Tooltips.attr Tooltips.compendiumInEncounter
                        , attribute "aria-label" "in encounter"
                        ]
                        []

                  else
                    text ""
                ]
            , span [ class "compendium__row-meta" ]
                [ text (rowMetaLine c) ]
            ]
        ]


{-| Bulk-selection checkbox at the leading edge of each row.
Clicks here are stopped from bubbling so the surrounding row
button doesn't also fire `CompendiumSelect` (which would shift
the right-pane stat block) — the GM expects checkbox clicks to
ONLY toggle bulk selection.

The custom event decoder reads `event.shiftKey` so we can
implement the shift+click select-all / clear-all semantics in
`Update.Compendium.Browser.rowToggle`.

-}
rowCheckbox : String -> Bool -> Html Msg
rowCheckbox creatureId isChecked =
    Html.input
        [ type_ "checkbox"
        , class "compendium__row-check"
        , Attr.checked isChecked
        , attribute "aria-label" "Select for bulk action"
        , Tooltips.attr Tooltips.compendiumRowSelect
        , Html.Events.stopPropagationOn "click"
            (Decode.field "shiftKey" Decode.bool
                |> Decode.map
                    (\shift ->
                        ( CompendiumRowToggle creatureId shift, True )
                    )
            )
        ]
        []


rowMetaLine : Compendium.Creature -> String
rowMetaLine c =
    let
        bits =
            List.filter (not << String.isEmpty)
                [ CompendiumUi.creatureKindLabel c.kind
                , c.race
                , "AC\u{00A0}" ++ String.fromInt c.armorClass
                , "HP\u{00A0}" ++ String.fromInt c.maxHp
                , crLabel c.challengeRating
                ]
    in
    String.join " · " bits


crLabel : String -> String
crLabel cr =
    if String.isEmpty cr then
        ""

    else
        "CR\u{00A0}" ++ cr


detail : Auth.AuthState -> CompendiumUi -> List Compendium.Creature -> List Lore.Group -> List String -> Html Msg
detail auth ui visible userLoreGroups encounterIds =
    let
        chosenLore =
            ui.selectedLoreId
                |> Maybe.andThen
                    (\id ->
                        (userLoreGroups ++ Lore.bundled)
                            |> List.filter (\g -> g.id == id)
                            |> List.head
                    )

        chosenGroup =
            ui.selectedGroupId
                |> Maybe.andThen (\id -> Dict.get id ui.groups)

        chosen =
            ui.selectedId
                |> Maybe.andThen (\id -> List.filter (\c -> c.id == id) visible |> List.head)
    in
    case ( chosenLore, chosenGroup, chosen ) of
        ( Just loreGroup, _, _ ) ->
            div [ class "compendium__detail" ]
                [ loreActionBar auth loreGroup
                , loreDetailBody loreGroup
                ]

        ( Nothing, Just group, _ ) ->
            div [ class "compendium__detail" ]
                [ groupActionBar auth group
                , groupDetailBody ui group
                ]

        ( Nothing, Nothing, Just creature ) ->
            div [ class "compendium__detail" ]
                [ actionBar creature
                    (encounterInstancesOf creature.id encounterIds)
                    ui.selectedIds
                , View.StatBlock.view RollFromStatBlock AbilityCheckOpen AbilitySaveOpen View.StatBlock.TagBadgesOpenInNewTab creature
                ]

        ( Nothing, Nothing, Nothing ) ->
            div [ class "compendium__detail compendium__detail--empty" ]
                [ text "Select a creature or group on the left." ]


groupActionBar : Auth.AuthState -> Compendium.Group.Group -> Html Msg
groupActionBar auth group =
    div [ class "compendium__action-bar" ]
        [ span [ class "compendium__in-encounter" ]
            [ text
                (String.fromInt (Compendium.Group.totalCreatureCount group)
                    ++ " creatures · "
                    ++ Compendium.Group.initiativeModeLabel group.initiativeMode
                )
            ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumGroupAdd group.id)
            , Tooltips.attr Tooltips.compendiumGroupAdd
            ]
            [ text "➕ Add Group to Encounter" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick
                (AuthGate.clickWhenAuthed auth
                    (CompendiumGroupEditOpenExisting group.id)
                )
            , Tooltips.attr
                (AuthGate.tooltipWhenAuthed auth
                    Tooltips.compendiumGroupEdit
                    "Sign in to edit encounter groups."
                )
            ]
            [ text "✏️ Edit" ]
        , button
            [ class "action-btn action-btn--red compendium__delete-btn"
            , onClick
                (AuthGate.clickWhenAuthed auth
                    (CompendiumGroupDelete group.id)
                )
            , Tooltips.attr
                (AuthGate.tooltipWhenAuthed auth
                    Tooltips.compendiumGroupDelete
                    "Sign in to delete encounter groups."
                )
            , attribute "aria-label" "Delete group"
            ]
            [ text "🗑" ]
        ]


{-| Right-pane content for the selected group: a heading + the
list of entries with their counts and minion types. Read-only;
to mutate the group the GM opens the Edit modal.
-}
groupDetailBody : CompendiumUi -> Compendium.Group.Group -> Html Msg
groupDetailBody ui group =
    let
        creatureNameById creatureId =
            case ui.db of
                CompendiumDbLoaded db ->
                    Compendium.find creatureId db
                        |> Maybe.map .name
                        |> Maybe.withDefault "Unknown creature"

                _ ->
                    "Unknown creature"

        entryLine entry =
            let
                minionSuffix =
                    case entry.minionType of
                        Compendium.Group.MinionNone ->
                            ""

                        other ->
                            " · " ++ Compendium.Group.minionTypeLabel other
            in
            div [ class "compendium__group-entry" ]
                [ text
                    (String.fromInt entry.count
                        ++ " × "
                        ++ creatureNameById entry.creatureId
                        ++ minionSuffix
                    )
                ]
    in
    div [ class "compendium__group-detail" ]
        [ h3 [ class "compendium__group-detail-title" ] [ text group.name ]
        , p [ class "compendium__group-detail-mode" ]
            [ text ("Initiative: " ++ Compendium.Group.initiativeModeLabel group.initiativeMode)
            , case group.initiativeMode of
                Compendium.Group.InitiativeSharedManual n ->
                    text (" (" ++ String.fromInt n ++ ")")

                _ ->
                    text ""
            ]
        , div [ class "compendium__group-detail-entries" ]
            (List.map entryLine group.entries)
        ]


{-| Right-pane action bar for the selected creature. Replaces
the old Count input with a read-only "[N] in Encounter" badge so
the GM can see at a glance how many instances of this creature
are already in the queue. Each click of "Add to Encounter"
spawns one fresh instance; the modal stays open across adds.

When one or more rows are checkbox-selected, an "Add Selected"
button appears next to "+ Add to Encounter" to bulk-add every
checked creature in a single batched roll.

-}
actionBar : Compendium.Creature -> Int -> Set String -> Html Msg
actionBar creature inEncounter selectedIds =
    let
        badgeClass =
            if inEncounter > 0 then
                "compendium__in-encounter compendium__in-encounter--present"

            else
                "compendium__in-encounter"

        selectedCount =
            Set.size selectedIds

        addSelectedButton =
            if selectedCount == 0 then
                text ""

            else
                button
                    [ class "action-btn action-btn--green compendium__add-btn"
                    , onClick CompendiumAddSelectedToQueue
                    , Tooltips.attr Tooltips.compendiumAddSelected
                    ]
                    [ text
                        ("➕ Add Selected ("
                            ++ String.fromInt selectedCount
                            ++ ")"
                        )
                    ]
    in
    let
        -- Bundled (SRD) creatures are read-only.  The Edit button
        -- is rendered greyed-out (with an explanatory hover
        -- tooltip) so the affordance stays in the same place
        -- across rows; Duplicate is the path to a per-user copy.
        -- Pre-Phase-2 snapshots may load a creature with
        -- `isBundled = False` even when the id happens to belong
        -- to the bundle, but those rows are now flagged correctly
        -- on every fresh fetch.
        editButton =
            if creature.isBundled then
                -- Wrapper span carries the fast tooltip because the
                -- disabled button itself swallows mouse events in
                -- Chrome (so `data-tooltip` would never fire). The
                -- wrapper also overrides the default not-allowed
                -- cursor — the disabled styling alone is enough to
                -- communicate inertness without the extra "🚫"
                -- mouse glyph.
                span
                    [ class "compendium__edit-btn-bundled-wrap"
                    , Tooltips.attr Tooltips.compendiumEditBundled
                    ]
                    [ button
                        [ class "action-btn action-btn--blue compendium__edit-btn"
                        , disabled True
                        ]
                        [ text "✏️ Edit" ]
                    ]

            else
                button
                    [ class "action-btn action-btn--blue compendium__edit-btn"
                    , onClick CompendiumEditExisting
                    , Tooltips.attr Tooltips.compendiumEdit
                    ]
                    [ text "✏️ Edit" ]

        deleteButton =
            if creature.isBundled then
                text ""

            else
                button
                    [ class "action-btn action-btn--red compendium__delete-btn"
                    , onClick (CompendiumDeleteFromBrowser creature.id creature.name)
                    , Tooltips.attr Tooltips.compendiumDelete
                    , attribute "aria-label" "Delete creature"
                    ]
                    [ text "🗑" ]
    in
    div [ class "compendium__action-bar" ]
        [ span
            [ class badgeClass
            , Tooltips.attr Tooltips.compendiumInstanceCount
            ]
            [ text (String.fromInt inEncounter ++ " in Encounter") ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumAddToQueue creature.id)
            , Tooltips.attr Tooltips.compendiumAddToEncounter
            ]
            [ text "➕ Add to Encounter" ]
        , addSelectedButton
        , editButton
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditDuplicate
            , Tooltips.attr Tooltips.compendiumDuplicate
            ]
            [ text "📋 Duplicate" ]
        , deleteButton
        ]


newButton : Html Msg
newButton =
    button
        [ class "action-btn action-btn--green compendium__new-btn"
        , onClick CompendiumEditNew
        , Tooltips.attr Tooltips.compendiumNewCreature
        ]
        [ text "➕ New Creature" ]


pasteButton : Html Msg
pasteButton =
    button
        [ class "action-btn action-btn--blue"
        , onClick CompendiumPasteOpen
        , Tooltips.attr Tooltips.compendiumPasteStatBlock
        ]
        [ text "📋 Paste Stat Block" ]


{-| Cluster of bulk operations on the right edge of the filter
bar: Import / Export / Reset / Clear.

Import and Export are split-button dropdowns offering Server /
Device routes; Reset goes through the destructive-confirm
banner; Clear opens a dropdown with Clear All / Clear Selected.

-}
bulkButtons : Auth.AuthState -> CompendiumUi -> Html Msg
bulkButtons auth ui =
    div [ class "compendium__bulk-cluster" ]
        [ importMenu auth ui
        , exportMenu auth ui
        , button
            [ class "action-btn action-btn--orange"
            , onClick CompendiumResetClick
            , Tooltips.attr Tooltips.compendiumReset
            ]
            [ text "↺ Reset" ]
        , clearMenu ui
        ]


{-| Wrapper around one of the compendium-bulk split-button
dropdowns. The trigger flips the named menu open / closed via
`CompendiumBulkMenuToggle`; the wrapper stops mousedown
propagation so a click inside the popover doesn't bubble to the
document-level "click-outside closes" handler in
`Main.subscriptions`.
-}
splitMenu :
    { menu : CompendiumBulkMenu
    , isOpen : Bool
    , triggerClass : String
    , triggerLabel : String
    , triggerTitle : String
    , alignLeft : Bool
    , items : List (Html Msg)
    }
    -> Html Msg
splitMenu cfg =
    let
        wrapperClass =
            if cfg.isOpen then
                "compendium__bulk-menu compendium__bulk-menu--open"

            else
                "compendium__bulk-menu"

        listClass =
            if cfg.alignLeft then
                "compendium__bulk-menu__list compendium__bulk-menu__list--left"

            else
                "compendium__bulk-menu__list"
    in
    div
        [ class wrapperClass
        , Html.Events.stopPropagationOn "mousedown"
            (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class cfg.triggerClass
            , onClick (CompendiumBulkMenuToggle cfg.menu)
            , Tooltips.attr cfg.triggerTitle
            , attribute "aria-haspopup" "menu"
            , attribute "aria-expanded"
                (if cfg.isOpen then
                    "true"

                 else
                    "false"
                )
            ]
            [ text cfg.triggerLabel ]
        , if cfg.isOpen then
            div
                [ class listClass
                , attribute "role" "menu"
                ]
                cfg.items

          else
            text ""
        ]


{-| Render one menu item inside a `splitMenu`. Routes through
the same disabled-tooltip pattern the Clear menu uses so a
disabled item still surfaces a hint via `title`.
-}
menuItem : Msg -> String -> Html Msg
menuItem msg label_ =
    button
        [ class "compendium__bulk-menu__item"
        , onClick msg
        , attribute "role" "menuitem"
        ]
        [ text label_ ]


{-| Server-only menu item that gates on auth state. Anonymous
users see the same row in the dropdown — the click navigates to
the login route and the tooltip explains why, instead of firing
a request that would 401.
-}
serverMenuItem :
    Auth.AuthState
    -> { msg : Msg, label : String, signedInTooltip : String, anonymousTooltip : String }
    -> Html Msg
serverMenuItem auth opts =
    button
        [ class "compendium__bulk-menu__item"
        , onClick (AuthGate.clickWhenAuthed auth opts.msg)
        , Tooltips.attr
            (AuthGate.tooltipWhenAuthed auth opts.signedInTooltip opts.anonymousTooltip)
        , attribute "role" "menuitem"
        ]
        [ text opts.label ]


importMenu : Auth.AuthState -> CompendiumUi -> Html Msg
importMenu _ _ =
    -- Single button (no dropdown).  The Load Compendium modal
    -- it opens carries the Server / Device radios so the
    -- previous split-button was redundant.
    button
        [ class "action-btn action-btn--blue"
        , onClick LoadCompendiumOpen
        , Tooltips.attr Tooltips.compendiumImport
        ]
        [ text "📥 Import" ]


exportMenu : Auth.AuthState -> CompendiumUi -> Html Msg
exportMenu _ ui =
    let
        triggerClass =
            if ui.compendiumDirty then
                "action-btn action-btn--blue compendium__export--dirty"

            else
                "action-btn action-btn--blue"

        triggerTitle =
            if ui.compendiumDirty then
                Tooltips.compendiumExportDirty

            else
                Tooltips.compendiumExport
    in
    -- Plain button (no dropdown).  The Save Compendium modal
    -- itself carries the Server / Device radios, so the previous
    -- split-button menu was redundant.  Default destination is
    -- Device because it works for both anonymous and
    -- authenticated sessions; the modal lets the user switch to
    -- Server if they're signed in.
    button
        [ class triggerClass
        , onClick (SaveCompendiumOpen SaveDestinationDevice)
        , Tooltips.attr triggerTitle
        ]
        [ text "📤 Export" ]


{-| Clear button + popover dropdown. Same wrapper / behavior
as the Import / Export menus; the menu items dispatch the Clear
All / Clear Selected actions.
-}
clearMenu : CompendiumUi -> Html Msg
clearMenu ui =
    let
        nothingSelected =
            Set.isEmpty ui.selectedIds

        clearSelectedItem =
            button
                [ class "compendium__bulk-menu__item"
                , onClick CompendiumClearSelected
                , disabled nothingSelected
                , Tooltips.attr
                    (if nothingSelected then
                        Tooltips.compendiumClearSelectedNone

                     else
                        Tooltips.compendiumClearSelectedReady
                    )
                , attribute "role" "menuitem"
                ]
                [ text "Clear Selected" ]
    in
    splitMenu
        { menu = ClearMenu
        , isOpen = ui.bulkMenu == Just ClearMenu
        , triggerClass = "action-btn action-btn--red"
        , triggerLabel = "🗑 Clear"
        , triggerTitle = Tooltips.compendiumClear
        , alignLeft = False
        , items =
            [ menuItem CompendiumClearAll "Clear All"
            , clearSelectedItem
            ]
        }



-- ── LORE GROUPS SECTION ─────────────────────────────────────────────────────


{-| Renders the collapsible Lore groups section at the top of
the Compendium list. Header shows a "+ New" affordance plus a
disclosure caret; when expanded, each lore group (bundled +
user-curated) becomes its own selectable row with an optional
member-list expansion.

Returns a List of rows; the caller wraps them in the sticky
`compendium__lore-pane` container so the section stays pinned
at the top of the list while the creature rows scroll under it.

-}
loreSection : Auth.AuthState -> CompendiumUi -> List Lore.Group -> List (Html Msg)
loreSection auth ui userLoreGroups =
    let
        allGroups =
            -- User-authored first so the GM's own groups read
            -- at the top of the expanded list — bundled trails
            -- as the SRD fallback set.
            userLoreGroups ++ Lore.bundled

        header =
            loreSectionHeader auth ui (List.length allGroups)

        rows =
            if ui.loreGroupsExpanded then
                List.map (loreRow ui) allGroups

            else
                []
    in
    header :: rows


loreSectionHeader : Auth.AuthState -> CompendiumUi -> Int -> Html Msg
loreSectionHeader auth ui totalCount =
    let
        signedOut =
            not (Auth.isAuthenticated auth)

        newClickMsg =
            if signedOut then
                Msg.NoOp

            else
                LoreEditOpenNew

        newTitle =
            if signedOut then
                "Sign in first"

            else
                "Create a new Lore grouping"
    in
    div
        [ class "compendium__row compendium__row--lore-section"
        , onClick CompendiumLoreSectionToggle
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ button
            [ class "compendium__group-disclosure"
            , onClickStopPropagation CompendiumLoreSectionToggle
            , attribute "aria-expanded"
                (if ui.loreGroupsExpanded then
                    "true"

                 else
                    "false"
                )
            , attribute "aria-label" "Toggle Lore groupings"
            ]
            [ text
                (if ui.loreGroupsExpanded then
                    "▾"

                 else
                    "▸"
                )
            ]
        , div [ class "compendium__row-text" ]
            [ span [ class "compendium__row-name" ]
                [ text "📖 Lore groupings" ]
            , span [ class "compendium__row-meta" ]
                [ text (String.fromInt totalCount ++ " groupings") ]
            ]
        , button
            [ class
                ("action-btn action-btn--condition compendium__lore-new"
                    ++ (if signedOut then
                            " compendium__lore-new--locked"

                        else
                            ""
                       )
                )
            , onClickStopPropagation newClickMsg
            , Tooltips.attr newTitle
            , attribute "aria-label" newTitle
            ]
            [ text "+ New" ]
        ]


loreRow : CompendiumUi -> Lore.Group -> Html Msg
loreRow ui group =
    let
        isSelected =
            ui.selectedLoreId == Just group.id

        isExpanded =
            Set.member group.id ui.expandedLoreIds

        bundled =
            group.source == Lore.Bundled

        rowClass =
            "compendium__row compendium__row--lore"
                ++ (if isSelected then
                        " compendium__row--selected"

                    else
                        ""
                   )
                ++ (if bundled then
                        " compendium__row--lore-bundled"

                    else
                        ""
                   )

        memberCount =
            List.length group.members
    in
    div [ class "compendium__lore-row-wrap" ]
        [ div
            [ class rowClass
            , onClick (CompendiumLoreSelect group.id)
            , attribute "role" "button"
            , attribute "tabindex" "0"
            ]
            [ button
                [ class "compendium__group-disclosure"
                , onClickStopPropagation (CompendiumLoreExpandToggle group.id)
                , attribute "aria-expanded"
                    (if isExpanded then
                        "true"

                     else
                        "false"
                    )
                , attribute "aria-label" "Toggle lore group members"
                ]
                [ text
                    (if isExpanded then
                        "▾"

                     else
                        "▸"
                    )
                ]
            , div [ class "compendium__row-text" ]
                [ span [ class "compendium__row-name" ]
                    [ text
                        ((if bundled then
                            "🔒 "

                          else
                            "📖 "
                         )
                            ++ group.name
                        )
                    ]
                , span [ class "compendium__row-meta" ]
                    [ text
                        (String.fromInt memberCount
                            ++ " member"
                            ++ (if memberCount == 1 then
                                    ""

                                else
                                    "s"
                               )
                            ++ " · weight "
                            ++ String.fromInt group.weight
                        )
                    ]
                ]
            ]
        , if isExpanded then
            div [ class "compendium__lore-members" ]
                (List.map loreMemberRow group.members)

          else
            text ""
        ]


loreMemberRow : Lore.Slot -> Html Msg
loreMemberRow slot =
    let
        countText =
            if slot.countMin == slot.countMax then
                String.fromInt slot.countMin

            else
                String.fromInt slot.countMin
                    ++ "–"
                    ++ String.fromInt slot.countMax
    in
    div [ class "compendium__lore-member" ]
        [ span [ class "compendium__lore-member-count" ]
            [ text (countText ++ "× ") ]
        , span [ class "compendium__lore-member-name" ]
            [ text slot.name ]
        , span [ class "compendium__lore-member-role" ]
            [ text (" · " ++ loreRoleLabel slot.role) ]
        ]


loreRoleLabel : Lore.Role -> String
loreRoleLabel r =
    case r of
        Lore.Leader ->
            "leader"

        Lore.Member ->
            "member"

        Lore.Minion ->
            "minion"

        Lore.Pet ->
            "pet"



-- ── LORE GROUP RIGHT-PANE DETAIL ────────────────────────────────────────────


loreActionBar : Auth.AuthState -> Lore.Group -> Html Msg
loreActionBar auth group =
    let
        bundled =
            group.source == Lore.Bundled

        signedOut =
            not (Auth.isAuthenticated auth)

        editClickMsg =
            if bundled || signedOut then
                Msg.NoOp

            else
                LoreEditOpenExisting group.id

        deleteClickMsg =
            if bundled || signedOut then
                Msg.NoOp

            else
                CompendiumLoreDelete group.id

        editTitle =
            if bundled then
                "Bundled Lore groupings can't be edited. Duplicate or create a new one to customise."

            else if signedOut then
                "Sign in first"

            else
                "Create / Edit Lore grouping"

        deleteTitle =
            if bundled then
                "Bundled Lore groupings can't be deleted."

            else if signedOut then
                "Sign in first"

            else
                "Delete this Lore grouping"
    in
    div [ class "compendium__action-bar" ]
        [ span [ class "compendium__in-encounter" ]
            [ text
                (String.fromInt (List.length group.members)
                    ++ " members · weight "
                    ++ String.fromInt group.weight
                )
            ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumLoreAdd group.id)
            , Tooltips.attr "Roll counts and add this Lore grouping's creatures to the encounter"
            ]
            [ text "➕ Add Grouping to Encounter" ]
        , button
            [ class
                ("action-btn action-btn--blue compendium__edit-btn"
                    ++ (if bundled then
                            " compendium__edit-btn--disabled"

                        else if signedOut then
                            " compendium__edit-btn--locked"

                        else
                            ""
                       )
                )
            , onClick editClickMsg
            , Attr.disabled bundled
            , Tooltips.attr editTitle
            , attribute "aria-label" editTitle
            ]
            [ text "✏️ Create/Edit Lore grouping" ]
        , button
            [ class
                ("action-btn action-btn--red compendium__delete-btn"
                    ++ (if bundled then
                            " compendium__delete-btn--disabled"

                        else if signedOut then
                            " compendium__delete-btn--locked"

                        else
                            ""
                       )
                )
            , onClick deleteClickMsg
            , Attr.disabled bundled
            , Tooltips.attr deleteTitle
            , attribute "aria-label" deleteTitle
            ]
            [ text "🗑" ]
        ]


loreDetailBody : Lore.Group -> Html Msg
loreDetailBody group =
    div [ class "compendium__lore-detail" ]
        [ h3 [ class "compendium__lore-detail-name" ] [ text group.name ]
        , p [ class "compendium__lore-detail-meta" ]
            [ text
                ("Weight "
                    ++ String.fromInt group.weight
                    ++ " · "
                    ++ (case group.source of
                            Lore.Bundled ->
                                "Bundled"

                            Lore.UserCurated ->
                                "User-curated"
                       )
                )
            ]
        , div [ class "compendium__lore-detail-members" ]
            (List.map loreMemberRow group.members)
        , loreDescription group.description
        ]


loreDescription : String -> Html Msg
loreDescription desc =
    if String.isEmpty (String.trim desc) then
        text ""

    else
        div [ class "compendium__lore-detail-description" ]
            (List.map
                (\para -> p [] [ text para ])
                (String.split "\n\n" desc)
            )
