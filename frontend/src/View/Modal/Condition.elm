module View.Modal.Condition exposing (view)

{-| Condition / effect modal. Sections, top to bottom:
standard-condition radios, custom name input, note input, duration
choice (Manual / Until turn / Countdown) with the relevant
sub-controls, optional save-to-end block, multi-target apply scope,
and the action footer (Apply / Cancel / Delete-when-editing).
-}

import Dict exposing (Dict)
import Encounter exposing (Encounter)
import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes as Attr exposing (attribute, autofocus, checked, class, disabled, for, id, maxlength, placeholder, type_, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( DurationKind(..)
        , Msg(..)
        )
import Set
import Ui.Condition exposing (ConditionPreset, ConditionUi, SaveToEndUi)
import Ui.Condition.Bundled as Bundled
import Update.Condition
import View.Modal
import View.PhaseToggle
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalCondition ui) ->
            let
                presetSuffix =
                    case ui.loadedPresetName of
                        Just name ->
                            "  (loaded: " ++ name ++ ")"

                        Nothing ->
                            ""

                modalTitle =
                    (if ui.editingId == Nothing then
                        "Add Condition — "

                     else
                        "Edit Condition — "
                    )
                        ++ ui.target
                        ++ presetSuffix
            in
            View.Modal.view
                { close = ConditionClose
                , noOp = NoOp
                , title = modalTitle
                , extraClass = "modal--condition"
                , chrome = model.modalChrome
                , body =
                    [ standardSection ui
                    , customSection ui
                    , noteSection ui
                    , durationSection ui model
                    , saveSection ui
                    , applyScope ui model.encounter
                    , footer ui model.conditionPresets
                    ]
                }

        _ ->
            text ""


{-| Multi-target scope checkbox for the condition modal. Same
shape as the HP-change apply scope: hidden when no creatures are
selected, otherwise a toggle that splatters a fresh copy of the
new condition onto every selected creature (each gets its own id).

Hidden entirely when editing an existing condition — you're
modifying one specific row, not creating new ones in bulk.

-}
applyScope : ConditionUi -> Encounter -> Html Msg
applyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
    if ui.editingId /= Nothing || selectedCount == 0 then
        text ""

    else
        div [ class "cond-section" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick ConditionApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            , div [ class "cond-section__caption" ]
                [ text "Each selected creature gets its own copy of the condition (separate ids, independent durations)." ]
            ]


standardSection : ConditionUi -> Html Msg
standardSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Select a condition:" ]
        , div [ class "cond-radio-grid" ]
            (List.map (standardRadio ui) Encounter.standardConditions)
        ]


standardRadio : ConditionUi -> String -> Html Msg
standardRadio ui label =
    let
        isSelected =
            ui.name == label
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "condition-radio"
            , checked isSelected
            , onClick (ConditionPickStandard label)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


customSection : ConditionUi -> Html Msg
customSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "or, Custom:" ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.customName
            , placeholder "e.g. Bardic Inspiration, Burning"
            , onInput ConditionCustomNameChanged
            ]
            []
        , div [ class "cond-section__caption" ]
            [ text "Typing here overrides the radio selection above." ]
        ]


noteSection : ConditionUi -> Html Msg
noteSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text ("Note (max " ++ String.fromInt Update.Condition.maxConditionNoteLength ++ " chars)") ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.note
            , maxlength Update.Condition.maxConditionNoteLength
            , placeholder "e.g. from Lyra"
            , onInput ConditionNoteChanged
            ]
            []
        ]


durationSection : ConditionUi -> Model -> Html Msg
durationSection ui model =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Duration" ]
        , div [ class "cond-radio-row" ]
            [ durationKindRadio ui DurKindManual "Manual"
            , durationKindRadio ui DurKindUntilTurn "Next turn"
            , durationKindRadio ui DurKindCountdown "Countdown"
            , oneMinutePresetRadio ui
            ]
        , if ui.useOneMinutePreset then
            div [ class "cond-section__caption" ]
                [ text "Lasts 10 turns; expires at the end of the bearer's 10th turn." ]

          else
            case ui.durationKind of
                DurKindManual ->
                    div [ class "cond-section__caption" ]
                        [ text "Stays until the GM clicks the chip's × to remove." ]

                DurKindUntilTurn ->
                    durationUntilSubsection ui model

                DurKindCountdown ->
                    durationCountdownSubsection ui
        ]


durationKindRadio : ConditionUi -> DurationKind -> String -> Html Msg
durationKindRadio ui kind label =
    let
        -- Countdown radio yields its highlight to the 1-Minute
        -- preset when the preset flag is on (they share the
        -- underlying DurKindCountdown value).
        isSelected =
            ui.durationKind == kind && not ui.useOneMinutePreset
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "duration-kind"
            , checked isSelected
            , onClick (ConditionDurationKindSet kind)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


oneMinutePresetRadio : ConditionUi -> Html Msg
oneMinutePresetRadio ui =
    Html.label
        [ class
            (if ui.useOneMinutePreset then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "duration-kind"
            , checked ui.useOneMinutePreset
            , onClick ConditionDurationOneMinute
            ]
            []
        , span [ class "cond-radio__label" ] [ text "1 Minute" ]
        ]


{-| The "until ..." duration row. Reads as a sentence:
"At [begin|end] of [Creature]'s next turn". Always "next turn"
— the previous current/next selector was removed in favor of
context-aware resolution at submit time
(=Update.Condition.nextTurnTarget=).
-}
durationUntilSubsection : ConditionUi -> Model -> Html Msg
durationUntilSubsection ui model =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [] [ text "At" ]
            , View.PhaseToggle.view "until-phase" ui.untilPhase ConditionUntilPhaseSet
            , Html.label [] [ text "of" ]
            , Html.select
                [ class "cond-select"
                , onInput ConditionUntilCreatureChanged
                ]
                (List.map
                    (\c ->
                        Html.option
                            [ value c.name
                            , Attr.selected (c.name == ui.untilCreature)
                            ]
                            [ text c.name ]
                    )
                    model.encounter.creatures
                )
            , Html.label [] [ text "'s next turn" ]
            ]
        ]


durationCountdownSubsection : ConditionUi -> Html Msg
durationCountdownSubsection ui =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-countdown-turns" ]
                [ text "Lasts" ]
            , input
                [ id "cond-countdown-turns"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "99"
                , value ui.countdownTurnsText
                , onInput ConditionCountdownTurnsChanged
                ]
                []
            , Html.label [] [ text "turns, ticking at" ]
            , View.PhaseToggle.view "countdown-phase" ui.countdownPhase ConditionCountdownPhaseSet
            , Html.label [] [ text "of the bearer's turn" ]
            ]
        , div [ class "cond-section__caption" ]
            [ text
                ("If you set 'end' while it's already this creature's turn, "
                    ++ "the countdown skips this end-of-turn so they get a "
                    ++ "full first turn under the effect."
                )
            ]
        ]


saveSection : ConditionUi -> Html Msg
saveSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ Html.label []
                [ input
                    [ type_ "checkbox"
                    , checked (ui.saveToEnd /= Nothing)
                    , onClick ConditionSaveToggle
                    ]
                    []
                , text " Save-to-end"
                ]
            ]
        , case ui.saveToEnd of
            Nothing ->
                div [ class "cond-section__caption" ]
                    [ text "Optional: condition can end on a successful saving throw." ]

            Just s ->
                saveSubsection s
        ]


saveSubsection : SaveToEndUi -> Html Msg
saveSubsection s =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-save-ability" ] [ text "Ability" ]
            , Html.select
                [ id "cond-save-ability"
                , class "cond-select"
                , onInput ConditionSaveAbilityChanged
                ]
                (List.map
                    (\a ->
                        Html.option
                            [ value a
                            , Attr.selected (a == s.ability)
                            ]
                            [ text a ]
                    )
                    [ "STR", "DEX", "CON", "INT", "WIS", "CHA" ]
                )
            , Html.label [ for "cond-save-dc" ] [ text "DC" ]
            , input
                [ id "cond-save-dc"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "40"
                , value s.dcText
                , onInput ConditionSaveDcChanged
                ]
                []
            , Html.label [ for "cond-save-bonus" ] [ text "Bonus" ]
            , input
                [ id "cond-save-bonus"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Attr.min "-10"
                , Attr.max "20"
                , value s.bonusText
                , onInput ConditionSaveBonusChanged
                ]
                []
            ]
        , div [ class "cond-radio-stack" ]
            [ autoRollRadio s
                Encounter.AutoRollManual
                "Manual (no auto-roll — GM clicks 🎲 on the chip)"
            , autoRollRadio s
                Encounter.AutoRollAtBegin
                "Auto-roll at the bearer's beginning-of-turn"
            , autoRollRadio s
                Encounter.AutoRollAtEnd
                "Auto-roll at the bearer's end-of-turn"
            ]
        , div [ class "cond-section__caption" ]
            [ text (autoRollCaption s.autoRoll) ]
        ]


{-| One radio button in the auto-roll mode group. Shares the
.cond-radio chrome with the other radio groups in the modal.
-}
autoRollRadio : SaveToEndUi -> Encounter.AutoRollMode -> String -> Html Msg
autoRollRadio s mode label =
    let
        isSelected =
            s.autoRoll == mode
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Attr.name "cond-save-autoroll"
            , checked isSelected
            , onClick (ConditionSaveAutoRollSet mode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


{-| Caption text under the auto-roll radio group describing what
will actually happen in play. Updates live with the selection so
the GM can see the consequence without clicking submit.
-}
autoRollCaption : Encounter.AutoRollMode -> String
autoRollCaption mode =
    case mode of
        Encounter.AutoRollManual ->
            "The 🎲 button on the chip rolls manually — a reminder, not auto-applied."

        Encounter.AutoRollAtBegin ->
            "Save fires at the start of the bearer's turn; success removes the condition."

        Encounter.AutoRollAtEnd ->
            "Save fires at the end of the bearer's turn; success removes the condition."


footer : ConditionUi -> Dict String ConditionPreset -> Html Msg
footer ui presets =
    let
        canSubmit =
            not (String.isEmpty (String.trim ui.name))

        applyLabel =
            if ui.editingId == Nothing then
                "Apply"

            else
                "Save Changes"
    in
    div [ class "cond-footer" ]
        [ div [ class "cond-footer__presets" ]
            [ presetSaveControl ui canSubmit
            , presetLoadControl ui presets
            ]
        , div [ class "cond-footer__actions" ]
            [ case ui.editingId of
                Just _ ->
                    button
                        [ class "action-btn action-btn--damage"
                        , onClick ConditionDelete
                        , Tooltips.attr Tooltips.chipRemoveModalRow
                        ]
                        [ text "Delete" ]

                Nothing ->
                    text ""
            , button
                [ class "action-btn"
                , onClick ConditionClose
                ]
                [ text "Cancel" ]
            , button
                [ class "action-btn action-btn--green"
                , onClick ConditionSubmit
                , disabled (not canSubmit)
                , attribute "aria-disabled"
                    (if canSubmit then
                        "false"

                     else
                        "true"
                    )
                , Tooltips.attr
                    (if canSubmit then
                        applyLabel

                     else
                        "Pick a condition or type a custom name first"
                    )
                ]
                [ text applyLabel ]
            ]
        ]


{-| Save button + inline name prompt. When `pendingSaveName` is
`Nothing` the button reads "Save"; clicking it reveals the name
input and switches the buttons to `[name][Save][Cancel]`. The
Save submit is disabled until the typed name is non-empty (after
trim) AND the underlying form has a condition name set (no point
saving an empty preset).

The name input gets `autofocus` and an Enter keydown handler so a
quick GM workflow is: click Save → type "Stun" → press Enter →
preset stored.

-}
presetSaveControl : ConditionUi -> Bool -> Html Msg
presetSaveControl ui canSubmit =
    case ui.pendingSaveName of
        Nothing ->
            button
                [ class "action-btn cond-footer__save"
                , onClick ConditionPresetSaveStart
                , disabled (not canSubmit)
                , attribute "aria-disabled"
                    (if canSubmit then
                        "false"

                     else
                        "true"
                    )
                , Tooltips.attr
                    (if canSubmit then
                        "Save this configuration as a named preset"

                     else
                        "Pick a condition first, then Save the preset"
                    )
                ]
                [ text "Save" ]

        Just typed ->
            let
                trimmed =
                    String.trim typed

                categoryPicked =
                    not (String.isEmpty (String.trim ui.pendingSaveCategory))

                canSaveName =
                    not (String.isEmpty trimmed) && categoryPicked && canSubmit

                disabledReason =
                    if String.isEmpty trimmed then
                        "Type a name first"

                    else if not categoryPicked then
                        "Pick a category first"

                    else
                        "Save preset"
            in
            div [ class "cond-footer__save-row" ]
                [ input
                    [ class "cond-input cond-footer__save-input"
                    , type_ "text"
                    , value typed
                    , placeholder "Name this preset"
                    , autofocus True
                    , onInput ConditionPresetSaveNameChanged
                    , on "keydown" (enterKeyDecoder ConditionPresetSaveSubmit)
                    ]
                    []
                , Html.select
                    [ class "cond-input cond-footer__save-category"
                    , onInput ConditionPresetSaveCategoryChanged
                    , attribute "aria-label" "Category"
                    , Tooltips.attr "Pick a category for this preset"
                    ]
                    (Html.option
                        [ value ""
                        , Attr.selected (String.isEmpty ui.pendingSaveCategory)
                        , Attr.disabled True
                        ]
                        [ text "Pick category…" ]
                        :: List.map (categoryOption ui.pendingSaveCategory) Bundled.categories
                    )
                , button
                    [ class "action-btn action-btn--green"
                    , onClick ConditionPresetSaveSubmit
                    , disabled (not canSaveName)
                    , Tooltips.attr disabledReason
                    ]
                    [ text "Save" ]
                , button
                    [ class "action-btn"
                    , onClick ConditionPresetSaveCancel
                    , Tooltips.attr "Cancel"
                    ]
                    [ text "Cancel" ]
                ]


categoryOption : String -> String -> Html Msg
categoryOption pickedCategory category =
    Html.option
        [ value category
        , Attr.selected (pickedCategory == category)
        ]
        [ text category ]


enterKeyDecoder : Msg -> Decode.Decoder Msg
enterKeyDecoder msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                if key == "Enter" then
                    Decode.succeed msg

                else
                    Decode.fail "ignored key"
            )


{-| Load button + dropdown menu. Button stays disabled when the
presets dict is empty (nothing to load) and the menu's
`stopPropagationOn "mousedown"` keeps internal clicks from
bubbling to the document-level click-outside handler in
`Main.subscriptions`.

Menu layout:

  - The user's own presets (`category == ""`) render as a flat
    list at the top, alphabetical, no section header.
  - Below that, the four bundled categories from
    `Ui.Condition.Bundled.categories` render in fixed order,
    each as a collapsible section that starts collapsed. The
    section header shows a disclosure triangle, the category
    label, and the count of presets inside.

Each preset row is a `[name button][× delete]` pair. Clicking
the name fires `ConditionPresetLoad`; the × fires
`ConditionPresetDelete` and is `stopPropagationOn`'d so a misclick
on the × inside an otherwise-load row doesn't double-fire.

-}
presetLoadControl : ConditionUi -> Dict String ConditionPreset -> Html Msg
presetLoadControl ui userPresets =
    let
        -- Bundled SRD defaults are always available as a
        -- read-only layer underneath the user's own dict.  User
        -- entries override bundled ones with the same name
        -- (`Dict.union` keeps left-hand keys on collision).  That
        -- way the four collapsible category sections always
        -- render even when the user has saved nothing of their
        -- own — which fixes the "Load greyed out" case when
        -- `localStorage.conditionPresets` exists but is `{}`.
        displayPresets =
            Dict.union userPresets Bundled.defaults

        empty =
            Dict.isEmpty displayPresets

        userNames =
            -- Legacy: presets saved before the required-category
            -- pass landed with `category = ""` and surface in a
            -- flat list above the categorized sections.  Newly
            -- saved presets always carry a category and land in
            -- their group instead.
            userPresets
                |> Dict.filter (\_ p -> p.category == "")
                |> Dict.keys
                |> List.sortBy String.toLower

        categorizedSections =
            Bundled.categories
                |> List.map (categorySection ui userPresets displayPresets)
    in
    div
        [ class "cond-footer__load-wrap"
        , stopPropagationOn "mousedown" (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class "action-btn cond-footer__load"
            , onClick ConditionPresetLoadMenuToggle
            , disabled empty
            , attribute "aria-haspopup" "listbox"
            , attribute "aria-expanded"
                (if ui.loadMenuOpen then
                    "true"

                 else
                    "false"
                )
            , Tooltips.attr
                (if empty then
                    "No saved presets yet — click Save first"

                 else
                    "Load a saved preset"
                )
            ]
            [ text "Load ▾" ]
        , if ui.loadMenuOpen && not empty then
            div
                [ class "cond-footer__load-menu"
                , attribute "role" "listbox"
                ]
                (List.map (presetMenuItem True) userNames ++ categorizedSections)

          else
            text ""
        ]


categorySection : ConditionUi -> Dict String ConditionPreset -> Dict String ConditionPreset -> String -> Html Msg
categorySection ui userPresets displayPresets category =
    let
        names =
            displayPresets
                |> Dict.filter (\_ p -> p.category == category)
                |> Dict.keys
                |> List.sortBy String.toLower

        expanded =
            Set.member category ui.expandedCategories

        triangle =
            if expanded then
                "▾"

            else
                "▸"
    in
    div [ class "cond-footer__load-category" ]
        [ button
            [ class "cond-footer__load-category-header"
            , onClick (ConditionPresetCategoryToggle category)
            , attribute "aria-expanded"
                (if expanded then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ class "cond-footer__load-category-triangle" ] [ text triangle ]
            , span [ class "cond-footer__load-category-label" ] [ text category ]
            , span [ class "cond-footer__load-category-count" ]
                [ text (" (" ++ String.fromInt (List.length names) ++ ")") ]
            ]
        , if expanded then
            div [ class "cond-footer__load-category-body" ]
                (List.map (\n -> presetMenuItem (Dict.member n userPresets) n) names)

          else
            text ""
        ]


{-| One menu row. `isDeletable` controls whether the trailing ×
button renders — only user-saved presets can be deleted; bundled
SRD defaults are read-only and the × is omitted on those rows so
the only way to "remove" a bundled is to override it by saving
a user preset with the same name.
-}
presetMenuItem : Bool -> String -> Html Msg
presetMenuItem isDeletable name =
    div [ class "cond-footer__load-item" ]
        [ button
            [ class "cond-footer__load-item-name"
            , onClick (ConditionPresetLoad name)
            , Tooltips.attr ("Load preset: " ++ name)
            , attribute "role" "option"
            ]
            [ text name ]
        , if isDeletable then
            button
                [ class "cond-footer__load-item-delete"
                , stopPropagationOn "click"
                    (Decode.succeed ( ConditionPresetDelete name, True ))
                , Tooltips.attr ("Delete preset: " ++ name)
                , attribute "aria-label" ("Delete preset " ++ name)
                ]
                [ text "×" ]

          else
            text ""
        ]
