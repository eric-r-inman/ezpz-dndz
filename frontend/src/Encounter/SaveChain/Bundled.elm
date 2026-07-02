module Encounter.SaveChain.Bundled exposing (defaults)

{-| Bundled Save Chain presets seeded into a fresh visitor's
`Model.saveChainPresets` on the very first boot.

Picked to cover the four common chain shapes the GM will
build on their own within a session or two:

  - **Cantrip damage** (Sacred Flame, Poison Spray) — single
    save, small damage on fail, nothing on success.
  - **AoE damage with half-on-success** (Burning Hands,
    Fireball, Cone of Cold) — showcases the `HalfFailDamage`
    success option so a GM sees the pattern once and can
    replicate it for any other save-for-half spell.
  - **Condition control** (Blindness/Deafness, Hold Person,
    Fear, Web) — no HP change, just apply a standard 5e
    condition. Duration is left as `DurationManual` on the
    applied condition so the GM can attach a save-to-end
    after the fact if the spell needs one (Hold Person &
    Fear both do — the modal for editing the condition
    handles that end).
  - **Damage + condition combo** (Phantasmal Killer) — the
    only preset that lights up both outcome fields on fail,
    proving the composition works.

Damage amounts are the canonical dice formulas from the
spell text (`8d6` for Fireball, `1d8` for Sacred Flame,
etc.). The modal parses each formula at apply time and
rolls it once, applying the shared total to every selected
target (5e AoE convention). GMs who prefer flat averages
can edit the loaded chain in place — a plain integer
applies directly with no roll.

Seeding fires from `Main.init` when the
`localSaveChainPresets` boot flag is `Nothing` — the same
first-boot discipline the condition and timer preset dicts
use. Once any change writes to `localStorage.saveChainPresets`,
the flag is `Just _` on subsequent boots and the persisted
dict wins wholesale. Delete a bundled preset and it stays
gone.

-}

import Compendium exposing (Ability(..))
import Dict exposing (Dict)
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)


defaults : Dict String SaveChain
defaults =
    Dict.fromList
        [ ( "Sacred Flame (cantrip)", sacredFlame )
        , ( "Poison Spray (cantrip)", poisonSpray )
        , ( "Burning Hands (1st)", burningHands )
        , ( "Fireball (3rd)", fireball )
        , ( "Cone of Cold (5th)", coneOfCold )
        , ( "Blindness / Deafness (2nd)", blindnessDeafness )
        , ( "Hold Person (2nd)", holdPerson )
        , ( "Fear (3rd)", fear )
        , ( "Web (2nd)", web )
        , ( "Phantasmal Killer (4th)", phantasmalKiller )
        ]



-- ── Cantrip damage ───────────────────────────────────────────────


sacredFlame : SaveChain
sacredFlame =
    { name = "Sacred Flame (cantrip)"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d8") -- radiant
    , onSuccess = noEffect
    }


poisonSpray : SaveChain
poisonSpray =
    { name = "Poison Spray (cantrip)"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d12") -- poison
    , onSuccess = noEffect
    }



-- ── AoE damage with half-on-success ──────────────────────────────


burningHands : SaveChain
burningHands =
    { name = "Burning Hands (1st)"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d6") -- fire
    , onSuccess = damageOnly HalfFailDamage
    }


fireball : SaveChain
fireball =
    { name = "Fireball (3rd)"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d6") -- fire
    , onSuccess = damageOnly HalfFailDamage
    }


coneOfCold : SaveChain
coneOfCold =
    { name = "Cone of Cold (5th)"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d8") -- cold
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Condition control ───────────────────────────────────────────


blindnessDeafness : SaveChain
blindnessDeafness =
    { name = "Blindness / Deafness (2nd)"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = conditionOnly "Blinded" ""
    , onSuccess = noEffect
    }


holdPerson : SaveChain
holdPerson =
    { name = "Hold Person (2nd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        conditionOnly "Paralyzed" "Save at end of each turn to end"
    , onSuccess = noEffect
    }


fear : SaveChain
fear =
    { name = "Fear (3rd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        conditionOnly "Frightened" "Must Dash away; save at end of turn when caster out of sight"
    , onSuccess = noEffect
    }


web : SaveChain
web =
    { name = "Web (2nd)"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail =
        conditionOnly "Restrained" "STR check as action to escape"
    , onSuccess = noEffect
    }



-- ── Damage + condition combo ─────────────────────────────────────


phantasmalKiller : SaveChain
phantasmalKiller =
    { name = "Phantasmal Killer (4th)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "4d10" -- psychic
        , conditionName = "Frightened"
        , conditionNote = "Save at end of turn; on fail, take 4d10 psychic again; on success, spell ends"
        }
    , onSuccess = noEffect
    }



-- ── Outcome helpers ──────────────────────────────────────────────


noEffect : SaveOutcome
noEffect =
    SaveChain.empty.onFail


damageOnly : HpEffect -> SaveOutcome
damageOnly hp =
    { hp = hp
    , conditionName = ""
    , conditionNote = ""
    }


conditionOnly : String -> String -> SaveOutcome
conditionOnly name note =
    { hp = NoHpEffect
    , conditionName = name
    , conditionNote = note
    }
