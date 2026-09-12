module View.Inline.Condition exposing (Context, view)

{-| Condition / effect editor body. It opens in the editor
column's drawer, so the queue stays visible while the GM fills
it in.
-}

import Dict exposing (Dict)
import Encounter
import Html exposing (Html, button, div, h3, input, span, text)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, for, id, maxlength, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (DurationKind(..), Msg(..))
import Set exposing (Set)
import Ui.Condition exposing (ConditionLogEntry, ConditionPreset, ConditionUi, SaveToEndUi)
import Ui.Condition.Bundled as Bundled
import Update.Condition
import View.ConditionLog
import View.Inline.ApplyButton as ApplyButton
import View.Inline.Field as Field
import View.PhaseToggle
import View.Tooltips as Tooltips


{-| The model fragments the expansion consumes beyond its own
Ui record: the queue's creature names feed the "until X's turn"
select, the selected count drives the apply-to-selected scope,
and the presets dict backs the Load row.
-}
type alias Context =
    { creatureNames : List String
    , selectedCount : Int
    , placeholderWarning : Bool
    , presets : Dict String ConditionPreset
    , log : List ConditionLogEntry
    , logOpen : Bool
    , expanded : Set String
    }


view : Context -> ConditionUi -> Html Msg
view ctx ui =
    div [ class "editor-body" ]
        [ loadRow ui ctx.presets
        , standardSection ui
        , customAndNoteSection ui
        , durationSection ui ctx.creatureNames
        , saveSection ui
        , footer ui ctx.selectedCount ctx.placeholderWarning
        , View.ConditionLog.section { open = ctx.logOpen, expanded = ctx.expanded } ctx.log
        ]


{-| The preset picker comes first, under the target strip, so a
saved recipe is the first thing to reach for.
-}
loadRow : ConditionUi -> Dict String ConditionPreset -> Html Msg
loadRow ui presets =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ] [ presetLoadControl ui presets ] ]


standardSection : ConditionUi -> Html Msg
standardSection ui =
    div [ class "cond-section" ]
        [ div [ class "cond-radio-grid" ]
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
        , if isSelected then
            quickApplyCaret

          else
            text ""
        ]


{-| Applies the picked condition alone and folds the editor. It
takes the right edge of whatever names the condition, so the fast
path is a column of its own rather than something crowding the
name.
-}
quickApplyCaret : Html Msg
quickApplyCaret =
    button
        [ class "cond-quick-apply"
        , type_ "button"
        , onClick ConditionQuickApply
        , Tooltips.attr Tooltips.conditionQuickApply
        , attribute "aria-label" Tooltips.conditionQuickApply
        ]
        [ text "▶" ]


{-| Free-text condition name and note, each on its own labelled
row (an input wraps under its label when the editor is narrow).
The custom row hides while a standard-condition radio is
selected — the radio owns the name then, and re-clicking the
selected radio clears it to bring the row back.
-}
customAndNoteSection : ConditionUi -> Html Msg
customAndNoteSection ui =
    let
        customHidden =
            String.isEmpty ui.customName && not (String.isEmpty ui.name)
    in
    div [ class "cond-section" ]
        ((if customHidden then
            []

          else
            [ div [ class "cond-row" ]
                [ Html.label [ class "cond-label" ] [ text "Custom:" ]
                , input
                    [ class "cond-input cond-input--w20"
                    , type_ "text"
                    , value ui.customName
                    , maxlength Update.Condition.maxConditionNoteLength
                    , placeholder "e.g. Burning"
                    , onInput ConditionCustomNameChanged
                    ]
                    []
                , if String.isEmpty (String.trim ui.customName) then
                    text ""

                  else
                    quickApplyCaret
                ]
            , div [ class "cond-divider" ] []
            ]
         )
            ++ [ div [ class "cond-row" ]
                    [ Html.label [ class "cond-label" ] [ text "Note:" ]
                    , input
                        [ class "cond-input cond-input--w20"
                        , type_ "text"
                        , value ui.note
                        , maxlength Update.Condition.maxConditionNoteLength
                        , placeholder "e.g. from Lyra"
                        , onInput ConditionNoteChanged
                        ]
                        []
                    ]
               ]
        )


durationSection : ConditionUi -> List String -> Html Msg
durationSection ui creatureNames =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Duration:" ]
            , durationKindRadio ui DurKindManual "Manual"
            , durationKindRadio ui DurKindUntilTurn "Next turn"
            , durationKindRadio ui DurKindThisTurn "This turn"
            , durationKindRadio ui DurKindCountdown "Countdown"
            , oneMinutePresetRadio ui
            ]
        , if ui.useOneMinutePreset then
            div [ class "cond-section__caption" ]
                [ text "Expires at the end of the bearer's 10th turn." ]

          else
            case ui.durationKind of
                DurKindManual ->
                    text ""

                DurKindUntilTurn ->
                    durationUntilSubsection ui creatureNames

                DurKindThisTurn ->
                    div [ class "cond-section__caption" ]
                        [ text "Expires at the end of the target's current turn." ]

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
"At [begin|end] of [Creature]'s next turn".
-}
durationUntilSubsection : ConditionUi -> List String -> Html Msg
durationUntilSubsection ui creatureNames =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "At" ]
            , View.PhaseToggle.view "until-phase" ui.untilPhase ConditionUntilPhaseSet
            , Html.label [ class "cond-label" ] [ text "of" ]
            , Html.select
                [ class "cond-select"
                , onInput ConditionUntilCreatureChanged
                ]
                (List.map
                    (\name ->
                        Html.option
                            [ value name
                            , Attr.selected (name == ui.untilCreature)
                            ]
                            [ text name ]
                    )
                    creatureNames
                )
            , Html.label [ class "cond-label" ] [ text "'s next turn" ]
            ]
        ]


durationCountdownSubsection : ConditionUi -> Html Msg
durationCountdownSubsection ui =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-countdown-turns", class "cond-label" ]
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
            , Html.label [ class "cond-label" ] [ text "turns, ticking at" ]
            , View.PhaseToggle.view "countdown-phase" ui.countdownPhase ConditionCountdownPhaseSet
            , Html.label [ class "cond-label" ] [ text "of the bearer's turn" ]
            ]
        , div [ class "cond-section__caption" ]
            [ Html.em [] [ text "Countdown timer begins when active creature's turn ends." ] ]
        ]


saveSection : ConditionUi -> Html Msg
saveSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ Field.checkbox
                { checked = ui.saveToEnd /= Nothing
                , msg = ConditionSaveToggle
                , label = "Saving throw to end"
                , extra = []
                }
            ]
        , case ui.saveToEnd of
            Nothing ->
                text ""

            Just s ->
                saveSubsection s
        ]


saveSubsection : SaveToEndUi -> Html Msg
saveSubsection s =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-save-ability", class "cond-label" ] [ text "Ability" ]
            , Html.select
                [ id "cond-save-ability"
                , class "cond-select cond-select--save"
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
            , Html.label [ for "cond-save-dc", class "cond-label" ] [ text "DC" ]
            , input
                [ id "cond-save-dc"
                , class "cond-input cond-input--2ch cond-input--save"
                , type_ "text"
                , maxlength 2
                , value s.dcText
                , onInput ConditionSaveDcChanged
                ]
                []
            , Html.label [ for "cond-save-bonus", class "cond-label" ] [ text "Mod" ]
            , span [ class "cond-spin-wrap" ]
                [ input
                    [ id "cond-save-bonus"
                    , class "cond-input cond-input--2ch cond-input--save"
                    , type_ "text"
                    , maxlength 2
                    , value s.bonusText
                    , onInput ConditionSaveBonusChanged
                    ]
                    []
                , Field.spin
                    { up = ConditionSaveBonusAdjust 1
                    , down = ConditionSaveBonusAdjust -1
                    , what = "modifier"
                    }
                ]
            ]
        , div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Auto-roll:" ]
            , autoRollRadio s [] Encounter.AutoRollManual "Manual"
            , autoRollRadio s [] Encounter.AutoRollAtBegin "Start of turn"
            , autoRollRadio s [] Encounter.AutoRollAtEnd "End of turn"
            , autoRollRadio s [ Tooltips.attr Tooltips.saveAskAtEnd ] Encounter.AutoRollAskAtEnd "Ask at end of turn"
            ]
        , failedSaveRow s
        , onDamageRow s
        ]


{-| What taking damage does to the save: nothing, a flash of the
chip for the GM to judge the trigger, or a roll fired at once.
-}
onDamageRow : SaveToEndUi -> Html Msg
onDamageRow s =
    div [ class "cond-row" ]
        [ Html.label [ class "cond-label" ] [ text "When damaged:" ]
        , onDamageRadio s [] Encounter.NoDamageTrigger "Nothing"
        , onDamageRadio s [ Tooltips.attr Tooltips.saveFlashOnDamage ] Encounter.AskOnDamage "Flash the chip"
        , onDamageRadio s [] Encounter.RollOnDamage "Roll the save"
        , onDamageRadio s [] Encounter.RollOnDamageWithAdvantage "Roll with advantage"
        ]


onDamageRadio : SaveToEndUi -> List (Html.Attribute Msg) -> Encounter.DamageTrigger -> String -> Html Msg
onDamageRadio s extra trigger label =
    Field.radioWith extra
        { group = "cond-save-ondamage"
        , selected = s.onDamage == trigger
        , msg = ConditionSaveOnDamageSet trigger
        , label = label
        }


{-| What a failed save does besides leaving the condition in
place; both fields blank by default.
-}
failedSaveRow : SaveToEndUi -> Html Msg
failedSaveRow s =
    div [ class "cond-row" ]
        [ Html.label [ class "cond-label" ] [ text "On a failed save:" ]
        , Html.label [ for "cond-fail-damage", class "cond-label" ] [ text "takes" ]
        , input
            [ id "cond-fail-damage"
            , class "cond-input cond-input--narrow"
            , type_ "text"
            , placeholder "4d10"
            , value s.failDamageText
            , onInput ConditionSaveFailDamageChanged
            , Tooltips.attr "Damage the bearer takes on each failed save — a dice formula or a number"
            ]
            []
        , span [ class "cond-pair cond-pair--grow" ]
            [ Html.label [ for "cond-fail-becomes", class "cond-label" ] [ text "& becomes" ]
            , input
                [ id "cond-fail-becomes"
                , class "cond-input cond-input--grow"
                , type_ "text"
                , placeholder "e.g. Petrified (optional)"
                , value s.failBecomesText
                , onInput ConditionSaveFailBecomesChanged
                , attribute "list" "cond-fail-becomes-list"
                , Tooltips.attr "The condition this one turns into on a failed save, which ends the saving"
                ]
                []
            ]
        , Html.node "datalist"
            [ id "cond-fail-becomes-list" ]
            (List.map (\c -> Html.option [ value c ] []) Encounter.standardConditions)
        ]


{-| Plain radio — a bare dot and its label, not the bordered pill
`.cond-radio` renders elsewhere in this editor. The timing choices
read as a classic radio row better than as a row of chips.
-}
autoRollRadio : SaveToEndUi -> List (Html.Attribute Msg) -> Encounter.AutoRollMode -> String -> Html Msg
autoRollRadio s extra mode label =
    Field.radioWith extra
        { group = "cond-save-autoroll"
        , selected = s.autoRoll == mode
        , msg = ConditionSaveAutoRollSet mode
        , label = label
        }


footer : ConditionUi -> Int -> Bool -> Html Msg
footer ui selectedCount placeholderWarning =
    let
        canSubmit =
            not (String.isEmpty (String.trim ui.name))

        applyLabel =
            if ui.editingId == Nothing then
                "Target"

            else
                "Apply Changes"

        -- Delete (when editing) precedes Apply so Apply is always
        -- the last row — the commit action reads as the final
        -- word on the panel, not something with more choices
        -- beneath it. It's omitted entirely rather than rendered
        -- empty when there's nothing to delete, so it doesn't
        -- claim a row of its own in the now-stacked footer.
        deleteRow =
            case ui.editingId of
                Just _ ->
                    [ div [ class "cond-footer__actions" ]
                        [ button
                            [ class "action-btn action-btn--damage"
                            , onClick ConditionDelete
                            , Tooltips.attr Tooltips.chipRemoveModalRow
                            ]
                            [ text "Delete" ]
                        ]
                    ]

                Nothing ->
                    []

        placeholderRow =
            if placeholderWarning then
                [ ApplyButton.placeholderNotice True ]

            else
                []
    in
    div [ class "cond-footer" ]
        (presetControls canSubmit
            ++ deleteRow
            ++ [ applyControls ui canSubmit selectedCount applyLabel ]
            ++ placeholderRow
        )


{-| The preset row. Naming one happens in a modal, so the editor
keeps only what opens it.
-}
presetControls : Bool -> List (Html Msg)
presetControls canSubmit =
    let
        clearButton =
            button
                [ class "action-btn"
                , onClick ConditionClear
                , Tooltips.attr "Empty every setting and start over"
                ]
                [ text "Clear Settings" ]
    in
    [ div [ class "cond-row" ]
        [ button
            [ class "action-btn"
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
                    Tooltips.conditionPresetSaveStart

                 else
                    Tooltips.conditionPresetSaveStartBlocked
                )
            ]
            [ text "Save Settings" ]
        , clearButton
        ]
    ]


{-| The commit row. Editing an existing condition is a one-row
operation — there is nothing a selection could mean there — so
that mode commits with a single button and no scope lead-in.
-}
applyControls : ConditionUi -> Bool -> Int -> String -> Html Msg
applyControls ui canSubmit selectedCount applyLabel =
    let
        commit =
            ApplyButton.view
                { enabled = canSubmit
                , cls = "action-btn action-btn--green"
                , msg = ConditionSubmit
                , tip =
                    if canSubmit then
                        applyLabel

                    else
                        "Pick a condition or type a custom name first"
                , label = applyLabel
                }
    in
    if ui.editingId /= Nothing then
        div [ class "note-edit__buttons note-edit__buttons--start" ] [ commit ]

    else
        ApplyButton.row "Apply to:"
            [ commit
            , ApplyButton.view
                { enabled = canSubmit && selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = ConditionSubmitSelected
                , tip =
                    if not canSubmit then
                        "Pick a condition or type a custom name first"

                    else if selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Give every selected creature its own copy"
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]


{-| Load button + dropdown menu. Button stays disabled when the
presets dict is empty and the menu's `stopPropagationOn
"mousedown"` keeps internal clicks from bubbling to the
document-level click-outside handler in `Main.subscriptions`.
-}
presetLoadControl : ConditionUi -> Dict String ConditionPreset -> Html Msg
presetLoadControl ui userPresets =
    let
        -- Bundled SRD defaults are always available as a
        -- read-only layer underneath the user's own dict.  User
        -- entries override bundled ones with the same name
        -- (`Dict.union` keeps left-hand keys on collision).
        displayPresets =
            Dict.union userPresets Bundled.defaults

        empty =
            Dict.isEmpty displayPresets

        userNames =
            -- Legacy: presets saved before the required-category
            -- pass landed with `category = ""` and surface in a
            -- flat list above the categorized sections.
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
            [ text "Load ▼" ]
        , if ui.loadMenuOpen && not empty then
            div
                [ class "cond-footer__load-menu cond-footer__load-menu--below"
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
                "▼"

            else
                "▶"
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
SRD defaults are read-only.
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
