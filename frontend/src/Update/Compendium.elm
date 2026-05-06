module Update.Compendium exposing
    ( currentlySelectedCreature
    , editCancel
    , editCustomSectionAdd
    , editCustomSectionBodyChanged
    , editCustomSectionNameChanged
    , editCustomSectionRemove
    , editDelete
    , editDeleteResponse
    , editDuplicate
    , editExisting
    , editFeatureAdd
    , editFeatureDescriptionChanged
    , editFeatureNameChanged
    , editFeatureRemove
    , editFieldChanged
    , editKindSet
    , editNew
    , editSavingThrowAbilitySet
    , editSavingThrowAdd
    , editSavingThrowBonusChanged
    , editSavingThrowRemove
    , editSizeSet
    , editSkillAdd
    , editSkillBonusChanged
    , editSkillNameChanged
    , editSkillRemove
    , editSpeedHoverToggle
    , editSubmit
    , editSubmitResponse
    )

{-| Update branches for the compendium browser, the compendium-edit
modal, the paste-stat-block modal, and the bulk import/reset/delete
flow. This is the largest of the per-feature Update modules because
the compendium has the largest surface area: ~50 UI fields on the
edit form, four feature groups (traits / actions / bonus actions
/ reactions), the optional paste path, and a confirm-banner-driven
bulk flow.
-}

import Compendium
import Compendium.Wire
import Http
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CompendiumField(..)
        , FeatureGroup(..)
        , Msg(..)
        )
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


editNew : Model -> ( Model, Cmd Msg )
editNew model =
    ( { model | modal = Just (ModalCompendiumEdit CompendiumUi.blankEdit) }
    , Cmd.none
    )


editExisting : Model -> ( Model, Cmd Msg )
editExisting model =
    ( { model
        | modal =
            currentlySelectedCreature model
                |> Maybe.map (CompendiumUi.editFromCreature >> ModalCompendiumEdit)
      }
    , Cmd.none
    )


editDuplicate : Model -> ( Model, Cmd Msg )
editDuplicate model =
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


editCancel : Model -> ( Model, Cmd Msg )
editCancel model =
    ( { model | modal = Nothing }, Cmd.none )


editFieldChanged : CompendiumField -> String -> Model -> ( Model, Cmd Msg )
editFieldChanged field text model =
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

        CFDamageVulnerabilities ->
            { ui | damageVulnerabilities = text }

        CFDamageResistances ->
            { ui | damageResistances = text }

        CFDamageImmunities ->
            { ui | damageImmunities = text }

        CFConditionImmunities ->
            { ui | conditionImmunities = text }

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


editKindSet : Compendium.CreatureKind -> Model -> ( Model, Cmd Msg )
editKindSet kind model =
    ( withCompendiumEdit (\ui -> { ui | kind = kind }) model, Cmd.none )


editSizeSet : Compendium.Size -> Model -> ( Model, Cmd Msg )
editSizeSet size model =
    ( withCompendiumEdit (\ui -> { ui | size = size }) model, Cmd.none )


editSpeedHoverToggle : Model -> ( Model, Cmd Msg )
editSpeedHoverToggle model =
    ( withCompendiumEdit (\ui -> { ui | speedHover = not ui.speedHover }) model, Cmd.none )


editSavingThrowAdd : Model -> ( Model, Cmd Msg )
editSavingThrowAdd model =
    ( withCompendiumEdit
        (\ui -> { ui | savingThrows = ui.savingThrows ++ [ ( Compendium.Str, "0" ) ] })
        model
    , Cmd.none
    )


editSavingThrowRemove : Int -> Model -> ( Model, Cmd Msg )
editSavingThrowRemove idx model =
    ( withCompendiumEdit (\ui -> { ui | savingThrows = removeAt idx ui.savingThrows }) model
    , Cmd.none
    )


editSavingThrowAbilitySet : Int -> Compendium.Ability -> Model -> ( Model, Cmd Msg )
editSavingThrowAbilitySet idx ability model =
    ( withCompendiumEdit
        (\ui ->
            { ui | savingThrows = updateAt idx (\( _, b ) -> ( ability, b )) ui.savingThrows }
        )
        model
    , Cmd.none
    )


editSavingThrowBonusChanged : Int -> String -> Model -> ( Model, Cmd Msg )
editSavingThrowBonusChanged idx text model =
    ( withCompendiumEdit
        (\ui ->
            { ui | savingThrows = updateAt idx (\( a, _ ) -> ( a, text )) ui.savingThrows }
        )
        model
    , Cmd.none
    )


editSkillAdd : Model -> ( Model, Cmd Msg )
editSkillAdd model =
    ( withCompendiumEdit (\ui -> { ui | skills = ui.skills ++ [ ( "", "0" ) ] }) model
    , Cmd.none
    )


editSkillRemove : Int -> Model -> ( Model, Cmd Msg )
editSkillRemove idx model =
    ( withCompendiumEdit (\ui -> { ui | skills = removeAt idx ui.skills }) model
    , Cmd.none
    )


editSkillNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
editSkillNameChanged idx text model =
    ( withCompendiumEdit
        (\ui -> { ui | skills = updateAt idx (\( _, b ) -> ( text, b )) ui.skills })
        model
    , Cmd.none
    )


editSkillBonusChanged : Int -> String -> Model -> ( Model, Cmd Msg )
editSkillBonusChanged idx text model =
    ( withCompendiumEdit
        (\ui -> { ui | skills = updateAt idx (\( n, _ ) -> ( n, text )) ui.skills })
        model
    , Cmd.none
    )


editFeatureAdd : FeatureGroup -> Model -> ( Model, Cmd Msg )
editFeatureAdd group model =
    ( withCompendiumEdit (mapFeatureGroup group (\fs -> fs ++ [ CompendiumUi.emptyFeatureDraft ])) model
    , Cmd.none
    )


editFeatureRemove : FeatureGroup -> Int -> Model -> ( Model, Cmd Msg )
editFeatureRemove group idx model =
    ( withCompendiumEdit (mapFeatureGroup group (removeAt idx)) model, Cmd.none )


editFeatureNameChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
editFeatureNameChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group (updateAt idx (\f -> { f | name = text })))
        model
    , Cmd.none
    )


editFeatureDescriptionChanged : FeatureGroup -> Int -> String -> Model -> ( Model, Cmd Msg )
editFeatureDescriptionChanged group idx text model =
    ( withCompendiumEdit
        (mapFeatureGroup group (updateAt idx (\f -> { f | description = text })))
        model
    , Cmd.none
    )


editCustomSectionAdd : Model -> ( Model, Cmd Msg )
editCustomSectionAdd model =
    ( withCompendiumEdit
        (\ui -> { ui | customSections = ui.customSections ++ [ ( "", "" ) ] })
        model
    , Cmd.none
    )


editCustomSectionRemove : Int -> Model -> ( Model, Cmd Msg )
editCustomSectionRemove idx model =
    ( withCompendiumEdit
        (\ui -> { ui | customSections = removeAt idx ui.customSections })
        model
    , Cmd.none
    )


editCustomSectionNameChanged : Int -> String -> Model -> ( Model, Cmd Msg )
editCustomSectionNameChanged idx text model =
    ( withCompendiumEdit
        (\ui ->
            { ui | customSections = updateAt idx (\( _, b ) -> ( text, b )) ui.customSections }
        )
        model
    , Cmd.none
    )


editCustomSectionBodyChanged : Int -> String -> Model -> ( Model, Cmd Msg )
editCustomSectionBodyChanged idx text model =
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



-- ── EDIT SUBMIT / DELETE ────────────────────────────────────────────────


editSubmit : Model -> ( Model, Cmd Msg )
editSubmit model =
    case model.modal of
        Just (ModalCompendiumEdit ui) ->
            case CompendiumUi.validateEdit ui of
                Err message ->
                    ( withCompendiumEdit (\u -> { u | submitError = Just message }) model
                    , Cmd.none
                    )

                Ok creature ->
                    ( withCompendiumEdit
                        (\u -> { u | submitting = True, submitError = Nothing })
                        model
                    , submitCreatureCmd ui.mode creature
                    )

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


editSubmitResponse : Result Http.Error Compendium.Creature -> Model -> ( Model, Cmd Msg )
editSubmitResponse result model =
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
                    { ui | selectedId = Just creature.id }
            }
                |> Update.Toast.pushWith ToastSuccess
                    ("Saved " ++ creature.name)
                    (Compendium.Wire.fetchAll CompendiumLoaded)


editDelete : Model -> ( Model, Cmd Msg )
editDelete model =
    case model.modal of
        Just (ModalCompendiumEdit { mode }) ->
            case mode of
                EditExisting { id } ->
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

                CreateMode ->
                    ( { model | modal = Nothing }, Cmd.none )

        _ ->
            ( model, Cmd.none )


editDeleteResponse : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
editDeleteResponse deletedId result model =
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
                    if ui.selectedId == Just deletedId then
                        { ui | selectedId = Nothing, bulkBusy = False }

                    else
                        { ui | bulkBusy = False }
            in
            { model
                | modal = Nothing
                , compendium = clearedSelection model.compendium
            }
                |> Update.Toast.pushWith ToastSuccess
                    "Creature deleted"
                    (Compendium.Wire.fetchAll CompendiumLoaded)
