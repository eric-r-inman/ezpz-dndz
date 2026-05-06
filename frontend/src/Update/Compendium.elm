module Update.Compendium exposing
    ( addCountChanged
    , addToQueue
    , close
    , currentlySelectedCreature
    , deleteFromBrowser
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
    , focusSearch
    , importClick
    , importFileChosen
    , importFileRead
    , importResponse
    , initiativeRolled
    , kindToggled
    , loaded
    , open
    , panelShowCreature
    , pendingCancel
    , pendingConfirm
    , resetClick
    , resetResponse
    , searchChanged
    , searchId
    , select
    , sortChanged
    )

{-| Update branches for the compendium browser, the compendium-edit
modal, the paste-stat-block modal, and the bulk import/reset/delete
flow. This is the largest of the per-feature Update modules because
the compendium has the largest surface area: ~50 UI fields on the
edit form, four feature groups (traits / actions / bonus actions
/ reactions), the optional paste path, and a confirm-banner-driven
bulk flow.
-}

import Browser.Dom
import Compendium
import Compendium.Wire
import Dice
import Effects
import Encounter
import Encounter.Roster
import File exposing (File)
import File.Select
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( CompendiumField(..)
        , CompendiumSort
        , FeatureGroup(..)
        , Msg(..)
        )
import Random
import Set
import Task
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
import Update.Initiative
import Update.Toast
import Util.Http


{-| HTML id of the compendium search input. Exposed so the view
layer can wire up `id` and the `CompendiumFocusSearch` Msg can
focus it via `Browser.Dom.focus`.
-}
searchId : String
searchId =
    "compendium-search"


withCompendium : (CompendiumUi -> CompendiumUi) -> Model -> Model
withCompendium fn model =
    { model | compendium = fn model.compendium }


withCompendiumEdit : (CompendiumEditUi -> CompendiumEditUi) -> Model -> Model
withCompendiumEdit =
    Model.mapModal Model.compendiumEditLens



-- ── BROWSER LIFECYCLE ───────────────────────────────────────────────────


loaded : Result Http.Error (List Compendium.Creature) -> Model -> ( Model, Cmd Msg )
loaded result model =
    ( withCompendium (loadedUpdate result) model, Cmd.none )


loadedUpdate : Result Http.Error (List Compendium.Creature) -> CompendiumUi -> CompendiumUi
loadedUpdate result ui =
    case result of
        Ok creatures ->
            { ui | db = CompendiumDbLoaded (Compendium.fromList creatures) }

        Err err ->
            { ui | db = CompendiumDbFailed err }


open : Model -> ( Model, Cmd Msg )
open model =
    ( withCompendium openUpdate model, Cmd.none )


{-| Open the modal and pick a sensible default selection so the
right pane isn't blank on first open. We pick the first item of
the currently-rendered (filter+sort applied) list.
-}
openUpdate : CompendiumUi -> CompendiumUi
openUpdate ui =
    let
        opened =
            { ui | open = True }
    in
    case ui.selectedId of
        Just _ ->
            opened

        Nothing ->
            { opened
                | selectedId =
                    CompendiumUi.compendiumVisible opened
                        |> List.head
                        |> Maybe.map .id
            }


close : Model -> ( Model, Cmd Msg )
close model =
    ( withCompendium (\ui -> { ui | open = False }) model, Cmd.none )


searchChanged : String -> Model -> ( Model, Cmd Msg )
searchChanged text model =
    ( withCompendium
        (\ui -> { ui | searchText = text, selectedId = Nothing })
        model
    , Cmd.none
    )


kindToggled : Compendium.CreatureKind -> Model -> ( Model, Cmd Msg )
kindToggled kind model =
    ( withCompendium (toggleKindFilter kind) model, Cmd.none )


toggleKindFilter : Compendium.CreatureKind -> CompendiumUi -> CompendiumUi
toggleKindFilter kind ui =
    let
        key =
            CompendiumUi.kindToString kind

        next =
            if Set.member key ui.kindFilter then
                Set.remove key ui.kindFilter

            else
                Set.insert key ui.kindFilter
    in
    { ui | kindFilter = next, selectedId = Nothing }


sortChanged : CompendiumSort -> Model -> ( Model, Cmd Msg )
sortChanged sort model =
    ( withCompendium (\ui -> { ui | sort = sort }) model, Cmd.none )


select : String -> Model -> ( Model, Cmd Msg )
select id model =
    ( withCompendium (\ui -> { ui | selectedId = Just id }) model, Cmd.none )


addCountChanged : String -> Model -> ( Model, Cmd Msg )
addCountChanged raw model =
    ( withCompendium (addCountUpdate raw) model, Cmd.none )


addCountUpdate : String -> CompendiumUi -> CompendiumUi
addCountUpdate raw ui =
    let
        parsed =
            String.toInt raw
                |> Maybe.withDefault ui.addCount
                |> clamp 1 CompendiumUi.maxAddCount
    in
    { ui | addCountText = raw, addCount = parsed }


focusSearch : Model -> ( Model, Cmd Msg )
focusSearch model =
    ( model
    , Browser.Dom.focus searchId
        |> Task.attempt (\_ -> NoOp)
    )


panelShowCreature : String -> String -> Model -> ( Model, Cmd Msg )
panelShowCreature creatureId creatureName model =
    ( { model
        | panelCreaturePin =
            Just { id = creatureId, name = creatureName }
      }
    , Cmd.none
    )



-- ── ADD-TO-QUEUE FLOW ───────────────────────────────────────────────────


addToQueue : String -> Model -> ( Model, Cmd Msg )
addToQueue creatureId model =
    ( model, addToQueueCmd model creatureId )


{-| Resolve the selected compendium creature, build N auto-numbered
initiative roll specs, and dispatch a single batched Cmd. The
handler closes over `creatureId` so when the rolls land we can
look the source back up to spawn instances against the
freshly-rolled values.
-}
addToQueueCmd : Model -> String -> Cmd Msg
addToQueueCmd model creatureId =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        existing =
                            List.map .name model.encounter.creatures

                        names =
                            pickInstanceNames source.name model.compendium.addCount existing

                        specs =
                            List.map (instanceSpec source) names
                    in
                    Dice.batchRollCmd
                        (CompendiumInitiativeRolled creatureId)
                        specs

                Nothing ->
                    Cmd.none

        _ ->
            Cmd.none


{-| Generate `count` unique display names for new instances of
`base`, threading the running set of reserved names through so each
new pick honors prior picks within the same batch. So adding three
Goblins to a fresh queue yields `Goblin / Goblin 2 / Goblin 3`.
-}
pickInstanceNames : String -> Int -> List String -> List String
pickInstanceNames base count existing =
    let
        loop n acc reserved =
            if n <= 0 then
                List.reverse acc

            else
                let
                    next =
                        Encounter.Roster.uniqueInstanceName base reserved
                in
                loop (n - 1) (next :: acc) (next :: reserved)
    in
    loop count [] existing


instanceSpec :
    Compendium.Creature
    -> String
    -> ( String, Dice.Source, Random.Generator Dice.Roll )
instanceSpec source displayName =
    ( displayName
    , Update.Initiative.source displayName
    , Dice.generator (Update.Initiative.initiativeExpression source.initiativeBonus)
    )


initiativeRolled : String -> List ( String, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
initiativeRolled creatureId rolls model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        instances =
                            List.map
                                (\( displayName, roll ) ->
                                    Compendium.draftToInstance
                                        { displayName = displayName
                                        , initiativeRoll = roll.total
                                        }
                                        source
                                )
                                rolls

                        m1 =
                            List.foldl (\( _, r ) m -> Effects.pushDiceRoll r m) model rolls

                        addedCount =
                            List.length instances

                        toastMessage =
                            if addedCount == 1 then
                                "Added " ++ source.name ++ " to encounter"

                            else
                                "Added " ++ String.fromInt addedCount ++ " × " ++ source.name
                    in
                    { m1
                        | encounter = Encounter.Roster.appendCreatures instances m1.encounter
                        , compendium =
                            let
                                ui =
                                    m1.compendium
                            in
                            { ui | open = False }
                    }
                        |> Update.Toast.pushWith ToastSuccess
                            toastMessage
                            (Cmd.batch (List.map (\( _, r ) -> Effects.persistDiceRoll r) rolls))

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )



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



-- ── BULK IMPORT / RESET / DELETE ────────────────────────────────────────


importClick : Model -> ( Model, Cmd Msg )
importClick model =
    ( withCompendium (\ui -> { ui | bulkError = Nothing }) model
    , File.Select.file [ "application/json", "text/plain" ] CompendiumImportFileChosen
    )


importFileChosen : File -> Model -> ( Model, Cmd Msg )
importFileChosen file model =
    ( model, Task.perform CompendiumImportFileRead (File.toString file) )


importFileRead : String -> Model -> ( Model, Cmd Msg )
importFileRead raw model =
    ( withCompendium (importFileLoaded raw) model, Cmd.none )


{-| Decode the file the user picked. On parse success we set the
pending action and surface an inline confirmation banner so the GM
gets one final "yes, replace everything" before the wire call
fires. On parse failure we keep the modal open and show the
error.
-}
importFileLoaded : String -> CompendiumUi -> CompendiumUi
importFileLoaded raw ui =
    case Decode.decodeString (Decode.list Compendium.Wire.decodeCreature) raw of
        Ok creatures ->
            { ui
                | pending = Just (PendingImport creatures (List.length creatures))
                , bulkError = Nothing
            }

        Err err ->
            { ui
                | pending = Nothing
                , bulkError = Just ("Couldn't parse file: " ++ Decode.errorToString err)
            }


resetClick : Model -> ( Model, Cmd Msg )
resetClick model =
    ( withCompendium (\ui -> { ui | pending = Just PendingReset, bulkError = Nothing }) model
    , Cmd.none
    )


deleteFromBrowser : String -> String -> Model -> ( Model, Cmd Msg )
deleteFromBrowser id displayName model =
    ( withCompendium
        (\ui ->
            { ui
                | pending = Just (PendingDelete id displayName)
                , bulkError = Nothing
            }
        )
        model
    , Cmd.none
    )


pendingCancel : Model -> ( Model, Cmd Msg )
pendingCancel model =
    ( withCompendium (\ui -> { ui | pending = Nothing, bulkError = Nothing }) model
    , Cmd.none
    )


pendingConfirm : Model -> ( Model, Cmd Msg )
pendingConfirm model =
    case model.compendium.pending of
        Just PendingReset ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , resetCmd
            )

        Just (PendingImport creatures _) ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , importCmd creatures
            )

        Just (PendingDelete id _) ->
            ( withCompendium
                (\ui -> { ui | bulkBusy = True, pending = Nothing })
                model
            , deleteCmd id
            )

        Nothing ->
            ( model, Cmd.none )


deleteCmd : String -> Cmd Msg
deleteCmd id =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/compendium/creatures/" ++ id
        , body = Http.emptyBody
        , expect = Http.expectWhatever (CompendiumEditDeleteResponse id)
        , timeout = Nothing
        , tracker = Nothing
        }


resetCmd : Cmd Msg
resetCmd =
    Http.post
        { url = "/api/compendium/reset"
        , body = Http.emptyBody
        , expect =
            Http.expectJson CompendiumResetResponse
                (Decode.list Compendium.Wire.decodeCreature)
        }


importCmd : List Compendium.Creature -> Cmd Msg
importCmd creatures =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody (Encode.list Compendium.Wire.encodeCreature creatures)
        , expect =
            Http.expectJson CompendiumImportResponse
                (Decode.field "imported" Decode.int)
        }


importResponse : Result Http.Error Int -> Model -> ( Model, Cmd Msg )
importResponse result model =
    case result of
        Err err ->
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , bulkError = Just (Util.Http.errorToString err)
                    }
                )
                model
                |> Update.Toast.push ToastError
                    ("Import failed: " ++ Util.Http.errorToString err)

        Ok count ->
            withCompendium
                (\ui -> { ui | bulkBusy = False, selectedId = Nothing })
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Imported " ++ String.fromInt count ++ " creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)


resetResponse : Result Http.Error (List Compendium.Creature) -> Model -> ( Model, Cmd Msg )
resetResponse result model =
    case result of
        Err err ->
            withCompendium
                (\ui ->
                    { ui
                        | bulkBusy = False
                        , bulkError = Just (Util.Http.errorToString err)
                    }
                )
                model
                |> Update.Toast.push ToastError
                    ("Reset failed: " ++ Util.Http.errorToString err)

        Ok creatures ->
            withCompendium
                (\ui -> { ui | bulkBusy = False, selectedId = Nothing })
                model
                |> Update.Toast.pushWith ToastSuccess
                    ("Library reset to " ++ String.fromInt (List.length creatures) ++ " bundled creatures")
                    (Compendium.Wire.fetchAll CompendiumLoaded)
