module Ui.Condition.Bundled exposing
    ( defaults, retiredNames
    , categories
    , categoryPlayer, categorySpell, categoryMonster, categoryItem, categoryEnvironment
    )

{-| Bundled Add-Condition presets seeded into a fresh visitor's
`Model.conditionPresets` on the very first boot, and laid over a
stored copy by the Load menu's "Restore bundled presets" item.

The Load dropdown in the Add-Condition modal groups these into
five collapsible categories below the user's own saves:
_Player Classes_ / _Spell Effects_ / _Monster Abilities_ /
_Items_ / _Environment_. Each preset's `category` field selects
its section; user-saved presets default to `""` and render in
the flat "My Presets" list at the top.

Seeding fires from `Main.init` when the `localConditionPresets`
boot flag is `Nothing` — i.e. no `localStorage.conditionPresets`
key exists. Once any change writes to that key (delete a
bundled, save a new one, edit one), the flag is `Just _` on
every subsequent boot and seeding does not re-fire, so a stored
copy keeps the settings it was seeded with, shadowing the
shipped preset of its name, until the GM restores the bundled
presets.

Each preset follows the 2024 rules (SRD 5.2.1 where the effect is
in it) as far as the editor can express them; where it cannot,
`docs/CONDITION_PRESETS.org` records the gap. Only a custom-named
preset carries a note, since a standard condition's name already
says what it does. DC values are best-defaults; the GM adjusts per
cast (Stunning Strike's DC scales with Monk Wisdom, a dragon's
Fear with its CR, and so on).

@docs defaults, retiredNames
@docs categories
@docs categoryPlayer, categorySpell, categoryMonster, categoryItem, categoryEnvironment

-}

import Dict exposing (Dict)
import Encounter exposing (AutoRollMode(..), TurnPhase(..))
import Msg exposing (DurationKind(..))
import Ui.Condition exposing (ConditionPreset, SaveToEndUi)



-- ── CATEGORY KEYS ────────────────────────────────────────────────────────


categoryPlayer : String
categoryPlayer =
    "Player Classes"


categorySpell : String
categorySpell =
    "Spell Effects"


categoryMonster : String
categoryMonster =
    "Monster Abilities"


categoryItem : String
categoryItem =
    "Items"


categoryEnvironment : String
categoryEnvironment =
    "Environment"


{-| The five bundled categories in display order. The view layer
walks this list to render category sections in a fixed sequence
regardless of dict iteration order.
-}
categories : List String
categories =
    [ categoryPlayer
    , categorySpell
    , categoryMonster
    , categoryItem
    , categoryEnvironment
    ]



-- ── DEFAULTS DICT ────────────────────────────────────────────────────────


defaults : Dict String ConditionPreset
defaults =
    Dict.fromList
        [ -- Player Classes (64)
          ( "Stunning Strike (Monk)", stunningStrike )
        , ( "Trip Attack", tripAttack )
        , ( "Menacing Attack", menacingAttack )
        , ( "Goading Attack", goadingAttack )
        , ( "Wrathful Smite", wrathfulSmite )
        , ( "Searing Smite", searingSmite )
        , ( "Staggering Smite", staggeringSmite )
        , ( "Turn Undead", turnUndead )
        , ( "Bardic Inspiration (+d6)", bardicInspiration )
        , ( "Bardic Inspiration (+d8)", bardicInspirationD8 )
        , ( "Bardic Inspiration (+d10)", bardicInspirationD10 )
        , ( "Bless (+d4)", bless )
        , ( "Hex", hex )
        , ( "Hunter's Mark", huntersMark )
        , ( "Rage (Barbarian)", rage )
        , ( "Reckless Attack (Barbarian)", recklessAttack )
        , ( "Vicious Mockery (Bard)", viciousMockery )
        , ( "Guidance (Cleric)", guidance )
        , ( "Sanctuary (Cleric)", sanctuary )
        , ( "Shield of Faith (Cleric/Paladin)", shieldOfFaith )
        , ( "Wild Shape (Druid)", wildShape )
        , ( "Spike Growth (Druid/Ranger)", spikeGrowth )
        , ( "Action Surge (Fighter)", actionSurge )
        , ( "Disarming Attack (Battle Master)", disarmingAttack )
        , ( "Pushing Attack (Battle Master)", pushingAttack )
        , ( "Patient Defense (Monk)", patientDefense )
        , ( "Shining Smite (Paladin)", shiningSmite )
        , ( "Pass Without Trace (Druid/Ranger)", passWithoutTrace )
        , ( "Ensnaring Strike (Ranger)", ensnaringStrike )
        , ( "Sneak Attack (Rogue)", sneakAttack )
        , ( "Hexblade's Curse (Warlock)", hexbladeCurse )
        , ( "Shield (Wizard/Sorcerer)", shieldSpell )
        , ( "Haste (Wizard/Sorcerer)", haste )
        , ( "Heroism (Bard/Paladin)", heroism )
        , ( "Sap (Weapon Mastery)", sapMastery )
        , ( "Vex (Weapon Mastery)", vexMastery )
        , ( "Slow (Weapon Mastery)", slowMastery )
        , ( "Grapple (Unarmed Strike)", grappleUnarmed )
        , ( "Cunning Strike: Poison (Rogue)", cunningStrikePoison )
        , ( "Open Hand: Addle (Monk)", openHandAddle )
        , ( "Help: Assist an Attack", helpAssist )
        , ( "Intimidating Presence (Berserker)", intimidatingPresence )
        , ( "Abjure Foes (Paladin)", abjureFoes )
        , ( "Devious Strikes: Obscure (Rogue)", deviousObscure )
        , ( "Devious Strikes: Daze (Rogue)", deviousDaze )
        , ( "Devious Strikes: Knock Out (Rogue)", deviousKnockOut )
        , ( "Nature's Veil (Ranger)", naturesVeil )
        , ( "Studied Attacks (Fighter)", studiedAttacks )
        , ( "Brutal Strike: Hamstring (Barbarian)", hamstringBlow )
        , ( "Brutal Strike: Staggering (Barbarian)", staggeringBlow )
        , ( "Brutal Strike: Sundering (Barbarian)", sunderingBlow )
        , ( "Mindless Rage (Berserker)", mindlessRage )
        , ( "Aura of Courage (Paladin)", auraOfCourage )
        , ( "Aura of Devotion (Paladin)", auraOfDevotion )
        , ( "Frost's Chill (Goliath)", frostsChill )
        , ( "Hurl Through Hell (Warlock)", hurlThroughHell )
        , ( "Innate Sorcery (Sorcerer)", innateSorcery )
        , ( "Sacred Weapon (Paladin)", sacredWeapon )
        , ( "Heroic Inspiration", heroicInspiration )
        , ( "Aura of Protection (Paladin)", auraOfProtection )
        , ( "Stunning Strike, saved (Monk)", stunningStrikeSaved )
        , ( "Superior Defense (Monk)", superiorDefense )
        , ( "Quivering Palm (Monk)", quiveringPalm )
        , ( "Large Form (Goliath)", largeForm )

        -- Spell Effects (72)
        , ( "Bane (−d4)", bane )
        , ( "Hold Person", holdPerson )
        , ( "Hold Monster", holdMonster )
        , ( "Sleep", sleep )
        , ( "Charm Person", charmPerson )
        , ( "Command", command )
        , ( "Cause Fear", causeFear )
        , ( "Fear", fear )
        , ( "Hypnotic Pattern", hypnoticPattern )
        , ( "Hideous Laughter", hideousLaughter )
        , ( "Suggestion", suggestion )
        , ( "Slow", slow )
        , ( "Web", web )
        , ( "Entangle", entangle )
        , ( "Black Tentacles", blackTentacles )
        , ( "Faerie Fire", faerieFire )
        , ( "Blindness", blindness )
        , ( "Banishment", banishment )
        , ( "Stinking Cloud", stinkingCloud )
        , ( "Greater Invisibility", greaterInvisibility )
        , ( "Invisibility", invisibilitySpell )
        , ( "Blur", blur )
        , ( "Bestow Curse (Disadvantage)", bestowCurseDisadv )
        , ( "Bestow Curse (Attack You)", bestowCurseAttack )
        , ( "Bestow Curse (Dodge)", bestowCurseDodge )
        , ( "Bestow Curse (+1d8 Necrotic)", bestowCurseNecrotic )
        , ( "Confusion", confusion )
        , ( "Charm Monster", charmMonster )
        , ( "Dominate Person", dominatePerson )
        , ( "Phantasmal Killer", phantasmalKiller )
        , ( "Polymorph", polymorph )
        , ( "Dominate Beast", dominateBeast )
        , ( "Guiding Bolt", guidingBolt )
        , ( "Ray of Sickness", rayOfSickness )
        , ( "Color Spray", colorSpray )
        , ( "Protection from Evil and Good", protectionEvilGood )
        , ( "Shocking Grasp", shockingGrasp )
        , ( "Ray of Frost", rayOfFrost )
        , ( "Chill Touch", chillTouch )
        , ( "Enlarge", enlarge )
        , ( "Reduce", reduce )
        , ( "Enhance Ability", enhanceAbility )
        , ( "Ray of Enfeeblement", rayOfEnfeeblement )
        , ( "Heat Metal", heatMetal )
        , ( "Mirror Image", mirrorImage )
        , ( "Levitate", levitate )
        , ( "Warding Bond", wardingBond )
        , ( "Calm Emotions (Immunity)", calmEmotions )
        , ( "Calm Emotions (Indifferent)", calmEmotionsCalmed )
        , ( "Beacon of Hope", beaconOfHope )
        , ( "Protection from Energy (Acid)", protectionAcid )
        , ( "Protection from Energy (Cold)", protectionCold )
        , ( "Protection from Energy (Fire)", protectionFire )
        , ( "Protection from Energy (Lightning)", protectionLightning )
        , ( "Protection from Energy (Thunder)", protectionThunder )
        , ( "Fly", flySpell )
        , ( "Gaseous Form", gaseousForm )
        , ( "Stoneskin", stoneskin )
        , ( "Death Ward", deathWard )
        , ( "Freedom of Movement", freedomOfMovement )
        , ( "Fire Shield (Warm)", fireShieldWarm )
        , ( "Fire Shield (Chill)", fireShieldChill )
        , ( "Resilient Sphere", resilientSphere )
        , ( "Compulsion", compulsion )
        , ( "Contagion", contagion )
        , ( "Geas", geas )
        , ( "Eyebite (Panicked)", eyebitePanicked )
        , ( "Eyebite (Asleep)", eyebiteAsleep )
        , ( "Eyebite (Sickened)", eyebiteSickened )
        , ( "Flesh to Stone", fleshToStone )
        , ( "Irresistible Dance", irresistibleDance )
        , ( "Power Word Stun", powerWordStun )

        -- Monster Abilities (51)
        , ( "Petrifying Gaze (Medusa)", petrifyingGaze )
        , ( "Mind Blast (Mind Flayer)", mindBlast )
        , ( "Frightful Presence (Dragon)", frightfulPresence )
        , ( "Horrific Visage (Ghost)", horrificVisage )
        , ( "Claw (Ghoul)", ghoulClaw )
        , ( "Vampire Charm", vampireCharm )
        , ( "Luring Song (Harpy)", luringSong )
        , ( "Web (Giant Spider)", giantSpiderWeb )
        , ( "Tendril (Roper)", roperGrab )
        , ( "Sleep Ray (Beholder)", beholderSleepRay )
        , ( "Tentacles (Carrion Crawler)", carrionCrawler )
        , ( "Mummy Rot", mummyRot )
        , ( "Grappled (escape DC)", grappledEscape )
        , ( "Constricted", constricted )
        , ( "Swallowed", swallowed )
        , ( "Venomous Bite (1 round)", venomousBite )
        , ( "Petrifying Gaze (Basilisk)", basiliskGaze )
        , ( "Frightened (save ends)", frightenedSaveEnds )
        , ( "Frightened (1 round)", frightenedOneRound )
        , ( "Paralyzing Tentacles (Chuul)", chuulTentacles )
        , ( "Sleep Breath (Brass Dragon)", brassSleepBreath )
        , ( "Paralyzing Breath (Silver Dragon)", silverParalyzingBreath )
        , ( "Life Drain", lifeDrained )
        , ( "Paralyzing Touch (Lich)", lichParalyzingTouch )
        , ( "Possession (Ghost)", ghostPossession )
        , ( "Enslave (Aboleth)", abolethEnslave )
        , ( "Entangling Rope (Erinyes)", entanglingRope )
        , ( "Engulfed (Gelatinous Cube)", cubeEngulf )
        , ( "Engulfed (Shambling Mound)", shamblingEngulf )
        , ( "Smothered (Rug of Smothering)", rugSmother )
        , ( "Whelmed (Water Elemental)", waterWhelm )
        , ( "Attached (Cloaker)", cloakerAttach )
        , ( "Lycanthropy", lycanthropy )
        , ( "Spores (Vrock)", vrockSpores )
        , ( "Weight of Years (Sphinx)", weightOfYears )
        , ( "Venom Coma (Phase Spider)", venomComa )
        , ( "Sting (Pseudodragon)", pseudodragonSting )
        , ( "Dreadful Glare (Mummy Lord)", mummyLordGlare )
        , ( "Corrupting Touch (Lamia)", lamiaTouch )
        , ( "Infernal Wound", infernalWound )
        , ( "Diseased (Otyugh)", otyughDisease )
        , ( "Stunning Screech (Vrock)", vrockScreech )
        , ( "Blinded (1 round)", blindedOneRound )
        , ( "Blinding Gaze (Solar)", solarGaze )
        , ( "Incapacitated (1 round)", incapacitatedOneRound )
        , ( "Charmed (1 round)", charmedOneRound )
        , ( "Restless Curse (Incubus)", restlessCurse )
        , ( "Mucus Curse (Aboleth)", abolethMucus )
        , ( "Nightmare (Incubus)", incubusNightmare )
        , ( "Devil's Poison (No Healing)", poisonNoHeal )
        , ( "Deafened (1 round)", deafenedOneRound )

        -- Items (57)
        , ( "Wand of Paralysis", wandOfParalysis )
        , ( "Wand of Fear", wandOfFear )
        , ( "Staff of Charming", staffOfCharming )
        , ( "Potion of Invisibility", potionOfInvisibility )
        , ( "Dust of Sneezing and Choking", dustOfSneezingAndChoking )
        , ( "Potion of Heroism", potionOfHeroism )
        , ( "Potion of Giant Strength", potionOfGiantStrength )
        , ( "Potion of Climbing", potionOfClimbing )
        , ( "Dust of Disappearance", dustOfDisappearance )
        , ( "Net", net )
        , ( "Wand of Binding", wandOfBinding )
        , ( "Dagger of Venom", daggerOfVenom )
        , ( "Mace of Terror", maceOfTerror )
        , ( "Gem of Brightness", gemOfBrightness )
        , ( "Horn of Blasting", hornOfBlasting )
        , ( "Rod of Lordly Might (Paralyze)", rodParalyze )
        , ( "Rod of Lordly Might (Terrify)", rodTerrify )
        , ( "Rope of Entanglement", ropeOfEntanglement )
        , ( "Iron Bands of Binding", ironBands )
        , ( "Manacles", manacles )
        , ( "Hunting Trap", huntingTrap )
        , ( "Caltrops", caltrops )
        , ( "Ring of Invisibility", ringOfInvisibility )
        , ( "Cloak of Displacement", cloakOfDisplacement )
        , ( "Sword of Wounding", swordOfWounding )
        , ( "Sword of Sharpness", swordOfSharpness )
        , ( "Berserker Axe", berserkerAxe )
        , ( "Hammer of Thunderbolts", hammerOfThunderbolts )
        , ( "Philter of Love", philterOfLove )
        , ( "Potion of Poison", potionOfPoison )
        , ( "Potion of Flying", potionOfFlying )
        , ( "Winged Boots", wingedBoots )
        , ( "Potion of Gaseous Form", potionGaseousForm )
        , ( "Potion of Growth", potionOfGrowth )
        , ( "Potion of Diminution", potionOfDiminution )
        , ( "Potion of Invulnerability", potionOfInvulnerability )
        , ( "Potion of Resistance", potionOfResistance )
        , ( "Oil of Slipperiness", oilOfSlipperiness )
        , ( "Ring of Free Action", ringOfFreeAction )
        , ( "Boots of Speed", bootsOfSpeed )
        , ( "Slippers of Spider Climbing", slippersSpiderClimb )
        , ( "Ring of Regeneration", ringOfRegeneration )
        , ( "Rod of Rulership", rodOfRulership )
        , ( "Sentient Item Control", sentientItemControl )
        , ( "Trident of Fish Command", tridentFishCommand )
        , ( "Shield of Missile Attraction", shieldMissileAttraction )
        , ( "Periapt of Proof against Poison", periaptPoison )
        , ( "Crawler Mucus", crawlerMucus )
        , ( "Malice", malice )
        , ( "Essence of Ether", essenceOfEther )
        , ( "Oil of Taggit", oilOfTaggit )
        , ( "Spider's Sting", spidersSting )
        , ( "Assassin's Blood", assassinsBlood )
        , ( "Truth Serum", truthSerum )
        , ( "Torpor", torpor )
        , ( "Pale Tincture", paleTincture )
        , ( "Burnt Othur Fumes", burntOthurFumes )

        -- Environment (27)
        , ( "Quicksand", quicksand )
        , ( "Slippery Surface", slipperySurface )
        , ( "Heavy Obscurement", heavyObscurement )
        , ( "Drowning", drowning )
        , ( "On Fire", onFire )
        , ( "Extreme Cold", extremeCold )
        , ( "Extreme Heat", extremeHeat )
        , ( "Pit Trap", pitTrap )
        , ( "Extended Travel", extendedTravel )
        , ( "Dehydration", dehydration )
        , ( "Malnutrition", malnutrition )
        , ( "Frigid Water", frigidWater )
        , ( "Deep Water", deepWater )
        , ( "Underwater", underwater )
        , ( "Strong Wind", strongWind )
        , ( "Heavy Precipitation", heavyPrecipitation )
        , ( "High Altitude", highAltitude )
        , ( "Poisoned Needle (Trap)", poisonedNeedle )
        , ( "Collapsing Roof (Trap)", collapsingRoof )
        , ( "Sight Rot", sightRot )
        , ( "Cackle Fever", cackleFever )
        , ( "Cackling Fit", cacklingFit )
        , ( "Sewer Plague", sewerPlague )
        , ( "Demonic Possession", demonicPossession )
        , ( "Mental Stress (Short-Term)", shortTermStress )
        , ( "Mental Stress (Long-Term)", longTermStress )
        , ( "Holding Breath", holdingBreath )
        ]


{-| Bundled names no longer shipped, which a restore drops from a
stored copy so the Load menu doesn't offer both an old entry and
its replacement.
-}
retiredNames : List String
retiredNames =
    [ -- The 2024 rules replace it with Shining Smite.
      "Branding Smite (Paladin)"

    -- The SRD drops the wizard's name from the spell.
    , "Evard's Black Tentacles"

    -- The SRD ghost's action is Horrific Visage.
    , "Horrifying Visage (Ghost)"

    -- Paralyzing Touch is the lich's; the ghoul's is its Claw.
    , "Paralyzing Touch (Ghoul)"

    -- A pit leaves its victim Prone, not Restrained.
    , "Pit Trap (Restrained)"
    ]



-- ── BUILDERS ─────────────────────────────────────────────────────────────


{-| Empty save-spec template overlaid by individual presets that
opt into a save-to-end. DC defaults to 10 (overridden by the
caller); ability defaults to WIS, the most common save target.
-}
emptySave : SaveToEndUi
emptySave =
    { ability = "WIS"
    , dcText = "10"
    , dc = 10
    , bonusText = "0"
    , bonus = 0
    , autoRoll = AutoRollAtEnd
    , failDamageText = ""
    , failBecomesText = ""
    , onDamage = Encounter.NoDamageTrigger
    }


save : String -> Int -> AutoRollMode -> SaveToEndUi
save ability dc autoRoll =
    { emptySave | ability = ability, dc = dc, dcText = String.fromInt dc, autoRoll = autoRoll }


{-| One minute: the ten rounds an effect lasting "up to 1 minute"
runs, ending as the bearer's tenth turn ends.
-}
lastsOneMinute : ConditionPreset -> ConditionPreset
lastsOneMinute preset =
    { preset
        | durationKind = DurKindCountdown
        , countdownTurnsText = "10"
        , countdownTurns = 10
        , countdownPhase = AtEnd
    }


{-| Bare-bones preset with `Manual` duration and no save. Each
named preset overrides the fields it cares about. We expose
one per-category named record (rather than a function returning
one) so individual presets can use record-update syntax
(`{ playerBase | conditionName = ... }`) which Elm only allows
against an identifier, not a function call.
-}
playerBase : ConditionPreset
playerBase =
    { conditionName = ""
    , customName = ""
    , note = ""
    , durationKind = DurKindManual
    , untilPhase = AtEnd
    , countdownTurnsText = "1"
    , countdownTurns = 1
    , countdownPhase = AtEnd
    , saveToEnd = Nothing
    , category = categoryPlayer
    , companions = []
    }


spellBase : ConditionPreset
spellBase =
    { playerBase | category = categorySpell }


monsterBase : ConditionPreset
monsterBase =
    { playerBase | category = categoryMonster }


itemBase : ConditionPreset
itemBase =
    { playerBase | category = categoryItem }


environmentBase : ConditionPreset
environmentBase =
    { playerBase | category = categoryEnvironment }



-- ── PLAYER CLASSES ───────────────────────────────────────────────────────


stunningStrike : ConditionPreset
stunningStrike =
    { playerBase
        | conditionName = "Stunned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


tripAttack : ConditionPreset
tripAttack =
    { playerBase
        | conditionName = "Prone"
    }


menacingAttack : ConditionPreset
menacingAttack =
    { playerBase
        | conditionName = "Frightened"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


wrathfulSmite : ConditionPreset
wrathfulSmite =
    lastsOneMinute
        { playerBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
        }


searingSmite : ConditionPreset
searingSmite =
    lastsOneMinute
        { playerBase
            | customName = "Searing Smite"
            , note = "1d6 fire, then save"
            , saveToEnd = Just (save "CON" 13 AutoRollAtBegin)
        }


turnUndead : ConditionPreset
turnUndead =
    lastsOneMinute
        { playerBase
            | conditionName = "Frightened"
            , companions = [ "Incapacitated" ]
        }


bardicInspiration : ConditionPreset
bardicInspiration =
    { playerBase
        | customName = "Inspired +d6"
        , note = "to failed D20"
    }


bless : ConditionPreset
bless =
    lastsOneMinute
        { playerBase
            | customName = "Blessed +d4"
            , note = "to atk & save"
        }


bardicInspirationD8 : ConditionPreset
bardicInspirationD8 =
    { playerBase
        | customName = "Inspired +d8"
        , note = "to failed D20"
    }


hex : ConditionPreset
hex =
    { playerBase
        | customName = "Hexed"
        , note = "disadv abil cks"
    }


huntersMark : ConditionPreset
huntersMark =
    { playerBase
        | customName = "Marked"
    }


goadingAttack : ConditionPreset
goadingAttack =
    { playerBase
        | customName = "Goaded"
        , note = "Dis atk vs others"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


staggeringSmite : ConditionPreset
staggeringSmite =
    { playerBase
        | conditionName = "Stunned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


bardicInspirationD10 : ConditionPreset
bardicInspirationD10 =
    { playerBase
        | customName = "Inspired +d10"
        , note = "to failed D20"
    }


rage : ConditionPreset
rage =
    { playerBase
        | customName = "Raging"
        , note = "Res B/P/S, Adv STR"
    }


recklessAttack : ConditionPreset
recklessAttack =
    { playerBase
        | customName = "Reckless"
        , note = "Adv STR atk & vs it"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


viciousMockery : ConditionPreset
viciousMockery =
    { playerBase
        | customName = "Mocked"
        , note = "dis next atk"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


guidance : ConditionPreset
guidance =
    lastsOneMinute
        { playerBase
            | customName = "Guidance"
            , note = "+d4 one skill, conc"
        }


sanctuary : ConditionPreset
sanctuary =
    lastsOneMinute
        { playerBase
            | customName = "Sanctuary"
            , note = "atkr WIS save"
        }


shieldOfFaith : ConditionPreset
shieldOfFaith =
    { playerBase
        | customName = "Shield of Faith"
        , note = "+2 AC, conc"
    }


wildShape : ConditionPreset
wildShape =
    { playerBase
        | customName = "Wild Shape"
        , note = "THP = Druid level"
    }


spikeGrowth : ConditionPreset
spikeGrowth =
    { playerBase
        | customName = "Spike Growth"
        , note = "2d4/5ft moved, conc"
    }


actionSurge : ConditionPreset
actionSurge =
    { playerBase
        | customName = "Surged"
        , note = "+1 action, not Magic"
        , durationKind = DurKindThisTurn
    }


disarmingAttack : ConditionPreset
disarmingAttack =
    { playerBase
        | customName = "Disarmed"
        , note = "drop wpn"
    }


pushingAttack : ConditionPreset
pushingAttack =
    { playerBase
        | customName = "Pushed"
        , note = "up to 15 ft away"
        , durationKind = DurKindThisTurn
    }


patientDefense : ConditionPreset
patientDefense =
    { playerBase
        | customName = "Dodge"
        , note = "Dis vs it, Adv DEX"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


shiningSmite : ConditionPreset
shiningSmite =
    lastsOneMinute
        { playerBase
            | customName = "Shining Smite"
            , note = "Adv vs it, conc"
            , companions = [ "Can't be Invisible" ]
        }


passWithoutTrace : ConditionPreset
passWithoutTrace =
    { playerBase
        | customName = "Pass w/o Trace"
        , note = "+10 Stealth, conc"
    }


ensnaringStrike : ConditionPreset
ensnaringStrike =
    lastsOneMinute
        { playerBase
            | conditionName = "Restrained"
            , saveToEnd = Just (save "STR" 13 AutoRollManual)
        }


sneakAttack : ConditionPreset
sneakAttack =
    { playerBase
        | customName = "Sneak Atk used"
        , note = "once per turn"
        , durationKind = DurKindThisTurn
    }


hexbladeCurse : ConditionPreset
hexbladeCurse =
    lastsOneMinute
        { playerBase
            | customName = "Hexblade's Curse"
            , note = "+PB dmg, crit 19-20"
        }


shieldSpell : ConditionPreset
shieldSpell =
    { playerBase
        | customName = "Shield"
        , note = "+5 AC"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


haste : ConditionPreset
haste =
    lastsOneMinute
        { playerBase
            | customName = "Hasted"
            , note = "+2 AC, Adv DEX, conc"
        }


heroism : ConditionPreset
heroism =
    lastsOneMinute
        { playerBase
            | customName = "Heroism"
            , note = "+mod temp HP/turn"
            , companions = [ "Immunity: Frightened" ]
        }


sapMastery : ConditionPreset
sapMastery =
    { playerBase
        | customName = "Sapped"
        , note = "Dis on next attack"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


vexMastery : ConditionPreset
vexMastery =
    { playerBase
        | customName = "Vexed"
        , note = "Adv on next attack"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


slowMastery : ConditionPreset
slowMastery =
    { playerBase
        | customName = "Slowed -10 ft"
        , note = "Not cumulative"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


grappleUnarmed : ConditionPreset
grappleUnarmed =
    { playerBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 13 AutoRollManual)
    }


cunningStrikePoison : ConditionPreset
cunningStrikePoison =
    lastsOneMinute
        { playerBase
            | conditionName = "Poisoned"
            , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
        }


openHandAddle : ConditionPreset
openHandAddle =
    { playerBase
        | customName = "Addled"
        , note = "No opportunity atks"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


helpAssist : ConditionPreset
helpAssist =
    { playerBase
        | customName = "Distracted"
        , note = "Adv: next ally atk"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


intimidatingPresence : ConditionPreset
intimidatingPresence =
    lastsOneMinute
        { playerBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 15 AutoRollAtEnd)
        }


abjureFoes : ConditionPreset
abjureFoes =
    lastsOneMinute
        { playerBase
            | customName = "Abjured"
            , note = "1 action OR move"
            , saveToEnd = Just (save "WIS" 15 AutoRollAtEnd)
            , companions = [ "Frightened" ]
        }


deviousObscure : ConditionPreset
deviousObscure =
    { playerBase
        | conditionName = "Blinded"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


deviousDaze : ConditionPreset
deviousDaze =
    { playerBase
        | customName = "Dazed"
        , note = "1 action OR move"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


deviousKnockOut : ConditionPreset
deviousKnockOut =
    lastsOneMinute
        { playerBase
            | conditionName = "Unconscious"
            , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
        }


naturesVeil : ConditionPreset
naturesVeil =
    { playerBase
        | conditionName = "Invisible"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


studiedAttacks : ConditionPreset
studiedAttacks =
    { playerBase
        | customName = "Studied"
        , note = "Adv on next attack"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


hamstringBlow : ConditionPreset
hamstringBlow =
    { playerBase
        | customName = "Hamstrung -15 ft"
        , note = "One at a time"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


staggeringBlow : ConditionPreset
staggeringBlow =
    { playerBase
        | customName = "Staggered"
        , note = "Dis next save; no OA"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


sunderingBlow : ConditionPreset
sunderingBlow =
    { playerBase
        | customName = "Sundering Blow +5"
        , note = "Next atk vs it +5"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


mindlessRage : ConditionPreset
mindlessRage =
    { playerBase
        | customName = "Immune: Charm/Fear"
        , note = "While raging"
    }


auraOfCourage : ConditionPreset
auraOfCourage =
    { playerBase
        | customName = "Immune: Frightened"
        , note = "While in aura"
    }


auraOfDevotion : ConditionPreset
auraOfDevotion =
    { playerBase
        | customName = "Immune: Charmed"
        , note = "While in aura"
    }


frostsChill : ConditionPreset
frostsChill =
    { playerBase
        | customName = "Chilled -10 ft"
        , note = "To your next turn"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


hurlThroughHell : ConditionPreset
hurlThroughHell =
    { playerBase
        | conditionName = "Incapacitated"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
        , companions = [ "Gone to the Hells" ]
    }


innateSorcery : ConditionPreset
innateSorcery =
    lastsOneMinute
        { playerBase
            | customName = "Innate Sorcery"
            , note = "+1 DC, adv spell atk"
        }


sacredWeapon : ConditionPreset
sacredWeapon =
    { playerBase
        | customName = "Sacred Weapon"
        , note = "+CHA hit, radiant"
    }


heroicInspiration : ConditionPreset
heroicInspiration =
    { playerBase
        | customName = "Heroic Inspiration"
        , note = "Reroll any one die"
    }


auraOfProtection : ConditionPreset
auraOfProtection =
    { playerBase
        | customName = "Aura of Protection"
        , note = "+CHA to saves, 10ft"
    }


stunningStrikeSaved : ConditionPreset
stunningStrikeSaved =
    { playerBase
        | customName = "Rattled"
        , note = "Speed half; adv atk"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


superiorDefense : ConditionPreset
superiorDefense =
    lastsOneMinute
        { playerBase
            | customName = "Superior Defense"
            , note = "Resist all but Force"
        }


quiveringPalm : ConditionPreset
quiveringPalm =
    { playerBase
        | customName = "Quivering Palm"
        , note = "10d12 when released"
        , saveToEnd = Just (save "CON" 15 AutoRollManual)
    }


largeForm : ConditionPreset
largeForm =
    { playerBase
        | customName = "Large Form"
        , note = "Adv STR, +10 ft"
    }



-- ── SPELL EFFECTS ────────────────────────────────────────────────────────


bane : ConditionPreset
bane =
    lastsOneMinute
        { spellBase
            | customName = "Bane −d4"
            , note = "attacks & saves"
        }


holdPerson : ConditionPreset
holdPerson =
    lastsOneMinute
        { spellBase
            | conditionName = "Paralyzed"
            , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
        }


holdMonster : ConditionPreset
holdMonster =
    lastsOneMinute
        { spellBase
            | conditionName = "Paralyzed"
            , saveToEnd = Just (save "WIS" 14 AutoRollAtEnd)
        }


sleep : ConditionPreset
sleep =
    lastsOneMinute
        { spellBase
            | conditionName = "Incapacitated"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollAtEnd
                        , failBecomesText = "Unconscious"
                    }
        }


charmPerson : ConditionPreset
charmPerson =
    { spellBase
        | conditionName = "Charmed"
    }


command : ConditionPreset
command =
    { spellBase
        | customName = "Commanded"
        , note = "Cmd"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


causeFear : ConditionPreset
causeFear =
    lastsOneMinute
        { spellBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
        }


fear : ConditionPreset
fear =
    lastsOneMinute
        { spellBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 14 AutoRollAskAtEnd)
        }


hypnoticPattern : ConditionPreset
hypnoticPattern =
    lastsOneMinute
        { spellBase
            | conditionName = "Charmed"
            , companions = [ "Incapacitated", "Speed 0" ]
        }


hideousLaughter : ConditionPreset
hideousLaughter =
    lastsOneMinute
        { spellBase
            | conditionName = "Incapacitated"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollAtEnd
                        , onDamage = Encounter.RollOnDamageWithAdvantage
                    }
            , companions = [ "Prone" ]
        }


suggestion : ConditionPreset
suggestion =
    { spellBase
        | conditionName = "Charmed"
    }


slow : ConditionPreset
slow =
    lastsOneMinute
        { spellBase
            | customName = "Slowed"
            , note = "−2 AC/DEX, no reacts"
            , saveToEnd = Just (save "WIS" 14 AutoRollAtEnd)
        }


web : ConditionPreset
web =
    { spellBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 13 AutoRollManual)
    }


entangle : ConditionPreset
entangle =
    lastsOneMinute
        { spellBase
            | conditionName = "Restrained"
            , saveToEnd = Just (save "STR" 13 AutoRollManual)
        }


blackTentacles : ConditionPreset
blackTentacles =
    lastsOneMinute
        { spellBase
            | conditionName = "Restrained"
            , saveToEnd = Just (save "STR" 14 AutoRollManual)
        }


faerieFire : ConditionPreset
faerieFire =
    lastsOneMinute
        { spellBase
            | customName = "Faerie Fire"
            , note = "Adv vs it, conc"
            , companions = [ "Can't be Invisible" ]
        }


blindness : ConditionPreset
blindness =
    lastsOneMinute
        { spellBase
            | conditionName = "Blinded"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
        }


banishment : ConditionPreset
banishment =
    lastsOneMinute
        { spellBase
            | customName = "Banished"
            , note = "Fiend etc. stay gone"
            , companions = [ "Incapacitated" ]
        }


stinkingCloud : ConditionPreset
stinkingCloud =
    { spellBase
        | conditionName = "Poisoned"
        , durationKind = DurKindThisTurn
    }


greaterInvisibility : ConditionPreset
greaterInvisibility =
    lastsOneMinute
        { spellBase
            | conditionName = "Invisible"
        }


invisibilitySpell : ConditionPreset
invisibilitySpell =
    { spellBase
        | conditionName = "Invisible"
    }


blur : ConditionPreset
blur =
    lastsOneMinute
        { spellBase
            | customName = "Blur: Atk Disadv"
            , note = "Not vs Blindsight"
        }


bestowCurseDisadv : ConditionPreset
bestowCurseDisadv =
    lastsOneMinute
        { spellBase
            | customName = "Cursed: Disadv"
            , note = "1 chosen ability"
        }


bestowCurseAttack : ConditionPreset
bestowCurseAttack =
    lastsOneMinute
        { spellBase
            | customName = "Cursed: Atk You"
            , note = "Disadv vs caster"
        }


bestowCurseDodge : ConditionPreset
bestowCurseDodge =
    lastsOneMinute
        { spellBase
            | customName = "Cursed: Dodge"
            , note = "WIS save or Dodge"
        }


bestowCurseNecrotic : ConditionPreset
bestowCurseNecrotic =
    lastsOneMinute
        { spellBase
            | customName = "Cursed: +1d8 Necr"
            , note = "+1d8 from caster"
        }


confusion : ConditionPreset
confusion =
    lastsOneMinute
        { spellBase
            | customName = "Confused"
            , note = "Roll 1d10 behavior"
            , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
        }


charmMonster : ConditionPreset
charmMonster =
    { spellBase
        | conditionName = "Charmed"
    }


dominatePerson : ConditionPreset
dominatePerson =
    lastsOneMinute
        { spellBase
            | conditionName = "Charmed"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollManual
                        , onDamage = Encounter.RollOnDamage
                    }
            , companions = [ "Dominated" ]
        }


phantasmalKiller : ConditionPreset
phantasmalKiller =
    lastsOneMinute
        { spellBase
            | customName = "Nightmare"
            , note = "Disadv: checks/atk"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollAtEnd
                        , failDamageText = "4d10"
                    }
        }


polymorph : ConditionPreset
polymorph =
    { spellBase
        | customName = "Polymorphed"
        , note = "Beast stats; temp HP"
    }


dominateBeast : ConditionPreset
dominateBeast =
    lastsOneMinute
        { spellBase
            | conditionName = "Charmed"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollManual
                        , onDamage = Encounter.RollOnDamage
                    }
            , companions = [ "Dominated" ]
        }


guidingBolt : ConditionPreset
guidingBolt =
    { spellBase
        | customName = "Atk vs has Adv"
        , note = "Next attack only"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


rayOfSickness : ConditionPreset
rayOfSickness =
    { spellBase
        | conditionName = "Poisoned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


colorSpray : ConditionPreset
colorSpray =
    { spellBase
        | conditionName = "Blinded"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


protectionEvilGood : ConditionPreset
protectionEvilGood =
    { spellBase
        | customName = "Prot: Evil & Good"
        , note = "vs 6 creature types"
        , companions = [ "Immune: Charm/Fear" ]
    }


shockingGrasp : ConditionPreset
shockingGrasp =
    { spellBase
        | customName = "No Opp. Attacks"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


rayOfFrost : ConditionPreset
rayOfFrost =
    { spellBase
        | customName = "Speed -10 ft"
        , note = "Caster's next turn"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


chillTouch : ConditionPreset
chillTouch =
    { spellBase
        | customName = "No HP Regain"
        , note = "Caster's next turn"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


enlarge : ConditionPreset
enlarge =
    lastsOneMinute
        { spellBase
            | customName = "Enlarged"
            , note = "+1 size, +1d4 dmg"
        }


reduce : ConditionPreset
reduce =
    lastsOneMinute
        { spellBase
            | customName = "Reduced"
            , note = "-1 size, -1d4 dmg"
        }


enhanceAbility : ConditionPreset
enhanceAbility =
    { spellBase
        | customName = "Adv: Ability Chks"
        , note = "One chosen ability"
    }


rayOfEnfeeblement : ConditionPreset
rayOfEnfeeblement =
    lastsOneMinute
        { spellBase
            | customName = "Enfeebled"
            , note = "-1d8 dmg, STR disad"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
        }


heatMetal : ConditionPreset
heatMetal =
    lastsOneMinute
        { spellBase
            | customName = "Heat Metal"
            , note = "Drop it or disadv"
            , saveToEnd = Just (save "CON" 13 AutoRollAskAtEnd)
        }


mirrorImage : ConditionPreset
mirrorImage =
    lastsOneMinute
        { spellBase
            | customName = "Mirror Image x3"
            , note = "d6 per image, 3+"
        }


levitate : ConditionPreset
levitate =
    { spellBase
        | customName = "Levitating"
        , note = "Move by pushing only"
    }


wardingBond : ConditionPreset
wardingBond =
    { spellBase
        | customName = "Warding Bond"
        , note = "+1 AC/save, resist"
    }


calmEmotions : ConditionPreset
calmEmotions =
    lastsOneMinute
        { spellBase
            | customName = "Immune: Charm/Fear"
            , note = "Suppresses existing"
        }


calmEmotionsCalmed : ConditionPreset
calmEmotionsCalmed =
    lastsOneMinute
        { spellBase
            | customName = "Calmed"
            , note = "Indifferent"
        }


beaconOfHope : ConditionPreset
beaconOfHope =
    lastsOneMinute
        { spellBase
            | customName = "Beacon of Hope"
            , note = "Max heal, adv WIS"
        }


protectionAcid : ConditionPreset
protectionAcid =
    { spellBase
        | customName = "Resist: Acid"
    }


protectionCold : ConditionPreset
protectionCold =
    { spellBase
        | customName = "Resist: Cold"
    }


protectionFire : ConditionPreset
protectionFire =
    { spellBase
        | customName = "Resist: Fire"
    }


protectionLightning : ConditionPreset
protectionLightning =
    { spellBase
        | customName = "Resist: Lightning"
    }


protectionThunder : ConditionPreset
protectionThunder =
    { spellBase
        | customName = "Resist: Thunder"
    }


flySpell : ConditionPreset
flySpell =
    { spellBase
        | customName = "Flying 60 ft"
        , note = "Falls when it ends"
    }


gaseousForm : ConditionPreset
gaseousForm =
    { spellBase
        | customName = "Gaseous Form"
        , note = "No attacks or spells"
        , companions = [ "Resist: B/P/S" ]
    }


stoneskin : ConditionPreset
stoneskin =
    { spellBase
        | customName = "Resist: B/P/S"
        , note = "Nonmagical only"
    }


deathWard : ConditionPreset
deathWard =
    { spellBase
        | customName = "Death Ward"
        , note = "Drops to 1 HP once"
    }


freedomOfMovement : ConditionPreset
freedomOfMovement =
    { spellBase
        | customName = "Free Movement"
        , note = "No difficult terr"
        , companions = [ "Immune: Restrained" ]
    }


fireShieldWarm : ConditionPreset
fireShieldWarm =
    { spellBase
        | customName = "Fire Shield: Warm"
        , note = "2d8 to melee hitter"
    }


fireShieldChill : ConditionPreset
fireShieldChill =
    { spellBase
        | customName = "Fire Shield: Chill"
        , note = "2d8 to melee hitter"
    }


resilientSphere : ConditionPreset
resilientSphere =
    lastsOneMinute
        { spellBase
            | customName = "In Sphere"
            , note = "Can roll it at 1/2"
            , companions = [ "Incapacitated" ]
        }


compulsion : ConditionPreset
compulsion =
    lastsOneMinute
        { spellBase
            | conditionName = "Charmed"
            , saveToEnd = Just (save "WIS" 13 AutoRollAskAtEnd)
            , companions = [ "Forced to move" ]
        }


contagion : ConditionPreset
contagion =
    { spellBase
        | customName = "Contagion"
        , note = "3 fails = 7 days"
        , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
        , companions = [ "Poisoned" ]
    }


geas : ConditionPreset
geas =
    { spellBase
        | customName = "Geas"
        , note = "5d10 psy if defied"
        , companions = [ "Charmed" ]
    }


eyebitePanicked : ConditionPreset
eyebitePanicked =
    lastsOneMinute
        { spellBase
            | conditionName = "Frightened"
        }


eyebiteAsleep : ConditionPreset
eyebiteAsleep =
    lastsOneMinute
        { spellBase
            | conditionName = "Unconscious"
        }


eyebiteSickened : ConditionPreset
eyebiteSickened =
    lastsOneMinute
        { spellBase
            | conditionName = "Poisoned"
        }


fleshToStone : ConditionPreset
fleshToStone =
    lastsOneMinute
        { spellBase
            | conditionName = "Restrained"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "CON"
                        , dc = 13
                        , dcText = "13"
                        , autoRoll = AutoRollAtEnd
                        , failBecomesText = "Petrified"
                    }
        }


irresistibleDance : ConditionPreset
irresistibleDance =
    lastsOneMinute
        { spellBase
            | conditionName = "Charmed"
            , saveToEnd = Just (save "WIS" 13 AutoRollAtBegin)
            , companions = [ "Dancing" ]
        }


powerWordStun : ConditionPreset
powerWordStun =
    { spellBase
        | conditionName = "Stunned"
        , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
    }



-- ── MONSTER ABILITIES ────────────────────────────────────────────────────


petrifyingGaze : ConditionPreset
petrifyingGaze =
    { monsterBase
        | conditionName = "Restrained"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 13
                    , dcText = "13"
                    , autoRoll = AutoRollAtEnd
                    , failBecomesText = "Petrified"
                }
    }


mindBlast : ConditionPreset
mindBlast =
    { monsterBase
        | conditionName = "Stunned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


frightfulPresence : ConditionPreset
frightfulPresence =
    lastsOneMinute
        { monsterBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 18 AutoRollAskAtEnd)
        }


horrificVisage : ConditionPreset
horrificVisage =
    { monsterBase
        | conditionName = "Frightened"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


ghoulClaw : ConditionPreset
ghoulClaw =
    { monsterBase
        | conditionName = "Paralyzed"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


vampireCharm : ConditionPreset
vampireCharm =
    { monsterBase
        | conditionName = "Charmed"
    }


luringSong : ConditionPreset
luringSong =
    { monsterBase
        | conditionName = "Charmed"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "WIS"
                    , dc = 11
                    , dcText = "11"
                    , autoRoll = AutoRollAtEnd
                    , onDamage = Encounter.AskOnDamage
                }
        , companions = [ "Incapacitated" ]
    }


giantSpiderWeb : ConditionPreset
giantSpiderWeb =
    { monsterBase
        | conditionName = "Restrained"
    }


roperGrab : ConditionPreset
roperGrab =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 14 AutoRollManual)
        , companions = [ "Poisoned" ]
    }


beholderSleepRay : ConditionPreset
beholderSleepRay =
    lastsOneMinute
        { monsterBase
            | conditionName = "Unconscious"
        }


carrionCrawler : ConditionPreset
carrionCrawler =
    lastsOneMinute
        { monsterBase
            | conditionName = "Poisoned"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
            , companions = [ "Paralyzed" ]
        }


mummyRot : ConditionPreset
mummyRot =
    { monsterBase
        | customName = "Mummy Rot"
        , note = "can't regain HP"
    }


grappledEscape : ConditionPreset
grappledEscape =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 14 AutoRollManual)
    }


constricted : ConditionPreset
constricted =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 16 AutoRollManual)
        , companions = [ "Restrained" ]
    }


swallowed : ConditionPreset
swallowed =
    { monsterBase
        | customName = "Swallowed"
        , note = "Acid 5d6/turn start"
        , saveToEnd = Just (save "STR" 19 AutoRollManual)
        , companions = [ "Blinded", "Restrained" ]
    }


venomousBite : ConditionPreset
venomousBite =
    { monsterBase
        | conditionName = "Poisoned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


basiliskGaze : ConditionPreset
basiliskGaze =
    { monsterBase
        | conditionName = "Restrained"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 12
                    , dcText = "12"
                    , autoRoll = AutoRollAtEnd
                    , failBecomesText = "Petrified"
                }
    }


frightenedSaveEnds : ConditionPreset
frightenedSaveEnds =
    lastsOneMinute
        { monsterBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 12 AutoRollAtEnd)
        }


frightenedOneRound : ConditionPreset
frightenedOneRound =
    { monsterBase
        | conditionName = "Frightened"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


chuulTentacles : ConditionPreset
chuulTentacles =
    lastsOneMinute
        { monsterBase
            | conditionName = "Poisoned"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
            , companions = [ "Paralyzed" ]
        }


brassSleepBreath : ConditionPreset
brassSleepBreath =
    { monsterBase
        | conditionName = "Incapacitated"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 11
                    , dcText = "11"
                    , autoRoll = AutoRollAtEnd
                    , failBecomesText = "Unconscious"
                }
    }


silverParalyzingBreath : ConditionPreset
silverParalyzingBreath =
    { monsterBase
        | conditionName = "Incapacitated"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 13
                    , dcText = "13"
                    , autoRoll = AutoRollAtEnd
                    , failBecomesText = "Paralyzed"
                }
    }


lifeDrained : ConditionPreset
lifeDrained =
    { monsterBase
        | customName = "Life Drained"
        , note = "HP max reduced"
    }


lichParalyzingTouch : ConditionPreset
lichParalyzingTouch =
    { monsterBase
        | conditionName = "Paralyzed"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


ghostPossession : ConditionPreset
ghostPossession =
    { monsterBase
        | customName = "Possessed"
        , note = "CHA 13 to resist"
        , companions = [ "Incapacitated" ]
    }


abolethEnslave : ConditionPreset
abolethEnslave =
    { monsterBase
        | conditionName = "Charmed"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "WIS"
                    , dc = 16
                    , dcText = "16"
                    , autoRoll = AutoRollManual
                    , onDamage = Encounter.RollOnDamage
                }
    }


entanglingRope : ConditionPreset
entanglingRope =
    { monsterBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 16 AutoRollManual)
    }


cubeEngulf : ConditionPreset
cubeEngulf =
    { monsterBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 12 AutoRollManual)
        , companions = [ "Engulfed" ]
    }


shamblingEngulf : ConditionPreset
shamblingEngulf =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 14 AutoRollManual)
        , companions = [ "Blinded", "Restrained" ]
    }


rugSmother : ConditionPreset
rugSmother =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 13 AutoRollManual)
        , companions = [ "Blinded", "Restrained", "Suffocating" ]
    }


waterWhelm : ConditionPreset
waterWhelm =
    { monsterBase
        | conditionName = "Grappled"
        , saveToEnd = Just (save "STR" 14 AutoRollManual)
        , companions = [ "Restrained", "Suffocating" ]
    }


cloakerAttach : ConditionPreset
cloakerAttach =
    { monsterBase
        | conditionName = "Blinded"
        , saveToEnd = Just (save "STR" 14 AutoRollManual)
        , companions = [ "Attached" ]
    }


lycanthropy : ConditionPreset
lycanthropy =
    { monsterBase
        | customName = "Lycanthropy"
        , note = "Turns at 0 HP"
    }


vrockSpores : ConditionPreset
vrockSpores =
    { monsterBase
        | conditionName = "Poisoned"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 15
                    , dcText = "15"
                    , autoRoll = AutoRollAtEnd
                    , failDamageText = "1d10"
                }
    }


weightOfYears : ConditionPreset
weightOfYears =
    { monsterBase
        | conditionName = "Exhaustion"
    }


venomComa : ConditionPreset
venomComa =
    { monsterBase
        | conditionName = "Poisoned"
        , companions = [ "Paralyzed" ]
    }


pseudodragonSting : ConditionPreset
pseudodragonSting =
    { monsterBase
        | conditionName = "Poisoned"
        , companions = [ "Unconscious" ]
    }


mummyLordGlare : ConditionPreset
mummyLordGlare =
    { monsterBase
        | conditionName = "Paralyzed"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


lamiaTouch : ConditionPreset
lamiaTouch =
    { monsterBase
        | conditionName = "Charmed"
        , companions = [ "Poisoned" ]
    }


infernalWound : ConditionPreset
infernalWound =
    { monsterBase
        | customName = "Infernal Wound"
        , note = "Lose 1d10 at start"
        , durationKind = DurKindCountdown
        , countdownTurnsText = "10"
        , countdownTurns = 10
        , countdownPhase = AtBegin
    }


otyughDisease : ConditionPreset
otyughDisease =
    { monsterBase
        | conditionName = "Poisoned"
        , companions = [ "Diseased" ]
    }


vrockScreech : ConditionPreset
vrockScreech =
    { monsterBase
        | conditionName = "Stunned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


blindedOneRound : ConditionPreset
blindedOneRound =
    { monsterBase
        | conditionName = "Blinded"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


solarGaze : ConditionPreset
solarGaze =
    lastsOneMinute
        { monsterBase
            | conditionName = "Blinded"
        }


incapacitatedOneRound : ConditionPreset
incapacitatedOneRound =
    { monsterBase
        | conditionName = "Incapacitated"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


charmedOneRound : ConditionPreset
charmedOneRound =
    { monsterBase
        | conditionName = "Charmed"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


restlessCurse : ConditionPreset
restlessCurse =
    { monsterBase
        | customName = "No Rest Benefit"
        , note = "24h or till it dies"
    }


abolethMucus : ConditionPreset
abolethMucus =
    { monsterBase
        | customName = "Slimy Curse"
        , note = "No HP regain on land"
    }


incubusNightmare : ConditionPreset
incubusNightmare =
    { monsterBase
        | conditionName = "Unconscious"
    }


poisonNoHeal : ConditionPreset
poisonNoHeal =
    { monsterBase
        | customName = "Poison: No Heal"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
        , companions = [ "Poisoned" ]
    }


deafenedOneRound : ConditionPreset
deafenedOneRound =
    { monsterBase
        | conditionName = "Deafened"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }



-- ── ITEMS ────────────────────────────────────────────────────────────────


wandOfParalysis : ConditionPreset
wandOfParalysis =
    lastsOneMinute
        { itemBase
            | conditionName = "Paralyzed"
            , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
        }


wandOfFear : ConditionPreset
wandOfFear =
    lastsOneMinute
        { itemBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 15 AutoRollAskAtEnd)
        }


staffOfCharming : ConditionPreset
staffOfCharming =
    { itemBase
        | conditionName = "Charmed"
    }


potionOfInvisibility : ConditionPreset
potionOfInvisibility =
    { itemBase
        | conditionName = "Invisible"
    }


dustOfSneezingAndChoking : ConditionPreset
dustOfSneezingAndChoking =
    { itemBase
        | conditionName = "Incapacitated"
        , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
        , companions = [ "Suffocating" ]
    }


{-| The potion's own name on the chip keeps it apart from the
Heroism spell's, which a creature could carry at the same time.
-}
potionOfHeroism : ConditionPreset
potionOfHeroism =
    { itemBase
        | customName = "Potion of Heroism"
        , note = "10 temp HP, 1 hr"
        , companions = [ "Blessed +d4" ]
    }


potionOfGiantStrength : ConditionPreset
potionOfGiantStrength =
    { itemBase
        | customName = "Giant STR"
        , note = "STR 21-29 for 1 hr"
    }


potionOfClimbing : ConditionPreset
potionOfClimbing =
    { itemBase
        | customName = "Climbing"
        , note = "Climb speed, 1 hr"
    }


dustOfDisappearance : ConditionPreset
dustOfDisappearance =
    { itemBase
        | conditionName = "Invisible"
    }


net : ConditionPreset
net =
    { itemBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 10 AutoRollManual)
    }


wandOfBinding : ConditionPreset
wandOfBinding =
    lastsOneMinute
        { itemBase
            | conditionName = "Paralyzed"
            , saveToEnd = Just (save "WIS" 17 AutoRollAtEnd)
        }


daggerOfVenom : ConditionPreset
daggerOfVenom =
    lastsOneMinute
        { itemBase
            | conditionName = "Poisoned"
        }


maceOfTerror : ConditionPreset
maceOfTerror =
    lastsOneMinute
        { itemBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 15 AutoRollAtEnd)
            , companions = [ "Must flee & Dash" ]
        }


gemOfBrightness : ConditionPreset
gemOfBrightness =
    lastsOneMinute
        { itemBase
            | conditionName = "Blinded"
            , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
        }


hornOfBlasting : ConditionPreset
hornOfBlasting =
    lastsOneMinute
        { itemBase
            | conditionName = "Deafened"
        }


rodParalyze : ConditionPreset
rodParalyze =
    lastsOneMinute
        { itemBase
            | conditionName = "Paralyzed"
            , saveToEnd = Just (save "CON" 17 AutoRollAtEnd)
        }


rodTerrify : ConditionPreset
rodTerrify =
    lastsOneMinute
        { itemBase
            | conditionName = "Frightened"
            , saveToEnd = Just (save "WIS" 17 AutoRollAtEnd)
        }


ropeOfEntanglement : ConditionPreset
ropeOfEntanglement =
    { itemBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 15 AutoRollManual)
    }


ironBands : ConditionPreset
ironBands =
    { itemBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 20 AutoRollManual)
    }


manacles : ConditionPreset
manacles =
    { itemBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "DEX" 20 AutoRollManual)
        , companions = [ "Dis: attacks" ]
    }


huntingTrap : ConditionPreset
huntingTrap =
    { itemBase
        | customName = "Trapped"
        , note = "Speed 0; chain 3 ft"
        , saveToEnd = Just (save "STR" 13 AutoRollManual)
    }


caltrops : ConditionPreset
caltrops =
    { itemBase
        | customName = "Speed 0"
        , note = "Caltrops"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtBegin
    }


ringOfInvisibility : ConditionPreset
ringOfInvisibility =
    { itemBase
        | conditionName = "Invisible"
    }


cloakOfDisplacement : ConditionPreset
cloakOfDisplacement =
    { itemBase
        | customName = "Displaced"
        , note = "Dis: attacks vs you"
    }


swordOfWounding : ConditionPreset
swordOfWounding =
    { itemBase
        | customName = "No Healing"
        , note = "Can't regain HP"
        , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
    }


swordOfSharpness : ConditionPreset
swordOfSharpness =
    { itemBase
        | conditionName = "Exhaustion"
    }


berserkerAxe : ConditionPreset
berserkerAxe =
    { itemBase
        | customName = "Berserk"
        , note = "Nearest foe is enemy"
    }


hammerOfThunderbolts : ConditionPreset
hammerOfThunderbolts =
    { itemBase
        | conditionName = "Stunned"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


philterOfLove : ConditionPreset
philterOfLove =
    { itemBase
        | conditionName = "Charmed"
    }


potionOfPoison : ConditionPreset
potionOfPoison =
    { itemBase
        | conditionName = "Poisoned"
    }


potionOfFlying : ConditionPreset
potionOfFlying =
    { itemBase
        | customName = "Flying"
        , note = "Fly = Speed, 1 hr"
    }


wingedBoots : ConditionPreset
wingedBoots =
    { itemBase
        | customName = "Flying"
        , note = "Fly 30 ft, 1 hour"
    }


potionGaseousForm : ConditionPreset
potionGaseousForm =
    { itemBase
        | customName = "Gaseous Form"
        , note = "Fly 10, hover, 1 hr"
        , companions = [ "Resist: B/P/S" ]
    }


potionOfGrowth : ConditionPreset
potionOfGrowth =
    { itemBase
        | customName = "Enlarged"
        , note = "10 min; +1 size"
    }


potionOfDiminution : ConditionPreset
potionOfDiminution =
    { itemBase
        | customName = "Reduced"
        , note = "1d4 hr, -1 size"
    }


potionOfInvulnerability : ConditionPreset
potionOfInvulnerability =
    lastsOneMinute
        { itemBase
            | customName = "Resist: All"
        }


potionOfResistance : ConditionPreset
potionOfResistance =
    { itemBase
        | customName = "Resistance"
        , note = "GM picks type, 1hr"
    }


oilOfSlipperiness : ConditionPreset
oilOfSlipperiness =
    { itemBase
        | customName = "Free Action"
        , note = "No Para/Restr/slow"
    }


ringOfFreeAction : ConditionPreset
ringOfFreeAction =
    { itemBase
        | customName = "Free Action"
        , note = "No Para/Restr/slow"
    }


bootsOfSpeed : ConditionPreset
bootsOfSpeed =
    { itemBase
        | customName = "Speed Doubled"
        , note = "Dis: OA vs you"
    }


slippersSpiderClimb : ConditionPreset
slippersSpiderClimb =
    { itemBase
        | customName = "Spider Climb"
        , note = "Climb Spd = Speed"
    }


ringOfRegeneration : ConditionPreset
ringOfRegeneration =
    { itemBase
        | customName = "Regenerating"
        , note = "1d6 HP/10 min"
    }


rodOfRulership : ConditionPreset
rodOfRulership =
    { itemBase
        | conditionName = "Charmed"
    }


sentientItemControl : ConditionPreset
sentientItemControl =
    { itemBase
        | conditionName = "Charmed"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CHA"
                    , dc = 14
                    , dcText = "14"
                    , autoRoll = AutoRollManual
                    , onDamage = Encounter.RollOnDamage
                }
    }


tridentFishCommand : ConditionPreset
tridentFishCommand =
    lastsOneMinute
        { itemBase
            | conditionName = "Charmed"
            , saveToEnd =
                Just
                    { emptySave
                        | ability = "WIS"
                        , dc = 15
                        , dcText = "15"
                        , autoRoll = AutoRollAtEnd
                        , onDamage = Encounter.RollOnDamage
                    }
        }


shieldMissileAttraction : ConditionPreset
shieldMissileAttraction =
    { itemBase
        | customName = "Missile Magnet"
        , note = "Ranged hits redirect"
    }


periaptPoison : ConditionPreset
periaptPoison =
    { itemBase
        | customName = "Immunity: Poisoned"
    }


crawlerMucus : ConditionPreset
crawlerMucus =
    lastsOneMinute
        { itemBase
            | conditionName = "Poisoned"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
            , companions = [ "Paralyzed" ]
        }


malice : ConditionPreset
malice =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Blinded" ]
    }


essenceOfEther : ConditionPreset
essenceOfEther =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Unconscious" ]
    }


oilOfTaggit : ConditionPreset
oilOfTaggit =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Unconscious" ]
    }


spidersSting : ConditionPreset
spidersSting =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Unconscious" ]
    }


assassinsBlood : ConditionPreset
assassinsBlood =
    { itemBase
        | conditionName = "Poisoned"
    }


truthSerum : ConditionPreset
truthSerum =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Can't lie" ]
    }


torpor : ConditionPreset
torpor =
    { itemBase
        | conditionName = "Poisoned"
        , companions = [ "Speed halved" ]
    }


paleTincture : ConditionPreset
paleTincture =
    { itemBase
        | conditionName = "Poisoned"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 16
                    , dcText = "16"
                    , autoRoll = AutoRollManual
                    , failDamageText = "1d6"
                }
        , companions = [ "Can't regain HP" ]
    }


burntOthurFumes : ConditionPreset
burntOthurFumes =
    { itemBase
        | customName = "Burnt Othur"
        , note = "3 saves to end"
        , saveToEnd =
            Just
                { emptySave
                    | ability = "CON"
                    , dc = 13
                    , dcText = "13"
                    , autoRoll = AutoRollAtBegin
                    , failDamageText = "1d6"
                }
    }



-- ── ENVIRONMENT ──────────────────────────────────────────────────────────


quicksand : ConditionPreset
quicksand =
    { environmentBase
        | conditionName = "Restrained"
        , saveToEnd = Just (save "STR" 10 AutoRollManual)
    }


slipperySurface : ConditionPreset
slipperySurface =
    { environmentBase
        | conditionName = "Prone"
    }


heavyObscurement : ConditionPreset
heavyObscurement =
    { environmentBase
        | conditionName = "Blinded"
    }


drowning : ConditionPreset
drowning =
    { environmentBase
        | customName = "Suffocating"
        , note = "+1 Exh at turn end"
    }


onFire : ConditionPreset
onFire =
    { environmentBase
        | customName = "Burning"
        , note = "1d4 fire, start turn"
    }


extremeCold : ConditionPreset
extremeCold =
    { environmentBase
        | customName = "Extreme Cold"
        , note = "CON 10/hr or +1 Exh"
    }


extremeHeat : ConditionPreset
extremeHeat =
    { environmentBase
        | customName = "Extreme Heat"
        , note = "CON 5+1/hr or +1 Exh"
    }


pitTrap : ConditionPreset
pitTrap =
    { environmentBase
        | customName = "In Pit"
        , note = "10ft; needs climbing"
        , companions = [ "Prone" ]
    }


extendedTravel : ConditionPreset
extendedTravel =
    { environmentBase
        | conditionName = "Exhaustion"
        , companions = [ "Extended Travel" ]
    }


dehydration : ConditionPreset
dehydration =
    { environmentBase
        | conditionName = "Exhaustion"
        , companions = [ "Dehydrated" ]
    }


malnutrition : ConditionPreset
malnutrition =
    { environmentBase
        | conditionName = "Exhaustion"
        , companions = [ "Malnourished" ]
    }


frigidWater : ConditionPreset
frigidWater =
    { environmentBase
        | customName = "Frigid Water"
        , note = "CON 10/min or +1 Exh"
    }


deepWater : ConditionPreset
deepWater =
    { environmentBase
        | customName = "Deep Water"
        , note = "CON 10/hr or +1 Exh"
    }


underwater : ConditionPreset
underwater =
    { environmentBase
        | customName = "Underwater"
        , note = "Disadv melee+ranged"
    }


strongWind : ConditionPreset
strongWind =
    { environmentBase
        | customName = "Strong Wind"
        , note = "Disadv ranged atk"
    }


heavyPrecipitation : ConditionPreset
heavyPrecipitation =
    { environmentBase
        | customName = "Heavy Rain/Snow"
        , note = "Disadv WIS (Percep)"
    }


highAltitude : ConditionPreset
highAltitude =
    { environmentBase
        | customName = "High Altitude"
        , note = "1 travel hr counts 2"
    }


poisonedNeedle : ConditionPreset
poisonedNeedle =
    { environmentBase
        | conditionName = "Poisoned"
    }


collapsingRoof : ConditionPreset
collapsingRoof =
    { environmentBase
        | customName = "In Rubble"
        , note = "Difficult Terrain"
    }


sightRot : ConditionPreset
sightRot =
    { environmentBase
        | conditionName = "Blinded"
        , companions = [ "Sight Rot" ]
    }


cackleFever : ConditionPreset
cackleFever =
    { environmentBase
        | conditionName = "Exhaustion"
        , companions = [ "Cackle Fever" ]
    }


cacklingFit : ConditionPreset
cacklingFit =
    lastsOneMinute
        { environmentBase
            | conditionName = "Incapacitated"
            , saveToEnd = Just (save "CON" 13 AutoRollAtEnd)
        }


sewerPlague : ConditionPreset
sewerPlague =
    { environmentBase
        | conditionName = "Exhaustion"
        , companions = [ "Sewer Plague", "No rest recovery" ]
    }


demonicPossession : ConditionPreset
demonicPossession =
    { environmentBase
        | customName = "Demon Possessed"
        , note = "d20 1: demon acts"
        , saveToEnd = Just (save "CHA" 15 AutoRollAtEnd)
    }


shortTermStress : ConditionPreset
shortTermStress =
    { environmentBase
        | conditionName = "Frightened"
    }


longTermStress : ConditionPreset
longTermStress =
    { environmentBase
        | customName = "Mental Stress"
        , note = "Disadv some checks"
    }


holdingBreath : ConditionPreset
holdingBreath =
    { environmentBase
        | customName = "Holding Breath"
        , note = "1+CON mod minutes"
    }
