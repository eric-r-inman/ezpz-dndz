module Ui.SaveChain exposing
    ( SaveChainUi, OutcomeForm
    , fresh, fromChain, toChain
    , OutcomeSide(..)
    )

{-| Modal UI state for the Save Chain feature.

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
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)


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
    }


type alias OutcomeForm =
    { hpKind : HpEffect
    , hpAmountText : String
    , conditionName : String
    , conditionNote : String
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
    }


freshOutcome : OutcomeForm
freshOutcome =
    { hpKind = NoHpEffect
    , hpAmountText = ""
    , conditionName = ""
    , conditionNote = ""
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
    , conditionName = o.conditionName
    , conditionNote = o.conditionNote
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
    , conditionName = f.conditionName
    , conditionNote = f.conditionNote
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
