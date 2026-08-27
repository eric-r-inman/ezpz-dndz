module Ui.SaveChain exposing
    ( SaveChainUi, OutcomeForm
    , fresh, fromChain, toChain
    , OutcomeSide(..)
    , AppliedPart(..), SaveChainLogEntry, maxSaveChainLogEntries
    )

{-| Surface UI state for the Save Chain feature.

Mirrors `Encounter.SaveChain` closely but keeps the input
values as raw text (`dcText`, `hpAmountText`) so a
mid-typing dash or blank field doesn't get clobbered by
integer round-tripping — same trick the HP Change / Dice
modifier inputs use.

`OutcomeSide` is a tag the update handlers use to route a
form-field change to either the fail or success outcome
without doubling the Msg surface.

@docs SaveChainUi, OutcomeForm
@docs fresh, fromChain, toChain
@docs OutcomeSide

-}

import Compendium exposing (Ability(..))
import Encounter.SaveChain as SaveChain exposing (EffectApply, HpEffect(..), SaveChain, SaveOutcome)
import Msg exposing (SaveChainSide)


type alias SaveChainUi =
    { target : String
    , applyToSelected : Bool

    -- Editable form fields, projected back into a `SaveChain`
    -- via `toChain` at save-preset / apply time.
    , name : String
    , saveAbility : Ability
    , dcText : String
    , onFail : OutcomeForm
    , onSuccess : OutcomeForm

    -- Run-time DC override — used when the chain itself has
    -- `saveDc = Nothing` and the GM wants to enter a per-apply
    -- DC (typically because the DC comes from a monster's stat
    -- block, not the chain).  Not persisted onto the preset.
    , dcOverrideText : String

    -- Preset picker state.  `presetPickerSelection` is the raw
    -- <select> value the user has clicked; `loadedPresetName`
    -- is the name of the last preset actually loaded into the
    -- form (so "Delete" knows which entry to remove).
    , presetPickerSelection : String
    , loadedPresetName : Maybe String

    -- True once the current settings have been applied and not
    -- edited since.  Closing an applied editor resets it;
    -- closing an un-applied one stashes the settings as the
    -- draft the next open restores.
    , applied : Bool
    }


type alias OutcomeForm =
    { hpKind : HpEffect
    , hpAmountText : String
    , effects : List EffectApply
    }


type OutcomeSide
    = OnFail
    | OnSuccess


{-| Bare form pre-populated for a new chain targeted at
`target`. Kept in sync with `SaveChain.empty`.
-}
fresh : String -> SaveChainUi
fresh target =
    { target = target
    , applyToSelected = False
    , name = ""
    , saveAbility = Wis
    , dcText = ""
    , onFail = freshOutcome
    , onSuccess = freshOutcome
    , dcOverrideText = ""
    , presetPickerSelection = ""
    , loadedPresetName = Nothing
    , applied = False
    }


freshOutcome : OutcomeForm
freshOutcome =
    { hpKind = NoHpEffect
    , hpAmountText = ""
    , effects = []
    }


{-| Load a saved chain's fields into the form. Called by the
Load-preset handler; sets `loadedPresetName` so a subsequent
Delete knows what to remove.
-}
fromChain : SaveChainUi -> SaveChain -> SaveChainUi
fromChain baseline chain =
    { baseline
        | name = chain.name
        , saveAbility = chain.saveAbility
        , dcText =
            case chain.saveDc of
                Just n ->
                    String.fromInt n

                Nothing ->
                    ""
        , onFail = outcomeToForm chain.onFail
        , onSuccess = outcomeToForm chain.onSuccess
        , dcOverrideText = ""
        , loadedPresetName =
            if String.isEmpty chain.name then
                Nothing

            else
                Just chain.name
    }


outcomeToForm : SaveOutcome -> OutcomeForm
outcomeToForm o =
    { hpKind = o.hp
    , hpAmountText =
        case o.hp of
            DealDamage s ->
                s

            HealFor s ->
                s

            _ ->
                ""
    , effects = o.effects
    }


{-| Project the current form back into a `SaveChain`. Used
by both Save-Preset (to persist) and Apply (to run the
chain). Invalid numeric text falls back to `Nothing` for the
DC and `0` for damage amounts.
-}
toChain : SaveChainUi -> SaveChain
toChain ui =
    { name = String.trim ui.name
    , saveAbility = ui.saveAbility
    , saveDc = parseOptionalInt ui.dcText
    , onFail = formToOutcome ui.onFail
    , onSuccess = formToOutcome ui.onSuccess
    }


formToOutcome : OutcomeForm -> SaveOutcome
formToOutcome f =
    let
        raw =
            String.trim f.hpAmountText

        hp =
            case f.hpKind of
                NoHpEffect ->
                    NoHpEffect

                DealDamage _ ->
                    DealDamage raw

                HealFor _ ->
                    HealFor raw

                HalfFailDamage ->
                    HalfFailDamage
    in
    { hp = hp
    , effects =
        f.effects
            |> List.filter (\e -> not (String.isEmpty (String.trim e.name)))
    }


parseOptionalInt : String -> Maybe Int
parseOptionalInt raw =
    let
        trimmed =
            String.trim raw
    in
    if String.isEmpty trimmed then
        Nothing

    else
        String.toInt trimmed



-- ── Log entries ──────────────────────────────────────────────────


{-| One structured "thing applied" to a target as part of a
Save Chain resolution. Kept as a tagged union rather than a
pre-rendered string so the view can render each part with
its own colour — red for `DamagePart`, green for `HealPart`,
default text for `EffectPart` — without a stringly-typed
prefix / substring parse.
-}
type AppliedPart
    = DamagePart Int
    | HealPart Int
    | EffectPart String


{-| One row in the "recent applies" log shown at the bottom
of the Save Chain modal. Captures the target creature, which
side of the chain resolved (Fail / Pass), an optional roll
note (populated by the auto-roll path — `Just "rolled 12 vs
DC 15"`), and the structured list of things that were
applied — HP change + effect names. Empty `appliedParts`
renders as "(no effect)" in the view so the row still
communicates that the save was resolved.
-}
type alias SaveChainLogEntry =
    { target : String
    , side : SaveChainSide
    , rollNote : Maybe String
    , appliedParts : List AppliedPart
    }


{-| Cap on the log so it doesn't grow unbounded. New entries
are prepended; anything past this many rolls off the end.
-}
maxSaveChainLogEntries : Int
maxSaveChainLogEntries =
    15
