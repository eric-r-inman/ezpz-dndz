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
        [ -- Player Classes (34)
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

        -- Spell Effects (20)
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

        -- Monster Abilities (12)
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

        -- Items (10)
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

        -- Environment (8)
        , ( "Quicksand", quicksand )
        , ( "Slippery Surface", slipperySurface )
        , ( "Heavy Obscurement", heavyObscurement )
        , ( "Drowning", drowning )
        , ( "On Fire", onFire )
        , ( "Extreme Cold", extremeCold )
        , ( "Extreme Heat", extremeHeat )
        , ( "Pit Trap", pitTrap )
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
        , note = "on failed D20 Test"
    }


bless : ConditionPreset
bless =
    lastsOneMinute
        { playerBase
            | customName = "Bless +d4"
            , note = "atk & saves, conc"
        }


bardicInspirationD8 : ConditionPreset
bardicInspirationD8 =
    { playerBase
        | customName = "Inspired +d8"
        , note = "on failed D20 Test"
    }


hex : ConditionPreset
hex =
    { playerBase
        | customName = "Hexed"
        , note = "+1d6, dis checks"
    }


huntersMark : ConditionPreset
huntersMark =
    { playerBase
        | customName = "Marked"
        , note = "+d6 Force dmg, conc"
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
        , note = "on failed D20 Test"
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
        , companions = [ "Bless +d4" ]
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
