module Update.SaveChain exposing
    ( nameChanged, abilitySet, dcChanged
    , applyToSelectedToggle
    , outcomeHpKindSet, outcomeHpAmountChanged
    , outcomeEffectAdd, outcomeEffectRemove
    , outcomeEffectNameChanged, outcomeEffectNoteChanged
    , presetPickerChanged, presetLoad, presetSave, presetDelete, reset
    , applyFail, applyPass, applyRollLanded
    , rollSaves, savesRolled
    , areaRollNow, areaSaveLanded, areaSet, immunityDurationEdit, immunityToggle, markArea, outcomeEffectAutoRollSet, outcomeEffectDurationEdit, outcomeEffectFailBecomesChanged, outcomeEffectFailDamageChanged, outcomeEffectOnDamageSet, outcomeEffectSaveToEndToggle, outcomeEffectWithChanged, restoreBundled
    )

{-| Update branches for the Save Chain modal.

The modal is a form editor plus two apply buttons; the form's
raw state lives in `UiSaveChain.SaveChainUi`, projected back
to `Encounter.SaveChain.SaveChain` at save / apply time.
Presets are stored in `model.saveChainPresets` (dict keyed by
name); the persistence Cmd is fired from `Main.elm`'s model-
diff pass — `Ports.persistLocalSaveChainPresets` for anonymous
users, `Effects.putSaveChainPresets` for authenticated ones —
so update branches here return `Cmd.none` on preset mutations
and let the diff catch it.

@docs nameChanged, abilitySet, dcChanged
@docs applyToSelectedToggle
@docs outcomeHpKindSet, outcomeHpAmountChanged
@docs outcomeEffectAdd, outcomeEffectRemove
@docs outcomeEffectNameChanged, outcomeEffectNoteChanged
@docs presetPickerChanged, presetLoad, presetSave, presetDelete, reset
@docs applyFail, applyPass, applyRollLanded
@docs rollSaves, savesRolled

-}

import Compendium
import Dice
import Dict
import Effects
import Encounter
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)
import Encounter.SaveChain.Bundled
import Model exposing (Model, Surface(..))
import Msg
    exposing
        ( DurationEdit
        , Msg(..)
        , SaveChainHpKind(..)
        , SaveChainRollMode(..)
        , SaveChainSide(..)
        )
import Random
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.DurationEdit
import Ui.SaveChain as UiSaveChain exposing (OutcomeForm, SaveChainUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.saveChainLens model
        |> Maybe.map SurfaceSaveChain



-- ── FORM FIELD SETTERS ──────────────────────────────────────────


withUi : (SaveChainUi -> SaveChainUi) -> Model -> Model
withUi =
    Model.mapDrawer Model.saveChainLens


nameChanged : String -> Model -> ( Model, Cmd Msg )
nameChanged name model =
    ( withUi (\u -> { u | name = name }) model, Cmd.none )


abilitySet : Compendium.Ability -> Model -> ( Model, Cmd Msg )
abilitySet ability model =
    ( withUi (\u -> { u | saveAbility = ability }) model, Cmd.none )


dcChanged : String -> Model -> ( Model, Cmd Msg )
dcChanged text model =
    ( withUi (\u -> { u | dcText = text }) model, Cmd.none )


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

                SaveChainDrain ->
                    DrainDamage ""
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


outcomeEffectSaveToEndToggle : SaveChainSide -> Int -> Model -> ( Model, Cmd Msg )
outcomeEffectSaveToEndToggle side idx model =
    ( withUi
        (mapSide side
            (\o ->
                { o
                    | effects =
                        updateAt idx
                            (\e ->
                                { e
                                    | saveToEnd =
                                        case e.saveToEnd of
                                            Just _ ->
                                                Nothing

                                            Nothing ->
                                                Just
                                                    { autoRoll = Encounter.AutoRollAtEnd
                                                    , onFail = Encounter.noFailedSave
                                                    , onDamage = Encounter.NoDamageTrigger
                                                    }
                                }
                            )
                            o.effects
                }
            )
        )
        model
    , Cmd.none
    )


outcomeEffectAutoRollSet :
    SaveChainSide
    -> Int
    -> Encounter.AutoRollMode
    -> Model
    -> ( Model, Cmd Msg )
outcomeEffectAutoRollSet side idx mode model =
    ( withUi
        (mapSide side
            (\o ->
                { o
                    | effects =
                        updateAt idx
                            (\e -> { e | saveToEnd = Maybe.map (\s -> { s | autoRoll = mode }) e.saveToEnd })
                            o.effects
                }
            )
        )
        model
    , Cmd.none
    )


outcomeEffectDurationEdit : SaveChainSide -> Int -> DurationEdit -> Model -> ( Model, Cmd Msg )
outcomeEffectDurationEdit side idx edit model =
    ( withUi
        (mapSide side
            (\o ->
                { o
                    | effects =
                        updateAt idx
                            (\e -> { e | duration = Ui.DurationEdit.apply edit e.duration })
                            o.effects
                }
            )
        )
        model
    , Cmd.none
    )


outcomeEffectFailDamageChanged : SaveChainSide -> Int -> String -> Model -> ( Model, Cmd Msg )
outcomeEffectFailDamageChanged side idx text model =
    ( withUi (mapSide side (mapFailedSave idx (\f -> { f | damage = nonBlank text }))) model
    , Cmd.none
    )


outcomeEffectFailBecomesChanged : SaveChainSide -> Int -> String -> Model -> ( Model, Cmd Msg )
outcomeEffectFailBecomesChanged side idx text model =
    ( withUi (mapSide side (mapFailedSave idx (\f -> { f | becomes = nonBlank text }))) model
    , Cmd.none
    )


outcomeEffectOnDamageSet : SaveChainSide -> Int -> Encounter.DamageTrigger -> Model -> ( Model, Cmd Msg )
outcomeEffectOnDamageSet side idx trigger model =
    ( withUi
        (mapSide side
            (\o ->
                { o
                    | effects =
                        updateAt idx
                            (\e -> { e | saveToEnd = Maybe.map (\s -> { s | onDamage = trigger }) e.saveToEnd })
                            o.effects
                }
            )
        )
        model
    , Cmd.none
    )


outcomeEffectWithChanged : SaveChainSide -> Int -> String -> Model -> ( Model, Cmd Msg )
outcomeEffectWithChanged side idx text model =
    ( withUi
        (mapSide side
            (\o -> { o | effects = updateAt idx (\e -> { e | with = text }) o.effects })
        )
        model
    , Cmd.none
    )


areaSet : Maybe Encounter.TurnPhase -> Model -> ( Model, Cmd Msg )
areaSet phase model =
    ( withUi (\u -> { u | area = phase }) model, Cmd.none )


{-| Edit the failed-save outcome of the effect at `idx`; a no-op
for an effect without a save.
-}
mapFailedSave : Int -> (Encounter.FailedSave -> Encounter.FailedSave) -> OutcomeForm -> OutcomeForm
mapFailedSave idx fn o =
    { o
        | effects =
            updateAt idx
                (\e -> { e | saveToEnd = Maybe.map (\s -> { s | onFail = fn s.onFail }) e.saveToEnd })
                o.effects
    }


nonBlank : String -> Maybe String
nonBlank text =
    if String.isEmpty (String.trim text) then
        Nothing

    else
        Just text


immunityToggle : Model -> ( Model, Cmd Msg )
immunityToggle model =
    ( withUi
        (\u ->
            { u
                | immunity =
                    if u.immunity == Nothing then
                        Just SaveChain.LastsUntilRemoved

                    else
                        Nothing
            }
        )
        model
    , Cmd.none
    )


immunityDurationEdit : DurationEdit -> Model -> ( Model, Cmd Msg )
immunityDurationEdit edit model =
    ( withUi (\u -> { u | immunity = Maybe.map (Ui.DurationEdit.apply edit) u.immunity }) model
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
    -- Auto-load: picking a preset from the dropdown loads it
    -- immediately.  Also handles the placeholder "" option —
    -- that just resets the picker without touching the form.
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            let
                pickedUi =
                    { ui | presetPickerSelection = name }
            in
            if String.isEmpty name then
                ( Model.openDrawer Model.saveChainLens pickedUi model
                , Cmd.none
                )

            else
                case Dict.get name model.saveChainPresets of
                    Just chain ->
                        ( Model.openDrawer Model.saveChainLens
                            (UiSaveChain.fromChain pickedUi chain)
                            model
                        , Cmd.none
                        )

                    Nothing ->
                        ( Model.openDrawer Model.saveChainLens pickedUi model
                        , Cmd.none
                        )

        _ ->
            ( model, Cmd.none )


{-| Explicit "load selected preset" handler — kept around for
completeness even though the auto-load in
`presetPickerChanged` now covers the common case. Useful if a
future entry point wants to reload the current picker
selection without cycling through the dropdown.
-}
presetLoad : Model -> ( Model, Cmd Msg )
presetLoad model =
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            case Dict.get ui.presetPickerSelection model.saveChainPresets of
                Just chain ->
                    ( Model.openDrawer Model.saveChainLens
                        (UiSaveChain.fromChain ui chain)
                        model
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
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                trimmed =
                    String.trim chain.name
            in
            if String.isEmpty trimmed then
                ( model, Cmd.none )

            else
                ( { model
                    | saveChainPresets =
                        Dict.insert trimmed { chain | name = trimmed } model.saveChainPresets
                  }
                    |> withUi
                        (\u ->
                            { u
                                | loadedPresetName = Just trimmed
                                , presetPickerSelection = trimmed
                            }
                        )
                , Cmd.none
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
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
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
                ( { model | saveChainPresets = Dict.remove targetName model.saveChainPresets }
                    |> withUi
                        (\u ->
                            { u
                                | loadedPresetName = Nothing
                                , presetPickerSelection = ""
                            }
                        )
                , Cmd.none
                )

        _ ->
            ( model, Cmd.none )


{-| Reset the form to a blank chain without closing the modal.
-}
reset : Model -> ( Model, Cmd Msg )
reset model =
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            ( Model.openDrawer Model.saveChainLens
                (UiSaveChain.fresh ui.target)
                model
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


{-| Lay every bundled preset over `model.saveChainPresets`, drop
the names the bundle has since retired, and re-load the open
form when it holds a bundled preset so its rows show the
restored definition. The GM's own presets are untouched. The
persist Cmd comes from `Main.elm`'s model-diff pass, as for every
other preset mutation here; the toast is the only feedback a
restore that changes nothing visible would otherwise lack.
-}
restoreBundled : Model -> ( Model, Cmd Msg )
restoreBundled model =
    let
        bundled =
            Encounter.SaveChain.Bundled.defaults

        next =
            Dict.foldl Dict.insert model.saveChainPresets bundled
                |> Dict.filter (\k _ -> not (isRetiredBundledKey bundled k))

        reloadIfBundled ui =
            ui.loadedPresetName
                |> Maybe.andThen (\name -> Dict.get name bundled)
                |> Maybe.map (UiSaveChain.fromChain ui)
                |> Maybe.withDefault ui
    in
    Update.Toast.push ToastSuccess
        ("Restored "
            ++ String.fromInt (Dict.size bundled)
            ++ " bundled presets; your own presets are untouched."
        )
        ({ model | saveChainPresets = next } |> withUi reloadIfBundled)


{-| True for a stored key the bundle no longer ships under that
name: one of `Bundled.retiredNames`, or the "<base> (<level
suffix>)" shape of the earlier bundled naming ("Hold Person
(2nd)", "Sacred Flame (cantrip)", …) whose base is a current
bundled key. Matching the suffix shape against the current keys
rather than a hand-maintained list keeps a GM's own
parenthesised names safe, since their base is not bundled.
-}
isRetiredBundledKey : Dict.Dict String SaveChain -> String -> Bool
isRetiredBundledKey bundled key =
    List.member key Encounter.SaveChain.Bundled.retiredNames
        || hasRetiredSuffix bundled key


hasRetiredSuffix : Dict.Dict String SaveChain -> String -> Bool
hasRetiredSuffix bundled key =
    let
        suffixes =
            [ " (cantrip)"
            , " (1st)"
            , " (2nd)"
            , " (3rd)"
            , " (4th)"
            , " (5th)"
            , " (6th)"
            , " (7th)"
            , " (8th)"
            , " (9th)"
            ]

        stripped =
            List.foldl
                (\suffix acc ->
                    case acc of
                        Just _ ->
                            acc

                        Nothing ->
                            if String.endsWith suffix key then
                                Just (String.dropRight (String.length suffix) key)

                            else
                                Nothing
                )
                Nothing
                suffixes
    in
    case stripped of
        Just base ->
            Dict.member base bundled

        Nothing ->
            False



-- ── APPLY ───────────────────────────────────────────────────────


applyFail : Model -> ( Model, Cmd Msg )
applyFail model =
    applySide SaveChainFail model


applyPass : Model -> ( Model, Cmd Msg )
applyPass model =
    applySide SaveChainSuccess model


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
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui
            in
            -- Defence in depth behind the disabled buttons: a
            -- Save-to-end effect applied without a DC would land
            -- as a plain condition and never roll.
            if SaveChain.needsDc chain && chain.saveDc == Nothing then
                ( model, Cmd.none )

            else
                applyOutcome side ui chain model

        _ ->
            ( model, Cmd.none )


applyOutcome : SaveChainSide -> SaveChainUi -> SaveChain -> Model -> ( Model, Cmd Msg )
applyOutcome side ui chain model =
    let
        outcome =
            outcomeFor side chain

        targets =
            resolveTargets chain ui model.encounter

        -- Creatures carrying the chain's immunity sit this one
        -- out; the log says so rather than leaving them unmentioned.
        immuneEntries =
            immuneTargets chain ui model.encounter
                |> List.map (immuneEntry side)

        effectCtx =
            buildEffectContext chain model

        -- Effect list applies always fire (no dice needed), and an
        -- area chain marks each target as standing in it.
        withConditions =
            List.foldl
                (\name enc ->
                    enc
                        |> SaveChain.applyEffects effectCtx outcome name
                        |> SaveChain.markArea effectCtx chain name
                )
                model.encounter
                targets

        modelAfterCond =
            { model | encounter = withConditions }

        entriesAt amount =
            List.map
                (\name ->
                    { target = name
                    , side = side
                    , rollNote = Nothing
                    , appliedParts = appliedParts outcome amount
                    }
                )
                targets

        finish amount m =
            pushLog (immuneEntries ++ entriesAt amount) (grantImmunities side chain targets m)
    in
    case rawTextForResolve side chain of
        RawEmpty ->
            ( finish 0 modelAfterCond, Cmd.none )

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
            ( finish resolvedAmount { modelAfterCond | encounter = nextEnc }, Cmd.none )

        RawDice expr ->
            -- Log entries are pushed after the roll lands
            -- (see `applyRollLanded`) so the amount reflects
            -- the actual dice total, not the mid-flight zero.
            ( pushLog immuneEntries modelAfterCond
            , Dice.rollCmd (SaveChainApplyRollLanded side)
                (saveChainSource side chain ui model.encounter)
                expr
            )

        RawUnparseable ->
            -- Non-empty text that's neither an integer nor
            -- a valid dice expression: apply the condition
            -- side (already done above) and leave HP alone
            -- rather than crashing the click.
            ( finish 0 modelAfterCond, Cmd.none )


{-| Roll from a Save Chain apply landed. Halve if the outcome
was `HalfFailDamage` (success side); otherwise apply the raw
total. Recomputes targets from the current model state in case
the selection shifted while the roll was in flight.
-}
applyRollLanded : SaveChainSide -> Dice.Roll -> Model -> ( Model, Cmd Msg )
applyRollLanded side roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model
    in
    case drawerSurface logged of
        Just (SurfaceSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                outcome =
                    outcomeFor side chain

                targets =
                    resolveTargets chain ui logged.encounter

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

                entries =
                    List.map
                        (\name ->
                            { target = name
                            , side = side
                            , rollNote = Nothing
                            , appliedParts = appliedParts outcome resolvedAmount
                            }
                        )
                        targets
            in
            ( pushLog entries (grantImmunities side chain targets { logged | encounter = nextEnc })
            , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]
            )

        _ ->
            ( logged, Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ] )


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
                    resolveTargets chain ui enc
            in
            if List.isEmpty names then
                ui.target

            else
                String.join ", " names
    in
    { feature = feature, target = Just targetLabel }


{-| The creatures the chain acts on: the target, or the selection
when that scope is on, less placeholders and less any creature
carrying this chain's immunity.
-}
resolveTargets : SaveChain -> SaveChainUi -> Encounter.Encounter -> List String
resolveTargets chain ui enc =
    scopedTargets ui enc
        |> List.filter (\name -> not (SaveChain.isImmune chain name enc))


{-| The creatures in scope the chain must leave alone.
-}
immuneTargets : SaveChain -> SaveChainUi -> Encounter.Encounter -> List String
immuneTargets chain ui enc =
    scopedTargets ui enc
        |> List.filter (\name -> SaveChain.isImmune chain name enc)


scopedTargets : SaveChainUi -> Encounter.Encounter -> List String
scopedTargets ui enc =
    Encounter.excludingPlaceholderNames enc
        (if ui.applyToSelected then
            enc.creatures
                |> List.filter .selected
                |> List.map .name

         else
            [ ui.target ]
        )


immuneEntry : SaveChainSide -> String -> UiSaveChain.SaveChainLogEntry
immuneEntry side name =
    { target = name
    , side = side
    , rollNote = Just "immune"
    , appliedParts = []
    }


{-| The success side's last step. The chain's immunity, when it
grants one, lands after the outcome so a formula heal or a half
damage still reaches the target this apply.
-}
grantImmunities : SaveChainSide -> SaveChain -> List String -> Model -> Model
grantImmunities side chain targets model =
    case side of
        SaveChainSuccess ->
            { model
                | encounter =
                    List.foldl
                        (SaveChain.grantImmunity model.encounter.activeName chain)
                        model.encounter
                        targets
            }

        SaveChainFail ->
            model



-- ── ROLL SAVES (auto-apply) ─────────────────────────────────────


{-| "🎲 Roll saves" / "Roll Adv." / "Roll Disadv." buttons:
for every current target, build a `d20 + save-mod` spec (save
mod pulled from the target's compendium record — explicit
saving-throw override wins, otherwise the ability modifier is
used), fire a batch roll, and route the results back through
`SaveChainSavesRolled`.

`mode` picks between straight `1d20 + mod`
(`SaveChainRollNormal`), 5e advantage
(`SaveChainRollAdvantage` → 2d20-keep-highest), or 5e
disadvantage (`SaveChainRollDisadvantage` → 2d20-keep-lowest).
Each target rolls independently under the chosen mode — the
downstream fail / pass routing in `savesRolled` cares only
about `roll.total`.

Returns silently when the chain has no DC (either fixed or
overridden) — the panel disables the buttons visually in that
case; this guard is defence in depth.

-}
rollSaves : SaveChainRollMode -> Model -> ( Model, Cmd Msg )
rollSaves mode model =
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            case resolveDc ui of
                Nothing ->
                    ( model, Cmd.none )

                Just _ ->
                    let
                        specs =
                            buildSaveSpecs mode ui model

                        -- Creatures carrying the chain's immunity
                        -- don't roll; the log says why they sat out.
                        skipped =
                            immuneTargets (UiSaveChain.toChain ui) ui model.encounter
                                |> List.map (immuneEntry SaveChainSuccess)
                    in
                    if List.isEmpty specs then
                        ( pushLog skipped model, Cmd.none )

                    else
                        ( pushLog skipped model, Dice.batchRollCmd SaveChainSavesRolled specs )

        _ ->
            ( model, Cmd.none )


{-| Assemble the per-target `(name, source, generator)` specs
`Dice.batchRollCmd` wants. Skips a target if we can't find its
compendium record (placeholder rows, name drift) since we
have no way to attribute a modifier. The generator itself is
either `1d20 + <save-mod>`, `2d20-keep-highest + <save-mod>`
(advantage), or `2d20-keep-lowest + <save-mod>` (disadvantage),
picked by `mode`. Feature label carries the mode so the dice
history reads "Save (WIS, Adv)" when the GM rolled with
advantage.
-}
buildSaveSpecs :
    SaveChainRollMode
    -> UiSaveChain.SaveChainUi
    -> Model
    -> List ( String, Dice.Source, Random.Generator Dice.Roll )
buildSaveSpecs mode ui model =
    let
        chain =
            UiSaveChain.toChain ui

        db =
            currentCompendium model.compendium.db

        targets =
            resolveTargets chain ui model.encounter

        abilityLabel =
            saveAbilityLabel chain.saveAbility

        modeLabel =
            case mode of
                SaveChainRollNormal ->
                    ""

                SaveChainRollAdvantage ->
                    ", Adv"

                SaveChainRollDisadvantage ->
                    ", Disadv"

        genForMod modifier =
            case mode of
                SaveChainRollNormal ->
                    let
                        expressionText =
                            "1d20" ++ signedInt modifier
                    in
                    Dice.parse expressionText
                        |> Result.map Dice.generator
                        |> Result.toMaybe

                SaveChainRollAdvantage ->
                    Just (Dice.advantageGenerator modifier)

                SaveChainRollDisadvantage ->
                    Just (Dice.disadvantageGenerator modifier)

        specFor name =
            case findCreatureRecord db name model.encounter of
                Just c ->
                    case genForMod (saveModifier chain.saveAbility c) of
                        Just gen ->
                            Just
                                ( name
                                , { feature = "Save (" ++ abilityLabel ++ modeLabel ++ ")"
                                  , target = Just name
                                  }
                                , gen
                                )

                        Nothing ->
                            Nothing

                Nothing ->
                    Nothing
    in
    List.filterMap specFor targets


{-| Batch of `1d20 + mod` rolls landed. For each result,
compare `roll.total` against the resolved DC: `>= DC` walks
through the Pass outcome, otherwise the Fail outcome. Roll
history is pushed and persisted through the shared dice
plumbing so the GM can see every roll in the dice modal
afterwards.
-}
savesRolled : List ( String, Dice.Roll ) -> Model -> ( Model, Cmd Msg )
savesRolled results model =
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            case resolveDc ui of
                Nothing ->
                    ( model, Cmd.none )

                Just dc ->
                    let
                        chain =
                            UiSaveChain.toChain ui

                        ( failNames, passNames ) =
                            List.partition
                                (\( _, roll ) -> roll.total < dc)
                                results
                                |> (\( f, p ) ->
                                        ( List.map Tuple.first f
                                        , List.map Tuple.first p
                                        )
                                   )

                        modelWithHistory =
                            List.foldl
                                (\( _, roll ) acc ->
                                    Effects.pushDiceRoll roll acc
                                        |> Tuple.first
                                )
                                model
                                results

                        historyCmds =
                            List.map (\( _, roll ) -> Effects.persistDiceRoll roll)
                                results

                        failResolvedAmount =
                            resolvedAmountFor chain.onFail.hp 0

                        successResolvedAmount =
                            resolvedAmountFor chain.onSuccess.hp failResolvedAmount

                        effectCtx =
                            buildEffectContext chain model

                        encAfterFail =
                            List.foldl
                                (\name enc ->
                                    enc
                                        |> SaveChain.applyEffects effectCtx chain.onFail name
                                        |> SaveChain.applyResolvedHp chain.onFail.hp failResolvedAmount name
                                )
                                modelWithHistory.encounter
                                failNames

                        encAfterAll =
                            List.foldl
                                (\name enc ->
                                    enc
                                        |> SaveChain.applyEffects effectCtx chain.onSuccess name
                                        |> SaveChain.applyResolvedHp chain.onSuccess.hp successResolvedAmount name
                                )
                                encAfterFail
                                passNames

                        encWithImmunity =
                            List.foldl
                                (SaveChain.grantImmunity model.encounter.activeName chain)
                                encAfterAll
                                passNames
                                |> (\enc ->
                                        List.foldl (SaveChain.markArea effectCtx chain)
                                            enc
                                            (failNames ++ passNames)
                                   )

                        entryFor ( name, roll ) =
                            let
                                passed =
                                    roll.total >= dc

                                ( side, resolvedAmount, outcome ) =
                                    if passed then
                                        ( SaveChainSuccess
                                        , successResolvedAmount
                                        , chain.onSuccess
                                        )

                                    else
                                        ( SaveChainFail
                                        , failResolvedAmount
                                        , chain.onFail
                                        )
                            in
                            { target = name
                            , side = side
                            , rollNote = Just (rollNote roll.total dc)
                            , appliedParts = appliedParts outcome resolvedAmount
                            }

                        entries =
                            List.map entryFor results
                    in
                    ( pushLog entries { modelWithHistory | encounter = encWithImmunity }
                    , Cmd.batch historyCmds
                    )

        _ ->
            ( model, Cmd.none )



-- ── AREA EFFECTS ───────────────────────────────────────────────


{-| Mark every target as standing in the chain's area without
resolving anything now; the marker rolls the save at its phase of
each creature's turn. A creature already marked keeps its marker.
-}
markArea : Model -> ( Model, Cmd Msg )
markArea model =
    case drawerSurface model of
        Just (SurfaceSaveChain ui) ->
            let
                chain =
                    UiSaveChain.toChain ui

                effectCtx =
                    buildEffectContext chain model
            in
            ( { model
                | encounter =
                    List.foldl (SaveChain.markArea effectCtx chain)
                        model.encounter
                        (resolveTargets chain ui model.encounter)
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


{-| The 🎲 on an area marker's chip: a creature that walked into
the area mid-turn saves now rather than waiting for the phase.
-}
areaRollNow : String -> Int -> Model -> ( Model, Cmd Msg )
areaRollNow name id model =
    ( model
    , Encounter.findCondition name id model.encounter
        |> Maybe.andThen (\( _, cond ) -> Maybe.map (Tuple.pair cond) cond.area)
        |> Maybe.map (\( cond, tracker ) -> Effects.areaRollCmd name cond tracker)
        |> Maybe.withDefault Cmd.none
    )


{-| An area marker's save landed: the side the roll earned applies
to the bearer as one more resolution of the chain the marker
names, with an auto-rolled amount as `savesRolled` uses, and the
marker stays for the next turn. The chain is read from the
presets by name, so a preset the GM has since deleted leaves a
toast rather than an outcome.
-}
areaSaveLanded : String -> Int -> Dice.Roll -> Model -> ( Model, Cmd Msg )
areaSaveLanded name id roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model

        cmds =
            Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]

        tracker =
            Encounter.findCondition name id logged.encounter
                |> Maybe.andThen (\( _, cond ) -> cond.area)
    in
    case Maybe.map (\t -> ( t, Dict.get t.chain logged.saveChainPresets )) tracker of
        Just ( t, Just chain ) ->
            ( resolveAreaSave name t chain roll logged, cmds )

        Just ( t, Nothing ) ->
            Update.Toast.push ToastError
                ("No Save Chain preset named \"" ++ t.chain ++ "\" to resolve " ++ name ++ "'s save against.")
                logged
                |> Tuple.mapSecond (\toastCmd -> Cmd.batch [ cmds, toastCmd ])

        Nothing ->
            ( logged, cmds )


resolveAreaSave : String -> Encounter.AreaTracker -> SaveChain -> Dice.Roll -> Model -> Model
resolveAreaSave name tracker chain roll model =
    let
        passed =
            roll.total >= tracker.dc

        ( side, outcome ) =
            if passed then
                ( SaveChainSuccess, chain.onSuccess )

            else
                ( SaveChainFail, chain.onFail )

        -- The marker's own ability and DC stand in for the preset's,
        -- which a spell preset leaves blank for the caster to fill.
        effectCtx =
            buildEffectContext { chain | saveDc = Just tracker.dc } model

        failAmount =
            resolvedAmountFor chain.onFail.hp 0

        amount =
            if passed then
                resolvedAmountFor chain.onSuccess.hp failAmount

            else
                failAmount

        withOutcome =
            model.encounter
                |> SaveChain.applyEffects effectCtx outcome name
                |> SaveChain.applyResolvedHp outcome.hp amount name

        withImmunity =
            if passed then
                SaveChain.grantImmunity model.encounter.activeName chain name withOutcome

            else
                withOutcome
    in
    pushLog
        [ { target = name
          , side = side
          , rollNote = Just (rollNote roll.total tracker.dc)
          , appliedParts = appliedParts outcome amount
          }
        ]
        { model | encounter = withImmunity }


{-| The amount an auto-rolled resolution applies for an HP effect:
the fail side's resolved amount halved for a half-of-fail
success, the parsed-or-averaged formula otherwise.
-}
resolvedAmountFor : HpEffect -> Int -> Int
resolvedAmountFor hp failAmount =
    case hp of
        NoHpEffect ->
            0

        DealDamage s ->
            parseIntOrAverage s

        HealFor s ->
            parseIntOrAverage s

        HalfFailDamage ->
            SaveChain.halfFailDamage failAmount

        DrainDamage s ->
            parseIntOrAverage s



-- ── HELPERS ─────────────────────────────────────────────────────


{-| The DC the chain resolves against: `Nothing` while the DC
field is blank. The roll buttons are disabled in that state, but
the guard is here too.
-}
resolveDc : UiSaveChain.SaveChainUi -> Maybe Int
resolveDc ui =
    (UiSaveChain.toChain ui).saveDc


{-| Resolve the compendium view of a queue creature: prefer the
`creatureId` link, fall back to the by-name lookup for
paste-in creatures whose id has drifted.
-}
findCreatureRecord :
    Maybe Compendium.Db
    -> String
    -> Encounter.Encounter
    -> Maybe Compendium.Creature
findCreatureRecord maybeDb name enc =
    case maybeDb of
        Nothing ->
            Nothing

        Just db ->
            enc.creatures
                |> List.filter (\c -> c.name == name)
                |> List.head
                |> Maybe.andThen
                    (\c ->
                        case c.creatureId of
                            Just id ->
                                case Compendium.find id db of
                                    Just hit ->
                                        Just hit

                                    Nothing ->
                                        Compendium.findByName c.name db

                            Nothing ->
                                Compendium.findByName c.name db
                    )


currentCompendium : CompendiumDb -> Maybe Compendium.Db
currentCompendium db =
    case db of
        CompendiumDbLoaded loaded ->
            Just loaded

        _ ->
            Nothing


{-| Build the effect-application context that
`SaveChain.applyEffects` needs. Supplies the chain's save
ability + DC plus a per-target save-bonus resolver
(compendium lookup — proficient override wins, else raw
ability mod; 0 if the target isn't in the DB). Effects
that opt into save-to-end pick their own auto-roll mode;
the domain reads it off the effect and wires it in when
building the `SaveToEnd`.
-}
buildEffectContext : SaveChain -> Model -> SaveChain.EffectContext
buildEffectContext chain model =
    let
        db =
            currentCompendium model.compendium.db
    in
    { saveAbility = saveAbilityLabel chain.saveAbility
    , saveDc = chain.saveDc
    , bonusFor =
        \targetName ->
            findCreatureRecord db targetName model.encounter
                |> Maybe.map (saveModifier chain.saveAbility)
                |> Maybe.withDefault 0
    , activeName = model.encounter.activeName
    }


{-| Save modifier for `ability` on a compendium creature.
Explicit saving-throw override wins (proficient monster);
otherwise the raw ability modifier is used.
-}
saveModifier : Compendium.Ability -> Compendium.Creature -> Int
saveModifier ability c =
    case List.filter (\s -> s.ability == ability) c.savingThrows of
        first :: _ ->
            first.bonus

        [] ->
            abilityScoreModifier (abilityScore ability c.abilities)


abilityScore : Compendium.Ability -> Compendium.Abilities -> Int
abilityScore ability abs =
    case ability of
        Compendium.Str ->
            abs.str

        Compendium.Dex ->
            abs.dex

        Compendium.Con ->
            abs.con

        Compendium.Int_ ->
            abs.int

        Compendium.Wis ->
            abs.wis

        Compendium.Cha ->
            abs.cha


abilityScoreModifier : Int -> Int
abilityScoreModifier score =
    let
        raw =
            score - 10
    in
    -- 5e ability-modifier formula rounds toward negative infinity.
    -- Integer division `//` in Elm truncates toward zero, so a raw
    -- -3 divides as -1 rather than -2.  Adjust for odd-negative.
    if raw < 0 && modBy 2 raw /= 0 then
        raw // 2 - 1

    else
        raw // 2


signedInt : Int -> String
signedInt n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


saveAbilityLabel : Compendium.Ability -> String
saveAbilityLabel a =
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


{-| Parse an integer amount, or if the text is a dice formula,
fall back to the arithmetic average (rounded down) of the
expression. Used by the auto-roll path so a chain whose fail
damage is `8d6` still resolves to a concrete number without a
second dice roll — the GM sees one grand roll per creature for
the save; individual damage rolls would explode the click into
1 + N Cmds.
-}
parseIntOrAverage : String -> Int
parseIntOrAverage raw =
    let
        trimmed =
            String.trim raw
    in
    case String.toInt trimmed of
        Just n ->
            n

        Nothing ->
            case Dice.parse trimmed of
                Ok expr ->
                    diceAverage expr

                Err _ ->
                    0


diceAverage : Dice.Expression -> Int
diceAverage expr =
    -- Ballpark average: sum of (count * (faces+1) / 2) across
    -- each die group (with the group's sign), plus the flat
    -- constant.  Rounds down — fine for a GM's auto-apply
    -- flow; they can undo if the number lands too generous.
    let
        groupsAvg =
            List.foldl
                (\d acc ->
                    let
                        groupAvg =
                            d.count * (d.faces + 1) // 2
                    in
                    case d.sign of
                        Dice.Positive ->
                            acc + groupAvg

                        Dice.Negative ->
                            acc - groupAvg
                )
                0
                expr.dice
    in
    groupsAvg + expr.constant



-- ── LOG PUSH HELPERS ────────────────────────────────────────────


{-| Build the `appliedParts` list for a log entry: which HP
delta landed + which effect names got attached. Structured
(not stringified) so the view can colour each part — red
damage, green healing, plain-text effect names. Empty list =
"(no effect)" — the entry still records that the save
resolved.
-}
appliedParts : SaveOutcome -> Int -> List UiSaveChain.AppliedPart
appliedParts outcome resolvedAmount =
    let
        hpPart =
            case outcome.hp of
                NoHpEffect ->
                    []

                DealDamage _ ->
                    [ UiSaveChain.DamagePart resolvedAmount ]

                HealFor _ ->
                    [ UiSaveChain.HealPart resolvedAmount ]

                HalfFailDamage ->
                    [ UiSaveChain.DamagePart resolvedAmount ]

                DrainDamage _ ->
                    [ UiSaveChain.DrainPart resolvedAmount ]

        effectPart =
            outcome.effects
                |> List.filterMap
                    (\e ->
                        let
                            trimmed =
                                String.trim e.name
                        in
                        if String.isEmpty trimmed then
                            Nothing

                        else
                            Just (UiSaveChain.EffectPart trimmed)
                    )
    in
    hpPart ++ effectPart


{-| Prepend log entries to `model.saveChainLog`, capping at
`Ui.SaveChain.maxSaveChainLogEntries`. New entries are
built in target order, then reversed so the last-applied
target renders newest-first alongside the incoming entries
from a prior apply.
-}
pushLog : List UiSaveChain.SaveChainLogEntry -> Model -> Model
pushLog entries model =
    { model
        | saveChainLog =
            List.reverse entries
                ++ List.take
                    (Basics.max 0
                        (UiSaveChain.maxSaveChainLogEntries - List.length entries)
                    )
                    model.saveChainLog
    }


{-| Format the auto-roll note the roll-saves path attaches.
`Just "rolled 12 vs DC 15"` on entries built by
`savesRolled`, `Nothing` for entries built by the manual
Fail / Pass paths.
-}
rollNote : Int -> Int -> String
rollNote total dc =
    "rolled " ++ String.fromInt total ++ " vs DC " ++ String.fromInt dc
