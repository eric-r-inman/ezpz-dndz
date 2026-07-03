module View.Modal.SaveChain exposing (view)

{-| Save Chain modal — reusable "creature makes a save;
something happens" recipe editor plus a two-button apply row.

Layout, top to bottom:

  - Preset picker row (dropdown + Load / Delete)
  - Name field (required to save as preset)
  - Save ability radios + Save DC input
  - On Fail outcome (HP radio + condition apply)
  - On Success outcome (HP radio + condition apply, adds a
    "Half of Fail damage" option that resolves at apply time)
  - Apply-to-selected toggle (only visible when the selection
    is non-empty)
  - Two action buttons: Fail applies the fail outcome; Pass
    applies the success outcome. Neither closes the modal —
    the GM often runs Fail + Pass on the same open (fail for
    the creatures that missed, pass for the survivors).

-}

import Compendium exposing (Ability(..))
import Dict
import Encounter exposing (Encounter)
import Encounter.SaveChain as SaveChain exposing (EffectApply, HpEffect(..))
import Html exposing (Html, button, div, input, option, p, select, span, text)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, name, placeholder, selected, type_, value)
import Html.Events exposing (on, onClick, onInput)
import Json.Decode as Decode
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( Msg(..)
        , SaveChainHpKind(..)
        , SaveChainSide(..)
        )
import Ui.SaveChain exposing (OutcomeForm, SaveChainUi)
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            View.Modal.view
                { close = SaveChainClose
                , noOp = NoOp
                , title = title ui model.encounter
                , extraClass = "modal--save-chain"
                , chrome = model.modalChrome
                , body =
                    [ presetRow ui model.saveChainPresets
                    , nameRow ui
                    , saveRow ui
                    , outcomeBlock "On failed save" SaveChainFail ui.onFail
                    , outcomeBlock "On successful save" SaveChainSuccess ui.onSuccess
                    , applyScope ui model.encounter
                    , applyRow ui
                    ]
                }

        _ ->
            text ""


title : SaveChainUi -> Encounter -> String
title ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
    if ui.applyToSelected && selectedCount > 0 then
        "Save Chain — " ++ String.fromInt selectedCount ++ " selected"

    else
        "Save Chain — " ++ ui.target



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
        , loadedTag
        ]



-- ── Name + Save ability + DC ────────────────────────────────────


nameRow : SaveChainUi -> Html Msg
nameRow ui =
    div [ class "save-chain__row" ]
        [ span [ class "save-chain__field-label" ] [ text "Name" ]
        , input
            [ type_ "text"
            , class "save-chain__name-input"
            , value ui.name
            , placeholder "e.g. Hold Person, Blindness, Fireball…"
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
            [ span [ class "save-chain__field-label" ] [ text "Save" ]
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
            [ span [ class "save-chain__field-label" ] [ text "DC" ]
            , input
                [ type_ "text"
                , class "save-chain__dc-input"
                , value ui.dcText
                , placeholder "(blank = input at apply)"
                , onInput SaveChainDcChanged
                ]
                []
            ]
        ]


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
                        , span [ class "save-chain__caption" ]
                            [ text "number or dice formula" ]
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
    div [ class "save-chain__effect-row" ]
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
            , Tooltips.attr "Save at end of turn to end (inherits the chain's Save ability + DC on the applied condition)"
            ]
            [ input
                [ type_ "checkbox"
                , checked effect.saveToEnd
                , onClick (SaveChainOutcomeEffectSaveToEndToggle side idx)
                ]
                []
            , text " Save EoT"
            ]
        , button
            [ class "icon-btn icon-btn--sm save-chain__effect-remove"
            , type_ "button"
            , onClick (SaveChainOutcomeEffectRemove side idx)
            , attribute "aria-label" "Remove effect"
            ]
            [ text "×" ]
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


applyScope : SaveChainUi -> Encounter -> Html Msg
applyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
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

        dcHint =
            case chain.saveDc of
                Just n ->
                    span [ class "save-chain__caption" ]
                        [ text ("DC " ++ String.fromInt n ++ " · " ++ abilityLabel chain.saveAbility ++ " save") ]

                Nothing ->
                    span [ class "save-chain__caption save-chain__caption--warn" ]
                        [ text ("DC blank · " ++ abilityLabel chain.saveAbility ++ " save — enter the DC on the source spell / feature") ]
    in
    div [ class "save-chain__apply-row" ]
        [ dcHint
        , div [ class "save-chain__apply-actions" ]
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
                , onClick SaveChainRollSaves
                , disabled (isEmpty || not hasDc)
                , attribute "aria-label"
                    "Roll a d20 + save modifier for every target and auto-apply fail / success"
                ]
                [ text "🎲 Roll saves" ]
            ]
        ]


abilityLabel : Ability -> String
abilityLabel a =
    case a of
        Str ->
            "STR"

        Dex ->
            "DEX"

        Con ->
            "CON"

        Int_ ->
            "INT"

        Wis ->
            "WIS"

        Cha ->
            "CHA"
