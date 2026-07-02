module Encounter.SaveChain exposing
    ( SaveChain, SaveOutcome, HpEffect(..)
    , empty, isEffectivelyEmpty
    , applyOutcome, halfFailDamage
    )

{-| Save Chain: a reusable "creature makes a save; something
happens" bundle the GM can create once and re-apply through the
combat.

The domain type is intentionally small — it's the recipe, not
the resolution mechanism. A `SaveChain` names a save ability
(the target rolls this), an optional DC (the GM either fixes
the DC in the preset or enters it at apply-time), and two
outcomes (`onFail` / `onSuccess`). Each outcome may deal
damage, heal, or apply a condition — any combination, including
none-at-all which just marks a "the save happened but nothing
came of it" beat.

The `HpEffect.HalfFailDamage` variant is a run-time computation
hint: on the success side, the GM often wants "half of what the
fail would have dealt". `applyOutcome` resolves it against the
fail amount at apply time so the preset stays a static recipe.

@docs SaveChain, SaveOutcome, HpEffect
@docs empty, isEffectivelyEmpty
@docs applyOutcome, halfFailDamage

-}

import Compendium exposing (Ability(..))
import Encounter exposing (Creature)
import HpChange


{-| A saved chain the GM can pick from a dropdown. `name` is
`""` on a fresh new chain — the GM must fill it in to save the
recipe, but they can still apply an unnamed chain one-shot.
`saveDc` is `Nothing` for chains authored without a fixed DC;
the modal prompts for the DC at apply-time in that case.
-}
type alias SaveChain =
    { name : String
    , saveAbility : Ability
    , saveDc : Maybe Int
    , onFail : SaveOutcome
    , onSuccess : SaveOutcome
    }


{-| One side of the chain: what happens on a failed (or
successful) save. Both fields are independent — a spell can
deal damage AND apply a condition (Phantasmal Killer), or just
one, or neither.
-}
type alias SaveOutcome =
    { hp : HpEffect

    -- `""` means no condition applied.  Non-empty is the
    -- condition name (matched against the standard 5e list in
    -- the view, or free-form).  `conditionNote` is optional
    -- flavour text carried onto the applied condition.
    , conditionName : String
    , conditionNote : String
    }


{-| HP side of an outcome. `NoHpEffect` is the default — most
condition-apply chains don't touch HP at all.

`HalfFailDamage` is a success-side sentinel: the GM sets it on
the success outcome when the spell reads "half damage on
success"; `applyOutcome` computes the actual amount from the
fail's amount at apply time.

-}
type HpEffect
    = NoHpEffect
    | DealDamage Int
    | HealFor Int
    | HalfFailDamage


{-| Bare chain used as the modal's starting point when the GM
hits "+ New". Wisdom is the most-common save ability across
the spell list; picking it as the default saves a click on the
common case.
-}
empty : SaveChain
empty =
    { name = ""
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = emptyOutcome
    , onSuccess = emptyOutcome
    }


emptyOutcome : SaveOutcome
emptyOutcome =
    { hp = NoHpEffect
    , conditionName = ""
    , conditionNote = ""
    }


{-| True iff a chain has no effects on either side. Used by
the modal to grey out the Apply buttons — clicking a chain
that literally does nothing is almost always a mistake.
-}
isEffectivelyEmpty : SaveChain -> Bool
isEffectivelyEmpty chain =
    isOutcomeEmpty chain.onFail && isOutcomeEmpty chain.onSuccess


isOutcomeEmpty : SaveOutcome -> Bool
isOutcomeEmpty o =
    o.hp == NoHpEffect && String.isEmpty (String.trim o.conditionName)


{-| Apply an outcome to a creature. Composes the HP change
(via the shared `HpChange` engine so bloodied recomputation +
death-save clearing behave identically to the Manage HP modal)
with the condition apply.

`applyOutcome fail failAmount outcome creature` — for the
success side, pass the fail amount so `HalfFailDamage` can
compute correctly. For the fail side, `HalfFailDamage` is
inapplicable (falls through as no-op).

-}
applyOutcome :
    { failAmount : Int }
    -> SaveOutcome
    -> Encounter.Encounter
    -> String
    -> Encounter.Encounter
applyOutcome ctx outcome enc target =
    enc
        |> applyHp ctx outcome target
        |> applyCondition outcome target


applyHp : { failAmount : Int } -> SaveOutcome -> String -> Encounter.Encounter -> Encounter.Encounter
applyHp { failAmount } outcome target enc =
    case outcome.hp of
        NoHpEffect ->
            enc

        DealDamage n ->
            Encounter.mapCreature target
                (HpChange.apply (HpChange.Damage { amount = n, ignoreTemp = False }))
                enc

        HealFor n ->
            Encounter.mapCreature target
                (HpChange.apply (HpChange.Heal n))
                enc

        HalfFailDamage ->
            Encounter.mapCreature target
                (HpChange.apply
                    (HpChange.Damage
                        { amount = halfFailDamage failAmount
                        , ignoreTemp = False
                        }
                    )
                )
                enc


{-| Compute "half fail damage, rounded down" the same way 5e
does for save-for-half spells.
-}
halfFailDamage : Int -> Int
halfFailDamage n =
    Basics.max 0 (n // 2)


applyCondition : SaveOutcome -> String -> Encounter.Encounter -> Encounter.Encounter
applyCondition outcome target enc =
    let
        trimmedName =
            String.trim outcome.conditionName
    in
    if String.isEmpty trimmedName then
        enc

    else
        Encounter.addCondition target
            { name = trimmedName
            , note = String.trim outcome.conditionNote
            , duration = Encounter.DurationManual
            , saveToEnd = Nothing
            }
            enc
