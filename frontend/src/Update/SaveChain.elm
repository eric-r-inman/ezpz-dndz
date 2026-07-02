module Update.SaveChain exposing
    ( open, close
    , nameChanged, abilitySet, dcChanged, dcOverrideChanged
    , applyToSelectedToggle
    , outcomeHpKindSet, outcomeHpAmountChanged
    , outcomeConditionNameChanged, outcomeConditionNoteChanged
    , presetPickerChanged, presetLoad, presetSave, presetDelete, reset
    , applyFail, applyPass
    )

{-| Update branches for the Save Chain modal.

The modal is a form editor plus two apply buttons; the form's
raw state lives in `Ui.SaveChain.SaveChainUi`, projected back
to `Encounter.SaveChain.SaveChain` at save / apply time.
Presets are stored in `model.saveChainPresets` (dict keyed by
name) and persisted via `Ports.persistLocalSaveChainPresets`.

@docs open, close
@docs nameChanged, abilitySet, dcChanged, dcOverrideChanged
@docs applyToSelectedToggle
@docs outcomeHpKindSet, outcomeHpAmountChanged
@docs outcomeConditionNameChanged, outcomeConditionNoteChanged
@docs presetPickerChanged, presetLoad, presetSave, presetDelete, reset
@docs applyFail, applyPass

-}

import Compendium
import Dict
import Encounter
import Encounter.SaveChain as SaveChain exposing (HpEffect(..))
import Encounter.SaveChain.Wire
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( Msg(..)
        , SaveChainHpKind(..)
        , SaveChainSide(..)
        )
import Ports
import Ui.SaveChain as UiSaveChain exposing (OutcomeForm, SaveChainUi)



-- ── OPEN / CLOSE ────────────────────────────────────────────────


open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( { model | modal = Just (ModalSaveChain (UiSaveChain.fresh target)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )



-- ── FORM FIELD SETTERS ──────────────────────────────────────────


withUi : (SaveChainUi -> SaveChainUi) -> Model -> Model
withUi fn model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            { model | modal = Just (ModalSaveChain (fn ui)) }

        _ ->
            model


nameChanged : String -> Model -> ( Model, Cmd Msg )
nameChanged name model =
    ( withUi (\u -> { u | name = name }) model, Cmd.none )


abilitySet : Compendium.Ability -> Model -> ( Model, Cmd Msg )
abilitySet ability model =
    ( withUi (\u -> { u | saveAbility = ability }) model, Cmd.none )


dcChanged : String -> Model -> ( Model, Cmd Msg )
dcChanged text model =
    ( withUi (\u -> { u | dcText = text }) model, Cmd.none )


dcOverrideChanged : String -> Model -> ( Model, Cmd Msg )
dcOverrideChanged text model =
    ( withUi (\u -> { u | dcOverrideText = text }) model, Cmd.none )


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withUi (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )



-- ── OUTCOME FIELD SETTERS (shared fail + success) ───────────────


mapSide : SaveChainSide -> (OutcomeForm -> OutcomeForm) -> SaveChainUi -> SaveChainUi
mapSide side fn ui =
    case side of
        SaveChainFail ->
            { ui | onFail = fn ui.onFail }

        SaveChainSuccess ->
            { ui | onSuccess = fn ui.onSuccess }


outcomeHpKindSet : SaveChainSide -> SaveChainHpKind -> Model -> ( Model, Cmd Msg )
outcomeHpKindSet side kind model =
    let
        hpEffect =
            case kind of
                SaveChainNoHp ->
                    NoHpEffect

                SaveChainDamage ->
                    DealDamage 0

                SaveChainHeal ->
                    HealFor 0

                SaveChainHalfFail ->
                    HalfFailDamage
    in
    ( withUi (mapSide side (\o -> { o | hpKind = hpEffect })) model
    , Cmd.none
    )


outcomeHpAmountChanged : SaveChainSide -> String -> Model -> ( Model, Cmd Msg )
outcomeHpAmountChanged side text model =
    ( withUi (mapSide side (\o -> { o | hpAmountText = text })) model
    , Cmd.none
    )


outcomeConditionNameChanged : SaveChainSide -> String -> Model -> ( Model, Cmd Msg )
outcomeConditionNameChanged side text model =
    ( withUi (mapSide side (\o -> { o | conditionName = text })) model
    , Cmd.none
    )


outcomeConditionNoteChanged : SaveChainSide -> String -> Model -> ( Model, Cmd Msg )
outcomeConditionNoteChanged side text model =
    ( withUi (mapSide side (\o -> { o | conditionNote = text })) model
    , Cmd.none
    )



-- ── PRESET OPS ──────────────────────────────────────────────────


presetPickerChanged : String -> Model -> ( Model, Cmd Msg )
presetPickerChanged name model =
    ( withUi (\u -> { u | presetPickerSelection = name }) model
    , Cmd.none
    )


{-| Load the currently-picked preset into the form. If the
picker is blank or the name isn't in the dict, this is a
no-op.
-}
presetLoad : Model -> ( Model, Cmd Msg )
presetLoad model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            case Dict.get ui.presetPickerSelection model.saveChainPresets of
                Just chain ->
                    ( { model
                        | modal =
                            Just (ModalSaveChain (UiSaveChain.fromChain ui chain))
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Save the current form as a named preset. Uses the `name`
field verbatim (whitespace-trimmed); refuses to save when the
name is empty so a nameless "one-shot" chain doesn't clobber
the dict with a `""` key.
-}
presetSave : Model -> ( Model, Cmd Msg )
presetSave model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                trimmed =
                    String.trim chain.name
            in
            if String.isEmpty trimmed then
                ( model, Cmd.none )

            else
                let
                    next =
                        Dict.insert trimmed { chain | name = trimmed } model.saveChainPresets

                    modelWithPreset =
                        { model
                            | saveChainPresets = next
                            , modal =
                                Just
                                    (ModalSaveChain
                                        { ui
                                            | loadedPresetName = Just trimmed
                                            , presetPickerSelection = trimmed
                                        }
                                    )
                        }
                in
                ( modelWithPreset
                , Ports.persistLocalSaveChainPresets (Encounter.SaveChain.Wire.encodePresets next)
                )

        _ ->
            ( model, Cmd.none )


{-| Delete the currently-loaded preset (identified by
`loadedPresetName`). Falls back to the picker selection if
nothing has been loaded yet, so the GM can nuke a stale entry
without loading it first.
-}
presetDelete : Model -> ( Model, Cmd Msg )
presetDelete model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                targetName =
                    case ui.loadedPresetName of
                        Just name ->
                            name

                        Nothing ->
                            ui.presetPickerSelection
            in
            if String.isEmpty (String.trim targetName) then
                ( model, Cmd.none )

            else
                let
                    next =
                        Dict.remove targetName model.saveChainPresets
                in
                ( { model
                    | saveChainPresets = next
                    , modal =
                        Just
                            (ModalSaveChain
                                { ui
                                    | loadedPresetName = Nothing
                                    , presetPickerSelection = ""
                                }
                            )
                  }
                , Ports.persistLocalSaveChainPresets (Encounter.SaveChain.Wire.encodePresets next)
                )

        _ ->
            ( model, Cmd.none )


{-| Reset the form to a blank chain without closing the modal.
-}
reset : Model -> ( Model, Cmd Msg )
reset model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            ( { model
                | modal =
                    Just (ModalSaveChain (UiSaveChain.fresh ui.target))
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )



-- ── APPLY ───────────────────────────────────────────────────────


{-| Apply the fail outcome to the target creature (or, when
`applyToSelected` is on, every selected creature). Doesn't
close the modal — the GM often resolves fail + pass in one
open (fail first for the creatures that missed, pass for the
survivors).
-}
applyFail : Model -> ( Model, Cmd Msg )
applyFail =
    applySide SaveChainFail


applyPass : Model -> ( Model, Cmd Msg )
applyPass =
    applySide SaveChainSuccess


applySide : SaveChainSide -> Model -> ( Model, Cmd Msg )
applySide side model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                failAmount =
                    case chain.onFail.hp of
                        DealDamage n ->
                            n

                        _ ->
                            0

                outcome =
                    case side of
                        SaveChainFail ->
                            chain.onFail

                        SaveChainSuccess ->
                            chain.onSuccess

                targets =
                    resolveTargets ui model.encounter

                nextEnc =
                    List.foldl
                        (SaveChain.applyOutcome
                            { failAmount = failAmount }
                            outcome
                            |> flipEnc
                        )
                        model.encounter
                        targets
            in
            ( { model | encounter = nextEnc }, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Adapter: `SaveChain.applyOutcome` takes `enc -> target ->
enc`; `List.foldl` wants `target -> enc -> enc`. Flip the
argument order so the fold composes cleanly.
-}
flipEnc :
    (Encounter.Encounter -> String -> Encounter.Encounter)
    -> String
    -> Encounter.Encounter
    -> Encounter.Encounter
flipEnc fn target enc =
    fn enc target


resolveTargets : SaveChainUi -> Encounter.Encounter -> List String
resolveTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]
