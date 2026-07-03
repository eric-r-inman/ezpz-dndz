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
        [ ( "Acid Splash", acidSplash )
        , ( "Poison Spray", poisonSpray )
        , ( "Sacred Flame", sacredFlame )
        , ( "Toll the Dead", tollTheDead )
        , ( "Bane", bane )
        , ( "Burning Hands", burningHands )
        , ( "Command", command )
        , ( "Thunderwave", thunderwave )
        , ( "Blindness / Deafness", blindnessDeafness )
        , ( "Hold Person", holdPerson )
        , ( "Shatter", shatter )
        , ( "Suggestion", suggestion )
        , ( "Web", web )
        , ( "Fear", fear )
        , ( "Fireball", fireball )
        , ( "Hypnotic Pattern", hypnoticPattern )
        , ( "Lightning Bolt", lightningBolt )
        , ( "Slow", slow )
        , ( "Stinking Cloud", stinkingCloud )
        , ( "Banishment", banishment )
        , ( "Blight", blight )
        , ( "Confusion", confusion )
        , ( "Ice Storm", iceStorm )
        , ( "Phantasmal Killer", phantasmalKiller )
        , ( "Cloudkill", cloudkill )
        , ( "Cone of Cold", coneOfCold )
        , ( "Flame Strike", flameStrike )
        , ( "Hold Monster", holdMonster )
        , ( "Chain Lightning", chainLightning )
        , ( "Disintegrate", disintegrate )
        , ( "Harm", harm )
        , ( "Sunbeam", sunbeam )
        , ( "Finger of Death", fingerOfDeath )
        , ( "Feeblemind", feeblemind )
        , ( "Meteor Swarm", meteorSwarm )
        , ( "Weird", weird )
        ]



-- ── Cantrip damage ───────────────────────────────────────────────


sacredFlame : SaveChain
sacredFlame =
    { name = "Sacred Flame"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d8") -- radiant
    , onSuccess = noEffect
    }


poisonSpray : SaveChain
poisonSpray =
    { name = "Poison Spray"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d12") -- poison
    , onSuccess = noEffect
    }



-- ── AoE damage with half-on-success ──────────────────────────────


burningHands : SaveChain
burningHands =
    { name = "Burning Hands"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d6") -- fire
    , onSuccess = damageOnly HalfFailDamage
    }


fireball : SaveChain
fireball =
    { name = "Fireball"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d6") -- fire
    , onSuccess = damageOnly HalfFailDamage
    }


coneOfCold : SaveChain
coneOfCold =
    { name = "Cone of Cold"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d8") -- cold
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Single-condition control ────────────────────────────────────


blindnessDeafness : SaveChain
blindnessDeafness =
    { name = "Blindness / Deafness"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Blinded" "" ]
    , onSuccess = noEffect
    }


holdPerson : SaveChain
holdPerson =
    { name = "Hold Person"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Paralyzed" "" ]
    , onSuccess = noEffect
    }


web : SaveChain
web =
    { name = "Web"
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
    { name = "Hypnotic Pattern"
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
    { name = "Fear"
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
    { name = "Slow"
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
    { name = "Confusion"
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
    { name = "Banishment"
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
    { name = "Suggestion"
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
    { name = "Phantasmal Killer"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "4d10" -- psychic
        , effects =
            [ effectSvEoT "Frightened" "+4d10 psy"
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


{-| Twin of `effectSvEoT` for spells whose save fires at the
**start** of the bearer's turn — Stinking Cloud's retching
save, Cloudkill's per-turn Con save while inside, etc. The
GM can still flip the mode after loading via the radio group.
-}
effectSvBoT : String -> String -> SaveChain.EffectApply
effectSvBoT name note =
    { name = name, note = note, saveToEnd = Just Encounter.AutoRollAtBegin }



-- ── Additional cantrips ─────────────────────────────────────────


tollTheDead : SaveChain
tollTheDead =
    { name = "Toll the Dead"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d8") -- necrotic; 1d12 if wounded
    , onSuccess = noEffect
    }


acidSplash : SaveChain
acidSplash =
    { name = "Acid Splash"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d6") -- acid
    , onSuccess = noEffect
    }



-- ── Level 1 additions ───────────────────────────────────────────


{-| Bane — CHA save; fail: -1d4 penalty to every attack roll
and every saving throw for the concentration duration. No
re-save; the caster ends it by dropping concentration.
-}
bane : SaveChain
bane =
    { name = "Bane"
    , saveAbility = Cha
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Baned" "-1d4 rolls" ]
    , onSuccess = noEffect
    }


{-| Command — WIS save; fail: the target obeys a one-word
command on its next turn. Duration is exactly one turn, so
no save-to-end — the GM removes the condition after the
target acts.
-}
command : SaveChain
command =
    { name = "Command"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Commanded" "1 turn" ]
    , onSuccess = noEffect
    }


{-| Thunderwave — CON save; fail: 2d8 thunder + pushed 10 ft
away from caster. Half damage on success. Push is a one-
time repositioning; not modeled as a persistent condition.
-}
thunderwave : SaveChain
thunderwave =
    { name = "Thunderwave"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "2d8") -- thunder + push 10ft
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 2 additions ───────────────────────────────────────────


{-| Shatter — CON save; fail: 3d8 thunder, half on success.
Constructs and objects have disadv on the save; the modal
doesn't discriminate — the GM applies with disadvantage in
mind by rolling saves manually if needed.
-}
shatter : SaveChain
shatter =
    { name = "Shatter"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d8") -- thunder
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 3 additions ───────────────────────────────────────────


lightningBolt : SaveChain
lightningBolt =
    { name = "Lightning Bolt"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d6") -- lightning
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Stinking Cloud — CON save at the **start** of the bearer's
turn while inside the cloud; on fail the creature spends its
action retching. Uses `effectSvBoT` so the save auto-fires
at begin-of-turn. GM manually removes the condition if the
creature leaves the cloud.
-}
stinkingCloud : SaveChain
stinkingCloud =
    { name = "Stinking Cloud"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvBoT "Retching" "wastes act" ]
    , onSuccess = noEffect
    }



-- ── Level 4 additions ───────────────────────────────────────────


blight : SaveChain
blight =
    { name = "Blight"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d8") -- necrotic
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Ice Storm — DEX save; fail: 2d8 bludgeoning + 4d6 cold,
half on success. Compound formula sums both damage types;
the GM narrates the split. Area becomes difficult terrain
until the end of the caster's next turn — a one-off note
attached to the caster, not a persistent condition on
targets.
-}
iceStorm : SaveChain
iceStorm =
    { name = "Ice Storm"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "2d8+4d6") -- bludg + cold
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 5 additions ───────────────────────────────────────────


{-| Cloudkill — CON save when a creature starts its turn in
the cloud; fail: 5d8 poison, half on success. Uses
`effectSvBoT` on a "Poisoned by cloud" tracker so the modal
auto-rerolls at begin-of-turn while the target stays inside;
GM removes the tracker when the creature exits.
-}
cloudkill : SaveChain
cloudkill =
    { name = "Cloudkill"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "5d8") -- poison
    , onSuccess = damageOnly HalfFailDamage
    }


holdMonster : SaveChain
holdMonster =
    { name = "Hold Monster"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Paralyzed" "" ]
    , onSuccess = noEffect
    }


flameStrike : SaveChain
flameStrike =
    { name = "Flame Strike"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "4d6+4d6") -- fire + radiant
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 6 additions ───────────────────────────────────────────


chainLightning : SaveChain
chainLightning =
    { name = "Chain Lightning"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "10d8") -- lightning
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Disintegrate — DEX save; fail: 10d6 + 40 force. If the
damage brings the target to 0 HP, they're disintegrated to
dust. No half-damage on success — the target takes zero if
they save.
-}
disintegrate : SaveChain
disintegrate =
    { name = "Disintegrate"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "10d6+40") -- force; 0→dust
    , onSuccess = noEffect
    }


{-| Harm — CON save; fail: 14d6 necrotic, half on success.
Also reduces max HP for 1 hour on a failed save; the note
reminds the GM to track that separately via the inline max-
HP edit on the card.
-}
harm : SaveChain
harm =
    { name = "Harm"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "14d6") -- necrotic; max HP debuff
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Sunbeam — CON save; fail: 6d8 radiant + Blinded until end
of caster's next turn. Half damage + no blind on success.
Blinded gets save-to-end so it auto-clears next turn, matching
the short-duration blindness.
-}
sunbeam : SaveChain
sunbeam =
    { name = "Sunbeam"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "6d8" -- radiant
        , effects = [ effectSvEoT "Blinded" "1 turn" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 7 additions ───────────────────────────────────────────


{-| Finger of Death — CON save; fail: 7d8 + 30 necrotic, half
on success. Note reminds the GM that a killed humanoid
rises as an under-control zombie at the start of the caster's
next turn — no condition applied to the target here, since
they'd already be at 0 HP.
-}
fingerOfDeath : SaveChain
fingerOfDeath =
    { name = "Finger of Death"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "7d8+30") -- necrotic; hmn→zombie
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 8 additions ───────────────────────────────────────────


{-| Feeblemind — INT save; fail: 4d6 psychic + INT/CHA drop
to 1, target can't cast spells or understand language. Half
damage + no mind effect on success. Duration is indefinite
with a 30-day re-save — far too long for the standard save-
to-end, so left off; GM removes manually or with Greater
Restoration / Wish.
-}
feeblemind : SaveChain
feeblemind =
    { name = "Feeblemind"
    , saveAbility = Int_
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "4d6" -- psychic
        , effects = [ effect "Feebleminded" "no cast" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 9 additions ───────────────────────────────────────────


meteorSwarm : SaveChain
meteorSwarm =
    { name = "Meteor Swarm"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "20d6+20d6") -- fire + bludg
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Weird — WIS save; fail: Frightened for the duration. On
each successive end-of-turn save the target either ends the
spell (save success) or takes another 4d10 psychic (save
fail). Note reminds the GM to apply the recurring damage on
each failed save — the modal auto-clears Frightened on
success but doesn't auto-deal damage.
-}
weird : SaveChain
weird =
    { name = "Weird"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Frightened" "+4d10 psy" ]
    , onSuccess = noEffect
    }
