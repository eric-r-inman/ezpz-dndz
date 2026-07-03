module Update.SaveChain exposing
    ( open, close
    , nameChanged, abilitySet, dcChanged, dcOverrideChanged
    , applyToSelectedToggle
    , outcomeHpKindSet, outcomeHpAmountChanged
    , outcomeEffectAdd, outcomeEffectRemove
    , outcomeEffectNameChanged, outcomeEffectNoteChanged
    , presetPickerChanged, presetLoad, presetSave, presetDelete, reset
    , applyFail, applyPass
    , applyRollLanded
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
@docs outcomeEffectAdd, outcomeEffectRemove
@docs outcomeEffectNameChanged, outcomeEffectNoteChanged
@docs presetPickerChanged, presetLoad, presetSave, presetDelete, reset
@docs applyFail, applyPass

-}

import Compendium
import Dice
import Dict
import Effects
import Encounter
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)
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
                    DealDamage ""

                SaveChainHeal ->
                    HealFor ""

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


outcomeEffectAdd : SaveChainSide -> Model -> ( Model, Cmd Msg )
outcomeEffectAdd side model =
    ( withUi
        (mapSide side
            (\o -> { o | effects = o.effects ++ [ SaveChain.emptyEffect ] })
        )
        model
    , Cmd.none
    )


outcomeEffectRemove : SaveChainSide -> Int -> Model -> ( Model, Cmd Msg )
outcomeEffectRemove side idx model =
    ( withUi
        (mapSide side
            (\o -> { o | effects = removeAt idx o.effects })
        )
        model
    , Cmd.none
    )


outcomeEffectNameChanged : SaveChainSide -> Int -> String -> Model -> ( Model, Cmd Msg )
outcomeEffectNameChanged side idx text model =
    ( withUi
        (mapSide side
            (\o -> { o | effects = updateAt idx (\e -> { e | name = text }) o.effects })
        )
        model
    , Cmd.none
    )


outcomeEffectNoteChanged : SaveChainSide -> Int -> String -> Model -> ( Model, Cmd Msg )
outcomeEffectNoteChanged side idx text model =
    ( withUi
        (mapSide side
            (\o -> { o | effects = updateAt idx (\e -> { e | note = text }) o.effects })
        )
        model
    , Cmd.none
    )


removeAt : Int -> List a -> List a
removeAt idx list =
    List.take idx list ++ List.drop (idx + 1) list


updateAt : Int -> (a -> a) -> List a -> List a
updateAt idx fn list =
    List.indexedMap
        (\i x ->
            if i == idx then
                fn x

            else
                x
        )
        list



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


applyFail : Model -> ( Model, Cmd Msg )
applyFail =
    applySide SaveChainFail


applyPass : Model -> ( Model, Cmd Msg )
applyPass =
    applySide SaveChainSuccess


{-| Apply one side of the chain. Walks the outcome:

  - `NoHpEffect` — no HP work, just apply the condition (if any).
  - `DealDamage` / `HealFor` — parse the raw text:
      - integer → apply the HP change immediately, then the condition
      - dice formula → fire a `Dice.rollCmd`; the roll lands in
        [`applyRollLanded`](#applyRollLanded), which finishes the
        apply
      - parse failure → skip the HP part, still apply the condition
  - `HalfFailDamage` (success side only) — same routing against the
    fail's raw text; the resolved integer is halved before applying.

The condition apply always fires synchronously — dice rolling
never gates it, because conditions don't depend on the rolled
amount. The Fail / Pass buttons don't close the modal either
so the GM can run Fail for the misses, then Pass for the
survivors, on the same open.

-}
applySide : SaveChainSide -> Model -> ( Model, Cmd Msg )
applySide side model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                outcome =
                    outcomeFor side chain

                targets =
                    resolveTargets ui model.encounter

                -- Effect list applies always fire (no dice needed).
                withConditions =
                    List.foldl
                        (\name enc ->
                            SaveChain.applyEffects outcome name enc
                        )
                        model.encounter
                        targets

                modelAfterCond =
                    { model | encounter = withConditions }
            in
            case rawTextForResolve side chain of
                RawEmpty ->
                    ( modelAfterCond, Cmd.none )

                RawInteger n ->
                    let
                        resolvedAmount =
                            case ( side, outcome.hp ) of
                                ( SaveChainSuccess, HalfFailDamage ) ->
                                    SaveChain.halfFailDamage n

                                _ ->
                                    n

                        nextEnc =
                            List.foldl
                                (\name enc ->
                                    SaveChain.applyResolvedHp outcome.hp resolvedAmount name enc
                                )
                                withConditions
                                targets
                    in
                    ( { modelAfterCond | encounter = nextEnc }, Cmd.none )

                RawDice expr ->
                    ( modelAfterCond
                    , Dice.rollCmd (SaveChainApplyRollLanded side)
                        (saveChainSource side chain ui model.encounter)
                        expr
                    )

                RawUnparseable ->
                    -- Non-empty text that's neither an integer nor
                    -- a valid dice expression: apply the condition
                    -- side (already done above) and leave HP alone
                    -- rather than crashing the click.
                    ( modelAfterCond, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Roll from a Save Chain apply landed. Halve if the outcome
was `HalfFailDamage` (success side); otherwise apply the raw
total. Recomputes targets from the current model state in case
the selection shifted while the roll was in flight.
-}
applyRollLanded : SaveChainSide -> Dice.Roll -> Model -> ( Model, Cmd Msg )
applyRollLanded side roll model =
    let
        ( logged, flashCmd ) =
            Effects.pushDiceRoll roll model
    in
    case logged.modal of
        Just (ModalSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                outcome =
                    outcomeFor side chain

                targets =
                    resolveTargets ui logged.encounter

                resolvedAmount =
                    case ( side, outcome.hp ) of
                        ( SaveChainSuccess, HalfFailDamage ) ->
                            SaveChain.halfFailDamage roll.total

                        _ ->
                            roll.total

                nextEnc =
                    List.foldl
                        (\name enc ->
                            SaveChain.applyResolvedHp outcome.hp resolvedAmount name enc
                        )
                        logged.encounter
                        targets
            in
            ( { logged | encounter = nextEnc }
            , Cmd.batch [ Effects.persistDiceRoll roll, flashCmd ]
            )

        _ ->
            ( logged, Cmd.batch [ Effects.persistDiceRoll roll, flashCmd ] )


outcomeFor : SaveChainSide -> SaveChain -> SaveOutcome
outcomeFor side chain =
    case side of
        SaveChainFail ->
            chain.onFail

        SaveChainSuccess ->
            chain.onSuccess


type ResolvedRaw
    = RawEmpty
    | RawInteger Int
    | RawDice Dice.Expression
    | RawUnparseable


{-| Decide what to do with the raw amount text on the outcome
we're applying. For `HalfFailDamage` on the success side, we
consult the fail's raw text (that's the amount getting halved).
Empty text or `NoHpEffect` short-circuits to `RawEmpty`.
-}
rawTextForResolve : SaveChainSide -> SaveChain -> ResolvedRaw
rawTextForResolve side chain =
    let
        outcome =
            outcomeFor side chain

        raw =
            case ( side, outcome.hp ) of
                ( SaveChainSuccess, HalfFailDamage ) ->
                    SaveChain.rawAmount chain.onFail.hp

                _ ->
                    SaveChain.rawAmount outcome.hp

        trimmed =
            String.trim raw
    in
    if String.isEmpty trimmed then
        RawEmpty

    else
        case String.toInt trimmed of
            Just n ->
                RawInteger n

            Nothing ->
                case Dice.parse trimmed of
                    Ok expr ->
                        RawDice expr

                    Err _ ->
                        RawUnparseable


{-| Label the dice history entry with a chain-flavoured source
so a GM scanning the dice history sees "Fireball (fail) →
Goblin 1, Goblin 2".
-}
saveChainSource :
    SaveChainSide
    -> SaveChain
    -> SaveChainUi
    -> Encounter.Encounter
    -> Dice.Source
saveChainSource side chain ui enc =
    let
        chainLabel =
            if String.isEmpty chain.name then
                "Save Chain"

            else
                chain.name

        sideLabel =
            case side of
                SaveChainFail ->
                    "fail"

                SaveChainSuccess ->
                    "success"

        feature =
            chainLabel ++ " (" ++ sideLabel ++ ")"

        targetLabel =
            let
                names =
                    resolveTargets ui enc
            in
            if List.isEmpty names then
                ui.target

            else
                String.join ", " names
    in
    { feature = feature, target = Just targetLabel }


resolveTargets : SaveChainUi -> Encounter.Encounter -> List String
resolveTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]
