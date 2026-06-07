module Update.Compendium.Edit exposing
    ( cancel
    , conditionToggle
    , currentlySelectedCreature
    , customSectionAdd
    , customSectionBodyChanged
    , customSectionNameChanged
    , customSectionRemove
    , damageToggle
    , delete
    , deleteResponse
    , duplicate
    , existing
    , featureAdd
    , featureDescriptionChanged
    , featureNameChanged
    , featureRemove
    , featureUsageKindSet
    , featureUsageRechargeHighChanged
    , featureUsageRechargeLowChanged
    , featureUsageUsesChanged
    , fieldChanged
    , habitatToggle
    , kindSet
    , lairAdd
    , lairDescriptionChanged
    , lairInitiativeChanged
    , lairOptionAdd
    , lairOptionDescriptionChanged
    , lairOptionNameChanged
    , lairOptionRemove
    , lairRemove
    , legendaryAdd
    , legendaryDescriptionChanged
    , legendaryOptionAdd
    , legendaryOptionDescriptionChanged
    , legendaryOptionNameChanged
    , legendaryOptionRemove
    , legendaryRemove
    , legendaryUsesChanged
    , legendaryUsesInLairChanged
    , new
    , regionalAdd
    , regionalDescriptionChanged
    , regionalEffectAdd
    , regionalEffectDescriptionChanged
    , regionalEffectNameChanged
    , regionalEffectRemove
    , regionalFadeAfterChanged
    , regionalRemove
    , savingThrowAbilitySet
    , savingThrowAdd
    , savingThrowBonusChanged
    , savingThrowRemove
    , sizeSet
    , skillAdd
    , skillBonusChanged
    , skillNameChanged
    , skillRemove
    , speedHoverToggle
    , spellcastingAbilitySet
    , spellcastingAdd
    , spellcastingAtWillChanged
    , spellcastingAttackBonusChanged
    , spellcastingDescriptionChanged
    , spellcastingInnateAdd
    , spellcastingInnateRemove
    , spellcastingInnateSpellsChanged
    , spellcastingInnateUsesChanged
    , spellcastingRemove
    , spellcastingSaveDcChanged
    , spellcastingSlotAdd
    , spellcastingSlotCountChanged
    , spellcastingSlotLevelChanged
    , spellcastingSlotRemove
    , spellcastingSlotSpellsChanged
    , submit
    , submitResponse
    , tagAdd
    , tagChanged
    , tagRemove
    , treasureToggle
    )

{-| Compendium-edit modal: the form for creating, editing, and
duplicating compendium creatures, plus the submit / delete /
response handlers that round-trip through `/api/compendium`.

This is the largest section by line count because the form has
~50 input fields plus four feature groups (traits, actions,
bonus actions, reactions) plus saving throws, skills, and custom
sections — each gets its own Add / Remove / FieldChanged
handler.

-}

import Auth
import Compendium
import Compendium.Wire
import Http
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CompendiumField(..)
        , DamagePicker(..)
        , FeatureGroup(..)
        , Msg(..)
        )
import Set
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumDb(..)
        , CompendiumEditUi
        , CompendiumUi
        , EditMode(..)
        , FeatureDraft
        , PendingAction(..)
        )
import Ui.Toast exposing (ToastKind(..))
import Update.Compendium.Browser exposing (withCompendium)
import Update.Toast
import Util.Http


withCompendiumEdit : (CompendiumEditUi -> CompendiumEditUi) -> Model -> Model
withCompendiumEdit =
    Model.mapModal Model.compendiumEditLens



-- ── EDIT MODAL ──────────────────────────────────────────────────────────


new : Model -> ( Model, Cmd Msg )
new model =
    ( { model | modal = Just (ModalCompendiumEdit CompendiumUi.blankEdit) }
    , Cmd.none
    )


existing : Model -> ( Model, Cmd Msg )
existing model =
    ( { model
        | modal =
            currentlySelectedCreature model
                |> Maybe.map (CompendiumUi.editFromCreature >> ModalCompendiumEdit)
      }
    , Cmd.none
    )


duplicate : Model -> ( Model, Cmd Msg )
duplicate model =
    ( { model
        | modal =
            currentlySelectedCreature model
                |> Maybe.map (editFromDuplicate >> ModalCompendiumEdit)
      }
    , Cmd.none
    )


currentlySelectedCreature : Model -> Maybe Compendium.Creature
currentlySelectedCreature model =
    case ( model.compendium.db, model.compendium.selectedId ) of
        ( CompendiumDbLoaded db, Just id ) ->
            Compendium.find id db

        _ ->
            Nothing


{-| Build an edit form pre-filled from `source` but with the mode
flipped to `CreateMode` and a "(copy)"-suffixed name. The back end
will issue a fresh id on submit.
-}
editFromDuplicate : Compendium.Creature -> CompendiumEditUi
editFromDuplicate source =
    let
        base =
            CompendiumUi.editFromCreature source
    in
    { base
        | mode = CreateMode
        , name = source.name ++ " (copy)"
    }


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | modal = Nothing }, Cmd.none )


fieldChanged : CompendiumField -> String -> Model -> ( Model, Cmd Msg )
fieldChanged field text model =
    ( withCompendiumEdit (setEditField field text) model, Cmd.none )


setEditField : CompendiumField -> String -> CompendiumEditUi -> CompendiumEditUi
setEditField field text ui =
    case field of
        CFName ->
            { ui | name = text }

        CFRace ->
            { ui | race = text }

        CFSubrace ->
            { ui | subrace = text }

        CFAlignment ->
            { ui | alignment = text }

        CFSource ->
            { ui | source = text }

        CFDescription ->
            { ui | description = text }

        CFArmorClass ->
            { ui | armorClass = text }

        CFArmorClassNote ->
            { ui | armorClassNote = text }

        CFMaxHp ->
            { ui | maxHp = text }

        CFHpFormula ->
            { ui | hpFormula = text }

        CFInitiativeBonus ->
            { ui | initiativeBonus = text }

        CFSpeedWalk ->
            { ui | speedWalk = text }

        CFSpeedFly ->
            { ui | speedFly = text }

        CFSpeedSwim ->
            { ui | speedSwim = text }

        CFSpeedClimb ->
            { ui | speedClimb = text }

        CFSpeedBurrow ->
            { ui | speedBurrow = text }

        CFAbilityStr ->
            { ui | abilityStr = text }

        CFAbilityDex ->
            { ui | abilityDex = text }

        CFAbilityCon ->
            { ui | abilityCon = text }

        CFAbilityInt ->
            { ui | abilityInt = text }

        CFAbilityWis ->
            { ui | abilityWis = text }

        CFAbilityCha ->
            { ui | abilityCha = text }

        CFSensesBlindsight ->
            { ui | sensesBlindsight = text }

        CFSensesDarkvision ->
            { ui | sensesDarkvision = text }

        CFSensesTremorsense ->
            { ui | sensesTremorsense = text }

        CFSensesTruesight ->
            { ui | sensesTruesight = text }

        CFSensesPassivePerception ->
            { ui | sensesPassivePerception = text }

        CFLanguages ->
            { ui | languages = text }

        CFChallengeRating ->
            { ui | challengeRating = text }

        CFXp ->
            { ui | xp = text }

        CFXpInLair ->
            { ui | xpInLair = text }

        CFProficiencyBonus ->
            { ui | proficiencyBonus = text }


kindSet : Compendium.CreatureKind -> Model -> ( Model, Cmd Msg )
kindSet kind model =
    ( withCompendiumEdit (\ui -> { ui | kind = kind }) model, Cmd.none )


sizeSet : Compendium.Size -> Model -> ( Model, Cmd Msg )
sizeSet size model =
    ( withCompendiumEdit (\ui -> { ui | size = size }) model, Cmd.none )


speedHoverToggle : Model -> ( Model, Cmd Msg )
speedHoverToggle model =
    ( withCompendiumEdit (\ui -> { ui | speedHover = not ui.speedHover }) model, Cmd.none )


savingThrowAdd : Model -> ( Model, Cmd Msg )
savingThrowAdd model =
    ( withCompendiumEdit
        (\ui -> { ui | savingThrows = ui.savingThrows ++ [ ( Compendium.Str, "0" ) ] })
        model
    , Cmd.none
    )


savingThrowRemove : Int -> Model -> ( Model, Cmd Msg )
savingThrowRemove idx model =
    ( withCompendiumEdit (\ui -> { ui | savingThrows = removeAt idx ui.savingThrows }) model
    , Cmd.none
    )


savingThrowAbilitySet : Int -> Compendium.Ability -> Model -> ( Model, Cmd Msg )
savingThrowAbilitySet idx ability model =
    ( withCompendiumEdit
        (\ui ->
            { ui | savingThrows = updateAt idx (\( _, b ) -> ( ability, b )) ui.savingThrows }
        )
        model
    , Cmd.none
    )


savingThrowBonusChanged : Int -> String -> Model -> ( Model, Cmd Msg )
savingThrowBonusChanged idx text model =
    ( withCompendiumEdit
        (\ui ->
            { ui | savingThrows = updateAt idx (\( a, _ ) -> ( a, text )) ui.savingThrows }
        )
        model
    , Cmd.none
    )


skillAdd : Model -> ( Model, Cmd Msg )
skillAdd model =
    ( withCompendiumEdit (\ui -> { ui | skills = ui.skills ++ [ ( "", "0" ) ] }) model
    , Cmd.none
    )


skillRemove : Int -> Model -> ( Model, Cmd Msg )
skillRemove idx model =
    ( withCompendiumEdit (\ui -> { ui | skills = removeAt idx ui.skills }) model
    , Cmd.none
    )


skillNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
skillNameChanged idx text model =
    ( withCompendiumEdit
        (\ui -> { ui | skills = updateAt idx (\( _, b ) -> ( text, b )) ui.skills })
        model
    , Cmd.none
    )


skillBonusChanged : Int -> String -> Model -> ( Model, Cmd Msg )
skillBonusChanged idx text model =
    ( withCompendiumEdit
        (\ui -> { ui | skills = updateAt idx (\( n, _ ) -> ( n, text )) ui.skills })
        model
    , Cmd.none
    )


featureAdd : FeatureGroup -> Model -> ( Model, Cmd Msg )
featureAdd group model =
    ( withCompendiumEdit (mapFeatureGroup group (\fs -> fs ++ [ CompendiumUi.emptyFeatureDraft ])) model
    , Cmd.none
    )


featureRemove : FeatureGroup -> Int -> Model -> ( Model, Cmd Msg )
featureRemove group idx model =
    ( withCompendiumEdit (mapFeatureGroup group (removeAt idx)) model, Cmd.none )


featureNameChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
featureNameChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group (updateAt idx (\f -> { f | name = text })))
        model
    , Cmd.none
    )


featureDescriptionChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
featureDescriptionChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group (updateAt idx (\f -> { f | description = text })))
        model
    , Cmd.none
    )


{-| Switch a feature's `usage` between the six `UsageKind`
options. The kind selector is the dropdown; per-kind params
(Recharge low/high, per-day-style uses count) are tweaked by
the `featureUsageRechargeLowChanged` etc. handlers below.

When the transition lands ON Recharge, any trailing
`(Recharge N-M)` parenthetical in the feature name is stripped
so the structured `usage` field is the single source of truth.
When the transition leaves Recharge, the just-vacated range is
re-appended to the name so a Recharge → None → Recharge round
trip is information-preserving — important for bundled SRD
creatures whose canonical name bakes the recharge mechanic in.

-}
featureUsageKindSet : FeatureGroup -> Int -> Msg.UsageKind -> Model -> ( Model, Cmd Msg )
featureUsageKindSet group idx kind model =
    ( withCompendiumEdit
        (mapFeatureGroup group
            (updateAt idx (applyUsageKindChange kind))
        )
        model
    , Cmd.none
    )


applyUsageKindChange : Msg.UsageKind -> CompendiumUi.FeatureDraft -> CompendiumUi.FeatureDraft
applyUsageKindChange kind f =
    let
        newUsage =
            usageFromKind kind f.usage

        newName =
            rechargeAwareNameTransition f.usage newUsage f.name
    in
    { f | usage = newUsage, name = newName }


{-| Pure decision: given the previous and next `Usage` values and
the current feature name, return the name the form should now
show.

  - Leaving Recharge → re-append `(Recharge low-high)` using the
    _previous_ range so the user can round-trip without losing the
    mechanic embedded in the name.
  - Entering Recharge → strip a trailing recharge parenthetical so
    it doesn't double up against the structured field.
  - Recharge → Recharge with a new range → keep the name as-is (the
    invariant maintained on entry already excluded any suffix).
  - Any non-Recharge ↔ non-Recharge transition → name unchanged.

-}
rechargeAwareNameTransition : Maybe Compendium.Usage -> Maybe Compendium.Usage -> String -> String
rechargeAwareNameTransition prev next name =
    case ( prev, next ) of
        ( Just (Compendium.Recharge _), Just (Compendium.Recharge _) ) ->
            -- Both Recharge: range tweak only, name already
            -- canonical (no suffix).  Nothing to do.
            name

        ( Just (Compendium.Recharge prevRange), _ ) ->
            -- Leaving Recharge for some other kind (or None):
            -- restore the parenthetical so the printed name still
            -- conveys the mechanic.
            Compendium.appendRechargeSuffix prevRange name

        ( _, Just (Compendium.Recharge _) ) ->
            -- Entering Recharge from a non-Recharge state: drop
            -- the trailing `(Recharge ...)` so the structured field
            -- is the single source of truth.
            Compendium.stripTrailingRecharge name

        _ ->
            name


{-| When the user picks a new Usage kind, carry over any param
values that still make sense (e.g. switching Per Day → Per Long
Rest preserves the uses count) so the form doesn't drop input
on every kind change.
-}
usageFromKind : Msg.UsageKind -> Maybe Compendium.Usage -> Maybe Compendium.Usage
usageFromKind kind prev =
    let
        prevUses =
            case prev of
                Just (Compendium.PerDay n) ->
                    n

                Just (Compendium.PerShortRest n) ->
                    n

                Just (Compendium.PerLongRest n) ->
                    n

                _ ->
                    1

        prevRecharge =
            case prev of
                Just (Compendium.Recharge r) ->
                    r

                _ ->
                    { low = 5, high = 6 }
    in
    case kind of
        Msg.UsageNone ->
            Nothing

        Msg.UsageRecharge ->
            Just (Compendium.Recharge prevRecharge)

        Msg.UsagePerDay ->
            Just (Compendium.PerDay prevUses)

        Msg.UsagePerShortRest ->
            Just (Compendium.PerShortRest prevUses)

        Msg.UsagePerLongRest ->
            Just (Compendium.PerLongRest prevUses)

        Msg.UsageAtWill ->
            Just Compendium.AtWill


featureUsageRechargeLowChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
featureUsageRechargeLowChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group
            (updateAt idx (mapRecharge (\r -> { r | low = CompendiumUi.parseIntOr r.low text })))
        )
        model
    , Cmd.none
    )


featureUsageRechargeHighChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
featureUsageRechargeHighChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group
            (updateAt idx (mapRecharge (\r -> { r | high = CompendiumUi.parseIntOr r.high text })))
        )
        model
    , Cmd.none
    )


featureUsageUsesChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
featureUsageUsesChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group
            (updateAt idx (\f -> { f | usage = mapUses (CompendiumUi.parseIntOr 1 text) f.usage }))
        )
        model
    , Cmd.none
    )


mapRecharge : ({ low : Int, high : Int } -> { low : Int, high : Int }) -> CompendiumUi.FeatureDraft -> CompendiumUi.FeatureDraft
mapRecharge fn f =
    case f.usage of
        Just (Compendium.Recharge r) ->
            { f | usage = Just (Compendium.Recharge (fn r)) }

        _ ->
            f


mapUses : Int -> Maybe Compendium.Usage -> Maybe Compendium.Usage
mapUses uses usage =
    case usage of
        Just (Compendium.PerDay _) ->
            Just (Compendium.PerDay uses)

        Just (Compendium.PerShortRest _) ->
            Just (Compendium.PerShortRest uses)

        Just (Compendium.PerLongRest _) ->
            Just (Compendium.PerLongRest uses)

        _ ->
            usage


customSectionAdd : Model -> ( Model, Cmd Msg )
customSectionAdd model =
    ( withCompendiumEdit
        (\ui -> { ui | customSections = ui.customSections ++ [ ( "", "" ) ] })
        model
    , Cmd.none
    )


customSectionRemove : Int -> Model -> ( Model, Cmd Msg )
customSectionRemove idx model =
    ( withCompendiumEdit
        (\ui -> { ui | customSections = removeAt idx ui.customSections })
        model
    , Cmd.none
    )


customSectionNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
customSectionNameChanged idx text model =
    ( withCompendiumEdit
        (\ui ->
            { ui | customSections = updateAt idx (\( _, b ) -> ( text, b )) ui.customSections }
        )
        model
    , Cmd.none
    )


customSectionBodyChanged : Int -> String -> Model -> ( Model, Cmd Msg )
customSectionBodyChanged idx text model =
    ( withCompendiumEdit
        (\ui ->
            { ui | customSections = updateAt idx (\( n, _ ) -> ( n, text )) ui.customSections }
        )
        model
    , Cmd.none
    )


mapFeatureGroup :
    FeatureGroup
    -> (List FeatureDraft -> List FeatureDraft)
    -> CompendiumEditUi
    -> CompendiumEditUi
mapFeatureGroup group fn ui =
    case group of
        TraitsGroup ->
            { ui | traits = fn ui.traits }

        ActionsGroup ->
            { ui | actions = fn ui.actions }

        BonusActionsGroup ->
            { ui | bonusActions = fn ui.bonusActions }

        ReactionsGroup ->
            { ui | reactions = fn ui.reactions }


updateAt : Int -> (a -> a) -> List a -> List a
updateAt idx fn xs =
    List.indexedMap
        (\i x ->
            if i == idx then
                fn x

            else
                x
        )
        xs


removeAt : Int -> List a -> List a
removeAt idx xs =
    List.indexedMap (\i x -> ( i, x )) xs
        |> List.filter (\( i, _ ) -> i /= idx)
        |> List.map Tuple.second



-- ── DAMAGE / CONDITION MULTI-SELECT TOGGLES ────────────────────────────


{-| Flip the named damage type in or out of one of the three
damage-list pickers (vulnerabilities / resistances / immunities).
The picker enum identifies which list; the string is the canonical
damage-type name from `Compendium.Reference.damageTypes`.
-}
damageToggle : DamagePicker -> String -> Model -> ( Model, Cmd Msg )
damageToggle picker name model =
    ( withCompendiumEdit (toggleDamage picker name) model, Cmd.none )


toggleDamage : DamagePicker -> String -> CompendiumEditUi -> CompendiumEditUi
toggleDamage picker name ui =
    case picker of
        DamageVulnerabilitiesPicker ->
            { ui | damageVulnerabilities = toggleListMember name ui.damageVulnerabilities }

        DamageResistancesPicker ->
            { ui | damageResistances = toggleListMember name ui.damageResistances }

        DamageImmunitiesPicker ->
            { ui | damageImmunities = toggleListMember name ui.damageImmunities }


conditionToggle : String -> Model -> ( Model, Cmd Msg )
conditionToggle name model =
    ( withCompendiumEdit
        (\ui -> { ui | conditionImmunities = toggleListMember name ui.conditionImmunities })
        model
    , Cmd.none
    )


habitatToggle : Compendium.Habitat -> Model -> ( Model, Cmd Msg )
habitatToggle h model =
    ( withCompendiumEdit
        (\ui -> { ui | habitats = toggleListMember h ui.habitats })
        model
    , Cmd.none
    )


treasureToggle : Compendium.Treasure -> Model -> ( Model, Cmd Msg )
treasureToggle t model =
    ( withCompendiumEdit
        (\ui -> { ui | treasures = toggleListMember t ui.treasures })
        model
    , Cmd.none
    )


toggleListMember : a -> List a -> List a
toggleListMember name xs =
    if List.member name xs then
        List.filter ((/=) name) xs

    else
        xs ++ [ name ]



-- ── FREE-FORM TAGS ──────────────────────────────────────────────────────


tagAdd : Model -> ( Model, Cmd Msg )
tagAdd model =
    ( withCompendiumEdit (\ui -> { ui | tags = ui.tags ++ [ "" ] }) model
    , Cmd.none
    )


tagRemove : Int -> Model -> ( Model, Cmd Msg )
tagRemove idx model =
    ( withCompendiumEdit (\ui -> { ui | tags = removeAt idx ui.tags }) model
    , Cmd.none
    )


tagChanged : Int -> String -> Model -> ( Model, Cmd Msg )
tagChanged idx text model =
    ( withCompendiumEdit
        (\ui -> { ui | tags = updateAt idx (\_ -> text) ui.tags })
        model
    , Cmd.none
    )



-- ── ADVANCED SECTION EDITORS: LEGENDARY ─────────────────────────────────


emptyLegendary : Compendium.LegendaryActions
emptyLegendary =
    { description = ""
    , uses = 3
    , usesInLair = 3
    , options = []
    }


emptyLegendaryOption : Compendium.LegendaryOption
emptyLegendaryOption =
    { name = "", cost = 1, description = "" }


withLegendary :
    (Compendium.LegendaryActions -> Compendium.LegendaryActions)
    -> CompendiumEditUi
    -> CompendiumEditUi
withLegendary fn ui =
    { ui | legendaryActions = Maybe.map fn ui.legendaryActions }


legendaryAdd : Model -> ( Model, Cmd Msg )
legendaryAdd model =
    ( withCompendiumEdit
        (\ui -> { ui | legendaryActions = Just emptyLegendary })
        model
    , Cmd.none
    )


legendaryRemove : Model -> ( Model, Cmd Msg )
legendaryRemove model =
    ( withCompendiumEdit (\ui -> { ui | legendaryActions = Nothing }) model
    , Cmd.none
    )


legendaryDescriptionChanged : String -> Model -> ( Model, Cmd Msg )
legendaryDescriptionChanged text model =
    ( withCompendiumEdit
        (withLegendary (\la -> { la | description = text }))
        model
    , Cmd.none
    )


legendaryUsesChanged : String -> Model -> ( Model, Cmd Msg )
legendaryUsesChanged text model =
    ( withCompendiumEdit
        (withLegendary (\la -> { la | uses = CompendiumUi.parseIntOr la.uses text }))
        model
    , Cmd.none
    )


legendaryUsesInLairChanged : String -> Model -> ( Model, Cmd Msg )
legendaryUsesInLairChanged text model =
    ( withCompendiumEdit
        (withLegendary (\la -> { la | usesInLair = CompendiumUi.parseIntOr la.usesInLair text }))
        model
    , Cmd.none
    )


legendaryOptionAdd : Model -> ( Model, Cmd Msg )
legendaryOptionAdd model =
    ( withCompendiumEdit
        (withLegendary (\la -> { la | options = la.options ++ [ emptyLegendaryOption ] }))
        model
    , Cmd.none
    )


legendaryOptionRemove : Int -> Model -> ( Model, Cmd Msg )
legendaryOptionRemove idx model =
    ( withCompendiumEdit
        (withLegendary (\la -> { la | options = removeAt idx la.options }))
        model
    , Cmd.none
    )


legendaryOptionNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
legendaryOptionNameChanged idx text model =
    ( withCompendiumEdit
        (withLegendary
            (\la -> { la | options = updateAt idx (\o -> { o | name = text }) la.options })
        )
        model
    , Cmd.none
    )


legendaryOptionDescriptionChanged : Int -> String -> Model -> ( Model, Cmd Msg )
legendaryOptionDescriptionChanged idx text model =
    ( withCompendiumEdit
        (withLegendary
            (\la -> { la | options = updateAt idx (\o -> { o | description = text }) la.options })
        )
        model
    , Cmd.none
    )



-- ── ADVANCED SECTION EDITORS: LAIR ─────────────────────────────────────


emptyLair : Compendium.LairActions
emptyLair =
    { initiative = 20
    , description = ""
    , options = []
    }


withLair : (Compendium.LairActions -> Compendium.LairActions) -> CompendiumEditUi -> CompendiumEditUi
withLair fn ui =
    { ui | lairActions = Maybe.map fn ui.lairActions }


lairAdd : Model -> ( Model, Cmd Msg )
lairAdd model =
    ( withCompendiumEdit (\ui -> { ui | lairActions = Just emptyLair }) model
    , Cmd.none
    )


lairRemove : Model -> ( Model, Cmd Msg )
lairRemove model =
    ( withCompendiumEdit (\ui -> { ui | lairActions = Nothing }) model
    , Cmd.none
    )


lairInitiativeChanged : String -> Model -> ( Model, Cmd Msg )
lairInitiativeChanged text model =
    ( withCompendiumEdit
        (withLair (\la -> { la | initiative = CompendiumUi.parseIntOr la.initiative text }))
        model
    , Cmd.none
    )


lairDescriptionChanged : String -> Model -> ( Model, Cmd Msg )
lairDescriptionChanged text model =
    ( withCompendiumEdit
        (withLair (\la -> { la | description = text }))
        model
    , Cmd.none
    )


lairOptionAdd : Model -> ( Model, Cmd Msg )
lairOptionAdd model =
    ( withCompendiumEdit
        (withLair (\la -> { la | options = la.options ++ [ emptyLairFeature ] }))
        model
    , Cmd.none
    )


lairOptionRemove : Int -> Model -> ( Model, Cmd Msg )
lairOptionRemove idx model =
    ( withCompendiumEdit
        (withLair (\la -> { la | options = removeAt idx la.options }))
        model
    , Cmd.none
    )


lairOptionNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
lairOptionNameChanged idx text model =
    ( withCompendiumEdit
        (withLair
            (\la -> { la | options = updateAt idx (\o -> { o | name = text }) la.options })
        )
        model
    , Cmd.none
    )


lairOptionDescriptionChanged : Int -> String -> Model -> ( Model, Cmd Msg )
lairOptionDescriptionChanged idx text model =
    ( withCompendiumEdit
        (withLair
            (\la -> { la | options = updateAt idx (\o -> { o | description = text }) la.options })
        )
        model
    , Cmd.none
    )


emptyLairFeature : Compendium.Feature
emptyLairFeature =
    { name = "", description = "", usage = Nothing }



-- ── ADVANCED SECTION EDITORS: REGIONAL ─────────────────────────────────


emptyRegional : Compendium.RegionalEffects
emptyRegional =
    { description = ""
    , effects = []
    , fadeAfter = ""
    }


withRegional :
    (Compendium.RegionalEffects -> Compendium.RegionalEffects)
    -> CompendiumEditUi
    -> CompendiumEditUi
withRegional fn ui =
    { ui | regionalEffects = Maybe.map fn ui.regionalEffects }


regionalAdd : Model -> ( Model, Cmd Msg )
regionalAdd model =
    ( withCompendiumEdit (\ui -> { ui | regionalEffects = Just emptyRegional }) model
    , Cmd.none
    )


regionalRemove : Model -> ( Model, Cmd Msg )
regionalRemove model =
    ( withCompendiumEdit (\ui -> { ui | regionalEffects = Nothing }) model
    , Cmd.none
    )


regionalDescriptionChanged : String -> Model -> ( Model, Cmd Msg )
regionalDescriptionChanged text model =
    ( withCompendiumEdit
        (withRegional (\re -> { re | description = text }))
        model
    , Cmd.none
    )


regionalFadeAfterChanged : String -> Model -> ( Model, Cmd Msg )
regionalFadeAfterChanged text model =
    ( withCompendiumEdit
        (withRegional (\re -> { re | fadeAfter = text }))
        model
    , Cmd.none
    )


regionalEffectAdd : Model -> ( Model, Cmd Msg )
regionalEffectAdd model =
    ( withCompendiumEdit
        (withRegional (\re -> { re | effects = re.effects ++ [ emptyLairFeature ] }))
        model
    , Cmd.none
    )


regionalEffectRemove : Int -> Model -> ( Model, Cmd Msg )
regionalEffectRemove idx model =
    ( withCompendiumEdit
        (withRegional (\re -> { re | effects = removeAt idx re.effects }))
        model
    , Cmd.none
    )


regionalEffectNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
regionalEffectNameChanged idx text model =
    ( withCompendiumEdit
        (withRegional
            (\re -> { re | effects = updateAt idx (\f -> { f | name = text }) re.effects })
        )
        model
    , Cmd.none
    )


regionalEffectDescriptionChanged : Int -> String -> Model -> ( Model, Cmd Msg )
regionalEffectDescriptionChanged idx text model =
    ( withCompendiumEdit
        (withRegional
            (\re -> { re | effects = updateAt idx (\f -> { f | description = text }) re.effects })
        )
        model
    , Cmd.none
    )



-- ── ADVANCED SECTION EDITORS: SPELLCASTING ─────────────────────────────


emptySpellcasting : Compendium.Spellcasting
emptySpellcasting =
    { description = ""
    , ability = Compendium.Cha
    , saveDc = 0
    , attackBonus = 0
    , atWill = []
    , slots = []
    , innatePerDay = []
    }


emptySlotLevel : Compendium.SpellSlotLevel
emptySlotLevel =
    { level = 1, slots = 1, spells = [] }


emptyInnate : Compendium.InnatePerDay
emptyInnate =
    { uses = 1, spells = [] }


withSpellcasting :
    (Compendium.Spellcasting -> Compendium.Spellcasting)
    -> CompendiumEditUi
    -> CompendiumEditUi
withSpellcasting fn ui =
    { ui | spellcasting = Maybe.map fn ui.spellcasting }


spellcastingAdd : Model -> ( Model, Cmd Msg )
spellcastingAdd model =
    ( withCompendiumEdit (\ui -> { ui | spellcasting = Just emptySpellcasting }) model
    , Cmd.none
    )


spellcastingRemove : Model -> ( Model, Cmd Msg )
spellcastingRemove model =
    ( withCompendiumEdit (\ui -> { ui | spellcasting = Nothing }) model
    , Cmd.none
    )


spellcastingDescriptionChanged : String -> Model -> ( Model, Cmd Msg )
spellcastingDescriptionChanged text model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | description = text }))
        model
    , Cmd.none
    )


spellcastingAbilitySet : Compendium.Ability -> Model -> ( Model, Cmd Msg )
spellcastingAbilitySet ability model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | ability = ability }))
        model
    , Cmd.none
    )


spellcastingSaveDcChanged : String -> Model -> ( Model, Cmd Msg )
spellcastingSaveDcChanged text model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | saveDc = CompendiumUi.parseIntOr sc.saveDc text }))
        model
    , Cmd.none
    )


spellcastingAttackBonusChanged : String -> Model -> ( Model, Cmd Msg )
spellcastingAttackBonusChanged text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc -> { sc | attackBonus = CompendiumUi.parseIntOr sc.attackBonus text })
        )
        model
    , Cmd.none
    )


spellcastingAtWillChanged : String -> Model -> ( Model, Cmd Msg )
spellcastingAtWillChanged text model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | atWill = CompendiumUi.parseCsv text }))
        model
    , Cmd.none
    )


spellcastingSlotAdd : Model -> ( Model, Cmd Msg )
spellcastingSlotAdd model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | slots = sc.slots ++ [ emptySlotLevel ] }))
        model
    , Cmd.none
    )


spellcastingSlotRemove : Int -> Model -> ( Model, Cmd Msg )
spellcastingSlotRemove idx model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | slots = removeAt idx sc.slots }))
        model
    , Cmd.none
    )


spellcastingSlotLevelChanged : Int -> String -> Model -> ( Model, Cmd Msg )
spellcastingSlotLevelChanged idx text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc ->
                { sc
                    | slots =
                        updateAt idx
                            (\s -> { s | level = CompendiumUi.parseIntOr s.level text })
                            sc.slots
                }
            )
        )
        model
    , Cmd.none
    )


spellcastingSlotCountChanged : Int -> String -> Model -> ( Model, Cmd Msg )
spellcastingSlotCountChanged idx text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc ->
                { sc
                    | slots =
                        updateAt idx
                            (\s -> { s | slots = CompendiumUi.parseIntOr s.slots text })
                            sc.slots
                }
            )
        )
        model
    , Cmd.none
    )


spellcastingSlotSpellsChanged : Int -> String -> Model -> ( Model, Cmd Msg )
spellcastingSlotSpellsChanged idx text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc ->
                { sc
                    | slots =
                        updateAt idx
                            (\s -> { s | spells = CompendiumUi.parseCsv text })
                            sc.slots
                }
            )
        )
        model
    , Cmd.none
    )


spellcastingInnateAdd : Model -> ( Model, Cmd Msg )
spellcastingInnateAdd model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | innatePerDay = sc.innatePerDay ++ [ emptyInnate ] }))
        model
    , Cmd.none
    )


spellcastingInnateRemove : Int -> Model -> ( Model, Cmd Msg )
spellcastingInnateRemove idx model =
    ( withCompendiumEdit
        (withSpellcasting (\sc -> { sc | innatePerDay = removeAt idx sc.innatePerDay }))
        model
    , Cmd.none
    )


spellcastingInnateUsesChanged : Int -> String -> Model -> ( Model, Cmd Msg )
spellcastingInnateUsesChanged idx text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc ->
                { sc
                    | innatePerDay =
                        updateAt idx
                            (\i -> { i | uses = CompendiumUi.parseIntOr i.uses text })
                            sc.innatePerDay
                }
            )
        )
        model
    , Cmd.none
    )


spellcastingInnateSpellsChanged : Int -> String -> Model -> ( Model, Cmd Msg )
spellcastingInnateSpellsChanged idx text model =
    ( withCompendiumEdit
        (withSpellcasting
            (\sc ->
                { sc
                    | innatePerDay =
                        updateAt idx
                            (\i -> { i | spells = CompendiumUi.parseCsv text })
                            sc.innatePerDay
                }
            )
        )
        model
    , Cmd.none
    )



-- ── EDIT SUBMIT / DELETE ────────────────────────────────────────────────


submit : Model -> ( Model, Cmd Msg )
submit model =
    case model.modal of
        Just (ModalCompendiumEdit ui) ->
            case CompendiumUi.validateEdit ui of
                Err message ->
                    ( withCompendiumEdit (\u -> { u | submitError = Just message }) model
                    , Cmd.none
                    )

                Ok creature ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withCompendiumEdit
                                (\u -> { u | submitting = True, submitError = Nothing })
                                model
                            , submitCreatureCmd ui.mode creature
                            )

                        _ ->
                            applyLocalCreatureSubmit ui.mode creature model

        _ ->
            ( model, Cmd.none )


submitCreatureCmd : EditMode -> Compendium.Creature -> Cmd Msg
submitCreatureCmd mode creature =
    case mode of
        CreateMode ->
            Http.post
                { url = "/api/compendium/creatures"
                , body = Http.jsonBody (Compendium.Wire.encodeDraft creature)
                , expect = Http.expectJson CompendiumEditSubmitResponse Compendium.Wire.decodeCreature
                }

        EditExisting { id } ->
            Http.request
                { method = "PUT"
                , headers = []
                , url = "/api/compendium/creatures/" ++ id
                , body = Http.jsonBody (Compendium.Wire.encodeCreature creature)
                , expect = Http.expectJson CompendiumEditSubmitResponse Compendium.Wire.decodeCreature
                , timeout = Nothing
                , tracker = Nothing
                }


{-| Anonymous-mode equivalent of `submitCreatureCmd` +
`submitResponse` combined: mutate the in-memory compendium DB
directly (allocating a local id on CreateMode), close the modal,
mark the library dirty, and toast. The update-loop wrapper
notices the DB change and persists the snapshot to localStorage.
-}
applyLocalCreatureSubmit : EditMode -> Compendium.Creature -> Model -> ( Model, Cmd Msg )
applyLocalCreatureSubmit mode incoming model =
    let
        ( finalCreature, withId ) =
            case mode of
                CreateMode ->
                    let
                        idN =
                            model.nextLocalCreatureId
                    in
                    ( { incoming | id = "local-" ++ String.fromInt idN }
                    , { model | nextLocalCreatureId = idN + 1 }
                    )

                EditExisting _ ->
                    ( incoming, model )

        compendium =
            withId.compendium

        newDb =
            case compendium.db of
                CompendiumUi.CompendiumDbLoaded db ->
                    CompendiumUi.CompendiumDbLoaded
                        (Compendium.upsert finalCreature db)

                other ->
                    other
    in
    { withId
        | modal = Nothing
        , compendium =
            { compendium
                | db = newDb
                , selectedId = Just finalCreature.id
                , compendiumDirty = True
            }
    }
        |> Update.Toast.push ToastSuccess ("Saved " ++ finalCreature.name)


submitResponse : Result Http.Error Compendium.Creature -> Model -> ( Model, Cmd Msg )
submitResponse result model =
    case result of
        Err err ->
            ( withCompendiumEdit
                (\u -> { u | submitting = False, submitError = Just (Util.Http.errorToString err) })
                model
            , Cmd.none
            )

        Ok creature ->
            { model
                | modal = Nothing
                , compendium =
                    let
                        ui =
                            model.compendium
                    in
                    -- Mark the library altered so Export gets the
                    -- yellow-border cue.  Cleared by reset, import,
                    -- or an explicit export click.
                    { ui
                        | selectedId = Just creature.id
                        , compendiumDirty = True
                    }
            }
                |> Update.Toast.pushWith ToastSuccess
                    ("Saved " ++ creature.name)
                    (Compendium.Wire.fetchAll CompendiumLoaded)


delete : Model -> ( Model, Cmd Msg )
delete model =
    case model.modal of
        Just (ModalCompendiumEdit { mode }) ->
            case mode of
                EditExisting { id } ->
                    case model.auth of
                        Auth.AuthAuthenticated _ ->
                            ( withCompendiumEdit (\u -> { u | submitting = True, submitError = Nothing }) model
                            , Http.request
                                { method = "DELETE"
                                , headers = []
                                , url = "/api/compendium/creatures/" ++ id
                                , body = Http.emptyBody
                                , expect = Http.expectWhatever (CompendiumEditDeleteResponse id)
                                , timeout = Nothing
                                , tracker = Nothing
                                }
                            )

                        _ ->
                            applyLocalCreatureDelete id model

                CreateMode ->
                    ( { model | modal = Nothing }, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Anonymous-mode equivalent of the DELETE + `deleteResponse`
sequence: drop the creature from the in-memory DB, clear it from
any selections, close the modal, toast. The update-loop wrapper
persists the new snapshot.
-}
applyLocalCreatureDelete : String -> Model -> ( Model, Cmd Msg )
applyLocalCreatureDelete deletedId model =
    let
        compendium =
            model.compendium

        newDb =
            case compendium.db of
                CompendiumUi.CompendiumDbLoaded db ->
                    CompendiumUi.CompendiumDbLoaded
                        (Compendium.remove deletedId db)

                other ->
                    other

        clearedSelection =
            { compendium
                | db = newDb
                , selectedId =
                    if compendium.selectedId == Just deletedId then
                        Nothing

                    else
                        compendium.selectedId
                , selectedIds = Set.remove deletedId compendium.selectedIds
                , compendiumDirty = True
            }
    in
    { model | modal = Nothing, compendium = clearedSelection }
        |> Update.Toast.push ToastSuccess "Creature deleted"


deleteResponse : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
deleteResponse deletedId result model =
    case result of
        Err err ->
            withCompendiumEdit
                (\u -> { u | submitting = False, submitError = Just (Util.Http.errorToString err) })
                model
                |> withCompendium
                    (\ui -> { ui | bulkBusy = False, bulkError = Just (Util.Http.errorToString err) })
                |> Update.Toast.push ToastError
                    ("Delete failed: " ++ Util.Http.errorToString err)

        Ok () ->
            let
                clearedSelection ui =
                    let
                        baseSelectedId =
                            if ui.selectedId == Just deletedId then
                                Nothing

                            else
                                ui.selectedId
                    in
                    -- Drop the deleted id from the bulk-selection
                    -- set too, and mark the library altered.
                    { ui
                        | selectedId = baseSelectedId
                        , selectedIds = Set.remove deletedId ui.selectedIds
                        , bulkBusy = False
                        , compendiumDirty = True
                    }
            in
            { model
                | modal = Nothing
                , compendium = clearedSelection model.compendium
            }
                |> Update.Toast.pushWith ToastSuccess
                    "Creature deleted"
                    (Compendium.Wire.fetchAll CompendiumLoaded)
