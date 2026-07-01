module CompendiumParserTest exposing (suite)

import Compendium
import Compendium.Parser
import Dice
import Expect
import Test exposing (Test, describe, test)



-- ── ENTRY ────────────────────────────────────────────────────────────────────


suite : Test
suite =
    describe "Compendium.Parser.parseStatBlock"
        [ goblinSuite
        , dragonSuite
        , humanoidNpcSuite
        , spellcasterSuite
        , spellcasting2024ActionSuite
        , conditionImmunitiesSuite
        , minimalSuite
        , blueDragonSuite
        , standaloneInitiativeSuite
        , srd521DualSizeSuite
        , scanLairDice
        , empties
        , habitatSuite
        , treasureSuite
        , legendaryUsesSuite
        ]



-- ── FIXTURES + EXPECTATIONS ──────────────────────────────────────────────────


goblinSuite : Test
goblinSuite =
    let
        input =
            String.join "\n"
                [ "Goblin Skirmisher"
                , "Small humanoid (goblinoid), neutral evil"
                , "Armor Class 15 (leather armor, shield)"
                , "Hit Points 7 (2d6)"
                , "Speed 30 ft."
                , "STR 8 (-1) DEX 14 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1)"
                , "Skills Stealth +6"
                , "Senses darkvision 60 ft., passive Perception 9"
                , "Languages Common, Goblin"
                , "Challenge 1/4 (50 XP)"
                , "Nimble Escape. The goblin can take the Disengage or Hide action as a bonus action on each of its turns."
                , "Actions"
                , "Scimitar. Melee Weapon Attack: +4 to hit, reach 5 ft., one target. Hit: 5 (1d6 + 2) slashing damage."
                , "Shortbow. Ranged Weapon Attack: +4 to hit, range 80/320 ft., one target. Hit: 5 (1d6 + 2) piercing damage."
                ]
    in
    describe "Goblin (canonical SRD form)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "name + size + race + subrace + alignment" <|
            \_ ->
                expectFields input
                    (\c ->
                        { name = c.name
                        , size = c.size
                        , race = c.race
                        , subrace = c.subrace
                        , alignment = c.alignment
                        }
                            |> Expect.equal
                                { name = "Goblin Skirmisher"
                                , size = Compendium.Small
                                , race = "Humanoid"
                                , subrace = "goblinoid"
                                , alignment = "neutral evil"
                                }
                    )
        , test "AC + AC note" <|
            \_ ->
                expectFields input
                    (\c -> ( c.armorClass, c.armorClassNote ) |> Expect.equal ( 15, "leather armor, shield" ))
        , test "HP + HP formula" <|
            \_ ->
                expectFields input
                    (\c -> ( c.maxHp, c.hpFormula ) |> Expect.equal ( 7, "2d6" ))
        , test "walk speed = 30" <|
            \_ ->
                expectFields input (\c -> c.speed.walk |> Expect.equal 30)
        , test "abilities" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( c.abilities.str, c.abilities.dex, c.abilities.con )
                            |> Expect.equal ( 8, 14, 10 )
                    )
        , test "skill bonus" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.skills
                            |> Expect.equal [ { name = "Stealth", bonus = 6 } ]
                    )
        , test "senses (darkvision + passive Perception)" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( c.senses.darkvision, c.senses.passivePerception )
                            |> Expect.equal ( 60, 9 )
                    )
        , test "languages" <|
            \_ ->
                expectFields input
                    (\c -> c.languages |> Expect.equal [ "Common", "Goblin" ])
        , test "CR + XP" <|
            \_ ->
                expectFields input
                    (\c -> ( c.challengeRating, c.xp ) |> Expect.equal ( "1/4", 50 ))
        , test "Nimble Escape lands as a trait, not an action" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.traits
                            |> List.map .name
                            |> Expect.equal [ "Nimble Escape" ]
                    )
        , test "Scimitar + Shortbow land as actions" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.actions
                            |> List.map .name
                            |> Expect.equal [ "Scimitar", "Shortbow" ]
                    )
        ]


dragonSuite : Test
dragonSuite =
    let
        input =
            String.join "\n"
                [ "Young Storm Drake"
                , "Large dragon (storm), chaotic neutral"
                , "Armor Class 18 (natural armor)"
                , "Hit Points 110 (13d10 + 39)"
                , "Speed 40 ft., fly 80 ft. (hover), swim 30 ft."
                , "STR 19 (+4) DEX 16 (+3) CON 17 (+3) INT 14 (+2) WIS 13 (+1) CHA 17 (+3)"
                , "Saving Throws Dex +6, Con +6, Wis +4, Cha +6"
                , "Skills Perception +7, Stealth +6"
                , "Damage Resistances cold, thunder"
                , "Damage Immunities lightning"
                , "Condition Immunities frightened"
                , "Senses blindsight 30 ft., darkvision 120 ft., passive Perception 17"
                , "Languages Draconic"
                , "Challenge 7 (2,900 XP)"
                , "Proficiency Bonus +3"
                , "Amphibious. The drake can breathe air and water."
                , "Actions"
                , "Multiattack. The drake makes one bite attack and two claw attacks."
                , "Bite. Melee Weapon Attack: +7 to hit, reach 10 ft. Hit: 14 (2d10 + 4) piercing damage plus 5 (1d10) lightning damage."
                , "Legendary Actions"
                , "Detect. The drake makes a Wisdom (Perception) check."
                , "Tail Swipe. The drake makes one tail attack."
                ]
    in
    describe "Storm Drake (fly+hover, multiple resistances, legendary actions)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "subrace 'storm' parsed out of parens" <|
            \_ -> expectFields input (\c -> c.subrace |> Expect.equal "storm")
        , test "fly speed 80 with hover flag" <|
            \_ ->
                expectFields input
                    (\c -> ( c.speed.fly, c.speed.hover ) |> Expect.equal ( 80, True ))
        , test "swim speed 30" <|
            \_ -> expectFields input (\c -> c.speed.swim |> Expect.equal 30)
        , test "saving throws (4 of them)" <|
            \_ ->
                expectFields input
                    (\c -> List.length c.savingThrows |> Expect.equal 4)
        , test "two-skill bonus list" <|
            \_ ->
                expectFields input
                    (\c ->
                        List.map .name c.skills
                            |> Expect.equal [ "Perception", "Stealth" ]
                    )
        , test "damage resistances list" <|
            \_ ->
                expectFields input
                    (\c -> c.damageResistances |> Expect.equal [ "cold", "thunder" ])
        , test "damage immunities list" <|
            \_ ->
                expectFields input
                    (\c -> c.damageImmunities |> Expect.equal [ "lightning" ])
        , test "condition immunities list" <|
            \_ ->
                expectFields input
                    (\c -> c.conditionImmunities |> Expect.equal [ "frightened" ])
        , test "senses (blindsight + darkvision + passive)" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( c.senses.blindsight, c.senses.darkvision, c.senses.passivePerception )
                            |> Expect.equal ( 30, 120, 17 )
                    )
        , test "CR with comma-separated XP" <|
            \_ ->
                expectFields input
                    (\c -> ( c.challengeRating, c.xp ) |> Expect.equal ( "7", 2900 ))
        , test "proficiency bonus +3" <|
            \_ ->
                expectFields input
                    (\c -> c.proficiencyBonus |> Expect.equal 3)
        , test "Amphibious lands as a trait" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.traits |> List.map .name |> Expect.equal [ "Amphibious" ]
                    )
        , test "Multiattack + Bite land as actions" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.actions
                            |> List.map .name
                            |> Expect.equal [ "Multiattack", "Bite" ]
                    )
        , test "Legendary actions populated" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.legendaryActions
                            |> Maybe.map (\la -> List.map .name la.options)
                            |> Expect.equal (Just [ "Detect", "Tail Swipe" ])
                    )
        ]


humanoidNpcSuite : Test
humanoidNpcSuite =
    let
        input =
            String.join "\n"
                [ "Captain Vex"
                , "Medium humanoid (human), bandit captain"
                , "Armor Class 15 (studded leather)"
                , "Hit Points 65 (10d8 + 20)"
                , "Speed 30 ft."
                , "STR 15 (+2) DEX 16 (+3) CON 14 (+2) INT 14 (+2) WIS 11 (+0) CHA 14 (+2)"
                , "Saving Throws Str +4, Dex +5, Wis +2"
                , "Skills Athletics +4, Deception +4"
                , "Senses passive Perception 10"
                , "Languages any two languages"
                , "Challenge 2 (450 XP)"
                , "Actions"
                , "Multiattack. Vex makes three melee attacks: two with their scimitar and one with their dagger."
                , "Scimitar. Melee Weapon Attack: +5 to hit, reach 5 ft. Hit: 6 (1d6 + 3) slashing damage."
                , "Reactions"
                , "Parry. Vex adds 2 to their AC against one melee attack that would hit them."
                ]
    in
    describe "Captain Vex (NPC humanoid, multiple sections)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "subrace = bandit captain (after the )" <|
            \_ -> expectFields input (\c -> c.subrace |> Expect.equal "human")
        , test "saving throws (3 of them)" <|
            \_ ->
                expectFields input
                    (\c -> List.length c.savingThrows |> Expect.equal 3)
        , test "Reactions section yields one reaction" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.reactions |> List.map .name |> Expect.equal [ "Parry" ]
                    )
        , test "passive Perception only (no other senses)" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( c.senses.darkvision, c.senses.passivePerception )
                            |> Expect.equal ( 0, 10 )
                    )
        ]


spellcasterSuite : Test
spellcasterSuite =
    let
        input =
            String.join "\n"
                [ "Apprentice Necromancer"
                , "Medium humanoid (elf), neutral evil"
                , "Armor Class 12"
                , "Hit Points 27 (5d8 + 5)"
                , "Speed 30 ft."
                , "STR 9 (-1) DEX 14 (+2) CON 12 (+1) INT 16 (+3) WIS 12 (+1) CHA 11 (+0)"
                , "Senses darkvision 60 ft., passive Perception 11"
                , "Languages Common, Elvish"
                , "Challenge 1/2 (100 XP)"
                , "Actions"
                , "Quarterstaff. Melee Weapon Attack: +1 to hit. Hit: 2 (1d6 - 1) bludgeoning damage."
                , "Spellcasting"
                , "Cantrips. The necromancer knows chill touch and mage hand."
                ]
    in
    describe "Spellcaster (Spellcasting section parks as custom)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "Quarterstaff lands as an action" <|
            \_ ->
                expectFields input
                    (\c -> c.actions |> List.map .name |> Expect.equal [ "Quarterstaff" ])
        , test "Spellcasting content parks as a custom section" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.customSections
                            |> List.map .name
                            |> Expect.equal [ "Spellcasting: Cantrips" ]
                    )
        ]


spellcasting2024ActionSuite : Test
spellcasting2024ActionSuite =
    let
        input =
            String.join "\n"
                [ "Djinni"
                , "Large elemental, chaotic good"
                , "Armor Class 17"
                , "Hit Points 218 (19d10 + 114)"
                , "Speed 30 ft."
                , "STR 21 (+5) DEX 15 (+2) CON 22 (+6) INT 15 (+2) WIS 16 (+3) CHA 20 (+5)"
                , "Senses darkvision 120 ft., passive Perception 13"
                , "Languages Primordial (Auran)"
                , "Challenge 11 (7,200 XP)"
                , "Actions"
                , "Storm Blade. Melee Attack Roll: +9, reach 5 feet. Hit: 12 (2d6 + 5) Slashing damage."
                , "Spellcasting. The djinni casts one of the following spells, using Charisma as the spellcasting ability (spell save DC 17):"
                , " - **At Will:** Detect Evil and Good, Detect Magic"
                , " - **2/Day Each:** Create Food and Water, Tongues, Wind Walk"
                , " - **1/Day Each:** Creation, Gaseous Form, Invisibility, Major Image, Plane Shift"
                ]
    in
    describe "Djinni (2024 MM Spellcasting action → structured field)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "Storm Blade stays as an action" <|
            \_ ->
                expectFields input
                    (\c -> c.actions |> List.map .name |> Expect.equal [ "Storm Blade" ])
        , test "Spellcasting action is consumed (not left in actions)" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.actions
                            |> List.any (\a -> a.name == "Spellcasting")
                            |> Expect.equal False
                    )
        , test "spellcasting field is populated" <|
            \_ ->
                expectFields input
                    (\c ->
                        case c.spellcasting of
                            Just _ ->
                                Expect.pass

                            Nothing ->
                                Expect.fail "expected c.spellcasting to be Just, got Nothing"
                    )
        , test "at-will spells captured" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.spellcasting
                            |> Maybe.map .atWill
                            |> Maybe.withDefault []
                            |> Expect.equal [ "Detect Evil and Good", "Detect Magic" ]
                    )
        , test "innate per-day groups captured" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.spellcasting
                            |> Maybe.map .innatePerDay
                            |> Maybe.withDefault []
                            |> List.map (\g -> ( g.uses, List.length g.spells ))
                            |> Expect.equal [ ( 2, 3 ), ( 1, 5 ) ]
                    )
        , test "save DC extracted from prose" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.spellcasting
                            |> Maybe.map .saveDc
                            |> Expect.equal (Just 17)
                    )
        , test "ability extracted from prose" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.spellcasting
                            |> Maybe.map .ability
                            |> Expect.equal (Just Compendium.Cha)
                    )
        ]


conditionImmunitiesSuite : Test
conditionImmunitiesSuite =
    let
        input =
            String.join "\n"
                [ "Stone Sentinel"
                , "Large construct, unaligned"
                , "Armor Class 18 (natural armor)"
                , "Hit Points 78 (12d10 + 12)"
                , "Speed 25 ft."
                , "STR 18 (+4) DEX 8 (-1) CON 16 (+3) INT 3 (-4) WIS 11 (+0) CHA 1 (-5)"
                , "Damage Vulnerabilities thunder"
                , "Damage Resistances bludgeoning, piercing, slashing from nonmagical attacks"
                , "Damage Immunities poison, psychic"
                , "Condition Immunities charmed, exhaustion, frightened, paralyzed, petrified, poisoned"
                , "Senses darkvision 60 ft., passive Perception 10"
                , "Languages —"
                , "Challenge 5 (1,800 XP)"
                ]
    in
    describe "Stone Sentinel (every damage / condition list, em-dash language)"
        [ test "vulnerabilities" <|
            \_ ->
                expectFields input
                    (\c -> c.damageVulnerabilities |> Expect.equal [ "thunder" ])
        , test "resistances (single multi-word entry)" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.damageResistances
                            |> Expect.equal
                                [ "bludgeoning"
                                , "piercing"
                                , "slashing from nonmagical attacks"
                                ]
                    )
        , test "immunities" <|
            \_ ->
                expectFields input
                    (\c -> c.damageImmunities |> Expect.equal [ "poison", "psychic" ])
        , test "condition immunities (six entries)" <|
            \_ ->
                expectFields input
                    (\c -> List.length c.conditionImmunities |> Expect.equal 6)
        , test "languages '—' renders as a one-element list (not blank)" <|
            \_ ->
                expectFields input
                    (\c -> c.languages |> Expect.equal [ "—" ])
        ]


minimalSuite : Test
minimalSuite =
    let
        input =
            String.join "\n"
                [ "Tiny Mouse"
                , "Tiny beast, unaligned"
                , "Armor Class 10"
                , "Hit Points 1"
                , "Speed 20 ft., climb 10 ft."
                , "STR 2 (-4) DEX 11 (+0) CON 8 (-1) INT 2 (-4) WIS 10 (+0) CHA 3 (-4)"
                , "Senses passive Perception 10"
                , "Languages —"
                , "Challenge 0 (0 XP)"
                ]
    in
    describe "Minimal stat block (no skills/saves/damage/conditions/features)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "speed (walk + climb)" <|
            \_ ->
                expectFields input
                    (\c -> ( c.speed.walk, c.speed.climb ) |> Expect.equal ( 20, 10 ))
        , test "no traits / actions" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( List.length c.traits, List.length c.actions )
                            |> Expect.equal ( 0, 0 )
                    )
        , test "size = Tiny" <|
            \_ -> expectFields input (\c -> c.size |> Expect.equal Compendium.Tiny)
        ]


standaloneInitiativeSuite : Test
standaloneInitiativeSuite =
    let
        positiveBonus =
            String.join "\n"
                [ "Sample"
                , "Medium humanoid, neutral"
                , "AC 14"
                , "HP 30"
                , "Speed 30 ft."
                , "Initiative +7 (17)"
                , "STR 10 (+0) DEX 14 (+2) CON 12 (+1) INT 10 (+0) WIS 10 (+0) CHA 10 (+0)"
                , "Challenge 1 (200 XP)"
                ]

        negativeBonus =
            String.join "\n"
                [ "Sluggish"
                , "Tiny beast, unaligned"
                , "AC 10"
                , "HP 5"
                , "Speed 10 ft."
                , "Initiative -3 (7)"
                , "STR 5 (-3) DEX 5 (-3) CON 8 (-1) INT 2 (-4) WIS 8 (-1) CHA 3 (-4)"
                , "Challenge 0 (10 XP)"
                ]
    in
    describe "Standalone Initiative line (D&D Beyond 2024 separate row)"
        [ test "captures positive bonus" <|
            \_ ->
                expectFields positiveBonus
                    (\c -> c.initiativeBonus |> Expect.equal 7)
        , test "captures negative bonus" <|
            \_ ->
                expectFields negativeBonus
                    (\c -> c.initiativeBonus |> Expect.equal -3)
        ]


blueDragonSuite : Test
blueDragonSuite =
    let
        input =
            String.join "\n"
                [ "Adult Blue Dragon"
                , "Huge Dragon (Chromatic), Lawful Evil"
                , "AC 19    Initiative +10 (20)"
                , "HP 212 (17d12 + 102)"
                , "Speed 40 ft., Burrow 30 ft., Fly 80 ft."
                , "Mod\tSave"
                , "STR\t25\t+7\t+7"
                , "DEX\t10\t+0\t+5"
                , "CON\t23\t+6\t+6"
                , "Mod\tSave"
                , "INT\t16\t+3\t+3"
                , "WIS\t15\t+2\t+7"
                , "CHA\t20\t+5\t+5"
                , "Skills Perception +12, Stealth +5"
                , "Immunities Lightning"
                , "Senses Blindsight 60 ft., Darkvision 120 ft.; Passive Perception 22"
                , "Languages Common, Draconic"
                , "CR 16 (XP 15,000, or 18,000 in lair; PB +5)"
                , "Traits"
                , "Legendary Resistance (3/Day, or 4/Day in Lair). If the dragon fails a saving throw, it can choose to succeed instead."
                , "Actions"
                , "Multiattack. The dragon makes three Rend attacks. It can replace one attack with a use of Spellcasting to cast Shatter."
                , "Rend. Melee Attack Roll: +12, reach 10 ft. Hit: 16 (2d8 + 7) Slashing damage plus 5 (1d10) Lightning damage."
                , "Lightning Breath (Recharge 5-6). Dexterity Saving Throw: DC 19, each creature in a 90-foot-long, 5-foot-wide Line. Failure: 60 (11d10) Lightning damage. Success: Half damage."
                , "Spellcasting. The dragon casts one of the following spells, requiring no Material components and using Charisma as the spellcasting ability (spell save DC 18):"
                , "At Will: Detect Magic, Invisibility, Mage Hand, Shatter"
                , "1/Day Each: Scrying, Sending"
                , "Legendary Actions"
                , "Cloaked Flight. The dragon uses Spellcasting to cast Invisibility on itself, and it can fly up to half its Fly Speed. The dragon can't take this action again until the start of its next turn."
                , "Sonic Boom. The dragon uses Spellcasting to cast Shatter. The dragon can't take this action again until the start of its next turn."
                , "Tail Swipe. The dragon makes one Rend attack."
                , "Adult blue dragons command small empires, which might be territories of subjugated followers, shadowy criminal networks, or cultic enclaves. Endlessly suspicious and wary of rivals, these dragons enact elaborate schemes to ruin their foes, test the loyalty of their servants, and ensure their dominance for centuries."
                , "Blue Dragons"
                , "Arrogant and imperious, blue dragons are chromatic dragons that crave control and collect followers like other dragons hoard treasure. They seek to transform their territories into empires, domains to be feared by nations."
                , "Blue Dragon Lairs"
                , "Blue dragons dwell in arid lands. Their lairs might be death traps meant to entomb invaders or ostentatious fortresses where they plot domination."
                , "The region containing an adult or ancient blue dragon's lair is changed by its presence, creating the following effects:"
                , "Sinkholes. Sinkholes form more frequently in the area within 1 mile of the lair. Whenever a creature in that area other than the dragon and its allies finishes a Long Rest, roll 1d20. On a 1, a sinkhole opens beneath the creature, and the creature must succeed on a DC 15 Dexterity saving throw or fall 2d4 × 10 feet into the sinkhole."
                , "Spiteful Storms. Dust devils and thunderstorms rage within 1 mile of the lair. The area is Lightly Obscured."
                ]
    in
    describe "Adult Blue Dragon (D&D Beyond 2024 export — short prefixes, tab abilities, lore)"
        [ test "parses without error" <|
            \_ -> expectOk input
        , test "size = Huge, race = Dragon, subrace = Chromatic, alignment = Lawful Evil" <|
            \_ ->
                expectFields input
                    (\c ->
                        { size = c.size, race = c.race, subrace = c.subrace, alignment = c.alignment }
                            |> Expect.equal
                                { size = Compendium.Huge
                                , race = "Dragon"
                                , subrace = "Chromatic"
                                , alignment = "Lawful Evil"
                                }
                    )
        , test "AC 19 (no spurious note from Initiative parens)" <|
            \_ ->
                expectFields input
                    (\c -> ( c.armorClass, c.armorClassNote ) |> Expect.equal ( 19, "" ))
        , test "initiative bonus +10 captured from the AC-line annotation" <|
            \_ ->
                expectFields input
                    (\c -> c.initiativeBonus |> Expect.equal 10)
        , test "HP 212 with 17d12 + 102 formula" <|
            \_ ->
                expectFields input
                    (\c -> ( c.maxHp, c.hpFormula ) |> Expect.equal ( 212, "17d12 + 102" ))
        , test "speed: walk 40, burrow 30, fly 80" <|
            \_ ->
                expectFields input
                    (\c ->
                        { walk = c.speed.walk, burrow = c.speed.burrow, fly = c.speed.fly }
                            |> Expect.equal { walk = 40, burrow = 30, fly = 80 }
                    )
        , test "abilities parsed from tab-separated rows (real scores, not 10s)" <|
            \_ ->
                expectFields input
                    (\c ->
                        { str = c.abilities.str
                        , dex = c.abilities.dex
                        , con = c.abilities.con
                        , int = c.abilities.int
                        }
                            |> Expect.equal
                                { str = 25, dex = 10, con = 23, int = 16 }
                    )
        , test "saving throws picked up from save column (only proficient ones)" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.savingThrows
                            |> List.map (\s -> ( s.ability, s.bonus ))
                            |> Expect.equal
                                [ ( Compendium.Dex, 5 ), ( Compendium.Wis, 7 ) ]
                    )
        , test "skills" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.skills
                            |> Expect.equal
                                [ { name = "Perception", bonus = 12 }
                                , { name = "Stealth", bonus = 5 }
                                ]
                    )
        , test "Immunities short-form maps to damage immunities" <|
            \_ ->
                expectFields input
                    (\c -> c.damageImmunities |> Expect.equal [ "Lightning" ])
        , test "Senses splits on both ',' and ';'" <|
            \_ ->
                expectFields input
                    (\c ->
                        ( c.senses.blindsight, c.senses.darkvision, c.senses.passivePerception )
                            |> Expect.equal ( 60, 120, 22 )
                    )
        , test "Languages" <|
            \_ ->
                expectFields input
                    (\c -> c.languages |> Expect.equal [ "Common", "Draconic" ])
        , test "CR 16 + XP 15,000 + lair XP 18,000 + PB +5 from one combined line" <|
            \_ ->
                expectFields input
                    (\c ->
                        { cr = c.challengeRating
                        , xp = c.xp
                        , xpInLair = c.xpInLair
                        , pb = c.proficiencyBonus
                        }
                            |> Expect.equal
                                { cr = "16"
                                , xp = 15000
                                , xpInLair = 18000
                                , pb = 5
                                }
                    )
        , test "'Traits' section header used (no Traits-preamble custom section)" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.customSections
                            |> List.map .name
                            |> List.filter (String.startsWith "Traits")
                            |> Expect.equal []
                    )
        , test "Legendary Resistance lands as a trait" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.traits
                            |> List.map .name
                            |> Expect.equal [ "Legendary Resistance (3/Day, or 4/Day in Lair)" ]
                    )
        , test "actions: Multiattack, Rend, Lightning Breath, Spellcasting" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.actions
                            |> List.map .name
                            |> Expect.equal
                                [ "Multiattack"
                                , "Rend"
                                , "Lightning Breath (Recharge 5-6)"
                                , "Spellcasting"
                                ]
                    )
        , test "Tail Swipe body does NOT contain the trailing lore prose" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.legendaryActions
                            |> Maybe.andThen
                                (\la ->
                                    la.options
                                        |> List.filter (\o -> o.name == "Tail Swipe")
                                        |> List.head
                                )
                            |> Maybe.map .description
                            |> Expect.equal (Just "The dragon makes one Rend attack.")
                    )
        , test "lore prose ends up in a Description custom section, not bleeding into the last action" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.customSections
                            |> List.filter (\s -> s.name == "Description")
                            |> List.length
                            |> Expect.atLeast 1
                    )
        , test "\"Blue Dragon Lairs\" heading triggers a lair section even from lore mode" <|
            \_ ->
                expectFields input
                    (\c ->
                        case c.lairActions of
                            Just _ ->
                                Expect.pass

                            Nothing ->
                                Expect.fail "expected lairActions to be populated"
                    )
        , test "lair description captures the preamble paragraphs (not parked as a custom section)" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.lairActions
                            |> Maybe.map .description
                            |> Maybe.map (String.contains "Blue dragons dwell in arid lands")
                            |> Expect.equal (Just True)
                    )
        , test "lair options: Sinkholes + Spiteful Storms as named effects" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.lairActions
                            |> Maybe.map (\la -> List.map .name la.options)
                            |> Expect.equal (Just [ "Sinkholes", "Spiteful Storms" ])
                    )
        , test "Sinkholes body retains the dice notation '1d20' for the clickable roll" <|
            \_ ->
                expectFields input
                    (\c ->
                        c.lairActions
                            |> Maybe.andThen
                                (\la ->
                                    la.options
                                        |> List.filter (\o -> o.name == "Sinkholes")
                                        |> List.head
                                )
                            |> Maybe.map .description
                            |> Maybe.map (String.contains "1d20")
                            |> Expect.equal (Just True)
                    )
        ]


empties : Test
empties =
    describe "Empty / malformed input"
        [ test "empty string returns EmptyInput" <|
            \_ ->
                Compendium.Parser.parseStatBlock ""
                    |> Expect.equal (Err Compendium.Parser.EmptyInput)
        , test "single-line input returns MissingHeader" <|
            \_ ->
                Compendium.Parser.parseStatBlock "Just A Name"
                    |> Expect.equal (Err Compendium.Parser.MissingHeader)
        ]


legendaryUsesSuite : Test
legendaryUsesSuite =
    let
        minimal preamble =
            String.join "\n"
                [ "Test Drake"
                , "Large dragon, neutral"
                , "Armor Class 18"
                , "Hit Points 200"
                , "Speed 40 ft."
                , "STR 20 (+5) DEX 10 (+0) CON 20 (+5) INT 14 (+2) WIS 14 (+2) CHA 18 (+4)"
                , "Challenge 17 (18,000 XP)"
                , "Actions"
                , "Bite. Reach 10 ft., one target."
                , "Legendary Actions"
                , preamble
                , "Detect. The drake makes a Wisdom (Perception) check."
                ]
    in
    describe "Legendary Actions preamble — uses + uses-in-lair extraction"
        [ test "2024 MM phrasing: 'Legendary Action Uses: 3 (4 in Lair).'" <|
            \_ ->
                expectFields
                    (minimal "Legendary Action Uses: 3 (4 in Lair).")
                    (\c ->
                        c.legendaryActions
                            |> Maybe.map (\la -> ( la.uses, la.usesInLair ))
                            |> Expect.equal (Just ( 3, 4 ))
                    )
        , test "2024 MM phrasing without lair clause stays at usesInLair=0" <|
            \_ ->
                expectFields
                    (minimal "Legendary Action Uses: 3.")
                    (\c ->
                        c.legendaryActions
                            |> Maybe.map (\la -> ( la.uses, la.usesInLair ))
                            |> Expect.equal (Just ( 3, 0 ))
                    )
        , test "older 5e phrasing: 'The dragon can take 3 legendary actions'" <|
            \_ ->
                expectFields
                    (minimal "The dragon can take 3 legendary actions, choosing from the options below.")
                    (\c ->
                        c.legendaryActions
                            |> Maybe.map (\la -> ( la.uses, la.usesInLair ))
                            |> Expect.equal (Just ( 3, 0 ))
                    )
        , test "multi-digit base: 'Legendary Action Uses: 10 (12 in Lair).'" <|
            \_ ->
                expectFields
                    (minimal "Legendary Action Uses: 10 (12 in Lair).")
                    (\c ->
                        c.legendaryActions
                            |> Maybe.map (\la -> ( la.uses, la.usesInLair ))
                            |> Expect.equal (Just ( 10, 12 ))
                    )
        ]


habitatSuite : Test
habitatSuite =
    let
        minimal habitatLine =
            String.join "\n"
                [ "Test Creature"
                , "Medium humanoid, neutral"
                , "Armor Class 12"
                , "Hit Points 10"
                , "Speed 30 ft."
                , "STR 10 (+0) DEX 10 (+0) CON 10 (+0) INT 10 (+0) WIS 10 (+0) CHA 10 (+0)"
                , habitatLine
                ]
    in
    describe "Habitat line (2024 MM)"
        [ test "colon-prefixed Material-Plane CSV" <|
            \_ ->
                expectFields (minimal "Habitat: Mountain, Hill")
                    (\c ->
                        c.habitats
                            |> Expect.equal [ Compendium.Mountain, Compendium.Hill ]
                    )
        , test "bare prefix without colon also matches" <|
            \_ ->
                expectFields (minimal "Habitat Forest, Swamp")
                    (\c ->
                        c.habitats
                            |> Expect.equal [ Compendium.Forest, Compendium.Swamp ]
                    )
        , test "trailing '; Treasure: ...' is trimmed before splitting" <|
            \_ ->
                expectFields (minimal "Habitat: Underdark; Treasure: Any")
                    (\c ->
                        c.habitats
                            |> Expect.equal [ Compendium.Underdark ]
                    )
        , test "planar habitats with multi-word names round-trip" <|
            \_ ->
                expectFields
                    (minimal "Habitat: Elemental Plane of Fire, Nine Hells")
                    (\c ->
                        c.habitats
                            |> Expect.equal
                                [ Compendium.ElementalPlaneOfFire
                                , Compendium.NineHells
                                ]
                    )
        , test "unknown tokens drop silently, known ones survive" <|
            \_ ->
                expectFields (minimal "Habitat: Forest, Cyberspace, Urban")
                    (\c ->
                        c.habitats
                            |> Expect.equal [ Compendium.Forest, Compendium.Urban ]
                    )
        , test "no Habitat line leaves the field empty" <|
            \_ ->
                expectFields (minimal "Languages Common")
                    (\c -> c.habitats |> Expect.equal [])
        , test "Planar (X) wrapper unwraps to the planar habitat" <|
            \_ ->
                expectFields (minimal "Habitat: Planar (Limbo)")
                    (\c ->
                        c.habitats |> Expect.equal [ Compendium.Limbo ]
                    )
        , test "Planar (X, Y) wrapper expands across multiple planes" <|
            \_ ->
                expectFields (minimal "Habitat: Planar (Abyss, Nine Hells)")
                    (\c ->
                        c.habitats
                            |> Expect.equal
                                [ Compendium.Abyss, Compendium.NineHells ]
                    )
        , test "Mixed Material + Planar (X) on one line" <|
            \_ ->
                expectFields (minimal "Habitat: Mountain, Planar (Abyss)")
                    (\c ->
                        c.habitats
                            |> Expect.equal
                                [ Compendium.Mountain, Compendium.Abyss ]
                    )
        , test "Same-line Habitat + Treasure: habitats parsed correctly" <|
            \_ ->
                expectFields
                    (minimal "Habitat: Planar (Limbo) Treasure: Any")
                    (\c ->
                        c.habitats |> Expect.equal [ Compendium.Limbo ]
                    )
        , test "Same-line Habitat + Treasure: treasure parsed correctly" <|
            \_ ->
                expectFields
                    (minimal "Habitat: Forest Treasure: Arcana, Relics")
                    (\c ->
                        c.treasures
                            |> Expect.equal
                                [ Compendium.Arcana, Compendium.Relics ]
                    )
        , test "Same-line Treasure + Habitat (reverse order)" <|
            \_ ->
                expectFields
                    (minimal "Treasure: Arcana Habitat: Forest")
                    (\c ->
                        ( c.habitats, c.treasures )
                            |> Expect.equal
                                ( [ Compendium.Forest ]
                                , [ Compendium.Arcana ]
                                )
                    )
        , test "Habitat after lore prose still parses (2024 MM order)" <|
            \_ ->
                let
                    input =
                        String.join "\n"
                            [ "Test Creature"
                            , "Medium aberration, chaotic evil"
                            , "AC 12"
                            , "HP 10"
                            , "Speed 30 ft."
                            , "STR 10 (+0) DEX 10 (+0) CON 10 (+0) INT 10 (+0) WIS 10 (+0) CHA 10 (+0)"
                            , "Actions"
                            , "Bite. Melee Attack Roll: +2. Hit: 1 piercing damage."
                            , "Lore paragraph one talks about the creature's origins."
                            , "Lore paragraph two adds further colour about the species."
                            , "Habitat: Planar (Limbo)"
                            , "Treasure: Arcana"
                            ]
                in
                expectFields input
                    (\c ->
                        ( c.habitats, c.treasures )
                            |> Expect.equal
                                ( [ Compendium.Limbo ]
                                , [ Compendium.Arcana ]
                                )
                    )
        ]


treasureSuite : Test
treasureSuite =
    let
        minimal treasureLine =
            String.join "\n"
                [ "Test Creature"
                , "Medium humanoid, neutral"
                , "Armor Class 12"
                , "Hit Points 10"
                , "Speed 30 ft."
                , "STR 10 (+0) DEX 10 (+0) CON 10 (+0) INT 10 (+0) WIS 10 (+0) CHA 10 (+0)"
                , treasureLine
                ]
    in
    describe "Treasure line (2024 MM)"
        [ test "colon-prefixed CSV" <|
            \_ ->
                expectFields (minimal "Treasure: Arcana, Implements")
                    (\c ->
                        c.treasures
                            |> Expect.equal [ Compendium.Arcana, Compendium.Implements ]
                    )
        , test "bare prefix without colon also matches" <|
            \_ ->
                expectFields (minimal "Treasure Armaments, Relics")
                    (\c ->
                        c.treasures
                            |> Expect.equal [ Compendium.Armaments, Compendium.Relics ]
                    )
        , test "unknown tokens drop silently" <|
            \_ ->
                expectFields (minimal "Treasure: Arcana, Goldpiles, Relics")
                    (\c ->
                        c.treasures
                            |> Expect.equal [ Compendium.Arcana, Compendium.Relics ]
                    )
        , test "no Treasure line leaves the field empty" <|
            \_ ->
                expectFields (minimal "Languages Common")
                    (\c -> c.treasures |> Expect.equal [])
        , test "case-insensitive label matching" <|
            \_ ->
                expectFields (minimal "Treasure: arcana, RELICS")
                    (\c ->
                        c.treasures
                            |> Expect.equal [ Compendium.Arcana, Compendium.Relics ]
                    )
        , test "'Treasure: Any' expands to all four buckets" <|
            \_ ->
                expectFields (minimal "Treasure: Any")
                    (\c ->
                        c.treasures
                            |> Expect.equal
                                [ Compendium.Arcana
                                , Compendium.Armaments
                                , Compendium.Implements
                                , Compendium.Relics
                                ]
                    )
        ]



-- ── SRD 5.2.1 dual-size type line ────────────────────────────────────────────


srd521DualSizeSuite : Test
srd521DualSizeSuite =
    let
        input =
            String.join "\n"
                [ "Bandit"
                , "Medium or Small Humanoid, Neutral"
                , "AC 12"
                , "HP 11 (2d8 + 2)"
                , "Speed 30 ft."
                , "Str 11 +0 +0 Dex 12 +1 +1 Con 12 +1 +1"
                , "Int 10 +0 +0 Wis 10 +0 +0 Cha 10 +0 +0"
                , "Gear Leather Armor, Scimitar"
                , "Senses Passive Perception 10"
                , "Languages Common"
                , "CR 1/8 (XP 25; PB +2)"
                , "Actions"
                , "Scimitar. Melee Attack Roll: +3, reach 5 ft. Hit: 4 (1d6 + 1) Slashing damage."
                ]

        lycanInput =
            String.join "\n"
                [ "Werewolf"
                , "Medium or Small Monstrosity (Lycanthrope), Chaotic Evil"
                , "AC 15"
                , "HP 71 (11d8 + 22)"
                , "Speed 30 ft."
                , "Str 16 +3 +3 Dex 14 +2 +2 Con 14 +2 +2"
                , "Int 10 +0 +0 Wis 11 +0 +0 Cha 10 +0 +0"
                , "Senses Darkvision 60 ft.; Passive Perception 14"
                , "Languages Common (can't speak in wolf form)"
                , "CR 3 (XP 700; PB +2)"
                ]

        tinyInput =
            String.join "\n"
                [ "Will-o'-Wisp"
                , "Tiny Undead, Chaotic Evil"
                , "AC 19"
                , "HP 27 (11d4)"
                , "Speed 5 ft., Fly 50 ft. (hover)"
                , "Str 1 -5 -5 Dex 28 +9 +9 Con 10 +0 +0"
                , "Int 13 +1 +1 Wis 14 +2 +2 Cha 11 +0 +0"
                , "Senses Darkvision 120 ft.; Passive Perception 12"
                , "Languages Common plus one other language"
                , "CR 2 (XP 450; PB +2)"
                ]
    in
    describe "SRD 5.2.1 type-line variants"
        [ test "'Medium or Small Humanoid' picks the larger size" <|
            \_ ->
                expectFields input (\c -> c.size |> Expect.equal Compendium.Medium)
        , test "'Medium or Small Humanoid' race is 'Humanoid', not 'Or Small Humanoid'" <|
            \_ ->
                expectFields input (\c -> c.race |> Expect.equal "Humanoid")
        , test "'Medium or Small Monstrosity (Lycanthrope)' parses size + race + subrace" <|
            \_ ->
                expectFields lycanInput
                    (\c ->
                        ( c.size, c.race, c.subrace )
                            |> Expect.equal ( Compendium.Medium, "Monstrosity", "Lycanthrope" )
                    )
        , test "single 'Tiny Undead' still works" <|
            \_ ->
                expectFields tinyInput
                    (\c -> ( c.size, c.race ) |> Expect.equal ( Compendium.Tiny, "Undead" ))
        ]



-- ── HELPERS ──────────────────────────────────────────────────────────────────


expectOk : String -> Expect.Expectation
expectOk input =
    case Compendium.Parser.parseStatBlock input of
        Ok _ ->
            Expect.pass

        Err err ->
            Expect.fail ("parser returned an error: " ++ Debug.toString err)


expectFields : String -> (Compendium.Creature -> Expect.Expectation) -> Expect.Expectation
expectFields input check =
    case Compendium.Parser.parseStatBlock input of
        Ok creature ->
            check creature

        Err err ->
            Expect.fail ("parser returned an error: " ++ Debug.toString err)


{-| Regression tests for Dice.scan recognizing inline dice
notation in prose. Two parser bugs we previously hit:

1.  `Parser.int` treats trailing "." as a malformed float and
    fails with a committed error, so "roll 1d20. On a 1…" never
    matched a DiceLink.
2.  The optional modifier branch's `Parser.spaces` greedily
    consumed a trailing space, then the missing sign caused a
    committed failure that the surrounding backtrackable
    couldn't fully unwind, so "1d20 " (trailing space) failed
    to match too.

These tests lock both fixes in.

-}
scanLairDice : Test
scanLairDice =
    let
        countLinks input =
            Dice.scan input
                |> List.filter
                    (\seg ->
                        case seg of
                            Dice.DiceLink _ _ ->
                                True

                            _ ->
                                False
                    )
                |> List.length

        firstLink input =
            Dice.scan input
                |> List.filterMap
                    (\seg ->
                        case seg of
                            Dice.DiceLink shown _ ->
                                Just shown

                            _ ->
                                Nothing
                    )
                |> List.head
    in
    describe "Dice.scan recognizes inline dice in lair-effect prose"
        [ test "trailing period: 'roll 1d20. On a 1...'" <|
            \_ ->
                firstLink "Long Rest, roll 1d20. On a 1, a sinkhole opens."
                    |> Expect.equal (Just "1d20")
        , test "trailing space: '1d20 '" <|
            \_ -> firstLink "1d20 " |> Expect.equal (Just "1d20")
        , test "bare dice with each common trailing punctuation" <|
            \_ ->
                List.map countLinks
                    [ "1d20"
                    , "1d20."
                    , "1d20,"
                    , "1d20!"
                    , "1d20)"
                    , "1d20 "
                    , "1d20a"
                    ]
                    |> Expect.equal [ 1, 1, 1, 1, 1, 1, 1 ]
        , test "Sinkholes body picks up both 1d20 and 2d4" <|
            \_ ->
                let
                    body =
                        "Sinkholes form more frequently. Whenever a creature finishes a Long Rest, roll 1d20. On a 1, fall 2d4 × 10 feet."
                in
                Dice.scan body
                    |> List.filterMap
                        (\seg ->
                            case seg of
                                Dice.DiceLink shown _ ->
                                    Just shown

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ "1d20", "2d4" ]
        , test "average-wrap with trailing damage type captures the type" <|
            \_ ->
                Dice.scan "Hit: 16 (2d8 + 7) Slashing damage."
                    |> List.filterMap
                        (\seg ->
                            case seg of
                                Dice.DiceLink _ expr ->
                                    Maybe.map String.toLower expr.damageType

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ "slashing" ]
        , test "bare formula with trailing damage type captures the type" <|
            \_ ->
                Dice.scan "plus 5 (1d10) Lightning damage"
                    |> List.filterMap
                        (\seg ->
                            case seg of
                                Dice.DiceLink _ expr ->
                                    Maybe.map String.toLower expr.damageType

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ "lightning" ]
        , test "non-damage trailing word doesn't get captured as a type" <|
            \_ ->
                Dice.scan "1d6 from the spell"
                    |> List.filterMap
                        (\seg ->
                            case seg of
                                Dice.DiceLink _ expr ->
                                    Just expr.damageType

                                _ ->
                                    Nothing
                        )
                    |> Expect.equal [ Nothing ]
        ]
