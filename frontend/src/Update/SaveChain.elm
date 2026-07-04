module Update.SaveChain exposing
    ( open, close
    , nameChanged, abilitySet, dcChanged, dcOverrideChanged
    , applyToSelectedToggle
    , outcomeHpKindSet, outcomeHpAmountChanged
    , outcomeEffectAdd, outcomeEffectRemove
    , outcomeEffectNameChanged, outcomeEffectNoteChanged
    , presetPickerChanged, presetLoad, presetSave, presetDelete, reset
    , applyFail, applyPass, applyRollLanded
    , rollSaves, savesRolled
    , exportBundled, outcomeEffectAutoRollSet, outcomeEffectSaveToEndToggle, restoreBundled
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

@docs open, close
@docs nameChanged, abilitySet, dcChanged, dcOverrideChanged
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
import Encounter.SaveChain.Export
import Model exposing (Modal(..), Model)
import Msg
    exposing
        ( Msg(..)
        , SaveChainHpKind(..)
        , SaveChainRollMode(..)
        , SaveChainSide(..)
        )
import Ports
import Random
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.SaveChain as UiSaveChain exposing (OutcomeForm, SaveChainUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast



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
                                                Just Encounter.AutoRollAtEnd
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
                            (\e -> { e | saveToEnd = Just mode })
                            o.effects
                }
            )
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
    -- Auto-load: picking a preset from the dropdown loads it
    -- immediately.  Also handles the placeholder "" option —
    -- that just resets the picker without touching the form.
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                pickedUi =
                    { ui | presetPickerSelection = name }
            in
            if String.isEmpty name then
                ( { model | modal = Just (ModalSaveChain pickedUi) }
                , Cmd.none
                )

            else
                case Dict.get name model.saveChainPresets of
                    Just chain ->
                        ( { model
                            | modal =
                                Just (ModalSaveChain (UiSaveChain.fromChain pickedUi chain))
                          }
                        , Cmd.none
                        )

                    Nothing ->
                        ( { model | modal = Just (ModalSaveChain pickedUi) }
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
                ( modelWithPreset, Cmd.none )

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
                , Cmd.none
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


{-| Overwrite every bundled-named preset in
`model.saveChainPresets` with its current bundled definition,
AND prune any stale entries left over from a previous naming
scheme. Non-bundled (user-authored) presets are untouched.

Persists to `localStorage.saveChainPresets` (or the server,
when authenticated) via `Main.elm`'s model-diff pass; if the
modal has a loaded preset that happens to be a bundled name,
re-loads its refreshed form so the checkbox / mode radio
state reflects the freshly-restored data.

Rationale: users who saved anything to the modal before a
wire-shape refactor (e.g. the pre-`save_to_end` era) have
stale bundled presets in their localStorage that predate the
newer fields; loading Hold Person then shows Save-to-end
unchecked even though the current bundled definition has it
on. Additionally, since the earlier "strip level suffix"
pass, users see BOTH the pre-rename entry ("Hold Person
(2nd)") and the fresh one ("Hold Person") in the picker as
duplicates. Pruning removes the old-suffix entries so the
picker settles down to one entry per spell.

The prune predicate is deliberately conservative — a key is
only removed if it matches "<base> (<level suffix>)" AND
`base` currently exists in `defaults`. A user preset named
"My Hold Person" or a legitimate free-form preset with a
parenthesised note is left alone.

-}
restoreBundled : Model -> ( Model, Cmd Msg )
restoreBundled model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                bundled =
                    Encounter.SaveChain.Bundled.defaults

                withRestored =
                    Dict.foldl Dict.insert model.saveChainPresets bundled

                next =
                    withRestored
                        |> Dict.filter (\k _ -> not (isRetiredBundledKey bundled k))

                refreshedModal =
                    case ui.loadedPresetName of
                        Just name ->
                            case Dict.get name bundled of
                                Just chain ->
                                    Just (ModalSaveChain (UiSaveChain.fromChain ui chain))

                                Nothing ->
                                    Just (ModalSaveChain ui)

                        Nothing ->
                            Just (ModalSaveChain ui)
            in
            ( { model | saveChainPresets = next, modal = refreshedModal }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


{-| True iff `key` has the shape "<base> (<level suffix>)"
where `base` is a current bundled key. This matches the
pre-rename bundled names ("Hold Person (2nd)", "Fireball
(3rd)", "Sacred Flame (cantrip)", …) so `restoreBundled` can
prune them without a hand-maintained migration list.
-}
isRetiredBundledKey : Dict.Dict String SaveChain -> String -> Bool
isRetiredBundledKey bundled key =
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


{-| Copy the currently-open Save Chain form to the clipboard as
an Elm source snippet ready to paste into
`Encounter.SaveChain.Bundled.elm`. Used to promote a
user-authored preset into a bundled default without hand-
translating the wire JSON.

The snippet includes a header comment (where to paste + to
extend `defaults`). A short "Copied…" toast confirms the
port fired — the OS clipboard has no observable state we can
verify from Elm, so this is the only feedback the GM sees.

-}
exportBundled : Model -> ( Model, Cmd Msg )
exportBundled model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            let
                snippet =
                    Encounter.SaveChain.Export.asElm (UiSaveChain.toChain ui)
            in
            Update.Toast.push ToastSuccess
                "Copied Elm snippet to clipboard — paste into Bundled.elm."
                model
                |> Tuple.mapSecond
                    (\cmd -> Cmd.batch [ cmd, Ports.copyToClipboard snippet ])

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

                effectCtx =
                    buildEffectContext chain model

                -- Effect list applies always fire (no dice needed).
                withConditions =
                    List.foldl
                        (\name enc ->
                            SaveChain.applyEffects effectCtx outcome name enc
                        )
                        model.encounter
                        targets

                modelAfterCond =
                    { model | encounter = withConditions }
            in
            case rawTextForResolve side chain of
                RawEmpty ->
                    let
                        entries =
                            List.map
                                (\name ->
                                    { target = name
                                    , side = side
                                    , rollNote = Nothing
                                    , appliedParts = appliedParts outcome 0
                                    }
                                )
                                targets
                    in
                    ( pushLog entries modelAfterCond, Cmd.none )

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
                    ( pushLog entries { modelAfterCond | encounter = nextEnc }, Cmd.none )

                RawDice expr ->
                    -- Log entries are pushed after the roll lands
                    -- (see `applyRollLanded`) so the amount reflects
                    -- the actual dice total, not the mid-flight zero.
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
                    let
                        entries =
                            List.map
                                (\name ->
                                    { target = name
                                    , side = side
                                    , rollNote = Nothing
                                    , appliedParts = appliedParts outcome 0
                                    }
                                )
                                targets
                    in
                    ( pushLog entries modelAfterCond, Cmd.none )

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
            ( pushLog entries { logged | encounter = nextEnc }
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
overridden) — the modal disables the buttons visually in that
case; this guard is defence in depth.

-}
rollSaves : SaveChainRollMode -> Model -> ( Model, Cmd Msg )
rollSaves mode model =
    case model.modal of
        Just (ModalSaveChain ui) ->
            case resolveDc ui of
                Nothing ->
                    ( model, Cmd.none )

                Just _ ->
                    let
                        specs =
                            buildSaveSpecs mode ui model
                    in
                    if List.isEmpty specs then
                        ( model, Cmd.none )

                    else
                        ( model, Dice.batchRollCmd SaveChainSavesRolled specs )

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
            resolveTargets ui model.encounter

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
    case model.modal of
        Just (ModalSaveChain ui) ->
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
                            case chain.onFail.hp of
                                DealDamage s ->
                                    parseIntOrAverage s

                                _ ->
                                    0

                        successResolvedAmount =
                            case ( chain.onSuccess.hp, chain.onFail.hp ) of
                                ( HalfFailDamage, _ ) ->
                                    SaveChain.halfFailDamage failResolvedAmount

                                ( DealDamage s, _ ) ->
                                    parseIntOrAverage s

                                ( HealFor s, _ ) ->
                                    parseIntOrAverage s

                                _ ->
                                    0

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
                    ( pushLog entries { modelWithHistory | encounter = encAfterAll }
                    , Cmd.batch historyCmds
                    )

        _ ->
            ( model, Cmd.none )



-- ── HELPERS ─────────────────────────────────────────────────────


{-| Pick the DC to use: chain's fixed DC wins, else the run-time
override the modal renders when the chain's DC is blank.
Returns `Nothing` when neither is available — the button is
disabled in that state, but the guard is here too.
-}
resolveDc : UiSaveChain.SaveChainUi -> Maybe Int
resolveDc ui =
    let
        chain =
            UiSaveChain.toChain ui
    in
    case chain.saveDc of
        Just n ->
            Just n

        Nothing ->
            String.toInt (String.trim ui.dcOverrideText)


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
