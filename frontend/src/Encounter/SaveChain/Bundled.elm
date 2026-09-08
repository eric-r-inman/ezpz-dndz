module Encounter.SaveChain.Bundled exposing (defaults, retiredNames)

{-| Bundled Save Chain presets, seeded into a fresh visitor's
`Model.saveChainPresets` on the very first boot and laid over a
stored copy by the editor's "Restore bundled" button.

Each preset transcribes one saving-throw effect from the 2024
rules — SRD 5.2.1 where the effect is in it — as far as the
editor can express it: the save ability, a DC when the source
fixes one (a monster's ability does; a spell's comes from the
caster), and what each side of the save does. Where the rules
ask for something the editor has no setting for, such as a
duration that ends on someone's turn or a second failure that
escalates, the effect's note carries the reminder, and
`docs/SAVE_CHAIN_PRESETS.org` records the gap.

Damage amounts are the dice formulas from the source text. The
editor parses each at apply time and rolls it once, applying
the shared total to every target; a GM who prefers flat
averages can overwrite the loaded amount with an integer.

Seeding fires from `Main.init` when the boot flag
`localSaveChainPresets` is `Nothing` — the same first-boot
discipline the condition and timer preset dicts use. Delete a
bundled preset and it stays gone until the GM restores.

-}

import Compendium exposing (Ability(..))
import Dict exposing (Dict)
import Encounter
import Encounter.SaveChain as SaveChain exposing (HpEffect(..), SaveChain, SaveOutcome)


defaults : Dict String SaveChain
defaults =
    Dict.fromList
        [ ( "Acid Splash", acidSplash )
        , ( "Sacred Flame", sacredFlame )
        , ( "Toll the Dead", tollTheDead )
        , ( "Bane", bane )
        , ( "Burning Hands", burningHands )
        , ( "Command", command )
        , ( "Hideous Laughter", hideousLaughter )
        , ( "Sleep", sleep )
        , ( "Thunderwave", thunderwave )
        , ( "Blindness / Deafness", blindnessDeafness )
        , ( "Hold Person", holdPerson )
        , ( "Ray of Enfeeblement", rayOfEnfeeblement )
        , ( "Shatter", shatter )
        , ( "Suggestion", suggestion )
        , ( "Web", web )
        , ( "Fear", fear )
        , ( "Fireball", fireball )
        , ( "Hypnotic Pattern", hypnoticPattern )
        , ( "Lightning Bolt", lightningBolt )
        , ( "Slow", slow )
        , ( "Spirit Guardians", spiritGuardians )
        , ( "Stinking Cloud", stinkingCloud )
        , ( "Banishment", banishment )
        , ( "Blight", blight )
        , ( "Confusion", confusion )
        , ( "Ice Storm", iceStorm )
        , ( "Phantasmal Killer", phantasmalKiller )
        , ( "Cloudkill", cloudkill )
        , ( "Cone of Cold", coneOfCold )
        , ( "Dominate Person", dominatePerson )
        , ( "Flame Strike", flameStrike )
        , ( "Hold Monster", holdMonster )
        , ( "Chain Lightning", chainLightning )
        , ( "Disintegrate", disintegrate )
        , ( "Harm", harm )
        , ( "Sunbeam", sunbeam )
        , ( "Finger of Death", fingerOfDeath )
        , ( "Befuddlement", befuddlement )
        , ( "Meteor Swarm", meteorSwarm )
        , ( "Weird", weird )
        , ( "Ghoul Claw", ghoulClaw )
        , ( "Ghast Stench", ghastStench )
        , ( "Harpy Luring Song", harpyLuringSong )
        , ( "Mummy Dreadful Glare", mummyDreadfulGlare )
        , ( "Medusa Petrifying Gaze", medusaPetrifyingGaze )
        ]


{-| Bundled names no longer shipped, which a restore drops from a
stored copy so the picker doesn't offer both an old entry and
its replacement.
-}
retiredNames : List String
retiredNames =
    [ -- The 2024 rules rename it Befuddlement.
      "Feeblemind"

    -- The 2024 rules make it a spell attack, so it is not a save.
    , "Poison Spray"
    ]



-- ── Cantrips ────────────────────────────────────────────────────


acidSplash : SaveChain
acidSplash =
    { name = "Acid Splash"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d6")
    , onSuccess = noEffect
    }


sacredFlame : SaveChain
sacredFlame =
    { name = "Sacred Flame"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d8")
    , onSuccess = noEffect
    }


{-| The damage is 1d12 rather than 1d8 when the target is missing
any hit points; the GM overwrites the amount before applying in
that case.
-}
tollTheDead : SaveChain
tollTheDead =
    { name = "Toll the Dead"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "1d8")
    , onSuccess = noEffect
    }



-- ── Level 1 ─────────────────────────────────────────────────────


{-| No repeat save: the penalty lasts until the caster's
concentration ends.
-}
bane : SaveChain
bane =
    { name = "Bane"
    , saveAbility = Cha
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Baned" "−1d4 attacks & saves" ]
    , onSuccess = noEffect
    }


burningHands : SaveChain
burningHands =
    { name = "Burning Hands"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d6")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The target obeys on its next turn only, so the GM removes the
condition once it has acted.
-}
command : SaveChain
command =
    { name = "Command"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Commanded" "next turn only" ]
    , onSuccess = noEffect
    }


{-| Prone carries no save of its own: when the laughter ends the
target is still on the ground until it stands, which is what
the rules say. The repeat save also fires whenever the target
takes damage, with advantage — the GM rolls that one from the
chip.
-}
hideousLaughter : SaveChain
hideousLaughter =
    { name = "Hideous Laughter"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effectSvEoT "Incapacitated" "laughing; re-save on dmg (adv)"
            , effect "Prone" "can't stand while laughing"
            ]
    , onSuccess = noEffect
    }


{-| A second failed save turns the Incapacitated target
Unconscious for the rest of the duration; the editor can end a
condition on a save but not escalate it, so the note carries
that step.
-}
sleep : SaveChain
sleep =
    { name = "Sleep"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Incapacitated" "Sleep; 2nd fail → Unconscious" ]
    , onSuccess = noEffect
    }


{-| The 10-foot push on a failed save is repositioning, not a
condition, and stays with the GM.
-}
thunderwave : SaveChain
thunderwave =
    { name = "Thunderwave"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "2d8")
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 2 ─────────────────────────────────────────────────────


{-| The caster picks Blinded or Deafened; the GM renames the
effect before applying when it's the latter.
-}
blindnessDeafness : SaveChain
blindnessDeafness =
    { name = "Blindness / Deafness"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Blinded" "or Deafened" ]
    , onSuccess = noEffect
    }


holdPerson : SaveChain
holdPerson =
    { name = "Hold Person"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Paralyzed" "" ]
    , onSuccess = noEffect
    }


{-| Both sides do something: a failed save enfeebles until the
target saves at the end of a turn, while a successful one still
costs it disadvantage on its next attack roll.
-}
rayOfEnfeeblement : SaveChain
rayOfEnfeeblement =
    { name = "Ray of Enfeeblement"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Enfeebled" "disadv STR tests; −1d8 dmg" ]
    , onSuccess = effectsOnly [ effect "Disadv next attack" "until caster's next turn" ]
    }


{-| Constructs have disadvantage on the save; the Roll Disadv.
button covers that when the targets are all constructs.
-}
shatter : SaveChain
shatter =
    { name = "Shatter"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d8")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The 2024 text makes the target Charmed for the duration, so
the standard condition carries the spell in its note; it ends
early if the caster or an ally damages the target.
-}
suggestion : SaveChain
suggestion =
    { name = "Suggestion"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Charmed" "Suggestion; up to 8 hr" ]
    , onSuccess = noEffect
    }


{-| Escaping is a Strength (Athletics) check against the spell
DC, not a save, so the effect has no Save-to-end.
-}
web : SaveChain
web =
    { name = "Web"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Restrained" "Athletics chk vs DC to escape" ]
    , onSuccess = noEffect
    }



-- ── Level 3 ─────────────────────────────────────────────────────


{-| The repeat save only happens when the target ends its turn
without line of sight to the caster. End-of-turn auto-roll is
the nearest timing; the GM skips a roll the target hasn't
earned.
-}
fear : SaveChain
fear =
    { name = "Fear"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Frightened" "drop items, Dash away; save if no LoS" ]
    , onSuccess = noEffect
    }


fireball : SaveChain
fireball =
    { name = "Fireball"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d6")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Charmed, and Incapacitated with a Speed of 0 while Charmed.
Neither has a repeat save: damage or an ally's action ends the
spell. Two rows so the card shows both conditions.
-}
hypnoticPattern : SaveChain
hypnoticPattern =
    { name = "Hypnotic Pattern"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        effectsOnly
            [ effect "Charmed" "ends on dmg or shake"
            , effect "Incapacitated" "Speed 0"
            ]
    , onSuccess = noEffect
    }


lightningBolt : SaveChain
lightningBolt =
    { name = "Lightning Bolt"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d6")
    , onSuccess = damageOnly HalfFailDamage
    }


slow : SaveChain
slow =
    { name = "Slow"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Slowed" "½ speed, −2 AC/DEX, 1 action" ]
    , onSuccess = noEffect
    }


{-| The save recurs whenever a creature enters the emanation or
ends its turn there, once per turn; the GM applies the chain
again each time.
-}
spiritGuardians : SaveChain
spiritGuardians =
    { name = "Spirit Guardians"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "3d8")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Each creature saves at the start of its turn in the cloud and
is Poisoned only until the end of that turn on a failure. The
start-of-turn auto-roll re-checks a still-Poisoned creature each
turn; the GM removes the condition when it leaves the cloud.
-}
stinkingCloud : SaveChain
stinkingCloud =
    { name = "Stinking Cloud"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvBoT "Poisoned" "Stinking Cloud; no action this turn" ]
    , onSuccess = noEffect
    }



-- ── Level 4 ─────────────────────────────────────────────────────


{-| No repeat save: the target stays banished, and Incapacitated,
until the caster's concentration ends.
-}
banishment : SaveChain
banishment =
    { name = "Banishment"
    , saveAbility = Cha
    , saveDc = Nothing
    , onFail = effectsOnly [ effect "Banished" "Incapacitated; conc. 1 min" ]
    , onSuccess = noEffect
    }


{-| A Plant creature fails the save automatically — the GM
clicks Fail for those.
-}
blight : SaveChain
blight =
    { name = "Blight"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d8")
    , onSuccess = damageOnly HalfFailDamage
    }


confusion : SaveChain
confusion =
    { name = "Confusion"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvEoT "Confused" "roll d10 each turn" ]
    , onSuccess = noEffect
    }


{-| The 2024 text deals 2d10 bludgeoning rather than 2d8; the
formula sums both damage types and the GM narrates the split.
-}
iceStorm : SaveChain
iceStorm =
    { name = "Ice Storm"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "2d10+4d6")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The 2024 spell no longer frightens: a failed save costs the
target disadvantage on ability checks and attack rolls, and
each failed end-of-turn save deals the damage again, which the
editor can't roll on its own. A successful first save still
takes half damage.
-}
phantasmalKiller : SaveChain
phantasmalKiller =
    { name = "Phantasmal Killer"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "4d10"
        , effects = [ effectSvEoT "Nightmare" "disadv checks & attacks; 4d10 per failed save" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 5 ─────────────────────────────────────────────────────


{-| The save recurs when the fog moves into a creature's space
and when it enters the fog or ends its turn there, once per
turn; the GM applies the chain again each time.
-}
cloudkill : SaveChain
cloudkill =
    { name = "Cloudkill"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "5d8")
    , onSuccess = damageOnly HalfFailDamage
    }


coneOfCold : SaveChain
coneOfCold =
    { name = "Cone of Cold"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "8d8")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The repeat save comes whenever the target takes damage rather
than on a turn boundary, so the chip carries a manual save for
the GM to roll at that moment.
-}
dominatePerson : SaveChain
dominatePerson =
    { name = "Dominate Person"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail = effectsOnly [ effectSvManual "Charmed" "Dominated; re-save when damaged" ]
    , onSuccess = noEffect
    }


{-| The 2024 text deals 5d6 of each damage type rather than 4d6.
-}
flameStrike : SaveChain
flameStrike =
    { name = "Flame Strike"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "5d6+5d6")
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



-- ── Level 6 ─────────────────────────────────────────────────────


chainLightning : SaveChain
chainLightning =
    { name = "Chain Lightning"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "10d8")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| Nothing on a successful save; a target the damage brings to
0 HP is dust.
-}
disintegrate : SaveChain
disintegrate =
    { name = "Disintegrate"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "10d6+40")
    , onSuccess = noEffect
    }


{-| A failed save also lowers the target's hit point maximum by
the damage taken, which the GM enters through the card's Manage
HP editor.
-}
harm : SaveChain
harm =
    { name = "Harm"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "14d6")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The blindness ends at the start of the caster's next turn,
not on a save, so the effect carries the timing as a note for
the GM to clear.
-}
sunbeam : SaveChain
sunbeam =
    { name = "Sunbeam"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "6d8"
        , effects = [ effect "Blinded" "until caster's next turn" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 7 ─────────────────────────────────────────────────────


fingerOfDeath : SaveChain
fingerOfDeath =
    { name = "Finger of Death"
    , saveAbility = Con
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "7d8+30")
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 8 ─────────────────────────────────────────────────────


{-| Feeblemind's 2024 name and numbers. The repeat save comes
every 30 days, far outside a fight, so the effect has no
Save-to-end.
-}
befuddlement : SaveChain
befuddlement =
    { name = "Befuddlement"
    , saveAbility = Int_
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "10d12"
        , effects = [ effect "Befuddled" "no spells or Magic action" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Level 9 ─────────────────────────────────────────────────────


meteorSwarm : SaveChain
meteorSwarm =
    { name = "Meteor Swarm"
    , saveAbility = Dex
    , saveDc = Nothing
    , onFail = damageOnly (DealDamage "20d6+20d6")
    , onSuccess = damageOnly HalfFailDamage
    }


{-| The 2024 spell deals 10d10 up front (half on a success) and
5d10 more on each failed end-of-turn save, which the editor
can't roll on its own.
-}
weird : SaveChain
weird =
    { name = "Weird"
    , saveAbility = Wis
    , saveDc = Nothing
    , onFail =
        { hp = DealDamage "10d10"
        , effects = [ effectSvEoT "Frightened" "5d10 psychic per failed save" ]
        }
    , onSuccess = damageOnly HalfFailDamage
    }



-- ── Monster abilities ───────────────────────────────────────────
-- Each carries the DC its stat block fixes, so the applied
-- condition's save is ready without typing.


{-| Paralysis until the end of the target's next turn: it ends
by the clock, not by a save, so the effect has no Save-to-end
and the GM clears it. Undead and elves are immune.
-}
ghoulClaw : SaveChain
ghoulClaw =
    { name = "Ghoul Claw"
    , saveAbility = Con
    , saveDc = Just 10
    , onFail = effectsOnly [ effect "Paralyzed" "Ghoul; until end of its next turn" ]
    , onSuccess = noEffect
    }


{-| The save comes at the start of each turn a creature begins
within 5 feet of the ghast; a failure poisons it until the
start of its next turn, and a success grants a day's immunity,
which the success side records on the card.
-}
ghastStench : SaveChain
ghastStench =
    { name = "Ghast Stench"
    , saveAbility = Con
    , saveDc = Just 10
    , onFail = effectsOnly [ effectSvBoT "Poisoned" "Ghast stench; until its next turn" ]
    , onSuccess = effectsOnly [ effect "Stench immunity" "this ghast; 24 hr" ]
    }


{-| Charmed until the song ends, repeating the save at the end of
each turn; while Charmed the target is Incapacitated and walks
toward the harpy. A success grants a day's immunity.
-}
harpyLuringSong : SaveChain
harpyLuringSong =
    { name = "Harpy Luring Song"
    , saveAbility = Wis
    , saveDc = Just 11
    , onFail = effectsOnly [ effectSvEoT "Charmed" "Luring Song; Incapacitated, walks to harpy" ]
    , onSuccess = effectsOnly [ effect "Song immunity" "this harpy; 24 hr" ]
    }


{-| Frightened until the end of the mummy's next turn — by the
clock, so no Save-to-end. A success grants a day's immunity.
-}
mummyDreadfulGlare : SaveChain
mummyDreadfulGlare =
    { name = "Mummy Dreadful Glare"
    , saveAbility = Wis
    , saveDc = Just 11
    , onFail = effectsOnly [ effect "Frightened" "until end of mummy's next turn" ]
    , onSuccess = effectsOnly [ effect "Glare immunity" "this mummy; 24 hr" ]
    }


{-| A first failure restrains the target, which repeats the save
at the end of its next turn; a second failure petrifies it.
The editor ends the condition on a success but can't escalate
on a failure, so the note carries that step.
-}
medusaPetrifyingGaze : SaveChain
medusaPetrifyingGaze =
    { name = "Medusa Petrifying Gaze"
    , saveAbility = Con
    , saveDc = Just 13
    , onFail = effectsOnly [ effectSvEoT "Restrained" "Petrifying Gaze; 2nd fail → Petrified" ]
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


{-| An effect whose applied condition inherits the chain's save
and DC and rolls at the end of each of the bearer's turns — the
usual "repeats the save at the end of each of its turns" shape.
-}
effectSvEoT : String -> String -> SaveChain.EffectApply
effectSvEoT name note =
    { name = name, note = note, saveToEnd = Just Encounter.AutoRollAtEnd }


{-| Twin of `effectSvEoT` for saves the rules place at the start
of the bearer's turn.
-}
effectSvBoT : String -> String -> SaveChain.EffectApply
effectSvBoT name note =
    { name = name, note = note, saveToEnd = Just Encounter.AutoRollAtBegin }


{-| Twin of `effectSvEoT` for a repeat save with no turn timing,
such as one made whenever the target takes damage: the chip
carries the save for the GM to roll when the trigger comes.
-}
effectSvManual : String -> String -> SaveChain.EffectApply
effectSvManual name note =
    { name = name, note = note, saveToEnd = Just Encounter.AutoRollManual }
