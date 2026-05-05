module Compendium.Wire exposing
    ( fetchAll
    , decodeCreature, encodeCreature, encodeDraft
    , defaultSpeed, defaultAbilities, defaultSenses
    )

{-| Wire format + HTTP client for the compendium domain.

JSON encoders / decoders for every type in `Compendium.elm`,
plus the `fetchAll` HTTP helper. Pulled out of the domain
module so the rules engine reads cleanly without scrolling past
600 lines of codecs, and so a future schema bump only touches
this file.

@docs fetchAll
@docs decodeCreature, encodeCreature, encodeDraft
@docs defaultSpeed, defaultAbilities, defaultSenses

-}

import Compendium
    exposing
        ( Abilities
        , Ability(..)
        , AbilitySave
        , Creature
        , CreatureKind(..)
        , CustomSection
        , Feature
        , InnatePerDay
        , LairActions
        , LegendaryActions
        , LegendaryOption
        , RegionalEffects
        , Senses
        , Size(..)
        , SkillBonus
        , Speed
        , SpellSlotLevel
        , Spellcasting
        , Usage(..)
        )
import Http
import Json.Decode as D
import Json.Encode as E



-- ── PIPELINE HELPERS ─────────────────────────────────────────────────────────


required : String -> D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
required name decoder =
    D.map2 (|>) (D.field name decoder)


optional : String -> D.Decoder a -> a -> D.Decoder (a -> b) -> D.Decoder b
optional name decoder default =
    D.map2 (|>)
        (D.oneOf
            [ D.field name decoder
            , D.field name (D.null default)
            , D.succeed default
            ]
        )



-- ── HTTP ─────────────────────────────────────────────────────────────────────


{-| Fire a `GET /api/compendium/creatures` request. The handler
should expect `Result Http.Error (List Creature)`.
-}
fetchAll : (Result Http.Error (List Creature) -> msg) -> Cmd msg
fetchAll toMsg =
    Http.get
        { url = "/api/compendium/creatures"
        , expect = Http.expectJson toMsg (D.list decodeCreature)
        }



-- ── JSON WIRE FORMAT ─────────────────────────────────────────────────────────


decodeCreature : D.Decoder Creature
decodeCreature =
    D.succeed Creature
        |> required "id" D.string
        |> required "name" D.string
        |> required "kind" decodeKind
        |> required "size" decodeSize
        |> optional "race" D.string ""
        |> optional "subrace" D.string ""
        |> optional "alignment" D.string ""
        |> optional "source" D.string ""
        |> optional "description" D.string ""
        |> required "armor_class" D.int
        |> optional "armor_class_note" D.string ""
        |> required "max_hp" D.int
        |> optional "hp_formula" D.string ""
        |> optional "initiative_bonus" D.int 0
        |> optional "speed" decodeSpeed defaultSpeed
        |> optional "abilities" decodeAbilities defaultAbilities
        |> optional "saving_throws" (D.list decodeAbilitySave) []
        |> optional "skills" (D.list decodeSkillBonus) []
        |> optional "damage_vulnerabilities" (D.list D.string) []
        |> optional "damage_resistances" (D.list D.string) []
        |> optional "damage_immunities" (D.list D.string) []
        |> optional "condition_immunities" (D.list D.string) []
        |> optional "senses" decodeSenses defaultSenses
        |> optional "languages" (D.list D.string) []
        |> optional "challenge_rating" D.string ""
        |> optional "xp" D.int 0
        |> optional "xp_in_lair" D.int 0
        |> optional "proficiency_bonus" D.int 2
        |> optional "traits" (D.list decodeFeature) []
        |> optional "actions" (D.list decodeFeature) []
        |> optional "bonus_actions" (D.list decodeFeature) []
        |> optional "reactions" (D.list decodeFeature) []
        |> optional "legendary_actions" (D.nullable decodeLegendaryActions) Nothing
        |> optional "lair_actions" (D.nullable decodeLairActions) Nothing
        |> optional "regional_effects" (D.nullable decodeRegionalEffects) Nothing
        |> optional "spellcasting" (D.nullable decodeSpellcasting) Nothing
        |> optional "custom_sections" (D.list decodeCustomSection) []
        |> optional "created_at" D.int 0
        |> optional "updated_at" D.int 0


decodeKind : D.Decoder CreatureKind
decodeKind =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "player" ->
                        D.succeed Player

                    "enemy" ->
                        D.succeed Enemy

                    "npc" ->
                        D.succeed Npc

                    other ->
                        D.fail ("Unknown creature kind: " ++ other)
            )


decodeSize : D.Decoder Size
decodeSize =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "tiny" ->
                        D.succeed Tiny

                    "small" ->
                        D.succeed Small

                    "medium" ->
                        D.succeed Medium

                    "large" ->
                        D.succeed Large

                    "huge" ->
                        D.succeed Huge

                    "gargantuan" ->
                        D.succeed Gargantuan

                    other ->
                        D.fail ("Unknown size: " ++ other)
            )


decodeAbility : D.Decoder Ability
decodeAbility =
    D.string
        |> D.andThen
            (\s ->
                case s of
                    "str" ->
                        D.succeed Str

                    "dex" ->
                        D.succeed Dex

                    "con" ->
                        D.succeed Con

                    "int" ->
                        D.succeed Int_

                    "wis" ->
                        D.succeed Wis

                    "cha" ->
                        D.succeed Cha

                    other ->
                        D.fail ("Unknown ability: " ++ other)
            )


decodeSpeed : D.Decoder Speed
decodeSpeed =
    D.succeed Speed
        |> optional "walk" D.int 0
        |> optional "fly" D.int 0
        |> optional "swim" D.int 0
        |> optional "climb" D.int 0
        |> optional "burrow" D.int 0
        |> optional "hover" D.bool False


defaultSpeed : Speed
defaultSpeed =
    Speed 0 0 0 0 0 False


decodeAbilities : D.Decoder Abilities
decodeAbilities =
    D.succeed Abilities
        |> optional "str" D.int 10
        |> optional "dex" D.int 10
        |> optional "con" D.int 10
        |> optional "int" D.int 10
        |> optional "wis" D.int 10
        |> optional "cha" D.int 10


defaultAbilities : Abilities
defaultAbilities =
    Abilities 10 10 10 10 10 10


decodeAbilitySave : D.Decoder AbilitySave
decodeAbilitySave =
    D.map2 AbilitySave
        (D.field "ability" decodeAbility)
        (D.field "bonus" D.int)


decodeSkillBonus : D.Decoder SkillBonus
decodeSkillBonus =
    D.map2 SkillBonus
        (D.field "name" D.string)
        (D.field "bonus" D.int)


decodeSenses : D.Decoder Senses
decodeSenses =
    D.succeed Senses
        |> optional "blindsight" D.int 0
        |> optional "darkvision" D.int 0
        |> optional "tremorsense" D.int 0
        |> optional "truesight" D.int 0
        |> optional "passive_perception" D.int 10


defaultSenses : Senses
defaultSenses =
    Senses 0 0 0 0 10


decodeFeature : D.Decoder Feature
decodeFeature =
    D.map3 Feature
        (D.field "name" D.string)
        (D.field "description" D.string)
        (D.maybe (D.field "usage" decodeUsage))


decodeUsage : D.Decoder Usage
decodeUsage =
    D.field "kind" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "recharge" ->
                        D.map2
                            (\lo hi -> Recharge { low = lo, high = hi })
                            (D.field "low" D.int)
                            (D.field "high" D.int)

                    "per_day" ->
                        D.map PerDay (D.field "uses" D.int)

                    "per_short_rest" ->
                        D.map PerShortRest (D.field "uses" D.int)

                    "per_long_rest" ->
                        D.map PerLongRest (D.field "uses" D.int)

                    "at_will" ->
                        D.succeed AtWill

                    other ->
                        D.fail ("Unknown usage kind: " ++ other)
            )


decodeLegendaryActions : D.Decoder LegendaryActions
decodeLegendaryActions =
    D.map4 LegendaryActions
        (D.field "description" D.string)
        (D.field "uses" D.int)
        (D.field "uses_in_lair" D.int)
        (D.field "options" (D.list decodeLegendaryOption))


decodeLegendaryOption : D.Decoder LegendaryOption
decodeLegendaryOption =
    D.map3 LegendaryOption
        (D.field "name" D.string)
        (D.field "cost" D.int)
        (D.field "description" D.string)


decodeLairActions : D.Decoder LairActions
decodeLairActions =
    D.map3 LairActions
        (D.field "initiative" D.int)
        (D.field "description" D.string)
        (D.field "options" (D.list decodeFeature))


decodeRegionalEffects : D.Decoder RegionalEffects
decodeRegionalEffects =
    D.map3 RegionalEffects
        (D.field "description" D.string)
        (D.field "effects" (D.list decodeFeature))
        (D.field "fade_after" D.string)


decodeSpellcasting : D.Decoder Spellcasting
decodeSpellcasting =
    D.succeed Spellcasting
        |> required "description" D.string
        |> required "ability" decodeAbility
        |> optional "save_dc" D.int 0
        |> optional "attack_bonus" D.int 0
        |> optional "at_will" (D.list D.string) []
        |> optional "slots" (D.list decodeSpellSlotLevel) []
        |> optional "innate_per_day" (D.list decodeInnatePerDay) []


decodeSpellSlotLevel : D.Decoder SpellSlotLevel
decodeSpellSlotLevel =
    D.map3 SpellSlotLevel
        (D.field "level" D.int)
        (D.field "slots" D.int)
        (D.field "spells" (D.list D.string))


decodeInnatePerDay : D.Decoder InnatePerDay
decodeInnatePerDay =
    D.map2 InnatePerDay
        (D.field "uses" D.int)
        (D.field "spells" (D.list D.string))


decodeCustomSection : D.Decoder CustomSection
decodeCustomSection =
    D.map2 CustomSection
        (D.field "name" D.string)
        (D.field "body" D.string)



-- ── ENCODERS ─────────────────────────────────────────────────────────────────
--
-- Symmetric to the decoders.  Used by the (forthcoming) edit-and-save
-- flow; the read-only browser doesn't need encoders.


{-| Encode a `Creature` as a `CreatureDraft` payload for POST.
The server allocates `id` / `created_at` / `updated_at` on
insert, so we omit those three fields here. The remaining
shape matches `crates/lib/src/compendium/types.rs::CreatureDraft`.
-}
encodeDraft : Creature -> E.Value
encodeDraft c =
    E.object (draftFields c)


encodeCreature : Creature -> E.Value
encodeCreature c =
    E.object
        ([ ( "id", E.string c.id ) ]
            ++ draftFields c
            ++ [ ( "created_at", E.int c.createdAt )
               , ( "updated_at", E.int c.updatedAt )
               ]
        )


draftFields : Creature -> List ( String, E.Value )
draftFields c =
    [ ( "name", E.string c.name )
    , ( "kind", encodeKind c.kind )
    , ( "size", encodeSize c.size )
    , ( "race", E.string c.race )
    , ( "subrace", E.string c.subrace )
    , ( "alignment", E.string c.alignment )
    , ( "source", E.string c.source )
    , ( "description", E.string c.description )
    , ( "armor_class", E.int c.armorClass )
    , ( "armor_class_note", E.string c.armorClassNote )
    , ( "max_hp", E.int c.maxHp )
    , ( "hp_formula", E.string c.hpFormula )
    , ( "initiative_bonus", E.int c.initiativeBonus )
    , ( "speed", encodeSpeed c.speed )
    , ( "abilities", encodeAbilities c.abilities )
    , ( "saving_throws", E.list encodeAbilitySave c.savingThrows )
    , ( "skills", E.list encodeSkillBonus c.skills )
    , ( "damage_vulnerabilities", E.list E.string c.damageVulnerabilities )
    , ( "damage_resistances", E.list E.string c.damageResistances )
    , ( "damage_immunities", E.list E.string c.damageImmunities )
    , ( "condition_immunities", E.list E.string c.conditionImmunities )
    , ( "senses", encodeSenses c.senses )
    , ( "languages", E.list E.string c.languages )
    , ( "challenge_rating", E.string c.challengeRating )
    , ( "xp", E.int c.xp )
    , ( "xp_in_lair", E.int c.xpInLair )
    , ( "proficiency_bonus", E.int c.proficiencyBonus )
    , ( "traits", E.list encodeFeature c.traits )
    , ( "actions", E.list encodeFeature c.actions )
    , ( "bonus_actions", E.list encodeFeature c.bonusActions )
    , ( "reactions", E.list encodeFeature c.reactions )
    , ( "legendary_actions", encodeMaybe encodeLegendaryActions c.legendaryActions )
    , ( "lair_actions", encodeMaybe encodeLairActions c.lairActions )
    , ( "regional_effects", encodeMaybe encodeRegionalEffects c.regionalEffects )
    , ( "spellcasting", encodeMaybe encodeSpellcasting c.spellcasting )
    , ( "custom_sections", E.list encodeCustomSection c.customSections )
    ]


encodeKind : CreatureKind -> E.Value
encodeKind k =
    case k of
        Player ->
            E.string "player"

        Enemy ->
            E.string "enemy"

        Npc ->
            E.string "npc"


encodeSize : Size -> E.Value
encodeSize s =
    case s of
        Tiny ->
            E.string "tiny"

        Small ->
            E.string "small"

        Medium ->
            E.string "medium"

        Large ->
            E.string "large"

        Huge ->
            E.string "huge"

        Gargantuan ->
            E.string "gargantuan"


encodeAbility : Ability -> E.Value
encodeAbility a =
    case a of
        Str ->
            E.string "str"

        Dex ->
            E.string "dex"

        Con ->
            E.string "con"

        Int_ ->
            E.string "int"

        Wis ->
            E.string "wis"

        Cha ->
            E.string "cha"


encodeSpeed : Speed -> E.Value
encodeSpeed s =
    E.object
        [ ( "walk", E.int s.walk )
        , ( "fly", E.int s.fly )
        , ( "swim", E.int s.swim )
        , ( "climb", E.int s.climb )
        , ( "burrow", E.int s.burrow )
        , ( "hover", E.bool s.hover )
        ]


encodeAbilities : Abilities -> E.Value
encodeAbilities a =
    E.object
        [ ( "str", E.int a.str )
        , ( "dex", E.int a.dex )
        , ( "con", E.int a.con )
        , ( "int", E.int a.int )
        , ( "wis", E.int a.wis )
        , ( "cha", E.int a.cha )
        ]


encodeAbilitySave : AbilitySave -> E.Value
encodeAbilitySave s =
    E.object
        [ ( "ability", encodeAbility s.ability )
        , ( "bonus", E.int s.bonus )
        ]


encodeSkillBonus : SkillBonus -> E.Value
encodeSkillBonus s =
    E.object
        [ ( "name", E.string s.name )
        , ( "bonus", E.int s.bonus )
        ]


encodeSenses : Senses -> E.Value
encodeSenses s =
    E.object
        [ ( "blindsight", E.int s.blindsight )
        , ( "darkvision", E.int s.darkvision )
        , ( "tremorsense", E.int s.tremorsense )
        , ( "truesight", E.int s.truesight )
        , ( "passive_perception", E.int s.passivePerception )
        ]


encodeFeature : Feature -> E.Value
encodeFeature f =
    E.object
        [ ( "name", E.string f.name )
        , ( "description", E.string f.description )
        , ( "usage", encodeMaybe encodeUsage f.usage )
        ]


encodeUsage : Usage -> E.Value
encodeUsage u =
    case u of
        Recharge { low, high } ->
            E.object
                [ ( "kind", E.string "recharge" )
                , ( "low", E.int low )
                , ( "high", E.int high )
                ]

        PerDay n ->
            E.object [ ( "kind", E.string "per_day" ), ( "uses", E.int n ) ]

        PerShortRest n ->
            E.object [ ( "kind", E.string "per_short_rest" ), ( "uses", E.int n ) ]

        PerLongRest n ->
            E.object [ ( "kind", E.string "per_long_rest" ), ( "uses", E.int n ) ]

        AtWill ->
            E.object [ ( "kind", E.string "at_will" ) ]


encodeLegendaryActions : LegendaryActions -> E.Value
encodeLegendaryActions la =
    E.object
        [ ( "description", E.string la.description )
        , ( "uses", E.int la.uses )
        , ( "uses_in_lair", E.int la.usesInLair )
        , ( "options", E.list encodeLegendaryOption la.options )
        ]


encodeLegendaryOption : LegendaryOption -> E.Value
encodeLegendaryOption o =
    E.object
        [ ( "name", E.string o.name )
        , ( "cost", E.int o.cost )
        , ( "description", E.string o.description )
        ]


encodeLairActions : LairActions -> E.Value
encodeLairActions la =
    E.object
        [ ( "initiative", E.int la.initiative )
        , ( "description", E.string la.description )
        , ( "options", E.list encodeFeature la.options )
        ]


encodeRegionalEffects : RegionalEffects -> E.Value
encodeRegionalEffects re =
    E.object
        [ ( "description", E.string re.description )
        , ( "effects", E.list encodeFeature re.effects )
        , ( "fade_after", E.string re.fadeAfter )
        ]


encodeSpellcasting : Spellcasting -> E.Value
encodeSpellcasting sc =
    E.object
        [ ( "description", E.string sc.description )
        , ( "ability", encodeAbility sc.ability )
        , ( "save_dc", E.int sc.saveDc )
        , ( "attack_bonus", E.int sc.attackBonus )
        , ( "at_will", E.list E.string sc.atWill )
        , ( "slots", E.list encodeSpellSlotLevel sc.slots )
        , ( "innate_per_day", E.list encodeInnatePerDay sc.innatePerDay )
        ]


encodeSpellSlotLevel : SpellSlotLevel -> E.Value
encodeSpellSlotLevel sl =
    E.object
        [ ( "level", E.int sl.level )
        , ( "slots", E.int sl.slots )
        , ( "spells", E.list E.string sl.spells )
        ]


encodeInnatePerDay : InnatePerDay -> E.Value
encodeInnatePerDay i =
    E.object
        [ ( "uses", E.int i.uses )
        , ( "spells", E.list E.string i.spells )
        ]


encodeCustomSection : CustomSection -> E.Value
encodeCustomSection cs =
    E.object
        [ ( "name", E.string cs.name )
        , ( "body", E.string cs.body )
        ]


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc m =
    case m of
        Just v ->
            enc v

        Nothing ->
            E.null
