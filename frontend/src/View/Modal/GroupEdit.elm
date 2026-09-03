module View.Modal.GroupEdit exposing (view)

{-| Create / Edit Group modal.

Three sections:

  - **Name** — single-line text input.
  - **Initiative** — radio group picking one of the three modes;
    when "Shared manual" is selected, an extra number input
    appears for the GM-typed value.
  - **Entries** — one row per creature in the group, each with
    a creature dropdown, a count input, a minion-type select,
    and a remove (×) button. A trailing "+ Add Entry" button
    appends a fresh empty row.

Renders nothing when the modal isn't open.

-}

import Compendium
import Compendium.Group as Group
    exposing
        ( InitiativeMode(..)
        , MinionType(..)
        )
import Encounter.Difficulty
import Encounter.RandomEncounter.Lore as Lore
import Encounter.RandomEncounter.Lore.Suggest as Suggest
import Html
    exposing
        ( Html
        , a
        , button
        , div
        , h3
        , input
        , label
        , li
        , option
        , p
        , section
        , select
        , span
        , text
        , ul
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , autofocus
        , checked
        , class
        , disabled
        , id
        , maxlength
        , name
        , placeholder
        , selected
        , step
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.GroupEdit as GroupEdit
    exposing
        ( EntryDraft
        , GroupEditMode(..)
        , GroupEditUi
        , LoreDraft
        , LoreMemberDraft
        , LoreSection
        )
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceGroupEdit ui) ->
            let
                creatures =
                    case model.compendium.db of
                        CompendiumDbLoaded db ->
                            Compendium.toList db

                        _ ->
                            []

                titleText =
                    case ui.mode of
                        GroupCreateMode ->
                            "Create Group"

                        GroupEditExisting _ ->
                            "Edit Group"
            in
            View.Modal.view
                { close = GroupEditClose
                , noOp = NoOp
                , title = "👥 " ++ titleText
                , extraClass = "modal--group-edit"
                , chrome = model.modalChrome
                , body =
                    [ nameSection ui
                    , initiativeSection ui
                    , entriesSection ui creatures
                    , errorBanner ui
                    , submitRow ui
                    ]
                }

        _ ->
            text ""



-- ── NAME ─────────────────────────────────────────────────────────────────────


nameSection : GroupEditUi -> Html Msg
nameSection ui =
    div [ class "group-edit__row" ]
        [ label
            [ class "group-edit__label", Attr.for "group-name" ]
            [ text "Name" ]
        , input
            [ id "group-name"
            , class "group-edit__input"
            , type_ "text"
            , value ui.name
            , maxlength GroupEdit.maxNameLength
            , placeholder "e.g. Goblin Patrol"
            , autofocus True
            , onInput GroupEditNameChanged
            ]
            []
        ]



-- ── INITIATIVE ───────────────────────────────────────────────────────────────


initiativeSection : GroupEditUi -> Html Msg
initiativeSection ui =
    div [ class "group-edit__row group-edit__row--initiative" ]
        [ label [ class "group-edit__label" ] [ text "Initiative" ]
        , div
            [ class "group-edit__radio-group"
            , attribute "role" "radiogroup"
            ]
            (List.map (initiativeRadio ui.initiativeMode)
                Group.initiativeModeAllValues
            )
        , case ui.initiativeMode of
            InitiativeSharedManual _ ->
                manualInitiativeInput ui.manualInitiative

            _ ->
                text ""
        ]


initiativeRadio : InitiativeMode -> InitiativeMode -> Html Msg
initiativeRadio current option_ =
    let
        key =
            Group.initiativeModeKey option_

        isActive =
            sameMode current option_
    in
    Html.label [ class "group-edit__radio" ]
        [ input
            [ type_ "radio"
            , name "group-initiative-mode"
            , value key
            , checked isActive
            , onClick (GroupEditInitiativeModeSet key)
            ]
            []
        , span [] [ text (Group.initiativeModeLabel option_) ]
        ]


{-| Compare two `InitiativeMode` values for radio-active state.
The `InitiativeSharedManual` variant carries an Int payload, so
naive `==` would only match identical numbers; the form treats
all `SharedManual` values as the same mode.
-}
sameMode : InitiativeMode -> InitiativeMode -> Bool
sameMode a b =
    Group.initiativeModeKey a == Group.initiativeModeKey b


manualInitiativeInput : String -> Html Msg
manualInitiativeInput rawValue =
    input
        [ class "group-edit__manual-initiative"
        , type_ "number"
        , Attr.min "-20"
        , Attr.max "40"
        , value rawValue
        , onInput GroupEditManualInitiativeChanged
        , attribute "aria-label" "Manual initiative value"
        ]
        []



-- ── ENTRIES ──────────────────────────────────────────────────────────────────


entriesSection : GroupEditUi -> List Compendium.Creature -> Html Msg
entriesSection ui creatures =
    div [ class "group-edit__entries" ]
        [ div [ class "group-edit__entries-header" ]
            [ label [ class "group-edit__label" ] [ text "Creatures" ]
            , button
                [ class "action-btn action-btn--blue group-edit__add-entry"
                , onClick GroupEditEntryAdd
                ]
                [ text "+ Add Entry" ]
            ]
        , if List.isEmpty ui.entries then
            p [ class "group-edit__empty" ]
                [ text "No creatures yet. Click + Add Entry to start." ]

          else
            div [ class "group-edit__entry-list" ]
                (List.indexedMap (entryRow creatures) ui.entries)
        ]


entryRow : List Compendium.Creature -> Int -> EntryDraft -> Html Msg
entryRow creatures index entry =
    div [ class "group-edit__entry" ]
        [ creaturePicker creatures index entry.creatureId
        , countInput index entry.count
        , minionTypeSelect index entry.minionType
        , button
            [ class "icon-btn icon-btn--danger group-edit__entry-remove"
            , onClick (GroupEditEntryRemove index)
            , attribute "aria-label" "Remove entry"
            ]
            [ text "×" ]
        ]


creaturePicker : List Compendium.Creature -> Int -> String -> Html Msg
creaturePicker creatures index currentId =
    let
        placeholderOption =
            option
                [ value "", selected (String.isEmpty currentId) ]
                [ text "— Pick a creature —" ]

        creatureOption c =
            option
                [ value c.id, selected (c.id == currentId) ]
                [ text c.name ]
    in
    select
        [ class "group-edit__creature"
        , onInput (GroupEditEntryCreatureChanged index)
        , attribute "aria-label" "Creature"
        ]
        (placeholderOption :: List.map creatureOption (sortByName creatures))


sortByName : List Compendium.Creature -> List Compendium.Creature
sortByName =
    List.sortBy (.name >> String.toLower)


countInput : Int -> String -> Html Msg
countInput index rawCount =
    input
        [ class "group-edit__count"
        , type_ "number"
        , Attr.min "1"
        , Attr.max "99"
        , value rawCount
        , onInput (GroupEditEntryCountChanged index)
        , attribute "aria-label" "Instance count"
        ]
        []


minionTypeSelect : Int -> MinionType -> Html Msg
minionTypeSelect index current =
    let
        minionOption mt =
            option
                [ value (Group.minionTypeKey mt)
                , selected (Group.minionTypeKey mt == Group.minionTypeKey current)
                ]
                [ text (Group.minionTypeLabel mt) ]
    in
    select
        [ class "group-edit__minion"
        , onInput (GroupEditEntryMinionTypeSet index)
        , attribute "aria-label" "Minion type"
        ]
        (List.map minionOption Group.minionTypeAllValues)



-- ── FOOTER ───────────────────────────────────────────────────────────────────


errorBanner : GroupEditUi -> Html Msg
errorBanner ui =
    case ui.submitError of
        Just err ->
            p [ class "group-edit__error" ] [ text err ]

        Nothing ->
            text ""


submitRow : GroupEditUi -> Html Msg
submitRow ui =
    let
        submitLabel =
            case ui.mode of
                GroupCreateMode ->
                    "Create Group"

                GroupEditExisting _ ->
                    "Save Group"
    in
    div [ class "group-edit__buttons" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick GroupEditSubmit
            , disabled ui.submitting
            ]
            [ text
                (if ui.submitting then
                    "Saving…"

                 else
                    submitLabel
                )
            ]
        , button
            [ class "action-btn"
            , onClick GroupEditClose
            , disabled ui.submitting
            ]
            [ text "Cancel" ]
        ]



-- ── LORE SECTION ─────────────────────────────────────────────────────────────


{-| Lore-groupings panel that sits below the regular group
form. Shows two collapsible sections — player-authored on top,
bundled below — with an expand toggle on each lore group
revealing its members. Player groups carry edit + delete
buttons; bundled are read-only. The "+ New lore group" button
opens an inline draft form.
-}
loreSection :
    GroupEditUi
    -> List Lore.Group
    -> List Compendium.Creature
    -> Html Msg
loreSection ui userGroups creatures =
    section [ class "group-edit__lore-section" ]
        ([ div [ class "group-edit__lore-divider" ] []
         , div [ class "group-edit__lore-header" ]
            [ h3 [ class "group-edit__lore-title" ]
                [ text "Lore groupings" ]
            , p [ class "group-edit__lore-blurb" ]
                [ text
                    ("Lore groupings are considered by the Random "
                        ++ "Encounter generator when Lore-leaning is "
                        ++ "selected. If your Lore grouping includes "
                        ++ "user-generated creatures, ensure all "
                        ++ "crucial stat block fields have values "
                        ++ "(CR, XP, Habitat, Type, etc., for each "
                        ++ "creature). If your Lore grouping is never "
                        ++ "pulled by the Encounter Generator, you "
                        ++ "may need to tweak some Lore Grouping, "
                        ++ "Random Encounter, or stat block values."
                    )
                ]
            ]
         ]
            ++ loreContent ui userGroups creatures
        )


loreContent :
    GroupEditUi
    -> List Lore.Group
    -> List Compendium.Creature
    -> List (Html Msg)
loreContent ui userGroups creatures =
    case ui.lore.editing of
        Just draft ->
            [ loreEditor draft creatures ui.lore.addSearch ui.lore.testResult ]

        Nothing ->
            [ loreActions ui.lore
            , loreUserList ui.lore userGroups
            , loreBundledList ui.lore
            , loreDeleteBanner ui.lore userGroups
            ]


loreActions : LoreSection -> Html Msg
loreActions _ =
    div [ class "group-edit__lore-actions" ]
        [ button
            [ class "action-btn action-btn--blue"
            , Attr.type_ "button"
            , onClick GroupEditLoreNew
            ]
            [ text "➕ New lore group" ]
        ]


loreDeleteBanner : LoreSection -> List Lore.Group -> Html Msg
loreDeleteBanner lore userGroups =
    case lore.confirmDelete of
        Just id ->
            let
                groupName =
                    List.filter (\g -> g.id == id) userGroups
                        |> List.head
                        |> Maybe.map .name
                        |> Maybe.withDefault id
            in
            div [ class "group-edit__lore-confirm" ]
                [ span []
                    [ text ("Delete \"" ++ groupName ++ "\"?") ]
                , button
                    [ class "action-btn action-btn--red"
                    , Attr.type_ "button"
                    , onClick GroupEditLoreDeleteConfirm
                    ]
                    [ text "Delete" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , Attr.type_ "button"
                    , onClick GroupEditLoreDeleteCancel
                    ]
                    [ text "Cancel" ]
                ]

        Nothing ->
            text ""


loreUserList : LoreSection -> List Lore.Group -> Html Msg
loreUserList lore userGroups =
    let
        count =
            List.length userGroups

        header =
            disclosureRow
                { expanded = lore.userExpanded
                , label =
                    "Your lore groups ("
                        ++ String.fromInt count
                        ++ ")"
                , msg = GroupEditLoreUserExpandToggle
                , extraClass = "group-edit__lore-disclosure--user"
                }
    in
    div [ class "group-edit__lore-list-block" ]
        (header
            :: (if lore.userExpanded then
                    if List.isEmpty userGroups then
                        [ p [ class "group-edit__lore-empty" ]
                            [ text "No custom lore groups yet — click \"+ New lore group\" to author one." ]
                        ]

                    else
                        [ ul [ class "group-edit__lore-list" ]
                            (List.map (userGroupRow lore.expandedGroups) userGroups)
                        ]

                else
                    []
               )
        )


loreBundledList : LoreSection -> Html Msg
loreBundledList lore =
    let
        count =
            List.length Lore.bundled

        header =
            disclosureRow
                { expanded = lore.bundledExpanded
                , label =
                    "Bundled lore groups ("
                        ++ String.fromInt count
                        ++ ")"
                , msg = GroupEditLoreBundledExpandToggle
                , extraClass = "group-edit__lore-disclosure--bundled"
                }
    in
    div [ class "group-edit__lore-list-block" ]
        (header
            :: (if lore.bundledExpanded then
                    [ ul [ class "group-edit__lore-list" ]
                        (List.map (bundledGroupRow lore.expandedGroups) Lore.bundled)
                    ]

                else
                    []
               )
        )


disclosureRow :
    { expanded : Bool, label : String, msg : Msg, extraClass : String }
    -> Html Msg
disclosureRow cfg =
    button
        [ class ("group-edit__lore-disclosure " ++ cfg.extraClass)
        , Attr.type_ "button"
        , onClick cfg.msg
        , attribute "aria-expanded"
            (if cfg.expanded then
                "true"

             else
                "false"
            )
        ]
        [ span [ class "group-edit__lore-disclosure-caret" ]
            [ text
                (if cfg.expanded then
                    "▼"

                 else
                    "▶"
                )
            ]
        , span [ class "group-edit__lore-disclosure-label" ]
            [ text cfg.label ]
        ]


userGroupRow : Set.Set String -> Lore.Group -> Html Msg
userGroupRow expandedSet g =
    let
        isOpen =
            Set.member g.id expandedSet
    in
    li [ class "group-edit__lore-row group-edit__lore-row--user" ]
        [ div [ class "group-edit__lore-row-header" ]
            [ button
                [ class "group-edit__lore-row-toggle"
                , Attr.type_ "button"
                , onClick (GroupEditLoreGroupExpandToggle g.id)
                , attribute "aria-expanded"
                    (if isOpen then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ class "group-edit__lore-row-caret" ]
                    [ text
                        (if isOpen then
                            "▼"

                         else
                            "▶"
                        )
                    ]
                , span [ class "group-edit__lore-row-name" ] [ text g.name ]
                , span [ class "group-edit__lore-row-meta" ]
                    [ text
                        (String.fromInt (List.length g.members)
                            ++ " species · weight "
                            ++ String.fromInt g.weight
                        )
                    ]
                ]
            , button
                [ class "icon-btn group-edit__lore-row-edit"
                , Attr.type_ "button"
                , onClick (GroupEditLoreEdit g.id)
                , Tooltips.attr "Edit this lore group"
                , attribute "aria-label" ("Edit " ++ g.name)
                ]
                [ text "✎" ]
            , button
                [ class "icon-btn icon-btn--danger group-edit__lore-row-delete"
                , Attr.type_ "button"
                , onClick (GroupEditLoreDeleteRequest g.id)
                , Tooltips.attr "Delete this lore group"
                , attribute "aria-label" ("Delete " ++ g.name)
                ]
                [ text "×" ]
            ]
        , if isOpen then
            loreMembersList g

          else
            text ""
        ]


bundledGroupRow : Set.Set String -> Lore.Group -> Html Msg
bundledGroupRow expandedSet g =
    let
        isOpen =
            Set.member g.id expandedSet
    in
    li [ class "group-edit__lore-row group-edit__lore-row--bundled" ]
        [ div [ class "group-edit__lore-row-header" ]
            [ button
                [ class "group-edit__lore-row-toggle"
                , Attr.type_ "button"
                , onClick (GroupEditLoreGroupExpandToggle g.id)
                , attribute "aria-expanded"
                    (if isOpen then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ class "group-edit__lore-row-caret" ]
                    [ text
                        (if isOpen then
                            "▼"

                         else
                            "▶"
                        )
                    ]
                , span [ class "group-edit__lore-row-name" ] [ text g.name ]
                , span [ class "group-edit__lore-row-meta" ]
                    [ text
                        (String.fromInt (List.length g.members)
                            ++ " species · weight "
                            ++ String.fromInt g.weight
                        )
                    ]
                , span [ class "group-edit__lore-row-locked" ]
                    [ text "🔒 bundled" ]
                ]
            ]
        , if isOpen then
            loreMembersList g

          else
            text ""
        ]


loreMembersList : Lore.Group -> Html Msg
loreMembersList g =
    ul [ class "group-edit__lore-members" ]
        (List.map loreMemberRow g.members)


loreMemberRow : Lore.Slot -> Html Msg
loreMemberRow s =
    let
        countLabel =
            if s.countMin == s.countMax then
                String.fromInt s.countMin

            else
                String.fromInt s.countMin ++ "–" ++ String.fromInt s.countMax
    in
    li [ class "group-edit__lore-member" ]
        [ span [ class "group-edit__lore-member-count" ] [ text countLabel ]
        , span [ class "group-edit__lore-member-name" ] [ text s.name ]
        , span [ class "group-edit__lore-member-role" ]
            [ text (roleLabel s.role) ]
        ]


roleLabel : Lore.Role -> String
roleLabel r =
    case r of
        Lore.Leader ->
            "leader"

        Lore.Member ->
            "member"

        Lore.Minion ->
            "minion"

        Lore.Pet ->
            "pet"



-- ── LORE EDITOR ──────────────────────────────────────────────────────────────


loreEditor :
    LoreDraft
    -> List Compendium.Creature
    -> String
    -> Maybe Suggest.Suggestion
    -> Html Msg
loreEditor draft creatures addSearch testResult =
    div [ class "group-edit__lore-editor" ]
        [ p [ class "group-edit__lore-editor-title" ]
            [ text
                (case draft.id of
                    Just _ ->
                        "Editing lore group"

                    Nothing ->
                        "New lore group"
                )
            ]
        , loreNameRow draft
        , loreWeightRow draft
        , loreMembersEditor draft
        , loreAddMemberPicker addSearch creatures draft.members
        , loreEditorActions
        , loreTestPanel testResult
        ]


loreNameRow : LoreDraft -> Html Msg
loreNameRow draft =
    div [ class "group-edit__row" ]
        [ label [ class "group-edit__label" ] [ text "Name" ]
        , input
            [ class "group-edit__input"
            , type_ "text"
            , value draft.name
            , maxlength GroupEdit.maxNameLength
            , placeholder "e.g. Kobold Skirmishers"
            , onInput GroupEditLoreDraftNameChanged
            ]
            []
        ]


loreWeightRow : LoreDraft -> Html Msg
loreWeightRow draft =
    div [ class "group-edit__row group-edit__lore-weight-row" ]
        [ label [ class "group-edit__label" ]
            [ text ("Weight (" ++ String.fromInt draft.weight ++ ")") ]
        , input
            [ class "group-edit__lore-weight-slider"
            , type_ "range"
            , Attr.min "1"
            , Attr.max "10"
            , step "1"
            , value (String.fromInt draft.weight)
            , onInput GroupEditLoreDraftWeightChanged
            ]
            []
        , span [ class "group-edit__lore-weight-hint" ]
            [ text "1 = rare · 10 = common" ]
        ]


loreMembersEditor : LoreDraft -> Html Msg
loreMembersEditor draft =
    if List.isEmpty draft.members then
        p [ class "group-edit__lore-empty" ]
            [ text "Add at least one creature to the lore group." ]

    else
        div [ class "group-edit__lore-members-editor" ]
            (List.indexedMap loreMemberEditorRow draft.members)


loreMemberEditorRow : Int -> LoreMemberDraft -> Html Msg
loreMemberEditorRow index m =
    div [ class "group-edit__lore-member-row" ]
        [ span [ class "group-edit__lore-member-name" ]
            [ text m.creatureName ]
        , select
            [ class "group-edit__lore-role-select"
            , onInput (GroupEditLoreDraftMemberRoleSet index)
            , attribute "aria-label" "Role"
            ]
            (List.map (roleOption m.role) allRoles)
        , label [ class "group-edit__lore-count-label" ] [ text "min" ]
        , input
            [ class "group-edit__lore-count-input"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "50"
            , value m.countMin
            , onInput (GroupEditLoreDraftMemberCountMinChanged index)
            , attribute "aria-label" "Minimum count"
            ]
            []
        , label [ class "group-edit__lore-count-label" ] [ text "max" ]
        , input
            [ class "group-edit__lore-count-input"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "50"
            , value m.countMax
            , onInput (GroupEditLoreDraftMemberCountMaxChanged index)
            , attribute "aria-label" "Maximum count"
            ]
            []
        , button
            [ class "icon-btn icon-btn--danger"
            , Attr.type_ "button"
            , onClick (GroupEditLoreDraftMemberRemove index)
            , Tooltips.attr "Remove this member"
            , attribute "aria-label" "Remove member"
            ]
            [ text "×" ]
        ]


allRoles : List Lore.Role
allRoles =
    [ Lore.Leader, Lore.Member, Lore.Minion, Lore.Pet ]


roleOption : Lore.Role -> Lore.Role -> Html Msg
roleOption current role =
    option
        [ value (roleKey role)
        , selected (role == current)
        ]
        [ text (roleLabel role) ]


roleKey : Lore.Role -> String
roleKey r =
    case r of
        Lore.Leader ->
            "leader"

        Lore.Member ->
            "member"

        Lore.Minion ->
            "minion"

        Lore.Pet ->
            "pet"


loreAddMemberPicker :
    String
    -> List Compendium.Creature
    -> List LoreMemberDraft
    -> Html Msg
loreAddMemberPicker addSearch creatures already =
    let
        alreadyNames =
            List.map .creatureName already

        matches =
            if String.isEmpty (String.trim addSearch) then
                []

            else
                creatures
                    |> List.filter
                        (\c ->
                            String.contains
                                (String.toLower addSearch)
                                (String.toLower c.name)
                        )
                    |> List.filter (\c -> not (List.member c.name alreadyNames))
                    |> List.sortBy .name
                    |> List.take 12
    in
    div [ class "group-edit__lore-add-row" ]
        [ input
            [ class "group-edit__input"
            , type_ "search"
            , placeholder "🔍 Search a creature to add…"
            , value addSearch
            , onInput GroupEditLoreAddSearchChanged
            ]
            []
        , if List.isEmpty matches then
            text ""

          else
            ul [ class "group-edit__lore-add-results" ]
                (List.map loreAddResultRow matches)
        ]


loreAddResultRow : Compendium.Creature -> Html Msg
loreAddResultRow c =
    li
        [ class "group-edit__lore-add-result"
        , onClick (GroupEditLoreDraftMemberAdd c.name)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ span [] [ text c.name ]
        , span [ class "group-edit__lore-add-result-cr" ]
            [ text ("CR " ++ c.challengeRating) ]
        ]


loreEditorActions : Html Msg
loreEditorActions =
    div [ class "group-edit__lore-editor-actions" ]
        [ button
            [ class "action-btn group-edit__lore-test"
            , Attr.type_ "button"
            , onClick GroupEditLoreDraftTest
            , Tooltips.attr "Estimate the generator settings most likely to roll this group"
            ]
            [ text "Test" ]
        , span [ class "group-edit__lore-actions-spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , Attr.type_ "button"
            , onClick GroupEditLoreDraftSubmit
            ]
            [ text "Save lore group" ]
        , button
            [ class "action-btn"
            , Attr.type_ "button"
            , onClick GroupEditLoreDraftCancel
            ]
            [ text "Cancel" ]
        ]


{-| Result of clicking the Test button — a recommendation for
the Random Encounter generator inputs that should reliably pick
this lore group. Hidden until the GM clicks Test; reset on any
draft edit so the panel never lags behind the form.
-}
loreTestPanel : Maybe Suggest.Suggestion -> Html Msg
loreTestPanel maybeResult =
    case maybeResult of
        Nothing ->
            text ""

        Just s ->
            let
                resolvedSomething =
                    s.maxXp > 0
            in
            div [ class "group-edit__lore-test-panel" ]
                (if resolvedSomething then
                    [ p [ class "group-edit__lore-test-title" ]
                        [ text "Settings most likely to roll this group:" ]
                    ]
                        ++ testRows s
                        ++ unresolvedBanner s.unresolved

                 else
                    [ p [ class "group-edit__lore-test-title" ]
                        [ text "Can't compute settings — no members resolved against the compendium." ]
                    ]
                        ++ unresolvedBanner s.unresolved
                )


testRows : Suggest.Suggestion -> List (Html Msg)
testRows s =
    [ testRow "Lore Leaning" "Enable the toggle (required for any lore group to fire)"
    , testRow "Habitat" (formatHabitats s.habitats)
    , testRow "Creature Type" (formatTypes s.creatureTypes)
    , testRow "Party"
        (String.fromInt s.partyCount
            ++ " characters at level "
            ++ String.fromInt s.partyLevel
        )
    , testRow "Difficulty" (formatDifficulty s.difficulty)
    , testRow "Suggested budget"
        ("≈ "
            ++ String.fromInt s.budgetAtSuggestion
            ++ " XP  (group natural range "
            ++ String.fromInt s.minXp
            ++ "–"
            ++ String.fromInt s.maxXp
            ++ " XP)"
        )
    ]


testRow : String -> String -> Html Msg
testRow label_ value_ =
    div [ class "group-edit__lore-test-row" ]
        [ span [ class "group-edit__lore-test-row-label" ] [ text label_ ]
        , span [ class "group-edit__lore-test-row-value" ] [ text value_ ]
        ]


formatHabitats : List Compendium.Habitat -> String
formatHabitats habitats =
    if List.isEmpty habitats then
        "Any (none of the members carry habitat tags)"

    else
        String.join ", " (List.map Compendium.habitatLabel habitats)


formatTypes : List String -> String
formatTypes types =
    if List.isEmpty types then
        "Any"

    else
        String.join ", " types


formatDifficulty : Encounter.Difficulty.Difficulty -> String
formatDifficulty d =
    case d of
        Encounter.Difficulty.LowDifficulty ->
            "Low"

        Encounter.Difficulty.HighDifficulty ->
            "High"

        _ ->
            "Moderate"


unresolvedBanner : List String -> List (Html Msg)
unresolvedBanner names =
    if List.isEmpty names then
        []

    else
        [ p [ class "group-edit__lore-test-unresolved" ]
            [ text
                ("⚠  Couldn't find these members in the compendium: "
                    ++ String.join ", " names
                    ++ ".  The generator silently drops unresolved members, so the recommendation above only reflects the rest."
                )
            ]
        ]
