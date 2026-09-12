module View.Compendium.EditPane exposing (view)

{-| Compendium edit / create editor, filling the browser's
detail pane. ~50-field form covering
identity, combat core, abilities, saves, skills, properties,
senses, and four feature groups (traits / actions / bonus actions
/ reactions) plus a free-form custom-sections list.

The four advanced sections (legendary / lair / regional /
spellcasting) aren't editable here yet — they're preserved
verbatim through submit. The notice at the bottom of the form
flags that to the GM when the source creature has any populated.

-}

import Compendium
import Compendium.Reference
import Html exposing (Html, button, div, input, label, option, span, text, textarea)
import Html.Attributes as Attr exposing (attribute, checked, class, disabled, name, placeholder, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg
    exposing
        ( CompendiumField(..)
        , DamagePicker(..)
        , FeatureGroup(..)
        , Msg(..)
        , UsageKind(..)
        )
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumEditUi
        , EditMode(..)
        , FeatureDraft
        )
import View.Compendium.Pane
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceCompendiumEdit ui) ->
            View.Compendium.Pane.chrome
                { close = CompendiumEditCancel
                , title = paneTitle ui
                , extraClass = "compendium__editor-pane--edit"
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
                        [ inlineRow
                            [ damageTypePicker
                                { label = "Damage Vulnerabilities"
                                , kind = DamageVulnerabilitiesPicker
                                , selected = ui.damageVulnerabilities
                                }
                            , damageTypePicker
                                { label = "Damage Resistances"
                                , kind = DamageResistancesPicker
                                , selected = ui.damageResistances
                                }
                            ]
                        , inlineRow
                            [ damageTypePicker
                                { label = "Damage Immunities"
                                , kind = DamageImmunitiesPicker
                                , selected = ui.damageImmunities
                                }
                            , conditionPicker ui.conditionImmunities
                            ]
                        , inlineRow
                            [ narrowTextField "Challenge Rating" CFChallengeRating ui.challengeRating []
                            , numberField "XP" CFXp ui.xp []
                            , numberField "XP in Lair" CFXpInLair ui.xpInLair []
                            , numberField "Proficiency Bonus" CFProficiencyBonus ui.proficiencyBonus []
                            ]
                        , inlineRow
                            [ textField "Languages" CFLanguages ui.languages [] ]
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
                    , editSection "Spellcasting"
                        (spellcastingEditor ui.spellcasting)
                    , editSection "Bonus Actions"
                        (featuresEditor BonusActionsGroup ui.bonusActions)
                    , editSection "Reactions"
                        (featuresEditor ReactionsGroup ui.reactions
                            ++ specialReactionsToggleRow ui.hasSpecialReactions
                        )
                    , editSection "Custom Sections"
                        (customSectionsEditor ui.customSections)
                    , editSection "Legendary Actions"
                        (legendaryEditor ui.legendaryActions)
                    , editSection "Tags"
                        (tagsEditor ui.tags)
                    , editSection "Loot"
                        (lootEditor ui.loot)
                    , editSection "Lair Actions"
                        (lairEditor ui.lairActions)
                    , editSection "Regional Effects"
                        (regionalEditor ui.regionalEffects)
                    , editSection "Habitats"
                        [ habitatPicker "Material Plane"
                            (List.filter (not << Compendium.isPlanarHabitat) Compendium.allHabitats)
                            ui.habitats
                        , habitatPicker "Planar"
                            (List.filter Compendium.isPlanarHabitat Compendium.allHabitats)
                            ui.habitats
                        ]
                    , editSection "Treasure"
                        [ treasurePicker Compendium.allTreasures ui.treasures ]
                    , footer ui
                    ]
                }

        _ ->
            text ""


paneTitle : CompendiumEditUi -> String
paneTitle ui =
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


{-| Width-constrained text field for short values like CR
("1/4", "20") that don't need the default 140px flex.
-}
narrowTextField : String -> CompendiumField -> String -> List (Html.Attribute Msg) -> Html Msg
narrowTextField labelText field current extras =
    label [ class "edit-field edit-field--narrow" ]
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
            , Tooltips.attr Tooltips.compendiumEditRemoveSave
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
            , Tooltips.attr Tooltips.compendiumEditRemoveSkill
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


{-| Single checkbox tagged onto the Reactions section. Flags the
creature as having reaction mechanics worth a heads-up beyond
the standard "one reaction per round" UX. Sets a Bool on the
creature; the card's reaction-pip glyph reads bold yellow `!`
when the flag is on.
-}
specialReactionsToggleRow : Bool -> List (Html Msg)
specialReactionsToggleRow checked_ =
    [ Html.label [ class "edit-feature edit-special-reactions" ]
        [ input
            [ type_ "checkbox"
            , checked checked_
            , onClick CompendiumEditSpecialReactionsToggle
            ]
            []
        , span [ class "edit-special-reactions__label" ]
            [ text "Special reaction mechanics" ]
        , span [ class "edit-special-reactions__hint" ]
            [ text "Card reaction pip shows a yellow ! to remind the GM to consult the stat block." ]
        ]
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
                , Tooltips.attr Tooltips.compendiumEditRemoveEntry
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
        , featureUsageRow group idx draft.usage
        ]


{-| Per-feature Usage editor: a kind dropdown plus conditional
param fields for the chosen variant. `None` collapses to just
the dropdown; `Recharge` shows low/high; the per-day-style
variants show a single uses count.

When the feature already has a usage set, a small × button trails
the row so the user can clear it back to None without opening the
dropdown (or having to delete the whole action just to drop the
usage). The clear routes through `featureUsageKindSet UsageNone`,
which already restores any `(Recharge ...)` parenthetical stripped
on the way in — so Recharge → × is a faithful inverse of None →
Recharge for bundled creatures.

-}
featureUsageRow : FeatureGroup -> Int -> Maybe Compendium.Usage -> Html Msg
featureUsageRow group idx usage =
    div [ class "edit-feature__usage" ]
        [ Html.label [ class "edit-feature__usage-label" ]
            [ Html.span [ class "edit-field__label" ] [ text "Usage" ]
            , Html.select
                [ class "edit-field__input"
                , Html.Events.onInput (usageKindFromString >> CompendiumEditFeatureUsageKindSet group idx)
                ]
                (List.map (usageKindOption usage)
                    [ ( UsageNone, "—" )
                    , ( UsageRecharge, "Recharge" )
                    , ( UsagePerDay, "Per Day" )
                    , ( UsagePerShortRest, "Per Short Rest" )
                    , ( UsagePerLongRest, "Per Long Rest" )
                    , ( UsageAtWill, "At Will" )
                    ]
                )
            ]
        , usageParams group idx usage
        , usageClearButton group idx usage
        ]


usageClearButton : FeatureGroup -> Int -> Maybe Compendium.Usage -> Html Msg
usageClearButton group idx usage =
    case usage of
        Just _ ->
            button
                [ class "edit-row__remove edit-feature__usage-clear"
                , Attr.type_ "button"
                , onClick (CompendiumEditFeatureUsageKindSet group idx UsageNone)
                , Tooltips.attr Tooltips.compendiumEditClearUsage
                , Attr.attribute "aria-label" Tooltips.compendiumEditClearUsage
                ]
                [ text "×" ]

        Nothing ->
            text ""


usageKindOption : Maybe Compendium.Usage -> ( UsageKind, String ) -> Html Msg
usageKindOption usage ( kind, label_ ) =
    Html.option
        [ value (usageKindToString kind)
        , selected (kind == kindOf usage)
        ]
        [ text label_ ]


kindOf : Maybe Compendium.Usage -> UsageKind
kindOf usage =
    case usage of
        Nothing ->
            UsageNone

        Just (Compendium.Recharge _) ->
            UsageRecharge

        Just (Compendium.PerDay _) ->
            UsagePerDay

        Just (Compendium.PerShortRest _) ->
            UsagePerShortRest

        Just (Compendium.PerLongRest _) ->
            UsagePerLongRest

        Just Compendium.AtWill ->
            UsageAtWill


usageKindToString : UsageKind -> String
usageKindToString kind =
    case kind of
        UsageNone ->
            "none"

        UsageRecharge ->
            "recharge"

        UsagePerDay ->
            "per_day"

        UsagePerShortRest ->
            "per_short_rest"

        UsagePerLongRest ->
            "per_long_rest"

        UsageAtWill ->
            "at_will"


usageKindFromString : String -> UsageKind
usageKindFromString s =
    case s of
        "recharge" ->
            UsageRecharge

        "per_day" ->
            UsagePerDay

        "per_short_rest" ->
            UsagePerShortRest

        "per_long_rest" ->
            UsagePerLongRest

        "at_will" ->
            UsageAtWill

        _ ->
            UsageNone


usageParams : FeatureGroup -> Int -> Maybe Compendium.Usage -> Html Msg
usageParams group idx usage =
    case usage of
        Just (Compendium.Recharge { low, high }) ->
            Html.span [ class "edit-feature__usage-params" ]
                [ rawNumberField "Low"
                    (CompendiumEditFeatureUsageRechargeLowChanged group idx)
                    (String.fromInt low)
                , rawNumberField "High"
                    (CompendiumEditFeatureUsageRechargeHighChanged group idx)
                    (String.fromInt high)
                ]

        Just (Compendium.PerDay n) ->
            usesField group idx n

        Just (Compendium.PerShortRest n) ->
            usesField group idx n

        Just (Compendium.PerLongRest n) ->
            usesField group idx n

        _ ->
            text ""


usesField : FeatureGroup -> Int -> Int -> Html Msg
usesField group idx n =
    Html.span [ class "edit-feature__usage-params" ]
        [ rawNumberField "Uses"
            (CompendiumEditFeatureUsageUsesChanged group idx)
            (String.fromInt n)
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
                , Tooltips.attr Tooltips.compendiumEditRemoveSection
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


{-| Free-form tag editor. Each row is a single text input + a
remove button; "+ Add Tag" appends an empty row. Validation
(one-word / dedup) runs at submit, so the UI accepts the row as
typed even mid-edit.
-}
tagsEditor : List String -> List (Html Msg)
tagsEditor rows =
    List.indexedMap tagRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditTagAdd
                ]
                [ text "+ Add Tag" ]
           ]


tagRow : Int -> String -> Html Msg
tagRow idx tag =
    div [ class "edit-row edit-row--list-item" ]
        [ input
            [ type_ "text"
            , value tag
            , Attr.placeholder "tag_name"
            , onInput (CompendiumEditTagChanged idx)
            , class "edit-field__input"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditTagRemove idx)
            , Tooltips.attr Tooltips.compendiumEditRemoveTag
            ]
            [ text "×" ]
        ]


{-| Free-form loot editor. One text input per item the creature
carries; "+ Add Loot Item" appends a row. Empty rows get
filtered on submit so a half-typed row mid-edit doesn't end up
as a phantom "" entry.
-}
lootEditor : List String -> List (Html Msg)
lootEditor rows =
    List.indexedMap lootRow rows
        ++ [ button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditLootAdd
                ]
                [ text "+ Add Loot Item" ]
           ]


lootRow : Int -> String -> Html Msg
lootRow idx item =
    div [ class "edit-row edit-row--list-item" ]
        [ input
            [ type_ "text"
            , value item
            , Attr.placeholder "e.g. Bone necklace, Crumpled map fragment"
            , onInput (CompendiumEditLootChanged idx)
            , class "edit-field__input"
            ]
            []
        , button
            [ class "edit-row__remove"
            , onClick (CompendiumEditLootRemove idx)
            ]
            [ text "×" ]
        ]



-- ── DAMAGE / CONDITION MULTI-SELECT PICKERS ────────────────────────────


{-| Multi-select chip picker for damage types — one cluster per
canonical 2024 damage list. `kind` selects which Ui field to
toggle (vulnerabilities / resistances / immunities); `selected`
is the current contents.
-}
damageTypePicker :
    { label : String, kind : DamagePicker, selected : List String }
    -> Html Msg
damageTypePicker cfg =
    chipPicker
        { label = cfg.label
        , options = Compendium.Reference.damageTypes
        , selected = cfg.selected
        , onToggle = CompendiumEditDamageToggle cfg.kind
        }


conditionPicker : List String -> Html Msg
conditionPicker selected =
    chipPicker
        { label = "Condition Immunities"
        , options = Compendium.Reference.conditions
        , selected = selected
        , onToggle = CompendiumEditConditionToggle
        }


{-| Typed multi-select for habitats. Mirrors `chipPicker` but
toggles a `Habitat` value (not a string) so the wire format is
the closed ADT and a typo can't sneak into the saved record.
-}
habitatPicker : String -> List Compendium.Habitat -> List Compendium.Habitat -> Html Msg
habitatPicker labelText options selected =
    let
        chip h =
            let
                active =
                    List.member h selected

                cls =
                    if active then
                        "edit-chip-picker__chip edit-chip-picker__chip--active"

                    else
                        "edit-chip-picker__chip"
            in
            button
                [ type_ "button"
                , class cls
                , onClick (CompendiumEditHabitatToggle h)
                , attribute "aria-pressed"
                    (if active then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text (Compendium.habitatLabel h) ]
    in
    div [ class "edit-field edit-field--picker" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , div [ class "edit-chip-picker" ]
            (List.map chip options)
        ]


{-| Typed multi-select for treasure tags. Same shape as
`habitatPicker`; kept as a sibling rather than abstracted to a
generic `typedChipPicker` because two callers don't pay for the
extra parameter plumbing.
-}
treasurePicker : List Compendium.Treasure -> List Compendium.Treasure -> Html Msg
treasurePicker options selected =
    let
        chip t =
            let
                active =
                    List.member t selected

                cls =
                    if active then
                        "edit-chip-picker__chip edit-chip-picker__chip--active"

                    else
                        "edit-chip-picker__chip"
            in
            button
                [ type_ "button"
                , class cls
                , onClick (CompendiumEditTreasureToggle t)
                , attribute "aria-pressed"
                    (if active then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text (Compendium.treasureLabel t) ]
    in
    div [ class "edit-field edit-field--picker" ]
        [ div [ class "edit-chip-picker" ]
            (List.map chip options)
        ]


{-| Generic multi-select chip picker. Renders the label, then a
flexbox of every option as a button with an "active" modifier
class when the option is currently in `selected`. Clicking
fires `onToggle` with the option's name.
-}
chipPicker :
    { label : String
    , options : List String
    , selected : List String
    , onToggle : String -> Msg
    }
    -> Html Msg
chipPicker cfg =
    let
        chip option =
            let
                active =
                    List.member option cfg.selected

                cls =
                    if active then
                        "edit-chip-picker__chip edit-chip-picker__chip--active"

                    else
                        "edit-chip-picker__chip"
            in
            button
                [ type_ "button"
                , class cls
                , onClick (cfg.onToggle option)
                , attribute "aria-pressed"
                    (if active then
                        "true"

                     else
                        "false"
                    )
                ]
                [ text option ]
    in
    div [ class "edit-field edit-field--picker" ]
        [ span [ class "edit-field__label" ] [ text cfg.label ]
        , div [ class "edit-chip-picker" ]
            (List.map chip cfg.options)
        ]



-- ── ADVANCED SECTION EDITORS ────────────────────────────────────────────
--
-- Each advanced section follows the same shape: when `Nothing`,
-- render an "Add" button; when `Just`, render the editor body
-- with a Remove button at the top.  The editor bodies are
-- straightforward CRUD over the substructure.


sectionToggle :
    { label : String, addMsg : Msg }
    -> Html Msg
sectionToggle cfg =
    button
        [ class "action-btn action-btn--blue edit-add-btn"
        , onClick cfg.addMsg
        ]
        [ text cfg.label ]


sectionRemoveButton : Msg -> Html Msg
sectionRemoveButton msg =
    button
        [ class "action-btn action-btn--red edit-add-btn"
        , onClick msg
        ]
        [ text "Remove section" ]


legendaryEditor : Maybe Compendium.LegendaryActions -> List (Html Msg)
legendaryEditor maybeLa =
    case maybeLa of
        Nothing ->
            [ sectionToggle
                { label = "+ Add Legendary Actions"
                , addMsg = CompendiumEditLegendaryAdd
                }
            ]

        Just la ->
            [ inlineRow
                [ rawNumberField "Uses"
                    (CompendiumEditLegendaryUsesChanged << identity)
                    (String.fromInt la.uses)
                , rawNumberField "Uses (in lair)"
                    (CompendiumEditLegendaryUsesInLairChanged << identity)
                    (String.fromInt la.usesInLair)
                ]
            , rawTextarea "Description"
                CompendiumEditLegendaryDescriptionChanged
                la.description
                3
            , Html.h4 [ class "edit-subheading" ] [ text "Options" ]
            , div [ class "edit-section__list" ]
                (List.indexedMap legendaryOptionRow la.options)
            , inlineRow
                [ button
                    [ class "action-btn action-btn--blue edit-add-btn"
                    , onClick CompendiumEditLegendaryOptionAdd
                    ]
                    [ text "+ Add Option" ]
                , sectionRemoveButton CompendiumEditLegendaryRemove
                ]
            ]


{-| Two-row layout per legendary option: the name + remove
button on the top row, and a wider, indented description
textarea below it. The 2024 PHB dropped the per-option "cost"
system in favour of a flat per-round uses count, so the editor
no longer surfaces Cost; existing imported creatures retain
whatever cost was on the data and it's preserved through
submit untouched.
-}
legendaryOptionRow : Int -> Compendium.LegendaryOption -> Html Msg
legendaryOptionRow idx opt =
    div [ class "edit-legendary-option" ]
        [ div [ class "edit-row edit-row--list-item" ]
            [ rawTextField "Name"
                (CompendiumEditLegendaryOptionNameChanged idx)
                opt.name
            , removeButton (CompendiumEditLegendaryOptionRemove idx)
            ]
        , div [ class "edit-legendary-option__body" ]
            [ rawTextarea "Description"
                (CompendiumEditLegendaryOptionDescriptionChanged idx)
                opt.description
                3
            ]
        ]


lairEditor : Maybe Compendium.LairActions -> List (Html Msg)
lairEditor maybeLa =
    case maybeLa of
        Nothing ->
            [ sectionToggle
                { label = "+ Add Lair Actions"
                , addMsg = CompendiumEditLairAdd
                }
            ]

        Just la ->
            [ inlineRow
                [ rawNumberField "Initiative"
                    CompendiumEditLairInitiativeChanged
                    (String.fromInt la.initiative)
                ]
            , rawTextarea "Description"
                CompendiumEditLairDescriptionChanged
                la.description
                3
            , Html.h4 [ class "edit-subheading" ] [ text "Options" ]
            , div [ class "edit-section__list" ]
                (List.indexedMap lairOptionRow la.options)
            , inlineRow
                [ button
                    [ class "action-btn action-btn--blue edit-add-btn"
                    , onClick CompendiumEditLairOptionAdd
                    ]
                    [ text "+ Add Option" ]
                , sectionRemoveButton CompendiumEditLairRemove
                ]
            ]


lairOptionRow : Int -> Compendium.Feature -> Html Msg
lairOptionRow idx feat =
    div [ class "edit-row edit-row--list-item" ]
        [ rawTextField "Name"
            (CompendiumEditLairOptionNameChanged idx)
            feat.name
        , rawTextField "Description"
            (CompendiumEditLairOptionDescriptionChanged idx)
            feat.description
        , removeButton (CompendiumEditLairOptionRemove idx)
        ]


regionalEditor : Maybe Compendium.RegionalEffects -> List (Html Msg)
regionalEditor maybeRe =
    case maybeRe of
        Nothing ->
            [ sectionToggle
                { label = "+ Add Regional Effects"
                , addMsg = CompendiumEditRegionalAdd
                }
            ]

        Just re ->
            [ rawTextarea "Description"
                CompendiumEditRegionalDescriptionChanged
                re.description
                2
            , rawTextField "Fade After"
                CompendiumEditRegionalFadeAfterChanged
                re.fadeAfter
            , Html.h4 [ class "edit-subheading" ] [ text "Effects" ]
            , div [ class "edit-section__list" ]
                (List.indexedMap regionalEffectRow re.effects)
            , inlineRow
                [ button
                    [ class "action-btn action-btn--blue edit-add-btn"
                    , onClick CompendiumEditRegionalEffectAdd
                    ]
                    [ text "+ Add Effect" ]
                , sectionRemoveButton CompendiumEditRegionalRemove
                ]
            ]


regionalEffectRow : Int -> Compendium.Feature -> Html Msg
regionalEffectRow idx feat =
    div [ class "edit-row edit-row--list-item" ]
        [ rawTextField "Name"
            (CompendiumEditRegionalEffectNameChanged idx)
            feat.name
        , rawTextField "Description"
            (CompendiumEditRegionalEffectDescriptionChanged idx)
            feat.description
        , removeButton (CompendiumEditRegionalEffectRemove idx)
        ]


spellcastingEditor : Maybe Compendium.Spellcasting -> List (Html Msg)
spellcastingEditor maybeSc =
    case maybeSc of
        Nothing ->
            [ sectionToggle
                { label = "+ Add Spellcasting"
                , addMsg = CompendiumEditSpellcastingAdd
                }
            ]

        Just sc ->
            [ rawTextarea "Description"
                CompendiumEditSpellcastingDescriptionChanged
                sc.description
                2
            , inlineRow
                [ spellcastingAbilityRadio sc.ability
                , rawNumberField "Save DC"
                    CompendiumEditSpellcastingSaveDcChanged
                    (String.fromInt sc.saveDc)
                , rawNumberField "Attack Bonus"
                    CompendiumEditSpellcastingAttackBonusChanged
                    (String.fromInt sc.attackBonus)
                ]
            , div [ class "spellcasting-atwill" ]
                [ Html.h4 [ class "edit-subheading" ]
                    [ text "At Will Spells (comma-separated)" ]
                , input
                    [ type_ "text"
                    , value (String.join ", " sc.atWill)
                    , onInput CompendiumEditSpellcastingAtWillChanged
                    , class "edit-field__input"
                    , attribute "aria-label" "At will spells, comma-separated"
                    ]
                    []
                ]
            , Html.h4 [ class "edit-subheading" ] [ text "Slot-Limited Spells" ]
            , div [ class "edit-section__list" ]
                (List.indexedMap spellcastingSlotRow sc.slots)
            , button
                [ class "action-btn action-btn--blue edit-add-btn"
                , onClick CompendiumEditSpellcastingSlotAdd
                ]
                [ text "+ Add Slot Level" ]
            , Html.h4 [ class "edit-subheading" ] [ text "Innate Per Day" ]
            , div [ class "edit-section__list" ]
                (List.indexedMap spellcastingInnateRow sc.innatePerDay)
            , inlineRow
                [ button
                    [ class "action-btn action-btn--blue edit-add-btn"
                    , onClick CompendiumEditSpellcastingInnateAdd
                    ]
                    [ text "+ Add Innate Group" ]
                , sectionRemoveButton CompendiumEditSpellcastingRemove
                ]
            ]


spellcastingSlotRow : Int -> Compendium.SpellSlotLevel -> Html Msg
spellcastingSlotRow idx slot =
    div [ class "edit-row edit-row--list-item" ]
        [ rawNumberField "Level"
            (CompendiumEditSpellcastingSlotLevelChanged idx)
            (String.fromInt slot.level)
        , rawNumberField "Slots"
            (CompendiumEditSpellcastingSlotCountChanged idx)
            (String.fromInt slot.slots)
        , rawTextField "Spells (comma-separated)"
            (CompendiumEditSpellcastingSlotSpellsChanged idx)
            (String.join ", " slot.spells)
        , removeButton (CompendiumEditSpellcastingSlotRemove idx)
        ]


spellcastingInnateRow : Int -> Compendium.InnatePerDay -> Html Msg
spellcastingInnateRow idx i =
    div [ class "edit-row edit-row--list-item" ]
        [ rawNumberField "Uses"
            (CompendiumEditSpellcastingInnateUsesChanged idx)
            (String.fromInt i.uses)
        , rawTextField "Spells (comma-separated)"
            (CompendiumEditSpellcastingInnateSpellsChanged idx)
            (String.join ", " i.spells)
        , removeButton (CompendiumEditSpellcastingInnateRemove idx)
        ]


spellcastingAbilityRadio : Compendium.Ability -> Html Msg
spellcastingAbilityRadio current =
    let
        radio ability label_ =
            Html.label [ class "edit-radio" ]
                [ input
                    [ type_ "radio"
                    , Attr.name "spellcasting-ability"
                    , checked (ability == current)
                    , onClick (CompendiumEditSpellcastingAbilitySet ability)
                    ]
                    []
                , text label_
                ]
    in
    div [ class "edit-field edit-field--radio-group" ]
        [ span [ class "edit-field__label" ] [ text "Ability" ]
        , div [ class "edit-radio-row" ]
            [ radio Compendium.Int_ "INT"
            , radio Compendium.Wis "WIS"
            , radio Compendium.Cha "CHA"
            ]
        ]



-- ── RAW INPUT HELPERS (any-Msg, not gated by CompendiumField) ──────────


rawTextField : String -> (String -> Msg) -> String -> Html Msg
rawTextField labelText toMsg current =
    label [ class "edit-field" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            [ type_ "text"
            , value current
            , onInput toMsg
            , class "edit-field__input"
            ]
            []
        ]


rawNumberField : String -> (String -> Msg) -> String -> Html Msg
rawNumberField labelText toMsg current =
    label [ class "edit-field edit-field--number" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , input
            [ type_ "number"
            , value current
            , onInput toMsg
            , class "edit-field__input"
            ]
            []
        ]


rawTextarea : String -> (String -> Msg) -> String -> Int -> Html Msg
rawTextarea labelText toMsg current rows =
    label [ class "edit-field edit-field--textarea" ]
        [ span [ class "edit-field__label" ] [ text labelText ]
        , textarea
            [ value current
            , onInput toMsg
            , class "edit-field__input"
            , Attr.rows rows
            ]
            []
        ]


removeButton : Msg -> Html Msg
removeButton msg =
    button
        [ class "edit-row__remove"
        , type_ "button"
        , onClick msg
        , attribute "aria-label" "Remove"
        , Tooltips.attr "Remove"
        ]
        [ text "×" ]


footer : CompendiumEditUi -> Html Msg
footer ui =
    div [ class "edit-footer" ]
        [ if isEditingExisting ui then
            button
                [ class "action-btn action-btn--red"
                , onClick CompendiumEditDelete
                , disabled ui.submitting
                , Tooltips.attr Tooltips.compendiumEditDeleteCreature
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
