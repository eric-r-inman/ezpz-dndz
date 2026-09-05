module View.Inline.SaveChain exposing (Context, view)

{-| Save Chain as an inline card expansion: a reusable "creature
makes a save; something happens" recipe, saveable as a preset,
with one outcome per side of the save.

Applying never closes the editor. A GM usually runs both sides
on the same open — fail for the creatures that missed, pass for
the survivors.

-}

import Compendium exposing (Ability(..))
import Dict
import Encounter
import Encounter.SaveChain as SaveChain exposing (EffectApply, HpEffect(..))
import Html exposing (Html, button, div, input, li, option, p, select, span, text, ul)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, name, placeholder, selected, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Json.Decode as Decode
import Msg
    exposing
        ( Msg(..)
        , SaveChainHpKind(..)
        , SaveChainRollMode(..)
        , SaveChainSide(..)
        )
import Ui.SaveChain exposing (AppliedPart(..), OutcomeForm, SaveChainLogEntry, SaveChainUi)
import View.Tooltips as Tooltips


{-| The model fragments the expansion consumes beyond its own
Ui record: the presets dict backs the picker row, the selected
count drives the apply-to-selected scope and the header title,
and the log renders the recent resolutions.
-}
type alias Context =
    { presets : Dict.Dict String SaveChain.SaveChain
    , selectedCount : Int
    , log : List SaveChainLogEntry
    }


view : Context -> SaveChainUi -> Html Msg
view ctx ui =
    div [ class "creature-card__inline" ]
        [ presetRow ui ctx.presets
        , nameRow ui
        , saveRow ui
        , outcomeBlock "On failed save" SaveChainFail ui.onFail
        , outcomeBlock "On successful save" SaveChainSuccess ui.onSuccess
        , applyScope ctx.selectedCount ui
        , applyRow ui
        , log ctx.log
        ]



-- ── Preset picker ───────────────────────────────────────────────


presetRow : SaveChainUi -> Dict.Dict String SaveChain.SaveChain -> Html Msg
presetRow ui presets =
    let
        names =
            Dict.keys presets

        placeholderOption =
            option [ value "" ] [ text "— pick a saved chain —" ]

        options =
            placeholderOption
                :: List.map
                    (\n ->
                        option
                            [ value n
                            , selected (n == ui.presetPickerSelection)
                            ]
                            [ text n ]
                    )
                    names

        loadedTag =
            case ui.loadedPresetName of
                Just n ->
                    span [ class "save-chain__loaded-tag" ]
                        [ text ("Loaded: " ++ n) ]

                Nothing ->
                    text ""
    in
    div [ class "save-chain__preset-row" ]
        [ span [ class "save-chain__field-label" ] [ text "Preset" ]
        , select
            [ class "save-chain__preset-picker"
            , onInput SaveChainPresetPickerChanged
            ]
            options
        , button
            [ class "action-btn action-btn--sm action-btn--red"
            , type_ "button"
            , onClick SaveChainPresetDelete
            , disabled (ui.loadedPresetName == Nothing && String.isEmpty ui.presetPickerSelection)
            ]
            [ text "Delete" ]
        , button
            [ class "action-btn action-btn--sm"
            , type_ "button"
            , onClick SaveChainReset
            ]
            [ text "+ New" ]
        , button
            [ class "action-btn action-btn--sm"
            , type_ "button"
            , onClick SaveChainRestoreBundled
            , Tooltips.attr "Overwrite every bundled preset with its current definition AND remove stale duplicates left over from earlier naming (e.g. \"Hold Person (2nd)\" is dropped when \"Hold Person\" is the current bundled key).  Your own presets are untouched."
            ]
            [ text "🔄 Restore bundled" ]
        , button
            [ class "action-btn action-btn--sm"
            , type_ "button"
            , onClick SaveChainExportBundled
            , Tooltips.attr "Copy the currently-open form as an Elm SaveChain literal you can paste into Encounter/SaveChain/Bundled.elm to promote it into the bundled default set."
            ]
            [ text "📤 Export as Elm" ]
        , loadedTag
        ]



-- ── Name + Save ability + DC ────────────────────────────────────


nameRow : SaveChainUi -> Html Msg
nameRow ui =
    div [ class "save-chain__row" ]
        [ span
            [ class "save-chain__field-label save-chain__field-label--tight" ]
            [ text "Name" ]
        , input
            [ type_ "text"
            , class "save-chain__name-input"
            , value ui.name
            , placeholder "e.g., Hold Person"
            , onInput SaveChainNameChanged
            ]
            []
        , button
            [ class "action-btn action-btn--sm action-btn--green"
            , type_ "button"
            , onClick SaveChainPresetSave
            , disabled (String.isEmpty (String.trim ui.name))
            ]
            [ text "Save preset" ]
        ]


saveRow : SaveChainUi -> Html Msg
saveRow ui =
    div [ class "save-chain__row save-chain__row--save" ]
        [ div [ class "save-chain__ability-group" ]
            [ span
                [ class "save-chain__field-label save-chain__field-label--tight" ]
                [ text "Save" ]
            , div [ class "save-chain__ability-radios" ]
                [ abilityRadio ui Str "STR"
                , abilityRadio ui Dex "DEX"
                , abilityRadio ui Con "CON"
                , abilityRadio ui Int_ "INT"
                , abilityRadio ui Wis "WIS"
                , abilityRadio ui Cha "CHA"
                ]
            ]
        , div [ class "save-chain__dc-group" ]
            [ span
                [ class "save-chain__field-label save-chain__field-label--tight" ]
                [ text "DC" ]
            , input
                [ type_ "text"
                , class "save-chain__dc-input"
                , value ui.dcText
                , Attr.maxlength 2
                , onInput SaveChainDcChanged
                ]
                []
            ]
        , dcHint ui
        ]


{-| The DC's caption, trailing the field on the same row. It
takes the row's leftover width and wraps inside it, so the
sentence can never push past the panel's edge.
-}
dcHint : SaveChainUi -> Html Msg
dcHint ui =
    span
        [ class
            (if String.toInt (String.trim ui.dcText) == Nothing then
                "save-chain__caption save-chain__caption--dc save-chain__caption--warn"

             else
                "save-chain__caption save-chain__caption--dc"
            )
        ]
        [ text "req. for save rolls and Save-to-end; blank = enter at apply" ]


abilityRadio : SaveChainUi -> Ability -> String -> Html Msg
abilityRadio ui ability label =
    Html.label [ class "save-chain__ability-radio" ]
        [ input
            [ type_ "radio"
            , name "save-chain-ability"
            , checked (ui.saveAbility == ability)
            , onClick (SaveChainAbilitySet ability)
            ]
            []
        , text label
        ]



-- ── Outcome block ───────────────────────────────────────────────


outcomeBlock : String -> SaveChainSide -> OutcomeForm -> Html Msg
outcomeBlock heading side form =
    div [ class "save-chain__outcome" ]
        [ div [ class "save-chain__outcome-heading" ] [ text heading ]
        , hpRow side form
        , effectsSection side form
        ]


hpRow : SaveChainSide -> OutcomeForm -> Html Msg
hpRow side form =
    let
        currentKind =
            asHpKind form.hpKind

        radios =
            [ hpKindRadio side currentKind SaveChainNoHp "None"
            , hpKindRadio side currentKind SaveChainDamage "Damage"
            , hpKindRadio side currentKind SaveChainHeal "Heal"
            ]
                ++ (case side of
                        SaveChainSuccess ->
                            [ hpKindRadio side currentKind SaveChainHalfFail "Half of Fail damage" ]

                        SaveChainFail ->
                            []
                   )

        amountInput =
            case form.hpKind of
                NoHpEffect ->
                    text ""

                HalfFailDamage ->
                    span [ class "save-chain__caption" ]
                        [ text "(rolls / halves the Fail amount at apply)" ]

                _ ->
                    div [ class "save-chain__amount-cluster" ]
                        [ input
                            [ type_ "text"
                            , class "save-chain__amount-input"
                            , value form.hpAmountText
                            , placeholder "12 or 2d6+3"
                            , onInput (SaveChainOutcomeHpAmountChanged side)
                            ]
                            []
                        , span [ class "save-chain__caption save-chain__caption--warn" ]
                            [ text "req. to apply dmg" ]
                        ]
    in
    div [ class "save-chain__hp-row" ]
        [ span [ class "save-chain__field-label" ] [ text "HP" ]
        , div [ class "save-chain__hp-radios" ] radios
        , amountInput
        ]


hpKindRadio : SaveChainSide -> SaveChainHpKind -> SaveChainHpKind -> String -> Html Msg
hpKindRadio side current kind label =
    let
        groupName =
            case side of
                SaveChainFail ->
                    "save-chain-hp-fail"

                SaveChainSuccess ->
                    "save-chain-hp-success"
    in
    Html.label [ class "save-chain__hp-radio" ]
        [ input
            [ type_ "radio"
            , name groupName
            , checked (current == kind)
            , onClick (SaveChainOutcomeHpKindSet side kind)
            ]
            []
        , text label
        ]


asHpKind : HpEffect -> SaveChainHpKind
asHpKind h =
    case h of
        NoHpEffect ->
            SaveChainNoHp

        DealDamage _ ->
            SaveChainDamage

        HealFor _ ->
            SaveChainHeal

        HalfFailDamage ->
            SaveChainHalfFail


{-| Zero-or-more effect rows plus an "+ Add effect" button.
Each row is a `[name] [note] [×]` triplet. When the list is
empty, the section is just the button — clicking it pushes a
first row. Standard 5e condition names are offered as
datalist suggestions on the name input but the field stays
free-form so spells like Banishment / Slow / Confusion can
use custom effect names.
-}
effectsSection : SaveChainSide -> OutcomeForm -> Html Msg
effectsSection side form =
    div [ class "save-chain__effects" ]
        [ span [ class "save-chain__field-label" ] [ text "Effects" ]
        , div [ class "save-chain__effect-list" ]
            (List.indexedMap (effectRow side) form.effects)
        , button
            [ class "action-btn action-btn--sm"
            , type_ "button"
            , onClick (SaveChainOutcomeEffectAdd side)
            ]
            [ text "+ Add effect" ]
        , conditionDatalist
        ]


effectRow : SaveChainSide -> Int -> EffectApply -> Html Msg
effectRow side idx effect =
    div [ class "save-chain__effect-block" ]
        [ div [ class "save-chain__effect-row" ]
            [ input
                [ type_ "text"
                , class "save-chain__condition-input"
                , list "save-chain-condition-list"
                , value effect.name
                , placeholder "condition or effect name"
                , onInput (SaveChainOutcomeEffectNameChanged side idx)
                ]
                []
            , input
                [ type_ "text"
                , class "save-chain__condition-note-input"
                , value effect.note
                , placeholder "note (optional)"
                , onInput (SaveChainOutcomeEffectNoteChanged side idx)
                ]
                []
            , Html.label
                [ class "save-chain__effect-save-to-end"
                , Tooltips.attr "Save-to-end: applied condition inherits the chain's Save ability + DC.  Auto-roll options appear below when checked."
                ]
                [ input
                    [ type_ "checkbox"
                    , checked (effect.saveToEnd /= Nothing)
                    , onClick (SaveChainOutcomeEffectSaveToEndToggle side idx)
                    ]
                    []
                , text " Save-to-end"
                ]
            , button
                [ class "icon-btn icon-btn--sm save-chain__effect-remove"
                , type_ "button"
                , onClick (SaveChainOutcomeEffectRemove side idx)
                , attribute "aria-label" "Remove effect"
                ]
                [ text "×" ]
            ]
        , autoRollRow side idx effect
        ]


{-| Auto-roll mode picker. Only rendered when the effect's
`saveToEnd` is `Just _` — mirrors the same three modes the
Condition modal offers so the two entry points behave
identically once the applied condition is on the card.
-}
autoRollRow : SaveChainSide -> Int -> EffectApply -> Html Msg
autoRollRow side idx effect =
    case effect.saveToEnd of
        Nothing ->
            text ""

        Just mode ->
            div [ class "save-chain__effect-autoroll" ]
                [ span [ class "save-chain__caption" ] [ text "Auto-roll:" ]
                , autoRollRadio side idx mode Encounter.AutoRollManual "Manual"
                , autoRollRadio side idx mode Encounter.AutoRollAtBegin "At begin of turn"
                , autoRollRadio side idx mode Encounter.AutoRollAtEnd "At end of turn"
                ]


autoRollRadio :
    SaveChainSide
    -> Int
    -> Encounter.AutoRollMode
    -> Encounter.AutoRollMode
    -> String
    -> Html Msg
autoRollRadio side idx current mode label =
    let
        groupName =
            case side of
                SaveChainFail ->
                    "save-chain-autoroll-fail-" ++ String.fromInt idx

                SaveChainSuccess ->
                    "save-chain-autoroll-success-" ++ String.fromInt idx
    in
    Html.label [ class "save-chain__autoroll-radio" ]
        [ input
            [ type_ "radio"
            , name groupName
            , checked (current == mode)
            , onClick (SaveChainOutcomeEffectAutoRollSet side idx mode)
            ]
            []
        , text label
        ]


{-| Attribute helper — `Attr.list` isn't in the core exposing
list. Wrap the raw `list` attribute so the datalist reference
compiles.
-}
list : String -> Html.Attribute msg
list =
    attribute "list"


conditionDatalist : Html Msg
conditionDatalist =
    Html.node "datalist"
        [ Attr.id "save-chain-condition-list" ]
        (List.map (\c -> option [ value c ] []) commonConditions)


{-| Standard 5e conditions offered as datalist suggestions.
The input stays free-form so custom homebrew effects still fit;
this just saves typing on the common cases.
-}
commonConditions : List String
commonConditions =
    [ "Blinded"
    , "Charmed"
    , "Deafened"
    , "Frightened"
    , "Grappled"
    , "Incapacitated"
    , "Invisible"
    , "Paralyzed"
    , "Petrified"
    , "Poisoned"
    , "Prone"
    , "Restrained"
    , "Stunned"
    , "Unconscious"
    ]



-- ── Apply scope + action buttons ────────────────────────────────


applyScope : Int -> SaveChainUi -> Html Msg
applyScope selectedCount ui =
    if selectedCount == 0 then
        text ""

    else
        div [ class "save-chain__row" ]
            [ Html.label [ class "save-chain__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick SaveChainApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            ]


applyRow : SaveChainUi -> Html Msg
applyRow ui =
    let
        chain =
            Ui.SaveChain.toChain ui

        isEmpty =
            SaveChain.isEffectivelyEmpty chain

        hasDc =
            chain.saveDc /= Nothing
    in
    div [ class "save-chain__apply-row" ]
        [ div [ class "save-chain__apply-actions" ]
            [ button
                [ class "action-btn action-btn--damage"
                , type_ "button"
                , onClick SaveChainApplyFail
                , disabled isEmpty
                ]
                [ text "Fail" ]
            , button
                [ class "action-btn action-btn--heal"
                , type_ "button"
                , onClick SaveChainApplyPass
                , disabled isEmpty
                ]
                [ text "Pass" ]
            , button
                [ class "action-btn action-btn--roll-saves"
                , type_ "button"
                , onClick (SaveChainRollSaves SaveChainRollNormal)
                , disabled (isEmpty || not hasDc)
                , attribute "aria-label"
                    "Roll a d20 + save modifier for every target and auto-apply fail / success"
                ]
                [ text "🎲 Roll saves" ]
            , button
                [ class "action-btn action-btn--roll-saves"
                , type_ "button"
                , onClick (SaveChainRollSaves SaveChainRollAdvantage)
                , disabled (isEmpty || not hasDc)
                , attribute "aria-label"
                    "Roll 2d20 keep-highest + save modifier for every target and auto-apply fail / success"
                ]
                [ text "Roll Adv." ]
            , button
                [ class "action-btn action-btn--roll-saves"
                , type_ "button"
                , onClick (SaveChainRollSaves SaveChainRollDisadvantage)
                , disabled (isEmpty || not hasDc)
                , attribute "aria-label"
                    "Roll 2d20 keep-lowest + save modifier for every target and auto-apply fail / success"
                ]
                [ text "Roll Disadv." ]
            ]
        ]



-- ── Log ─────────────────────────────────────────────────────────


{-| Recent-applies log at the bottom of the modal. Mirrors
the "Recent HP changes" log's structure: a small title, an
empty state when nothing's landed yet, and a compact list of
rows otherwise. Newest entry first — each apply prepends.
-}
log : List SaveChainLogEntry -> Html Msg
log entries =
    div [ class "save-chain__log" ]
        [ div [ class "save-chain__log-title" ]
            [ text
                ("Recent applies ("
                    ++ String.fromInt (List.length entries)
                    ++ ")"
                )
            ]
        , if List.isEmpty entries then
            div [ class "save-chain__log-empty" ]
                [ text "No applies yet." ]

          else
            ul [ class "save-chain__log-list" ]
                (List.map logEntry entries)
        ]


{-| One row: side badge · target · optional roll note · applied
summary. When no HP delta and no effects landed, the applied
column reads "(no effect)" so the row still reads as
"resolved but nothing to do."

Each `AppliedPart` gets its own span so damage / healing can
render in their own colour (red / green) while effect names
stay in the default text colour. Parts are joined by a " · "
separator span between siblings.

-}
logEntry : SaveChainLogEntry -> Html Msg
logEntry entry =
    let
        ( sideCls, sideLabel ) =
            case entry.side of
                SaveChainFail ->
                    ( "save-chain__log-side save-chain__log-side--fail", "FAIL" )

                SaveChainSuccess ->
                    ( "save-chain__log-side save-chain__log-side--pass", "PASS" )

        appliedNode =
            if List.isEmpty entry.appliedParts then
                span [ class "save-chain__log-applied" ]
                    [ text "(no effect)" ]

            else
                span [ class "save-chain__log-applied" ]
                    (List.intersperse
                        (span [ class "save-chain__log-applied-sep" ] [ text " · " ])
                        (List.map appliedPartSpan entry.appliedParts)
                    )

        rollNode =
            case entry.rollNote of
                Just note ->
                    span [ class "save-chain__log-roll" ] [ text note ]

                Nothing ->
                    text ""
    in
    li [ class "save-chain__log-entry" ]
        [ span [ class sideCls ] [ text sideLabel ]
        , span [ class "save-chain__log-target" ] [ text entry.target ]
        , rollNode
        , appliedNode
        ]


appliedPartSpan : AppliedPart -> Html Msg
appliedPartSpan part =
    case part of
        DamagePart n ->
            span [ class "save-chain__log-applied-part save-chain__log-applied-part--damage" ]
                [ text (String.fromInt n ++ " damage applied") ]

        HealPart n ->
            span [ class "save-chain__log-applied-part save-chain__log-applied-part--heal" ]
                [ text (String.fromInt n ++ " healing applied") ]

        EffectPart name ->
            span [ class "save-chain__log-applied-part save-chain__log-applied-part--effect" ]
                [ text name ]
