module Ui.Condition.Bundled exposing
    ( defaults
    , categories
    , categoryPlayer, categorySpell, categoryMonster, categoryItem, categoryEnvironment
    )

{-| Bundled Add-Condition presets seeded into a fresh visitor's
`Model.conditionPresets` on the very first boot.

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
every subsequent boot and seeding does not re-fire — so a GM
who deletes the bundled Hold Person doesn't get it back.

DC values are best-defaults from SRD 5.2.1 stat blocks; the GM
adjusts per cast (Stunning Strike's DC scales with Monk Wisdom,
dragon Frightful Presence by CR, etc.).

@docs defaults
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
        [ -- Player Classes (8)
          ( "Stunning Strike (Monk)", stunningStrike )
        , ( "Trip Attack", tripAttack )
        , ( "Menacing Attack", menacingAttack )
        , ( "Wrathful Smite", wrathfulSmite )
        , ( "Searing Smite", searingSmite )
        , ( "Turn Undead", turnUndead )
        , ( "Bardic Inspiration (+d6)", bardicInspiration )
        , ( "Bless (+d4)", bless )

        -- Spell Effects (15)
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
        , ( "Evard's Black Tentacles", blackTentacles )

        -- Monster Abilities (7)
        , ( "Petrifying Gaze (Medusa)", petrifyingGaze )
        , ( "Mind Blast (Mind Flayer)", mindBlast )
        , ( "Frightful Presence (Dragon)", frightfulPresence )
        , ( "Horrifying Visage (Ghost)", horrifyingVisage )
        , ( "Paralyzing Touch (Ghoul)", paralyzingTouch )
        , ( "Vampire Charm", vampireCharm )
        , ( "Luring Song (Harpy)", luringSong )

        -- Items (5)
        , ( "Wand of Paralysis", wandOfParalysis )
        , ( "Wand of Fear", wandOfFear )
        , ( "Staff of Charming", staffOfCharming )
        , ( "Potion of Invisibility", potionOfInvisibility )
        , ( "Dust of Sneezing and Choking", dustOfSneezingAndChoking )

        -- Environment (4)
        , ( "Quicksand", quicksand )
        , ( "Slippery Surface", slipperySurface )
        , ( "Heavy Obscurement", heavyObscurement )
        , ( "Drowning", drowning )
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
    }


save : String -> Int -> AutoRollMode -> SaveToEndUi
save ability dc autoRoll =
    { emptySave | ability = ability, dc = dc, dcText = String.fromInt dc, autoRoll = autoRoll }


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
        , note = "Monk"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


tripAttack : ConditionPreset
tripAttack =
    { playerBase
        | conditionName = "Prone"
        , note = "Trip"
    }


menacingAttack : ConditionPreset
menacingAttack =
    { playerBase
        | conditionName = "Frightened"
        , note = "Menacing"
        , durationKind = DurKindUntilTurn
        , untilPhase = AtEnd
    }


wrathfulSmite : ConditionPreset
wrathfulSmite =
    { playerBase
        | conditionName = "Frightened"
        , note = "Wrath"
        , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
    }


searingSmite : ConditionPreset
searingSmite =
    { playerBase
        | customName = "Searing Smite"
        , note = "1d6 fire"
        , saveToEnd = Just (save "CON" 13 AutoRollAtBegin)
    }


turnUndead : ConditionPreset
turnUndead =
    { playerBase
        | conditionName = "Frightened"
        , note = "Turned"
        , durationKind = DurKindCountdown
        , countdownTurnsText = "10"
        , countdownTurns = 10
        , countdownPhase = AtEnd
    }


bardicInspiration : ConditionPreset
bardicInspiration =
    { playerBase
        | customName = "Inspired +d6"
        , note = "Bard"
    }


bless : ConditionPreset
bless =
    { playerBase
        | customName = "Bless +d4"
        , note = "Cleric"
    }



-- ── SPELL EFFECTS ────────────────────────────────────────────────────────


bane : ConditionPreset
bane =
    { spellBase
        | customName = "Bane −d4"
        , note = "Cleric"
    }


holdPerson : ConditionPreset
holdPerson =
    { spellBase
        | conditionName = "Paralyzed"
        , note = "Hold P."
        , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
    }


holdMonster : ConditionPreset
holdMonster =
    { spellBase
        | conditionName = "Paralyzed"
        , note = "Hold M."
        , saveToEnd = Just (save "WIS" 14 AutoRollAtEnd)
    }


sleep : ConditionPreset
sleep =
    { spellBase
        | conditionName = "Unconscious"
        , note = "Sleep"
        , durationKind = DurKindCountdown
        , countdownTurnsText = "10"
        , countdownTurns = 10
        , countdownPhase = AtEnd
    }


charmPerson : ConditionPreset
charmPerson =
    { spellBase
        | conditionName = "Charmed"
        , note = "Charm P."
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
    { spellBase
        | conditionName = "Frightened"
        , note = "C.Fear"
        , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
    }


fear : ConditionPreset
fear =
    { spellBase
        | conditionName = "Frightened"
        , note = "Fear"
        , saveToEnd = Just (save "WIS" 14 AutoRollAtEnd)
    }


hypnoticPattern : ConditionPreset
hypnoticPattern =
    { spellBase
        | conditionName = "Incapacitated"
        , note = "HypPat"
    }


hideousLaughter : ConditionPreset
hideousLaughter =
    { spellBase
        | conditionName = "Incapacitated"
        , note = "HidLgh"
        , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
    }


suggestion : ConditionPreset
suggestion =
    { spellBase
        | conditionName = "Charmed"
        , note = "Sugg"
    }


slow : ConditionPreset
slow =
    { spellBase
        | customName = "Slowed"
        , note = "Slow"
        , saveToEnd = Just (save "WIS" 14 AutoRollAtEnd)
    }


web : ConditionPreset
web =
    { spellBase
        | conditionName = "Restrained"
        , note = "Web"
        , saveToEnd = Just (save "STR" 13 AutoRollAtBegin)
    }


entangle : ConditionPreset
entangle =
    { spellBase
        | conditionName = "Restrained"
        , note = "Tangle"
        , saveToEnd = Just (save "STR" 13 AutoRollAtEnd)
    }


blackTentacles : ConditionPreset
blackTentacles =
    { spellBase
        | conditionName = "Restrained"
        , note = "B.Tent"
        , saveToEnd = Just (save "STR" 14 AutoRollAtEnd)
    }



-- ── MONSTER ABILITIES ────────────────────────────────────────────────────


petrifyingGaze : ConditionPreset
petrifyingGaze =
    { monsterBase
        | conditionName = "Restrained"
        , note = "Gaze"
        , saveToEnd = Just (save "CON" 14 AutoRollAtEnd)
    }


mindBlast : ConditionPreset
mindBlast =
    { monsterBase
        | conditionName = "Stunned"
        , note = "MBlast"
        , saveToEnd = Just (save "INT" 15 AutoRollAtEnd)
    }


frightfulPresence : ConditionPreset
frightfulPresence =
    { monsterBase
        | conditionName = "Frightened"
        , note = "Dragon"
        , saveToEnd = Just (save "WIS" 18 AutoRollAtEnd)
    }


horrifyingVisage : ConditionPreset
horrifyingVisage =
    { monsterBase
        | conditionName = "Frightened"
        , note = "Ghost"
        , saveToEnd = Just (save "WIS" 13 AutoRollAtEnd)
    }


paralyzingTouch : ConditionPreset
paralyzingTouch =
    { monsterBase
        | conditionName = "Paralyzed"
        , note = "Ghoul"
        , saveToEnd = Just (save "CON" 10 AutoRollAtEnd)
    }


vampireCharm : ConditionPreset
vampireCharm =
    { monsterBase
        | conditionName = "Charmed"
        , note = "Vamp"
    }


luringSong : ConditionPreset
luringSong =
    { monsterBase
        | conditionName = "Charmed"
        , note = "Harpy"
        , saveToEnd = Just (save "WIS" 11 AutoRollAtEnd)
    }



-- ── ITEMS ────────────────────────────────────────────────────────────────


wandOfParalysis : ConditionPreset
wandOfParalysis =
    { itemBase
        | conditionName = "Paralyzed"
        , note = "Wand"
        , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
    }


wandOfFear : ConditionPreset
wandOfFear =
    { itemBase
        | conditionName = "Frightened"
        , note = "Wand"
        , saveToEnd = Just (save "WIS" 15 AutoRollAtEnd)
    }


staffOfCharming : ConditionPreset
staffOfCharming =
    { itemBase
        | conditionName = "Charmed"
        , note = "Staff"
    }


potionOfInvisibility : ConditionPreset
potionOfInvisibility =
    { itemBase
        | conditionName = "Invisible"
        , note = "Potion"
    }


dustOfSneezingAndChoking : ConditionPreset
dustOfSneezingAndChoking =
    { itemBase
        | conditionName = "Poisoned"
        , note = "+Incap"
        , saveToEnd = Just (save "CON" 15 AutoRollAtEnd)
    }



-- ── ENVIRONMENT ──────────────────────────────────────────────────────────


quicksand : ConditionPreset
quicksand =
    { environmentBase
        | conditionName = "Restrained"
        , note = "Quick"
        , saveToEnd = Just (save "STR" 10 AutoRollAtEnd)
    }


slipperySurface : ConditionPreset
slipperySurface =
    { environmentBase
        | conditionName = "Prone"
        , note = "Slick"
    }


heavyObscurement : ConditionPreset
heavyObscurement =
    { environmentBase
        | conditionName = "Blinded"
        , note = "Fog/Dk"
    }


drowning : ConditionPreset
drowning =
    { environmentBase
        | conditionName = "Unconscious"
        , note = "Drown"
        , durationKind = DurKindCountdown
        , countdownTurnsText = "3"
        , countdownTurns = 3
        , countdownPhase = AtEnd
    }
