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
import Html
    exposing
        ( Html
        , button
        , div
        , input
        , label
        , option
        , p
        , select
        , span
        , text
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
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.GroupEdit as GroupEdit exposing (EntryDraft, GroupEditMode(..), GroupEditUi)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalGroupEdit ui) ->
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
