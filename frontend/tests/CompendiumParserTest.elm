module CompendiumParserTest exposing (suite)

import Compendium
import Compendium.Parser
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
        , conditionImmunitiesSuite
        , minimalSuite
        , empties
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
