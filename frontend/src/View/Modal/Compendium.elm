module View.Modal.Compendium exposing (view)

{-| Read-only browser for the creature library. Two-column layout:
filterable + sortable list on the left, full stat block on the
right. The right pane has an action bar with the "Add to
Encounter" handoff plus per-creature edit / duplicate / delete.
-}

import Compendium
import Html exposing (Html, button, div, input, label, option, p, span, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, id, placeholder, selected, title, type_, value)
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
import Update.Compendium.Browser
import View.Modal
import View.StatBlock
import View.Tooltips as Tooltips


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
        , bulkButtons ui
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
        [ list ui totalCount visible encounterIds ui.selectedIds
        , detail ui visible encounterIds
        ]


list :
    CompendiumUi
    -> Int
    -> List Compendium.Creature
    -> List String
    -> Set String
    -> Html Msg
list ui totalCount visible encounterIds selectedIds =
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
            (List.map (listItem ui.selectedId selectedIds encounterIds) visible)


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
            , Tooltips.attr Tooltips.compendiumInstanceCount
            ]
            [ text (String.fromInt inEncounter ++ " in Encounter") ]
        , button
            [ class "action-btn action-btn--green compendium__add-btn"
            , onClick (CompendiumAddToQueue creature.id)
            , Tooltips.attr Tooltips.compendiumAddToEncounter
            ]
            [ text "➕ Add to Encounter" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditExisting
            , Tooltips.attr Tooltips.compendiumEdit
            ]
            [ text "✏️ Edit" ]
        , button
            [ class "action-btn action-btn--blue compendium__edit-btn"
            , onClick CompendiumEditDuplicate
            , Tooltips.attr Tooltips.compendiumDuplicate
            ]
            [ text "📋 Duplicate" ]
        , button
            [ class "action-btn action-btn--red compendium__delete-btn"
            , onClick (CompendiumDeleteFromBrowser creature.id creature.name)
            , Tooltips.attr Tooltips.compendiumDelete
            , attribute "aria-label" "Delete creature"
            ]
            [ text "🗑" ]
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
bulkButtons : CompendiumUi -> Html Msg
bulkButtons ui =
    div [ class "compendium__bulk-cluster" ]
        [ importMenu ui
        , exportMenu ui
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


importMenu : CompendiumUi -> Html Msg
importMenu ui =
    splitMenu
        { menu = ImportMenu
        , isOpen = ui.bulkMenu == Just ImportMenu
        , triggerClass = "action-btn action-btn--blue"
        , triggerLabel = "📥 Import ▾"
        , triggerTitle = Tooltips.compendiumImport
        , alignLeft = True
        , items =
            [ menuItem LoadCompendiumOpen "From Server"
            , menuItem CompendiumImportClick "From Device"
            ]
        }


exportMenu : CompendiumUi -> Html Msg
exportMenu ui =
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
    splitMenu
        { menu = ExportMenu
        , isOpen = ui.bulkMenu == Just ExportMenu
        , triggerClass = triggerClass
        , triggerLabel = "📤 Export ▾"
        , triggerTitle = triggerTitle
        , alignLeft = False
        , items =
            [ menuItem
                (SaveCompendiumOpen SaveDestinationServer)
                "To Server"
            , menuItem
                (SaveCompendiumOpen SaveDestinationDevice)
                "To Device"
            ]
        }


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
                , title
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
