module View.Inline.SaveChain exposing (Context, view)

{-| Save Chain as an inline card expansion: a reusable "creature
makes a save; something happens" recipe, saveable as a preset,
with one outcome per side of the save.

Applying never closes the editor. A GM usually runs both sides
on the same open — fail for the creatures that missed, pass for
the survivors.

The body is laid out in the Condition editor's vocabulary — the
same sections, rows, fields, and choice controls — so the two
editors read as one form.

-}

import Compendium exposing (Ability(..))
import Dict
import Encounter
import Encounter.SaveChain as SaveChain exposing (EffectApply, EffectDuration, HpEffect(..))
import Html exposing (Html, button, div, input, li, option, select, span, text, ul)
import Html.Attributes as Attr exposing (attribute, class, disabled, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg
    exposing
        ( Msg(..)
        , SaveChainHpKind(..)
        , SaveChainRollMode(..)
        , SaveChainSide(..)
        )
import Ui.SaveChain exposing (AppliedPart(..), OutcomeForm, SaveChainLogEntry, SaveChainUi)
import View.Inline.ApplyButton as ApplyButton
import View.Inline.DurationPicker as DurationPicker
import View.Inline.Field as Field
import View.Tooltips as Tooltips


{-| The model fragments the expansion consumes beyond its own
Ui record: the presets dict backs the picker row, the selected
count drives the apply-to-selected scope and the header title,
and the log renders the recent resolutions behind its fold.
-}
type alias Context =
    { presets : Dict.Dict String SaveChain.SaveChain
    , selectedCount : Int
    , placeholderWarning : Bool
    , log : List SaveChainLogEntry
    , logOpen : Bool
    , creatureNames : List String
    }


view : Context -> SaveChainUi -> Html Msg
view ctx ui =
    div [ class "editor-body" ]
        [ presetSection ui ctx.presets
        , identitySection ui
        , outcomeSection ctx.creatureNames "On failed save" SaveChainFail ui.onFail []
        , outcomeSection ctx.creatureNames
            "On successful save"
            SaveChainSuccess
            ui.onSuccess
            [ immunityRows ctx.creatureNames ui.immunity ]
        , applySection ctx ui
        , logSection ctx.logOpen ctx.log
        ]



-- ── Presets ─────────────────────────────────────────────────────


presetSection : SaveChainUi -> Dict.Dict String SaveChain.SaveChain -> Html Msg
presetSection ui presets =
    let
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
                    (Dict.keys presets)

        loadedTag =
            case ui.loadedPresetName of
                Just n ->
                    span [ class "cond-section__caption" ]
                        [ text ("Loaded: " ++ n) ]

                Nothing ->
                    text ""
    in
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Preset:" ]
            , select
                [ class "cond-select cond-select--grow"
                , onInput SaveChainPresetPickerChanged
                ]
                options
            , loadedTag
            ]
        , div [ class "cond-row" ]
            [ button
                [ class "action-btn"
                , type_ "button"
                , onClick SaveChainReset
                , Tooltips.attr "Start a new chain from nothing"
                ]
                [ text "New" ]
            , button
                [ class "action-btn"
                , type_ "button"
                , onClick SaveChainClear
                , Tooltips.attr "Empty every setting but keep the name and the loaded preset"
                ]
                [ text "Clear" ]
            , button
                [ class "action-btn action-btn--red"
                , type_ "button"
                , onClick SaveChainPresetDelete
                , disabled (ui.loadedPresetName == Nothing && String.isEmpty ui.presetPickerSelection)
                , Tooltips.attr "Delete the loaded preset"
                ]
                [ text "Delete" ]
            , button
                [ class "action-btn"
                , type_ "button"
                , onClick SaveChainRestoreBundled
                , Tooltips.attr "Overwrite the bundled presets with their shipped values; your own presets are not changed"
                ]
                [ text "Restore" ]
            ]
        ]



-- ── Name, save, DC, area ────────────────────────────────────────


identitySection : SaveChainUi -> Html Msg
identitySection ui =
    div [ class "cond-section" ]
        [ div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "Name:" ]
            , input
                [ type_ "text"
                , class "cond-input cond-input--w20"
                , value ui.name
                , placeholder "e.g. Hold Person"
                , onInput SaveChainNameChanged
                ]
                []
            , button
                [ class "action-btn action-btn--green"
                , type_ "button"
                , onClick SaveChainPresetSave
                , disabled (String.isEmpty (String.trim ui.name))
                ]
                [ text "Save preset" ]
            ]
        , div [ class "cond-row" ]
            (Html.label [ class "cond-label" ] [ text "Save:" ]
                :: List.map (abilityRadio ui)
                    [ ( Str, "STR" ), ( Dex, "DEX" ), ( Con, "CON" ), ( Int_, "INT" ), ( Wis, "WIS" ), ( Cha, "CHA" ) ]
            )
        , div [ class "cond-row" ]
            [ Html.label [ class "cond-label" ] [ text "DC:" ]
            , input
                [ type_ "text"
                , class "cond-input cond-input--2ch"
                , value ui.dcText
                , Attr.maxlength 2
                , onInput SaveChainDcChanged
                ]
                []
            ]
        , dcHint ui
        , div [ class "cond-row" ]
            [ Html.label
                [ class "cond-label"
                , Tooltips.attr Tooltips.saveChainArea
                ]
                [ text "Area:" ]
            , areaRadio ui Nothing "None"
            , areaRadio ui (Just Encounter.AtBegin) "Re-save at turn start"
            , areaRadio ui (Just Encounter.AtEnd) "Re-save at turn end"
            ]
        ]


{-| The DC's caption: a line of its own under the field, so it
never wraps mid-sentence beside it.
-}
dcHint : SaveChainUi -> Html Msg
dcHint ui =
    div
        [ class
            (if String.toInt (String.trim ui.dcText) == Nothing then
                "cond-section__caption cond-section__caption--warn"

             else
                "cond-section__caption"
            )
        ]
        [ text "A DC is needed to roll saves or to apply a Save-to-end or area effect." ]


areaRadio : SaveChainUi -> Maybe Encounter.TurnPhase -> String -> Html Msg
areaRadio ui phase label =
    Field.radio
        { group = "save-chain-area"
        , selected = ui.area == phase
        , msg = SaveChainAreaSet phase
        , label = label
        }


abilityRadio : SaveChainUi -> ( Ability, String ) -> Html Msg
abilityRadio ui ( ability, label ) =
    Field.radio
        { group = "save-chain-ability"
        , selected = ui.saveAbility == ability
        , msg = SaveChainAbilitySet ability
        , label = label
        }



-- ── Outcomes ────────────────────────────────────────────────────


{-| One side's section; `extra` is the success side's immunity
rows, nothing on the fail side.
-}
outcomeSection : List String -> String -> SaveChainSide -> OutcomeForm -> List (Html Msg) -> Html Msg
outcomeSection names heading side form extra =
    div [ class "cond-section" ]
        ([ Html.h3 [ class "cond-section__heading" ] [ text heading ]
         , hpRow side form
         , effectsRows names side form
         ]
            ++ extra
        )


{-| A successful save may leave the target immune to the chain for
a while; the chain then passes over that creature until the
immunity lapses.
-}
immunityRows : List String -> Maybe EffectDuration -> Html Msg
immunityRows names immunity =
    div [ class "cond-row" ]
        [ Field.checkbox
            { checked = immunity /= Nothing
            , msg = SaveChainImmunityToggle
            , label = "Grants immunity"
            , extra = [ Tooltips.attr "A creature that succeeds becomes immune to this chain for the duration below, and the chain skips it until then" ]
            }
        , case immunity of
            Just duration ->
                DurationPicker.view
                    { groupName = "save-chain-immunity"
                    , creatureNames = names
                    , value = duration
                    , toMsg = SaveChainImmunityDurationEdit
                    }

            Nothing ->
                text ""
        ]


{-| The HP choice and, once one is picked, its amount — all on one
wrapping row, so the label stays beside the first choice however
narrow the panel.
-}
hpRow : SaveChainSide -> OutcomeForm -> Html Msg
hpRow side form =
    let
        currentKind =
            asHpKind form.hpKind

        radios =
            [ hpKindRadio side currentKind SaveChainNoHp "None"
            , hpKindRadio side currentKind SaveChainDamage "Damage"
            , hpKindRadio side currentKind SaveChainHeal "Heal"
            , hpKindRadio side currentKind SaveChainDrain "Drain"
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
                    []

                HalfFailDamage ->
                    [ span [ class "cond-section__caption" ]
                        [ text "(rolls / halves the Fail amount at apply)" ]
                    ]

                _ ->
                    [ input
                        [ type_ "text"
                        , class "cond-input cond-input--w12 cond-input--amount"
                        , value form.hpAmountText
                        , placeholder "12 or 2d6+3"
                        , onInput (SaveChainOutcomeHpAmountChanged side)
                        ]
                        []
                    , span [ class "cond-section__caption cond-section__caption--warn" ]
                        [ text "req. to apply dmg" ]
                    ]
    in
    div [ class "cond-row" ]
        (Html.label [ class "cond-label" ] [ text "HP:" ] :: radios ++ amountInput)


hpKindRadio : SaveChainSide -> SaveChainHpKind -> SaveChainHpKind -> String -> Html Msg
hpKindRadio side current kind label =
    let
        radio =
            Field.radio
                { group = "save-chain-hp-" ++ sideKey side
                , selected = current == kind
                , msg = SaveChainOutcomeHpKindSet side kind
                , label = label
                }
    in
    case kind of
        SaveChainDrain ->
            span [ Tooltips.attr "Damage that also lowers the target's hit point maximum by the amount dealt, as Harm and a wight's Life Drain do" ]
                [ radio ]

        _ ->
            radio


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

        DrainDamage _ ->
            SaveChainDrain


{-| Zero-or-more effect blocks plus an "+ Add effect" button.
When the list is empty, the section is just the button —
clicking it pushes a first block. Standard 5e condition names
are offered as datalist suggestions on the name input but the
field stays free-form so spells like Banishment / Slow /
Confusion can use custom effect names.
-}
effectsRows : List String -> SaveChainSide -> OutcomeForm -> Html Msg
effectsRows names side form =
    div [ class "cond-radio-stack" ]
        (List.indexedMap (effectBlock names side) form.effects
            ++ [ div [ class "cond-row" ]
                    [ Html.label [ class "cond-label" ] [ text "Effects:" ]
                    , button
                        [ class "action-btn"
                        , type_ "button"
                        , onClick (SaveChainOutcomeEffectAdd side)
                        ]
                        [ text "+ Add effect" ]
                    ]
               , conditionDatalist
               ]
        )


effectBlock : List String -> SaveChainSide -> Int -> EffectApply -> Html Msg
effectBlock names side idx effect =
    div [ class "cond-subsection" ]
        ([ div [ class "cond-row" ]
            [ input
                [ type_ "text"
                , class "cond-input cond-input--grow"
                , list "save-chain-condition-list"
                , value effect.name
                , placeholder "condition or effect name"
                , onInput (SaveChainOutcomeEffectNameChanged side idx)
                ]
                []
            , input
                [ type_ "text"
                , class "cond-input cond-input--w12"
                , value effect.note
                , placeholder "note (optional)"
                , onInput (SaveChainOutcomeEffectNoteChanged side idx)
                ]
                []
            , Field.checkbox
                { checked = effect.saveToEnd /= Nothing
                , msg = SaveChainOutcomeEffectSaveToEndToggle side idx
                , label = "Save-to-end"
                , extra = [ Tooltips.attr "Save-to-end: the applied condition inherits the chain's save ability and DC, and rolls again as the timing below says" ]
                }
            , button
                [ class "icon-btn icon-btn--sm"
                , type_ "button"
                , onClick (SaveChainOutcomeEffectRemove side idx)
                , Tooltips.attr "Remove this effect"
                , attribute "aria-label" "Remove effect"
                ]
                [ text "×" ]
            ]
         , DurationPicker.view
            { groupName = "save-chain-duration-" ++ sideKey side ++ "-" ++ String.fromInt idx
            , creatureNames = names
            , value = effect.duration
            , toMsg = SaveChainOutcomeEffectDurationEdit side idx
            }
         , withRow side idx effect
         ]
            ++ saveRows side idx effect
        )


{-| A companion condition applied beside this one that ends when
it ends — Hypnotic Pattern's Incapacitated on its Charmed.
-}
withRow : SaveChainSide -> Int -> EffectApply -> Html Msg
withRow side idx effect =
    div [ class "cond-row" ]
        [ Html.label [ class "cond-label" ] [ text "Applies with:" ]
        , input
            [ type_ "text"
            , class "cond-input cond-input--w20"
            , list "save-chain-condition-list"
            , placeholder "companion condition (optional)"
            , value effect.with
            , onInput (SaveChainOutcomeEffectWithChanged side idx)
            , Tooltips.attr "A second condition applied alongside this one that ends when it ends, and carries no save of its own"
            ]
            []
        ]


{-| The rows a save adds beneath an effect; nothing while the
effect has no save.
-}
saveRows : SaveChainSide -> Int -> EffectApply -> List (Html Msg)
saveRows side idx effect =
    case effect.saveToEnd of
        Nothing ->
            []

        Just save ->
            let
                autoRoll extra mode label =
                    Field.radioWith extra
                        { group = "save-chain-autoroll-" ++ sideKey side ++ "-" ++ String.fromInt idx
                        , selected = save.autoRoll == mode
                        , msg = SaveChainOutcomeEffectAutoRollSet side idx mode
                        , label = label
                        }

                onDamage extra trigger label =
                    Field.radioWith extra
                        { group = "save-chain-ondamage-" ++ sideKey side ++ "-" ++ String.fromInt idx
                        , selected = save.onDamage == trigger
                        , msg = SaveChainOutcomeEffectOnDamageSet side idx trigger
                        , label = label
                        }
            in
            [ div [ class "cond-row" ]
                [ Html.label [ class "cond-label" ] [ text "Auto-roll:" ]
                , autoRoll [] Encounter.AutoRollManual "Manual"
                , autoRoll [] Encounter.AutoRollAtBegin "Start of turn"
                , autoRoll [] Encounter.AutoRollAtEnd "End of turn"
                , autoRoll [ Tooltips.attr Tooltips.saveAskAtEnd ] Encounter.AutoRollAskAtEnd "Ask at end of turn"
                ]
            , div [ class "cond-row" ]
                [ Html.label [ class "cond-label" ] [ text "On a failed save:" ]
                , Html.label [ class "cond-label" ] [ text "takes" ]
                , input
                    [ type_ "text"
                    , class "cond-input cond-input--narrow"
                    , placeholder "4d10"
                    , value (Maybe.withDefault "" save.onFail.damage)
                    , onInput (SaveChainOutcomeEffectFailDamageChanged side idx)
                    , Tooltips.attr "Damage the bearer takes on each failed save — a dice formula or a number"
                    ]
                    []
                , Html.label [ class "cond-label" ] [ text "becomes" ]
                , input
                    [ type_ "text"
                    , class "cond-input cond-input--w12"
                    , list "save-chain-condition-list"
                    , placeholder "e.g. Petrified"
                    , value (Maybe.withDefault "" save.onFail.becomes)
                    , onInput (SaveChainOutcomeEffectFailBecomesChanged side idx)
                    , Tooltips.attr "The condition this one turns into on a failed save, which ends the saving"
                    ]
                    []
                ]
            , div [ class "cond-row" ]
                [ Html.label [ class "cond-label" ] [ text "When damaged:" ]
                , onDamage [] Encounter.NoDamageTrigger "Nothing"
                , onDamage [ Tooltips.attr Tooltips.saveFlashOnDamage ] Encounter.AskOnDamage "Flash the chip"
                , onDamage [] Encounter.RollOnDamage "Roll the save"
                , onDamage [] Encounter.RollOnDamageWithAdvantage "Roll with advantage"
                ]
            ]


sideKey : SaveChainSide -> String
sideKey side =
    case side of
        SaveChainFail ->
            "fail"

        SaveChainSuccess ->
            "success"


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



-- ── Apply ───────────────────────────────────────────────────────


applySection : Context -> SaveChainUi -> Html Msg
applySection ctx ui =
    div [ class "cond-section" ]
        ((if ctx.selectedCount == 0 then
            []

          else
            [ div [ class "cond-row" ]
                [ Field.checkbox
                    { checked = ui.applyToSelected
                    , msg = SaveChainApplyToSelectedToggle
                    , label = "Apply to all selected creatures (" ++ String.fromInt ctx.selectedCount ++ ")"
                    , extra = []
                    }
                ]
            ]
         )
            ++ [ applyRow ui
               , ApplyButton.placeholderNotice ctx.placeholderWarning
               ]
        )


{-| The apply buttons, each explaining itself while it is dead.
A Save-to-end effect applied without a DC would land as a plain
condition and never roll, so Fail and Pass wait for the DC along
with the roll buttons whenever an effect opts in.
-}
applyRow : SaveChainUi -> Html Msg
applyRow ui =
    let
        chain =
            Ui.SaveChain.toChain ui

        isEmpty =
            SaveChain.isEffectivelyEmpty chain

        hasDc =
            chain.saveDc /= Nothing

        blockedByDc =
            not hasDc && SaveChain.needsDc chain

        outcomeTip verb =
            if isEmpty then
                "Give the chain an outcome first"

            else if blockedByDc then
                "Enter a DC first — a Save-to-end effect needs one"

            else
                verb

        rollTip verb =
            if isEmpty then
                "Give the chain an outcome first"

            else if not hasDc then
                "Enter a DC first"

            else
                verb

        -- An area chain can mark its targets without resolving an
        -- outcome, for an area that grants no save on its arrival.
        markButton =
            case chain.area of
                Just _ ->
                    [ ApplyButton.view
                        { enabled = hasDc
                        , cls = "action-btn"
                        , msg = SaveChainMarkArea
                        , tip =
                            if hasDc then
                                "Put the \"In:\" chip on every target without rolling now; the save rolls at each creature's turn"

                            else
                                "Enter a DC first"
                        , label = "Mark in area"
                        }
                    ]

                Nothing ->
                    []
    in
    div [ class "cond-row" ]
        (markButton
            ++ [ ApplyButton.view
                    { enabled = not isEmpty && not blockedByDc
                    , cls = "action-btn action-btn--damage"
                    , msg = SaveChainApplyFail
                    , tip = outcomeTip "Apply the failed-save outcome"
                    , label = "Fail"
                    }
               , ApplyButton.view
                    { enabled = not isEmpty && not blockedByDc
                    , cls = "action-btn action-btn--heal"
                    , msg = SaveChainApplyPass
                    , tip = outcomeTip "Apply the successful-save outcome"
                    , label = "Pass"
                    }
               , ApplyButton.view
                    { enabled = not isEmpty && hasDc
                    , cls = "action-btn action-btn--roll-saves"
                    , msg = SaveChainRollSaves SaveChainRollNormal
                    , tip = rollTip "Roll d20 + save modifier for every target and apply fail or pass"
                    , label = "🎲 Roll saves"
                    }
               , ApplyButton.view
                    { enabled = not isEmpty && hasDc
                    , cls = "action-btn action-btn--roll-saves"
                    , msg = SaveChainRollSaves SaveChainRollAdvantage
                    , tip = rollTip "Roll 2d20 keep highest + save modifier for every target and apply fail or pass"
                    , label = "Roll Adv."
                    }
               , ApplyButton.view
                    { enabled = not isEmpty && hasDc
                    , cls = "action-btn action-btn--roll-saves"
                    , msg = SaveChainRollSaves SaveChainRollDisadvantage
                    , tip = rollTip "Roll 2d20 keep lowest + save modifier for every target and apply fail or pass"
                    , label = "Roll Disadv."
                    }
               ]
        )



-- ── Log ─────────────────────────────────────────────────────────


{-| Recent-applies log at the editor's foot, behind a fold. It
starts folded and unfolds itself when an apply lands. Newest
entry first — each apply prepends.
-}
logSection : Bool -> List SaveChainLogEntry -> Html Msg
logSection open entries =
    div [ class "cond-section" ]
        (Field.foldHead
            { open = open
            , title = "Log (" ++ String.fromInt (List.length entries) ++ ")"
            , msg = SaveChainLogToggle
            , trail = []
            }
            :: (if not open then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ] [ text "No applies yet." ] ]

                else
                    [ ul [ class "save-chain__log-list" ] (List.map logEntry entries) ]
               )
        )


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

        DrainPart n ->
            span [ class "save-chain__log-applied-part save-chain__log-applied-part--damage" ]
                [ text (String.fromInt n ++ " damage applied; max HP lowered") ]

        EffectPart name ->
            span [ class "save-chain__log-applied-part save-chain__log-applied-part--effect" ]
                [ text name ]
