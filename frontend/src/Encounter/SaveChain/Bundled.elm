module Encounter.SaveChain.Bundled exposing (defaults)

{-| Bundled Save Chain presets seeded into a fresh visitor's
`Model.saveChainPresets` on the very first boot.

Covers the four canonical outcome shapes the modal supports —
plus a set of complex spells whose in-game effect involves
multiple standard conditions (Hypnotic Pattern) or a bespoke
effect name that isn't a 5e condition at all (Banishment,
Slow, Confusion). These use the effect-list model: each
outcome can carry zero, one, or many named effects.

  - **Cantrip damage** — Sacred Flame, Poison Spray.
  - **AoE damage + half-on-success** — Burning Hands,
    Fireball, Cone of Cold. Uses `HalfFailDamage` on the
    success side.
  - **Single-condition control** — Blindness / Deafness,
    Hold Person, Web.
  - **Multi-condition control** — Hypnotic Pattern (Charmed
      - Incapacitated).
  - **Custom effect name** — Banishment ("Banished"), Slow
    ("Slowed"), Confusion ("Confused"), Suggestion, Fear
    ("Frightened" with a specific note about Dashing away).
    None of these map to a stock 5e condition; the modal's
    free-form effect input covers them cleanly.
  - **Damage + condition combo** — Phantasmal Killer (4d10
    psychic + Frightened).

Damage amounts are the canonical dice formulas from the spell
text (`8d6` for Fireball, `1d8` for Sacred Flame, etc.). The
modal parses each formula at apply time and rolls it once,
applying the shared total to every selected target (5e AoE
convention). GMs who prefer flat averages can edit the
loaded chain in place — a plain integer applies directly
with no roll.

Seeding fires from `Main.init` when the boot flag
`localSaveChainPresets` is `Nothing` — the same first-boot
discipline the condition and timer preset dicts use. Delete
a bundled preset and it stays gone once localStorage is
populated.

-}

import Compendium exposing (Ability(..))
import Dict exposing (Dict)
import Encounter
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
        , ( "Web (2nd)", web )
        , ( "Suggestion (2nd)", suggestion )
        , ( "Hold Person (2nd)", holdPerson )
        , ( "Fear (3rd)", fear )
        , ( "Hypnotic Pattern (3rd)", hypnoticPattern )
        , ( "Slow (3rd)", slow )
        , ( "Confusion (4th)", confusion )
        , ( "Banishment (4th)", banishment )
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



-- ── Single-condition control ────────────────────────────────────


blindnessDeafness : SaveChain
blindnessDeafness =
    { name = "Blindness / Deafness (2nd)"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Blinded" "" ]
    , onSuccess = noEffect
    }


holdPerson : SaveChain
holdPerson =
    { name = "Hold Person (2nd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Paralyzed" "" ]
    , onSuccess = noEffect
    }


web : SaveChain
web =
    { name = "Web (2nd)"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effect "Restrained" "Str to esc" ]
    , onSuccess = noEffect
    }



-- ── Multi-condition control ─────────────────────────────────────


{-| Hypnotic Pattern — Wisdom save; fail: Charmed +
Incapacitated + speed 0. Ends if the creature is damaged or
if an ally uses an action to shake it awake. Two conditions
apply as separate rows so the GM can end them independently
(damage clears them both anyway, but a targeted "wake up"
action might only clear one).
-}
hypnoticPattern : SaveChain
hypnoticPattern =
    { name = "Hypnotic Pattern (3rd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effect "Charmed" "Ends w/dmg"
            , effect "Incapacitated" "Speed 0"
            ]
    , onSuccess = noEffect
    }



-- ── Custom effect names ─────────────────────────────────────────


{-| Fear — WIS save; fail: Frightened plus a specific ongoing
mechanic (drop items, Dash away). Uses the standard
Frightened condition name so the card badge is legible; the
note carries the compulsion.
-}
fear : SaveChain
fear =
    { name = "Fear (3rd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Frightened" "Dash away"
            ]
    , onSuccess = noEffect
    }


{-| Slow — WIS save; fail: `-2 AC / -2 Dex saves`, half speed,
no reactions, only one action per turn, 50% chance any spell
with S/V/M is delayed by a turn. This isn't any single 5e
condition — the GM sees "Slowed" on the card and consults the
note.
-}
slow : SaveChain
slow =
    { name = "Slow (3rd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Slowed" "1/2 spd 1a"
            ]
    , onSuccess = noEffect
    }


{-| Confusion — WIS save; fail: roll a d10 each turn to
determine behaviour. Not a standard condition; the note is
the whole spell.
-}
confusion : SaveChain
confusion =
    { name = "Confusion (4th)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Confused" "Roll d10"
            ]
    , onSuccess = noEffect
    }


{-| Banishment — CHA save; fail: banished to home / demiplane.
Custom effect name so the card reads "Banished" rather than
Frightened / Charmed / etc.
-}
banishment : SaveChain
banishment =
    { name = "Banishment (4th)"
    , saveAbility = Cha
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Banished" "1 min max"
            ]
    , onSuccess = noEffect
    }


{-| Suggestion — WIS save; fail: pursue reasonable suggested
action up to 8 hours. Not a stock condition; the note carries
the spell text.
-}
suggestion : SaveChain
suggestion =
    { name = "Suggestion (2nd)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effect "Suggested" "Obey 8 hr"
            ]
    , onSuccess = noEffect
    }



-- ── Damage + condition combo ─────────────────────────────────────


{-| Phantasmal Killer — WIS save; fail: Frightened AND 4d10
psychic. Both HP and effect fields light up, proving the
combined shape.
-}
phantasmalKiller : SaveChain
phantasmalKiller =
    { name = "Phantasmal Killer (4th)"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "4d10" -- psychic
        , effects =
            [ effectSvEoT "Frightened" "Sv +dmg"
            ]
        }
    , onSuccess = noEffect
    }



-- ── Outcome helpers ──────────────────────────────────────────────


noEffect : SaveOutcome
noEffect =
    SaveChain.empty.onFail


damageOnly : HpEffect -> SaveOutcome
damageOnly hp =
    { hp = hp, effects = [] }


effectsOnly : List SaveChain.EffectApply -> SaveOutcome
effectsOnly es =
    { hp = NoHpEffect, effects = es }


effect : String -> String -> SaveChain.EffectApply
effect name note =
    { name = name, note = note, saveToEnd = Nothing }


{-| Convenience for effects whose applied condition should
inherit the chain's Save + DC as its save-to-end, auto-
rolling at end-of-turn. Used for the classic "save at end
of each turn to end" spells (Paralyzed from Hold Person,
Frightened from Fear, Slowed, Confused, Banished, etc.).
GMs who want manual rolls or beginning-of-turn timing can
toggle after loading the preset via the auto-roll radio
group in the modal.
-}
effectSvEoT : String -> String -> SaveChain.EffectApply
effectSvEoT name note =
    { name = name, note = note, saveToEnd = Just Encounter.AutoRollAtEnd }
