module Encounter.SaveChain.Bundled exposing (defaults, retiredNames)

{-| Bundled Save Chain presets, seeded into a fresh visitor's
`Model.saveChainPresets` on the very first boot and laid over a
stored copy by the editor's "Restore bundled" button.

Each preset transcribes one saving-throw effect from the 2024
rules — SRD 5.2.1 where the effect is in it — as far as the
editor can express it: the save ability, a DC when the source
fixes one (a monster's ability does; a spell's comes from the
caster), what each side of the save does, how long it lasts,
and what a failed repeat save adds. Where the rules ask for
something the editor still has no setting for, the effect's
note carries the reminder, and `docs/SAVE_CHAIN_PRESETS.org`
records the gap.

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
import Encounter.SaveChain as SaveChain exposing (EffectApply, EffectDuration(..), HpEffect(..), SaveChain, SaveOutcome, TurnRef(..))


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
        , ( "Wight Life Drain", wightLifeDrain )
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
    chain "Acid Splash" Dex Nothing (damageOnly (DealDamage "1d6")) noEffect


sacredFlame : SaveChain
sacredFlame =
    chain "Sacred Flame" Dex Nothing (damageOnly (DealDamage "1d8")) noEffect


{-| The damage is 1d12 rather than 1d8 when the target is missing
any hit points; the GM overwrites the amount before applying in
that case.
-}
tollTheDead : SaveChain
tollTheDead =
    chain "Toll the Dead" Wis Nothing (damageOnly (DealDamage "1d8")) noEffect



-- ── Level 1 ─────────────────────────────────────────────────────


{-| No repeat save: the penalty runs out with the caster's
concentration, a minute at most.
-}
bane : SaveChain
bane =
    chain "Bane"
        Cha
        Nothing
        (effectsOnly [ effect "Baned" "−1d4 attacks & saves" |> lasting LastsOneMinute ])
        noEffect


burningHands : SaveChain
burningHands =
    chain "Burning Hands" Dex Nothing (damageOnly (DealDamage "3d6")) (damageOnly HalfFailDamage)


{-| The target obeys on its next turn only, so the condition ends
with that turn.
-}
command : SaveChain
command =
    chain "Command"
        Wis
        Nothing
        (effectsOnly [ effect "Commanded" "Command" |> lasting (LastsUntilTurn Encounter.AtEnd TurnOfBearer) ])
        noEffect


{-| Prone carries no save of its own: when the laughter ends the
target is still on the ground until it stands, which is what
the rules say. The repeat save also fires whenever the target
takes damage, with advantage.
-}
hideousLaughter : SaveChain
hideousLaughter =
    chain "Hideous Laughter"
        Wis
        Nothing
        (effectsOnly
            [ effectSvEoT "Incapacitated" "laughing"
                |> lasting LastsOneMinute
                |> onDamage Encounter.RollOnDamageWithAdvantage
            , effect "Prone" "can't stand while laughing"
            ]
        )
        noEffect


{-| A second failed save leaves the target Unconscious for the
rest of the minute; damage or a shake ends it early.
-}
sleep : SaveChain
sleep =
    chain "Sleep"
        Wis
        Nothing
        (effectsOnly
            [ effectSvEoT "Incapacitated" "Sleep"
                |> lasting LastsOneMinute
                |> onFailBecomes "Unconscious"
            ]
        )
        noEffect


{-| The 10-foot push on a failed save is repositioning, not a
condition, and stays with the GM.
-}
thunderwave : SaveChain
thunderwave =
    chain "Thunderwave" Con Nothing (damageOnly (DealDamage "2d8")) (damageOnly HalfFailDamage)



-- ── Level 2 ─────────────────────────────────────────────────────


{-| The caster picks Blinded or Deafened; the GM renames the
effect before applying when it's the latter.
-}
blindnessDeafness : SaveChain
blindnessDeafness =
    chain "Blindness / Deafness"
        Con
        Nothing
        (effectsOnly [ effectSvEoT "Blinded" "or Deafened" |> lasting LastsOneMinute ])
        noEffect


holdPerson : SaveChain
holdPerson =
    chain "Hold Person"
        Wis
        Nothing
        (effectsOnly [ effectSvEoT "Paralyzed" "" |> lasting LastsOneMinute ])
        noEffect


{-| Both sides do something: a failed save enfeebles until the
target saves at the end of a turn, while a successful one still
costs it disadvantage on its next attack roll, until the start
of the caster's next turn.
-}
rayOfEnfeeblement : SaveChain
rayOfEnfeeblement =
    chain "Ray of Enfeeblement"
        Con
        Nothing
        (effectsOnly [ effectSvEoT "Enfeebled" "disadv STR tests; −1d8 dmg" |> lasting LastsOneMinute ])
        (effectsOnly
            [ effect "Disadv next attack" "Ray of Enfeeblement"
                |> lasting (LastsUntilTurn Encounter.AtBegin TurnOfActive)
            ]
        )


{-| Constructs have disadvantage on the save; the Roll Disadv.
button covers that when the targets are all constructs.
-}
shatter : SaveChain
shatter =
    chain "Shatter" Con Nothing (damageOnly (DealDamage "3d8")) (damageOnly HalfFailDamage)


{-| The 2024 text makes the target Charmed for the duration, so
the standard condition carries the spell in its note; it ends
early if the caster or an ally damages the target.
-}
suggestion : SaveChain
suggestion =
    chain "Suggestion"
        Wis
        Nothing
        (effectsOnly [ effect "Charmed" "Suggestion; up to 8 hr" ])
        noEffect


{-| Escaping is a Strength (Athletics) check against the spell
DC, not a save, so the effect has no Save-to-end.
-}
web : SaveChain
web =
    chain "Web"
        Dex
        Nothing
        (effectsOnly [ effect "Restrained" "Athletics chk vs DC to escape" ])
        noEffect



-- ── Level 3 ─────────────────────────────────────────────────────


{-| The repeat save only happens when the target ends its turn
without line of sight to the caster, so the chip flashes as the
turn ends and the GM rolls when the target has earned it.
-}
fear : SaveChain
fear =
    chain "Fear"
        Wis
        Nothing
        (effectsOnly
            [ effectSvAskEoT "Frightened" "drop items, Dash away; save if no LoS"
                |> lasting LastsOneMinute
            ]
        )
        noEffect


fireball : SaveChain
fireball =
    chain "Fireball" Dex Nothing (damageOnly (DealDamage "8d6")) (damageOnly HalfFailDamage)


{-| Charmed, and Incapacitated with a Speed of 0 while Charmed —
the companion goes when the Charmed does. Neither has a repeat
save: damage or an ally's action ends the spell.
-}
hypnoticPattern : SaveChain
hypnoticPattern =
    chain "Hypnotic Pattern"
        Wis
        Nothing
        (effectsOnly
            [ effect "Charmed" "ends on dmg or shake"
                |> lasting LastsOneMinute
                |> withCompanion "Incapacitated"
            ]
        )
        noEffect


lightningBolt : SaveChain
lightningBolt =
    chain "Lightning Bolt" Dex Nothing (damageOnly (DealDamage "8d6")) (damageOnly HalfFailDamage)


slow : SaveChain
slow =
    chain "Slow"
        Wis
        Nothing
        (effectsOnly [ effectSvEoT "Slowed" "½ speed, −2 AC/DEX, 1 action" |> lasting LastsOneMinute ])
        noEffect


{-| The save recurs whenever a creature enters the emanation or
ends its turn there, once per turn: the "In:" marker rolls it at
the end of each marked creature's turn, and its 🎲 covers a
creature that enters mid-turn.
-}
spiritGuardians : SaveChain
spiritGuardians =
    chain "Spirit Guardians" Wis Nothing (damageOnly (DealDamage "3d8")) (damageOnly HalfFailDamage)
        |> area Encounter.AtEnd


{-| Each creature saves at the start of its turn in the cloud and
is Poisoned only until the end of that turn on a failure: the
"In:" marker rolls it at the start of each marked creature's
turn, and the GM removes the marker when the creature leaves.
-}
stinkingCloud : SaveChain
stinkingCloud =
    chain "Stinking Cloud"
        Con
        Nothing
        (effectsOnly [ effect "Poisoned" "Stinking Cloud; no action this turn" |> lasting LastsThisTurn ])
        noEffect
        |> area Encounter.AtBegin



-- ── Level 4 ─────────────────────────────────────────────────────


{-| No repeat save: the target stays banished, and Incapacitated,
until the caster's concentration ends.
-}
banishment : SaveChain
banishment =
    chain "Banishment"
        Cha
        Nothing
        (effectsOnly [ effect "Banished" "Incapacitated" |> lasting LastsOneMinute ])
        noEffect


{-| A Plant creature fails the save automatically — the GM
clicks Fail for those.
-}
blight : SaveChain
blight =
    chain "Blight" Con Nothing (damageOnly (DealDamage "8d8")) (damageOnly HalfFailDamage)


confusion : SaveChain
confusion =
    chain "Confusion"
        Wis
        Nothing
        (effectsOnly [ effectSvEoT "Confused" "roll d10 each turn" |> lasting LastsOneMinute ])
        noEffect


{-| The 2024 text deals 2d10 bludgeoning rather than 2d8; the
formula sums both damage types and the GM narrates the split.
-}
iceStorm : SaveChain
iceStorm =
    chain "Ice Storm" Dex Nothing (damageOnly (DealDamage "2d10+4d6")) (damageOnly HalfFailDamage)


{-| The 2024 spell no longer frightens: a failed save costs the
target disadvantage on ability checks and attack rolls, and
each failed end-of-turn save deals the damage again. A
successful first save still takes half damage.
-}
phantasmalKiller : SaveChain
phantasmalKiller =
    chain "Phantasmal Killer"
        Wis
        Nothing
        { hp = DealDamage "4d10"
        , effects =
            [ effectSvEoT "Nightmare" "disadv checks & attacks"
                |> lasting LastsOneMinute
                |> onFailDamage "4d10"
            ]
        }
        (damageOnly HalfFailDamage)



-- ── Level 5 ─────────────────────────────────────────────────────


{-| The save recurs when the fog moves into a creature's space
and when it enters the fog or ends its turn there, once per
turn: the "In:" marker rolls it at the end of each marked
creature's turn, and its 🎲 covers the fog reaching a creature
mid-turn.
-}
cloudkill : SaveChain
cloudkill =
    chain "Cloudkill" Con Nothing (damageOnly (DealDamage "5d8")) (damageOnly HalfFailDamage)
        |> area Encounter.AtEnd


coneOfCold : SaveChain
coneOfCold =
    chain "Cone of Cold" Con Nothing (damageOnly (DealDamage "8d8")) (damageOnly HalfFailDamage)


{-| The repeat save comes whenever the target takes damage rather
than on a turn boundary, so a hit rolls it.
-}
dominatePerson : SaveChain
dominatePerson =
    chain "Dominate Person"
        Wis
        Nothing
        (effectsOnly
            [ effectSvManual "Charmed" "Dominated"
                |> lasting LastsOneMinute
                |> onDamage Encounter.RollOnDamage
            ]
        )
        noEffect


{-| The 2024 text deals 5d6 of each damage type rather than 4d6.
-}
flameStrike : SaveChain
flameStrike =
    chain "Flame Strike" Dex Nothing (damageOnly (DealDamage "5d6+5d6")) (damageOnly HalfFailDamage)


holdMonster : SaveChain
holdMonster =
    chain "Hold Monster"
        Wis
        Nothing
        (effectsOnly [ effectSvEoT "Paralyzed" "" |> lasting LastsOneMinute ])
        noEffect



-- ── Level 6 ─────────────────────────────────────────────────────


chainLightning : SaveChain
chainLightning =
    chain "Chain Lightning" Dex Nothing (damageOnly (DealDamage "10d8")) (damageOnly HalfFailDamage)


{-| Nothing on a successful save; a target the damage brings to
0 HP is dust.
-}
disintegrate : SaveChain
disintegrate =
    chain "Disintegrate" Dex Nothing (damageOnly (DealDamage "10d6+40")) noEffect


{-| A failed save also lowers the target's hit point maximum by
the damage taken; a successful one takes half damage with the
maximum untouched.
-}
harm : SaveChain
harm =
    chain "Harm" Con Nothing (damageOnly (DrainDamage "14d6")) (damageOnly HalfFailDamage)


{-| The blindness ends at the start of the caster's next turn,
not on a save.
-}
sunbeam : SaveChain
sunbeam =
    chain "Sunbeam"
        Con
        Nothing
        { hp = DealDamage "6d8"
        , effects = [ effect "Blinded" "Sunbeam" |> lasting (LastsUntilTurn Encounter.AtBegin TurnOfActive) ]
        }
        (damageOnly HalfFailDamage)



-- ── Level 7 ─────────────────────────────────────────────────────


fingerOfDeath : SaveChain
fingerOfDeath =
    chain "Finger of Death" Con Nothing (damageOnly (DealDamage "7d8+30")) (damageOnly HalfFailDamage)



-- ── Level 8 ─────────────────────────────────────────────────────


{-| Feeblemind's 2024 name and numbers. The repeat save comes
every 30 days, far outside a fight, so the effect has no
Save-to-end.
-}
befuddlement : SaveChain
befuddlement =
    chain "Befuddlement"
        Int_
        Nothing
        { hp = DealDamage "10d12"
        , effects = [ effect "Befuddled" "no spells or Magic action" ]
        }
        (damageOnly HalfFailDamage)



-- ── Level 9 ─────────────────────────────────────────────────────


meteorSwarm : SaveChain
meteorSwarm =
    chain "Meteor Swarm" Dex Nothing (damageOnly (DealDamage "20d6+20d6")) (damageOnly HalfFailDamage)


{-| The 2024 spell deals 10d10 up front (half on a success) and
5d10 more on each failed end-of-turn save.
-}
weird : SaveChain
weird =
    chain "Weird"
        Wis
        Nothing
        { hp = DealDamage "10d10"
        , effects =
            [ effectSvEoT "Frightened" "Weird"
                |> lasting LastsOneMinute
                |> onFailDamage "5d10"
            ]
        }
        (damageOnly HalfFailDamage)



-- ── Monster abilities ───────────────────────────────────────────
-- Each carries the DC its stat block fixes, so the applied
-- condition's save is ready without typing.


{-| Paralysis until the end of the target's next turn. Undead and
elves are immune.
-}
ghoulClaw : SaveChain
ghoulClaw =
    chain "Ghoul Claw"
        Con
        (Just 10)
        (effectsOnly [ effect "Paralyzed" "Ghoul" |> lasting (LastsUntilTurn Encounter.AtEnd TurnOfBearer) ])
        noEffect


{-| The save comes at the start of each turn a creature begins
within 5 feet of the ghast: the "In:" marker rolls it then. A
failure poisons the creature until the start of its next turn,
and a success grants a day's immunity, which the marker honours.
-}
ghastStench : SaveChain
ghastStench =
    chain "Ghast Stench"
        Con
        (Just 10)
        (effectsOnly [ effect "Poisoned" "Ghast Stench" |> lasting (LastsUntilTurn Encounter.AtBegin TurnOfBearer) ])
        noEffect
        |> withImmunity LastsUntilRemoved
        |> area Encounter.AtBegin


{-| Charmed until the song ends, repeating the save at the end of
each turn and whenever damage from someone other than the harpy
lands — the chip flashes on a hit for the GM to judge. While
Charmed the target is Incapacitated and walks toward the harpy.
A success grants a day's immunity.
-}
harpyLuringSong : SaveChain
harpyLuringSong =
    chain "Harpy Luring Song"
        Wis
        (Just 11)
        (effectsOnly
            [ effectSvEoT "Charmed" "Luring Song; walks to harpy"
                |> withCompanion "Incapacitated"
                |> onDamage Encounter.AskOnDamage
            ]
        )
        noEffect
        |> withImmunity LastsUntilRemoved


{-| Frightened until the end of the mummy's next turn, the mummy
being the active creature when its glare applies. A success
grants a day's immunity.
-}
mummyDreadfulGlare : SaveChain
mummyDreadfulGlare =
    chain "Mummy Dreadful Glare"
        Wis
        (Just 11)
        (effectsOnly [ effect "Frightened" "Dreadful Glare" |> lasting (LastsUntilTurn Encounter.AtEnd TurnOfActive) ])
        noEffect
        |> withImmunity LastsUntilRemoved


{-| A first failure restrains the target, which repeats the save
at the end of its next turn; a second failure petrifies it.
-}
medusaPetrifyingGaze : SaveChain
medusaPetrifyingGaze =
    chain "Medusa Petrifying Gaze"
        Con
        (Just 13)
        (effectsOnly [ effectSvEoT "Restrained" "Petrifying Gaze" |> onFailBecomes "Petrified" ])
        noEffect


{-| The necrotic damage also lowers the target's hit point maximum
by the amount taken; a success takes half and keeps its maximum.
-}
wightLifeDrain : SaveChain
wightLifeDrain =
    chain "Wight Life Drain" Con (Just 13) (damageOnly (DrainDamage "1d8+2")) (damageOnly HalfFailDamage)



-- ── Preset helpers ───────────────────────────────────────────────


chain : String -> Ability -> Maybe Int -> SaveOutcome -> SaveOutcome -> SaveChain
chain name ability dc onFail onSuccess =
    { name = name
    , saveAbility = ability
    , saveDc = dc
    , onFail = onFail
    , onSuccess = onSuccess
    , immunity = Nothing
    , area = Nothing
    }


{-| A successful save leaves the target immune to the chain for
the duration.
-}
withImmunity : EffectDuration -> SaveChain -> SaveChain
withImmunity duration c =
    { c | immunity = Just duration }


{-| The chain keeps working on whoever stands in it, rolling its
save again at this phase of each marked creature's turn.
-}
area : Encounter.TurnPhase -> SaveChain -> SaveChain
area phase c =
    { c | area = Just phase }


noEffect : SaveOutcome
noEffect =
    SaveChain.empty.onFail


damageOnly : HpEffect -> SaveOutcome
damageOnly hp =
    { hp = hp, effects = [] }


effectsOnly : List EffectApply -> SaveOutcome
effectsOnly es =
    { hp = NoHpEffect, effects = es }


{-| An effect that lasts until removed and has no save of its own.
-}
effect : String -> String -> EffectApply
effect name note =
    let
        blank =
            SaveChain.emptyEffect
    in
    { blank | name = name, note = note }


lasting : EffectDuration -> EffectApply -> EffectApply
lasting duration e =
    { e | duration = duration }


{-| An effect whose applied condition inherits the chain's save
and DC and rolls at the end of each of the bearer's turns — the
usual "repeats the save at the end of each of its turns" shape.
-}
effectSvEoT : String -> String -> EffectApply
effectSvEoT name note =
    saving Encounter.AutoRollAtEnd (effect name note)


{-| Twin of `effectSvEoT` for saves the rules place at the start
of the bearer's turn.
-}
effectSvBoT : String -> String -> EffectApply
effectSvBoT name note =
    saving Encounter.AutoRollAtBegin (effect name note)


{-| Twin of `effectSvEoT` for a repeat save with no turn timing,
such as one made whenever the target takes damage: the chip
carries the save for the GM to roll when the trigger comes.
-}
effectSvManual : String -> String -> EffectApply
effectSvManual name note =
    saving Encounter.AutoRollManual (effect name note)


{-| Twin of `effectSvEoT` for a save the rules grant only when
some condition held as the turn ended: the chip flashes then and
the GM rolls if it did.
-}
effectSvAskEoT : String -> String -> EffectApply
effectSvAskEoT name note =
    saving Encounter.AutoRollAskAtEnd (effect name note)


saving : Encounter.AutoRollMode -> EffectApply -> EffectApply
saving mode e =
    { e
        | saveToEnd =
            Just
                { autoRoll = mode
                , onFail = Encounter.noFailedSave
                , onDamage = Encounter.NoDamageTrigger
                }
    }


{-| What a hit on the bearer does to the effect's save.
-}
onDamage : Encounter.DamageTrigger -> EffectApply -> EffectApply
onDamage trigger e =
    { e | saveToEnd = Maybe.map (\s -> { s | onDamage = trigger }) e.saveToEnd }


{-| A companion condition applied beside the effect that ends when
it ends.
-}
withCompanion : String -> EffectApply -> EffectApply
withCompanion name e =
    { e | with = name }


{-| A failed repeat save turns the condition into another, which
also ends the saving.
-}
onFailBecomes : String -> EffectApply -> EffectApply
onFailBecomes newName e =
    { e | saveToEnd = Maybe.map (\s -> { s | onFail = { damage = s.onFail.damage, becomes = Just newName } }) e.saveToEnd }


{-| A failed repeat save deals the formula's damage to the bearer.
-}
onFailDamage : String -> EffectApply -> EffectApply
onFailDamage formula e =
    { e | saveToEnd = Maybe.map (\s -> { s | onFail = { damage = Just formula, becomes = s.onFail.becomes } }) e.saveToEnd }
