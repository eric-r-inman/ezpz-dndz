module Compendium.WireTest exposing (suite)

{-| Round-trip tests for `Compendium.Wire`. Confirms that
encoding a `Creature` then decoding the result reproduces the
original value field-for-field. This is what guarantees that
saved compendiums (both server-side named snapshots and the
anonymous-mode localStorage snapshot) round-trip cleanly.

The fixture below sets EVERY field on `Compendium.Creature` to a
non-default value, including all the optional nested records
(`legendaryActions`, `lairActions`, `regionalEffects`,
`spellcasting`). If a new field is added to `Creature` but not
threaded through `encodeCreature` / `decodeCreature`, this test
fails with a structural mismatch.

-}

import Compendium
    exposing
        ( Ability(..)
        , CreatureKind(..)
        , Habitat(..)
        , Size(..)
        , Treasure(..)
        , Usage(..)
        )
import Compendium.Wire as Wire
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Compendium.Wire round-trip"
        [ test "fully-populated creature survives encode → decode" <|
            \_ ->
                fullyPopulatedCreature |> roundTripExpect
        , test "minimal creature (defaults for optionals) survives" <|
            \_ ->
                minimalCreature |> roundTripExpect
        , test "list of creatures survives encode → decode" <|
            \_ ->
                let
                    creatures =
                        [ fullyPopulatedCreature
                        , minimalCreature
                        , { minimalCreature | id = "alt", name = "Alt" }
                        ]

                    json =
                        E.list Wire.encodeCreature creatures

                    decoded =
                        D.decodeValue (D.list Wire.decodeCreature) json
                in
                decoded |> Expect.equal (Ok creatures)
        , test "encoder includes every top-level field key" <|
            \_ ->
                let
                    json =
                        E.encode 0 (Wire.encodeCreature fullyPopulatedCreature)
                in
                List.all (\key -> String.contains ("\"" ++ key ++ "\":") json)
                    expectedTopLevelKeys
                    |> Expect.equal True
        , test "habitat tokens round-trip via wire format" <|
            \_ ->
                let
                    creature =
                        { minimalCreature
                            | habitats =
                                [ Arctic, Underdark, AstralPlane, NineHells, ElementalPlaneOfFire ]
                        }
                in
                creature |> roundTripExpect
        , test "treasure tokens round-trip via wire format" <|
            \_ ->
                let
                    creature =
                        { minimalCreature
                            | treasures = [ Arcana, Armaments, Implements, Relics ]
                        }
                in
                creature |> roundTripExpect
        , test "all Usage variants round-trip" <|
            \_ ->
                let
                    usageFeature name usage =
                        { name = name, description = "desc", usage = Just usage }

                    creature =
                        { minimalCreature
                            | traits =
                                [ usageFeature "Recharge" (Recharge { low = 5, high = 6 })
                                , usageFeature "PerDay" (PerDay 3)
                                , usageFeature "PerShortRest" (PerShortRest 2)
                                , usageFeature "PerLongRest" (PerLongRest 1)
                                , usageFeature "AtWill" AtWill
                                ]
                        }
                in
                creature |> roundTripExpect
        , test "all Size variants round-trip" <|
            \_ ->
                let
                    sizes =
                        [ Tiny, Small, Medium, Large, Huge, Gargantuan ]

                    creatures =
                        List.map (\s -> { minimalCreature | size = s }) sizes
                in
                creatures
                    |> List.map roundTrips
                    |> List.all identity
                    |> Expect.equal True
        , test "all CreatureKind variants round-trip" <|
            \_ ->
                let
                    creatures =
                        List.map (\k -> { minimalCreature | kind = k })
                            [ Player, Enemy, Npc ]
                in
                creatures
                    |> List.map roundTrips
                    |> List.all identity
                    |> Expect.equal True
        ]



-- ── FIXTURES ────────────────────────────────────────────────────────────────


{-| Every field set to a non-default value, including all four
optional nested records. If you add a field to
`Compendium.Creature`, add a non-default value here too — the
round-trip will then catch any missing encode/decode entry.
-}
fullyPopulatedCreature : Compendium.Creature
fullyPopulatedCreature =
    { id = "smaug-uuid"
    , name = "Smaug"
    , kind = Enemy
    , size = Gargantuan
    , race = "Dragon"
    , subrace = "Red"
    , alignment = "chaotic evil"
    , source = "Custom"
    , description = "An ancient red dragon, gold-mad and proud."
    , armorClass = 22
    , armorClassNote = "natural armor"
    , maxHp = 546
    , hpFormula = "28d20 + 252"
    , initiativeBonus = 10
    , speed =
        { walk = 40
        , fly = 80
        , swim = 40
        , climb = 40
        , burrow = 30
        , hover = True
        }
    , abilities =
        { str = 30, dex = 10, con = 29, int = 18, wis = 15, cha = 23 }
    , savingThrows =
        [ { ability = Dex, bonus = 7 }
        , { ability = Con, bonus = 16 }
        , { ability = Wis, bonus = 9 }
        , { ability = Cha, bonus = 13 }
        ]
    , skills =
        [ { name = "Perception", bonus = 16 }
        , { name = "Stealth", bonus = 7 }
        ]
    , damageVulnerabilities = [ "cold" ]
    , damageResistances = [ "poison" ]
    , damageImmunities = [ "fire" ]
    , conditionImmunities = [ "frightened", "paralyzed" ]
    , senses =
        { blindsight = 60
        , darkvision = 120
        , tremorsense = 30
        , truesight = 30
        , passivePerception = 26
        }
    , languages = [ "Common", "Draconic" ]
    , challengeRating = "24"
    , xp = 62000
    , xpInLair = 75000
    , proficiencyBonus = 7
    , traits =
        [ { name = "Legendary Resistance"
          , description = "If the dragon fails a save, it can choose to succeed instead."
          , usage = Just (PerDay 3)
          }
        , { name = "Frightful Presence"
          , description = "Each creature within 120 feet must save vs Wis DC 21."
          , usage = Just (Recharge { low = 5, high = 6 })
          }
        ]
    , actions =
        [ { name = "Multiattack"
          , description = "Three attacks: one with bite, two with claws."
          , usage = Nothing
          }
        , { name = "Fire Breath"
          , description = "90-foot cone. DC 24 Dex save, 91 (26d6) fire."
          , usage = Just (Recharge { low = 5, high = 6 })
          }
        ]
    , bonusActions =
        [ { name = "Tail Swipe"
          , description = "One melee attack with tail."
          , usage = Just AtWill
          }
        ]
    , reactions =
        [ { name = "Wing Block"
          , description = "Impose disadvantage on an attack."
          , usage = Just (PerShortRest 1)
          }
        ]
    , legendaryActions =
        Just
            { description = "The dragon can take 3 legendary actions per turn."
            , uses = 3
            , usesInLair = 5
            , options =
                [ { name = "Detect", cost = 1, description = "Wisdom (Perception) check." }
                , { name = "Tail Attack", cost = 1, description = "Tail attack." }
                , { name = "Wing Attack", cost = 2, description = "Beats wings; all creatures within 15 ft save." }
                ]
            }
    , lairActions =
        Just
            { initiative = 20
            , description = "On initiative 20 (losing ties), the dragon takes a lair action."
            , options =
                [ { name = "Magma Erupts"
                  , description = "Magma erupts from a point on the ground."
                  , usage = Nothing
                  }
                , { name = "Tremor"
                  , description = "A tremor shakes the lair."
                  , usage = Just (PerLongRest 1)
                  }
                ]
            }
    , regionalEffects =
        Just
            { description = "The region around the dragon's lair is twisted."
            , effects =
                [ { name = "Ash and Cinders"
                  , description = "Cinders fall within 6 miles of the lair."
                  , usage = Nothing
                  }
                ]
            , fadeAfter = "1d10 days after the dragon's death"
            }
    , spellcasting =
        Just
            { description = "The dragon is a 12th-level spellcaster."
            , ability = Cha
            , saveDc = 21
            , attackBonus = 13
            , atWill = [ "detect magic", "mage hand", "prestidigitation" ]
            , slots =
                [ { level = 1, slots = 4, spells = [ "shield", "magic missile" ] }
                , { level = 2, slots = 3, spells = [ "scorching ray", "mirror image" ] }
                , { level = 3, slots = 3, spells = [ "fireball" ] }
                ]
            , innatePerDay =
                [ { uses = 3, spells = [ "fireball" ] }
                , { uses = 1, spells = [ "wish" ] }
                ]
            }
    , customSections =
        [ { name = "Notes", body = "Hoards gold under a mountain." }
        , { name = "Allies", body = "None — Smaug works alone." }
        ]
    , habitats = [ Mountain, Underdark, ElementalPlaneOfFire, NineHells ]
    , treasures = [ Arcana, Armaments, Implements, Relics ]
    , tags = [ "dragon", "boss", "legendary" ]
    , createdAt = 1714521600
    , updatedAt = 1714608000
    }


{-| Same shape but with the four optional nested records set to
`Nothing` and most list / numeric fields empty. Exercises the
"default" branches of the decoder so a future schema change that
breaks defaults shows up here.
-}
minimalCreature : Compendium.Creature
minimalCreature =
    { id = "minimal"
    , name = "Generic Bandit"
    , kind = Enemy
    , size = Medium
    , race = ""
    , subrace = ""
    , alignment = ""
    , source = ""
    , description = ""
    , armorClass = 12
    , armorClassNote = ""
    , maxHp = 11
    , hpFormula = ""
    , initiativeBonus = 0
    , speed = Wire.defaultSpeed
    , abilities = Wire.defaultAbilities
    , savingThrows = []
    , skills = []
    , damageVulnerabilities = []
    , damageResistances = []
    , damageImmunities = []
    , conditionImmunities = []
    , senses = Wire.defaultSenses
    , languages = []
    , challengeRating = "1/8"
    , xp = 25
    , xpInLair = 0
    , proficiencyBonus = 2
    , traits = []
    , actions = []
    , bonusActions = []
    , reactions = []
    , legendaryActions = Nothing
    , lairActions = Nothing
    , regionalEffects = Nothing
    , spellcasting = Nothing
    , customSections = []
    , habitats = []
    , treasures = []
    , tags = []
    , createdAt = 0
    , updatedAt = 0
    }


{-| All top-level snake\_case keys the encoder is contractually
required to emit. The "encoder includes every key" test sweeps
this list so a future commit that drops a field on encode (but
leaves the decoder happy thanks to its `optional` defaults) gets
flagged.
-}
expectedTopLevelKeys : List String
expectedTopLevelKeys =
    [ "id"
    , "name"
    , "kind"
    , "size"
    , "race"
    , "subrace"
    , "alignment"
    , "source"
    , "description"
    , "armor_class"
    , "armor_class_note"
    , "max_hp"
    , "hp_formula"
    , "initiative_bonus"
    , "speed"
    , "abilities"
    , "saving_throws"
    , "skills"
    , "damage_vulnerabilities"
    , "damage_resistances"
    , "damage_immunities"
    , "condition_immunities"
    , "senses"
    , "languages"
    , "challenge_rating"
    , "xp"
    , "xp_in_lair"
    , "proficiency_bonus"
    , "traits"
    , "actions"
    , "bonus_actions"
    , "reactions"
    , "legendary_actions"
    , "lair_actions"
    , "regional_effects"
    , "spellcasting"
    , "custom_sections"
    , "habitats"
    , "treasures"
    , "tags"
    , "created_at"
    , "updated_at"
    ]



-- ── HELPERS ─────────────────────────────────────────────────────────────────


roundTrips : Compendium.Creature -> Bool
roundTrips c =
    Wire.encodeCreature c
        |> D.decodeValue Wire.decodeCreature
        |> Result.map ((==) c)
        |> Result.withDefault False


roundTripExpect : Compendium.Creature -> Expect.Expectation
roundTripExpect c =
    c
        |> Wire.encodeCreature
        |> D.decodeValue Wire.decodeCreature
        |> Result.map ((==) c)
        |> Result.mapError (D.errorToString >> (++) "decode failed: ")
        |> (\result ->
                case result of
                    Ok True ->
                        Expect.pass

                    Ok False ->
                        Expect.fail
                            ("round-trip changed the value; original=\n"
                                ++ Debug.toString c
                                ++ "\nafter round-trip=\n"
                                ++ Debug.toString
                                    (Wire.encodeCreature c
                                        |> D.decodeValue Wire.decodeCreature
                                    )
                            )

                    Err msg ->
                        Expect.fail msg
           )
