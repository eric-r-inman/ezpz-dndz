module View.Modal.CompendiumEdit exposing (view)

{-| Compendium edit / create modal. ~50-field form covering
identity, combat core, abilities, saves, skills, properties,
senses, and four feature groups (traits / actions / bonus actions
/ reactions) plus a free-form custom-sections list.

The four advanced sections (legendary / lair / regional /
spellcasting) aren't editable here yet — they're preserved
verbatim through submit. The notice at the bottom of the form
flags that to the GM when the source creature has any populated.

-}

import Compendium
import Html exposing (Html, button, div, input, label, option, span, text)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, name, selected, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CompendiumField(..)
        , FeatureGroup(..)
        , Msg(..)
        )
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumEditUi
        , EditMode(..)
        , FeatureDraft
        )
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalCompendiumEdit ui) ->
            View.Modal.view
                { close = CompendiumEditCancel
                , noOp = NoOp
                , title = modalTitle ui
                , extraClass = "modal--compendium-edit"
                , body =
                    [ errorBanner ui
                    , editSection "Identity"
                        [ inlineRow
                            [ textField "Name" CFName ui.name [ attribute "required" "true" ]
                            , kindRadio ui.kind
                            ]
                        , inlineRow
                            [ sizeDropdown ui.size
                            , textField "Race" CFRace ui.race []
                            , textField "Subrace" CFSubrace ui.subrace []
                            ]
                        , inlineRow
                            [ textField "Alignment" CFAlignment ui.alignment []
                            , textField "Source" CFSource ui.source []
                            ]
                        , textareaField "Description (short blurb)" CFDescription ui.description 2
                        ]
                    , editSection "Combat Core"
                        [ inlineRow
                            [ numberField "AC" CFArmorClass ui.armorClass [ attribute "required" "true" ]
                            , textField "AC Note" CFArmorClassNote ui.armorClassNote []
                            , numberField "Max HP" CFMaxHp ui.maxHp [ attribute "required" "true" ]
                            , textField "HP Formula" CFHpFormula ui.hpFormula []
                            , numberField "Init Bonus" CFInitiativeBonus ui.initiativeBonus []
                            ]
                        , inlineRow
                            [ numberField "Walk" CFSpeedWalk ui.speedWalk []
                            , numberField "Fly" CFSpeedFly ui.speedFly []
                            , numberField "Swim" CFSpeedSwim ui.speedSwim []
                            , numberField "Climb" CFSpeedClimb ui.speedClimb []
                            , numberField "Burrow" CFSpeedBurrow ui.speedBurrow []
                            , hoverToggle ui.speedHover
                            ]
                        ]
                    , editSection "Abilities"
                        [ inlineRow
                            [ abilityField "STR" CFAbilityStr ui.abilityStr
                            , abilityField "DEX" CFAbilityDex ui.abilityDex
                            , abilityField "CON" CFAbilityCon ui.abilityCon
                            , abilityField "INT" CFAbilityInt ui.abilityInt
                            , abilityField "WIS" CFAbilityWis ui.abilityWis
                            , abilityField "CHA" CFAbilityCha ui.abilityCha
                            ]
                        ]
                    , editSection "Saving Throws"
                        (savingThrowsEditor ui.savingThrows)
                    , editSection "Skills"
                        (skillsEditor ui.skills)
                    , editSection "Properties"
                        [ textField "Damage Vulnerabilities (comma-separated)" CFDamageVulnerabilities ui.damageVulnerabilities []
                        , textField "Damage Resistances" CFDamageResistances ui.damageResistances []
                        , textField "Damage Immunities" CFDamageImmunities ui.damageImmunities []
                        , textField "Condition Immunities" CFConditionImmunities ui.conditionImmunities []
                        , textField "Languages" CFLanguages ui.languages []
                        , inlineRow
                            [ textField "Challenge Rating" CFChallengeRating ui.challengeRating []
                            , numberField "XP" CFXp ui.xp []
                            , numberField "XP in Lair" CFXpInLair ui.xpInLair []
                            , numberField "Proficiency Bonus" CFProficiencyBonus ui.proficiencyBonus []
                            ]
                        ]
                    , editSection "Senses"
                        [ inlineRow
                            [ numberField "Blindsight" CFSensesBlindsight ui.sensesBlindsight []
                            , numberField "Darkvision" CFSensesDarkvision ui.sensesDarkvision []
                            , numberField "Tremorsense" CFSensesTremorsense ui.sensesTremorsense []
                            , numberField "Truesight" CFSensesTruesight ui.sensesTruesight []
                            , numberField "Passive Perception" CFSensesPassivePerception ui.sensesPassivePerception []
                            ]
                        ]
                    , editSection "Traits"
                        (featuresEditor TraitsGroup ui.traits)
                    , editSection "Actions"
                        (featuresEditor ActionsGroup ui.actions)
                    , editSection "Bonus Actions"
                        (featuresEditor BonusActionsGroup ui.bonusActions)
                    , editSection "Reactions"
                        (featuresEditor ReactionsGroup ui.reactions)
                    , editSection "Custom Sections"
                        (customSectionsEditor ui.customSections)
                    , advancedSectionsNotice ui
                    , footer ui
                    ]
                }

        _ ->
            text ""


modalTitle : CompendiumEditUi -> String
modalTitle ui =
    case ui.mode of
        CreateMode ->
            "📚 New Creature"

        EditExisting _ ->
            "📚 Edit Creature"


errorBanner : CompendiumEditUi -> Html Msg
errorBanner ui =
    case ui.submitError of
        Nothing ->
            text ""

        Just msg ->
            div [ class "edit-error" ] [ text msg ]


editSection : String -> List (Html Msg) -> Html Msg
editSection heading children =
    Html.fieldset [ class "edit-section" ]
        (Html.legend [] [ text heading ] :: children)


inlineRow : List (Html Msg) -> Html Msg
inlineRow children =
    div [ class "edit-row" ] children


textField : String -> CompendiumField -> String -> List (Html.Attribute Msg) -> Html Msg
textField labelText field current extras =
    label [ class "edit-field" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            ([ type_ "text"
             , value current
             , onInput (CompendiumEditFieldChanged field)
             , class "edit-field__input"
             ]
                ++ extras
            )
            []
        ]


numberField : String -> CompendiumField -> String -> List (Html.Attribute Msg) -> Html Msg
numberField labelText field current extras =
    label [ class "edit-field edit-field--number" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            ([ type_ "number"
             , value current
             , onInput (CompendiumEditFieldChanged field)
             , class "edit-field__input"
             ]
                ++ extras
            )
            []
        ]


textareaField : String -> CompendiumField -> String -> Int -> Html Msg
textareaField labelText field current rows =
    label [ class "edit-field edit-field--textarea" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , Html.textarea
            [ value current
            , onInput (CompendiumEditFieldChanged field)
            , class "edit-field__input"
            , attribute "rows" (String.fromInt rows)
            ]
            []
        ]


abilityField : String -> CompendiumField -> String -> Html Msg
abilityField labelText field current =
    let
        score =
            String.toInt current |> Maybe.withDefault 10

        modValue =
            (score - 10) // 2
    in
    label [ class "edit-field edit-field--ability" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            [ type_ "number"
            , value current
            , onInput (CompendiumEditFieldChanged field)
            , class "edit-field__input"
            ]
            []
        , span [ class "edit-field__hint" ] [ text ("(" ++ signedInt modValue ++ ")") ]
        ]


signedInt : Int -> String
signedInt n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


kindRadio : Compendium.CreatureKind -> Html Msg
kindRadio current =
    let
        opt kind label_ =
            label [ class "edit-radio" ]
                [ input
                    [ type_ "radio"
                    , name "edit-kind"
                    , checked (kind == current)
                    , onClick (CompendiumEditKindSet kind)
                    ]
                    []
                , text label_
                ]
    in
    div [ class "edit-field edit-field--radio-group" ]
        [ span [ class "edit-field__label" ] [ text "Kind" ]
        , div [ class "edit-radio-row" ]
            [ opt Compendium.Player "Player"
            , opt Compendium.Enemy "Enemy"
            , opt Compendium.Npc "NPC"
            ]
        ]


sizeDropdown : Compendium.Size -> Html Msg
sizeDropdown current =
    let
        sizes =
            [ ( Compendium.Tiny, "Tiny" )
            , ( Compendium.Small, "Small" )
            , ( Compendium.Medium, "Medium" )
            , ( Compendium.Large, "Large" )
            , ( Compendium.Huge, "Huge" )
            , ( Compendium.Gargantuan, "Gargantuan" )
            ]
    in
    label [ class "edit-field" ]
        [ span [ class "edit-field__label" ] [ text "Size" ]
        , Html.select
            [ class "edit-field__input"
            , onInput sizeFromString
            ]
            (List.map
                (\( size, label_ ) ->
                    option
                        [ value (sizeKey size)
                        , selected (size == current)
                        ]
                        [ text label_ ]
                )
                sizes
            )
        ]


sizeKey : Compendium.Size -> String
sizeKey s =
    case s of
        Compendium.Tiny ->
            "tiny"

        Compendium.Small ->
            "small"

        Compendium.Medium ->
            "medium"

        Compendium.Large ->
            "large"

        Compendium.Huge ->
            "huge"

        Compendium.Gargantuan ->
            "gargantuan"


sizeFromString : String -> Msg
sizeFromString raw =
    let
        size =
            case raw of
                "tiny" ->
                    Compendium.Tiny

                "small" ->
                    Compendium.Small

                "large" ->
                    Compendium.Large

                "huge" ->
                    Compendium.Huge

                "gargantuan" ->
                    Compendium.Gargantuan

                _ ->
                    Compendium.Medium
    in
    CompendiumEditSizeSet size


hoverToggle : Bool -> Html Msg
hoverToggle current =
    label [ class "edit-field edit-field--checkbox" ]
        [ input
            [ type_ "checkbox"
            , checked current
            , onClick CompendiumEditSpeedHoverToggle
            ]
            []
        , text "hover"
        ]


savingThrowsEditor : List ( Compendium.Ability, String ) -> List (Html Msg)
savingThrowsEditor rows =
    List.indexedMap savingThrowRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditSavingThrowAdd
                ]
                [ text "+ Add Save" ]
           ]


savingThrowRow : Int -> ( Compendium.Ability, String ) -> Html Msg
savingThrowRow idx ( ability, bonus ) =
    div [ class "edit-row edit-row--list-item" ]
        [ Html.select
            [ class "edit-field__input edit-field--narrow"
            , onInput (abilityFromString >> CompendiumEditSavingThrowAbilitySet idx)
            ]
            (List.map
                (\a ->
                    option
                        [ value (abilityKey a)
                        , selected (a == ability)
                        ]
                        [ text (abilityShort a) ]
                )
                [ Compendium.Str
                , Compendium.Dex
                , Compendium.Con
                , Compendium.Int_
                , Compendium.Wis
                , Compendium.Cha
                ]
            )
        , input
            [ type_ "number"
            , value bonus
            , onInput (CompendiumEditSavingThrowBonusChanged idx)
            , class "edit-field__input edit-field--narrow"
            , attribute "aria-label" "Bonus"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditSavingThrowRemove idx)
            , title Tooltips.compendiumEditRemoveSave
            ]
            [ text "×" ]
        ]


abilityKey : Compendium.Ability -> String
abilityKey a =
    case a of
        Compendium.Str ->
            "str"

        Compendium.Dex ->
            "dex"

        Compendium.Con ->
            "con"

        Compendium.Int_ ->
            "int"

        Compendium.Wis ->
            "wis"

        Compendium.Cha ->
            "cha"


abilityFromString : String -> Compendium.Ability
abilityFromString raw =
    case raw of
        "dex" ->
            Compendium.Dex

        "con" ->
            Compendium.Con

        "int" ->
            Compendium.Int_

        "wis" ->
            Compendium.Wis

        "cha" ->
            Compendium.Cha

        _ ->
            Compendium.Str


abilityShort : Compendium.Ability -> String
abilityShort a =
    case a of
        Compendium.Str ->
            "STR"

        Compendium.Dex ->
            "DEX"

        Compendium.Con ->
            "CON"

        Compendium.Int_ ->
            "INT"

        Compendium.Wis ->
            "WIS"

        Compendium.Cha ->
            "CHA"


skillsEditor : List ( String, String ) -> List (Html Msg)
skillsEditor rows =
    List.indexedMap skillRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditSkillAdd
                ]
                [ text "+ Add Skill" ]
           ]


skillRow : Int -> ( String, String ) -> Html Msg
skillRow idx ( name_, bonus ) =
    div [ class "edit-row edit-row--list-item" ]
        [ input
            [ type_ "text"
            , value name_
            , Attr.placeholder "Skill name (e.g. Perception)"
            , onInput (CompendiumEditSkillNameChanged idx)
            , class "edit-field__input"
            ]
            []
        , input
            [ type_ "number"
            , value bonus
            , onInput (CompendiumEditSkillBonusChanged idx)
            , class "edit-field__input edit-field--narrow"
            , attribute "aria-label" "Bonus"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditSkillRemove idx)
            , title Tooltips.compendiumEditRemoveSkill
            ]
            [ text "×" ]
        ]


featuresEditor : FeatureGroup -> List FeatureDraft -> List (Html Msg)
featuresEditor group rows =
    List.indexedMap (featureRow group) rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick (CompendiumEditFeatureAdd group)
                ]
                [ text "+ Add Entry" ]
           ]


featureRow : FeatureGroup -> Int -> FeatureDraft -> Html Msg
featureRow group idx draft =
    div [ class "edit-feature" ]
        [ div [ class "edit-row edit-row--list-item" ]
            [ input
                [ type_ "text"
                , value draft.name
                , Attr.placeholder "Name (e.g. Multiattack)"
                , onInput (CompendiumEditFeatureNameChanged group idx)
                , class "edit-field__input"
                ]
                []
            , button
                [ class "edit-row__remove"
                , onClick (CompendiumEditFeatureRemove group idx)
                , title Tooltips.compendiumEditRemoveEntry
                ]
                [ text "×" ]
            ]
        , Html.textarea
            [ value draft.description
            , onInput (CompendiumEditFeatureDescriptionChanged group idx)
            , class "edit-field__input"
            , attribute "rows" "3"
            , Attr.placeholder "Description (free text; inline dice notation like 1d8+3 becomes clickable)"
            ]
            []
        ]


customSectionsEditor : List ( String, String ) -> List (Html Msg)
customSectionsEditor rows =
    List.indexedMap customSectionRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditCustomSectionAdd
                ]
                [ text "+ Add Section" ]
           ]


customSectionRow : Int -> ( String, String ) -> Html Msg
customSectionRow idx ( name_, body_ ) =
    div [ class "edit-feature" ]
        [ div [ class "edit-row edit-row--list-item" ]
            [ input
                [ type_ "text"
                , value name_
                , Attr.placeholder "Section heading"
                , onInput (CompendiumEditCustomSectionNameChanged idx)
                , class "edit-field__input"
                ]
                []
            , button
                [ class "edit-row__remove"
                , onClick (CompendiumEditCustomSectionRemove idx)
                , title Tooltips.compendiumEditRemoveSection
                ]
                [ text "×" ]
            ]
        , Html.textarea
            [ value body_
            , onInput (CompendiumEditCustomSectionBodyChanged idx)
            , class "edit-field__input"
            , attribute "rows" "3"
            ]
            []
        ]


{-| Heads-up: the four advanced sections (legendary / lair /
regional / spellcasting) aren't editable in this MVP form yet. If
the source creature had any populated, they're preserved verbatim
through submit; if you're starting from scratch they just stay
empty.
-}
advancedSectionsNotice : CompendiumEditUi -> Html Msg
advancedSectionsNotice ui =
    let
        hasAny =
            ui.legendaryActions
                /= Nothing
                || ui.lairActions
                /= Nothing
                || ui.regionalEffects
                /= Nothing
                || ui.spellcasting
                /= Nothing
    in
    if hasAny then
        div [ class "edit-advanced-notice" ]
            [ text "Note: this creature has Legendary / Lair / Regional / Spellcasting data that this form doesn't yet edit. Those sections will be preserved on save." ]

    else
        text ""


footer : CompendiumEditUi -> Html Msg
footer ui =
    div [ class "edit-footer" ]
        [ if isEditingExisting ui then
            button
                [ class "action-btn action-btn--red"
                , onClick CompendiumEditDelete
                , disabled ui.submitting
                , title Tooltips.compendiumEditDeleteCreature
                ]
                [ text "🗑 Delete" ]

          else
            text ""
        , div [ class "edit-footer__spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumEditCancel
            , disabled ui.submitting
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick CompendiumEditSubmit
            , disabled ui.submitting
            ]
            [ text
                (if ui.submitting then
                    "Saving…"

                 else
                    submitLabel ui.mode
                )
            ]
        ]


submitLabel : EditMode -> String
submitLabel mode =
    case mode of
        CreateMode ->
            "Create"

        EditExisting _ ->
            "Save"


isEditingExisting : CompendiumEditUi -> Bool
isEditingExisting ui =
    case ui.mode of
        CreateMode ->
            False

        EditExisting _ ->
            True
