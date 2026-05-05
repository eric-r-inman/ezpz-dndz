module Compendium exposing
    ( Creature, CreatureKind(..), Size(..)
    , Speed, Abilities, Ability(..), AbilitySave, SkillBonus
    , Senses, Feature, Usage(..)
    , LegendaryActions, LegendaryOption, LairActions, RegionalEffects
    , Spellcasting, SpellSlotLevel, InnatePerDay, CustomSection
    , Db, fromList, toList, count
    , find, findByName, search, filterByKind, sortByName, sortByCr, sortByRecency
    , crToFloat
    , draftToInstance
    , instanceKindLine, sourceHasLegendaryResistance
    )

{-| Pure domain layer for the compendium.

This module owns the canonical Creature type (mirroring the
Rust-side `crates/lib/src/compendium/types.rs` schema) plus the
client-side search / filter / sort helpers. No `Html`,
`Browser`, or `Url` imports — this is the rules-engine layer
matching the discipline of `Encounter`, `Dice`, and `HpChange`.

Display logic (the browser modal, the stat-block renderer, etc.)
lives in `View/` modules and consumes this domain.

@docs Creature, CreatureKind, Size
@docs Speed, Abilities, Ability, AbilitySave, SkillBonus
@docs Senses, Feature, Usage
@docs LegendaryActions, LegendaryOption, LairActions, RegionalEffects
@docs Spellcasting, SpellSlotLevel, InnatePerDay, CustomSection


# Database

@docs Db, fromList, toList, count


# Lookup / filter / sort

@docs find, findByName, search, filterByKind, sortByName, sortByCr, sortByRecency


# Helpers

@docs crToFloat


# Compendium → Encounter handoff

@docs draftToInstance


# HTTP / wire

The HTTP `fetchAll` helper plus all JSON encoders / decoders
live in [`Compendium.Wire`](Compendium-Wire) so the rules-engine
side reads cleanly.

-}

import Encounter
import Set



-- ── TYPES ────────────────────────────────────────────────────────────────────


{-| Single stat-block entry. Field order matches the Rust struct
in `crates/lib/src/compendium/types.rs` so the JSON wire format
round-trips cleanly via the pipeline decoder below.
-}
type alias Creature =
    { id : String
    , name : String
    , kind : CreatureKind
    , size : Size
    , race : String
    , subrace : String
    , alignment : String
    , source : String
    , description : String
    , armorClass : Int
    , armorClassNote : String
    , maxHp : Int
    , hpFormula : String
    , initiativeBonus : Int
    , speed : Speed
    , abilities : Abilities
    , savingThrows : List AbilitySave
    , skills : List SkillBonus
    , damageVulnerabilities : List String
    , damageResistances : List String
    , damageImmunities : List String
    , conditionImmunities : List String
    , senses : Senses
    , languages : List String
    , challengeRating : String
    , xp : Int
    , xpInLair : Int
    , proficiencyBonus : Int
    , traits : List Feature
    , actions : List Feature
    , bonusActions : List Feature
    , reactions : List Feature
    , legendaryActions : Maybe LegendaryActions
    , lairActions : Maybe LairActions
    , regionalEffects : Maybe RegionalEffects
    , spellcasting : Maybe Spellcasting
    , customSections : List CustomSection
    , createdAt : Int
    , updatedAt : Int
    }


type CreatureKind
    = Player
    | Enemy
    | Npc


type Size
    = Tiny
    | Small
    | Medium
    | Large
    | Huge
    | Gargantuan


type alias Speed =
    { walk : Int
    , fly : Int
    , swim : Int
    , climb : Int
    , burrow : Int
    , hover : Bool
    }


type alias Abilities =
    { str : Int, dex : Int, con : Int, int : Int, wis : Int, cha : Int }


type Ability
    = Str
    | Dex
    | Con
    | Int_
    | Wis
    | Cha


type alias AbilitySave =
    { ability : Ability, bonus : Int }


type alias SkillBonus =
    { name : String, bonus : Int }


type alias Senses =
    { blindsight : Int
    , darkvision : Int
    , tremorsense : Int
    , truesight : Int
    , passivePerception : Int
    }


type alias Feature =
    { name : String
    , description : String
    , usage : Maybe Usage
    }


type Usage
    = Recharge { low : Int, high : Int }
    | PerDay Int
    | PerShortRest Int
    | PerLongRest Int
    | AtWill


type alias LegendaryActions =
    { description : String
    , uses : Int
    , usesInLair : Int
    , options : List LegendaryOption
    }


type alias LegendaryOption =
    { name : String, cost : Int, description : String }


type alias LairActions =
    { initiative : Int, description : String, options : List Feature }


type alias RegionalEffects =
    { description : String, effects : List Feature, fadeAfter : String }


type alias Spellcasting =
    { description : String
    , ability : Ability
    , saveDc : Int
    , attackBonus : Int
    , atWill : List String
    , slots : List SpellSlotLevel
    , innatePerDay : List InnatePerDay
    }


type alias SpellSlotLevel =
    { level : Int, slots : Int, spells : List String }


type alias InnatePerDay =
    { uses : Int, spells : List String }


type alias CustomSection =
    { name : String, body : String }



-- ── DATABASE ─────────────────────────────────────────────────────────────────


{-| In-memory compendium. Wraps `List Creature` so future
storage changes (sorted index, lookup map, etc.) don't break
call sites.
-}
type Db
    = Db (List Creature)


fromList : List Creature -> Db
fromList =
    Db


toList : Db -> List Creature
toList (Db cs) =
    cs


count : Db -> Int
count (Db cs) =
    List.length cs


find : String -> Db -> Maybe Creature
find id (Db cs) =
    List.filter (\c -> c.id == id) cs |> List.head


{-| Case-insensitive name lookup. Used as a fallback when an
encounter's saved `creatureId` no longer matches anything in the
compendium (e.g. the creature was originally pasted under a
provisional id that has since drifted from the bundled UUIDs).
The first match wins — duplicate-name compendium entries aren't
disambiguated here, so the caller should treat the result as
"best effort".
-}
findByName : String -> Db -> Maybe Creature
findByName name (Db cs) =
    let
        target =
            String.toLower (String.trim name)
    in
    List.filter (\c -> String.toLower c.name == target) cs
        |> List.head



-- ── SEARCH / FILTER / SORT ───────────────────────────────────────────────────


{-| Substring match against name + race + alignment + source.
Case-insensitive. Empty query returns the full DB unchanged.
-}
search : String -> Db -> Db
search query (Db cs) =
    let
        needle =
            String.toLower (String.trim query)
    in
    if String.isEmpty needle then
        Db cs

    else
        Db
            (List.filter
                (\c ->
                    let
                        haystack =
                            String.toLower
                                (String.join " "
                                    [ c.name
                                    , c.race
                                    , c.alignment
                                    , c.source
                                    , c.challengeRating
                                    ]
                                )
                    in
                    String.contains needle haystack
                )
                cs
            )


filterByKind : List CreatureKind -> Db -> Db
filterByKind kinds (Db cs) =
    if List.isEmpty kinds then
        Db cs

    else
        Db (List.filter (\c -> List.member c.kind kinds) cs)


sortByName : Db -> Db
sortByName (Db cs) =
    Db (List.sortBy (.name >> String.toLower) cs)


sortByCr : Db -> Db
sortByCr (Db cs) =
    Db (List.sortBy (.challengeRating >> crToFloat) cs)


sortByRecency : Db -> Db
sortByRecency (Db cs) =
    Db (List.sortBy (\c -> -c.createdAt) cs)



-- ── HELPERS ──────────────────────────────────────────────────────────────────


{-| Build a fresh encounter combatant from a compendium template.

The compendium is a static catalog of templates; the encounter
queue carries live, mutable instances. This is the one-way
conversion. The caller passes:

  - `displayName` — the auto-numbered name to render. The
    Compendium → queue handoff in `Main.elm` computes this from
    the existing roster (e.g. `Goblin / Goblin 2 / Goblin 3`)
    rather than baking the suffix logic in here.
  - `initiativeRoll` — already-rolled initiative value.
    `Dice.batchRollCmd` sequences these so a multi-add doesn't
    collide on a shared millisecond seed.

The instance's `creatureId` field carries a back-reference to
the template's id so the future Quick View on cards can resolve
the source stat block.

-}
draftToInstance :
    { displayName : String, initiativeRoll : Int }
    -> Creature
    -> Encounter.Creature
draftToInstance { displayName, initiativeRoll } c =
    { name = displayName
    , kind = instanceKindLine c
    , initiative = initiativeRoll
    , initiativeBonus = c.initiativeBonus
    , currentHp = c.maxHp
    , maxHp = c.maxHp
    , tempHp = 0
    , armorClass = c.armorClass
    , speed = c.speed.walk
    , conditions = []
    , saveNotices = []
    , selected = False
    , cover = Encounter.NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    , bloodied = False
    , deathSaves = Encounter.emptyDeathSaves
    , holding = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Just c.id
    , hasLegendaryActions = c.legendaryActions /= Nothing
    , legendaryActionsUsed = Set.empty
    , hasLegendaryResistance = sourceHasLegendaryResistance c
    , legendaryResistanceUsed = Set.empty
    }


{-| Detect whether a compendium creature has the standard
"Legendary Resistance" trait. We don't have a structured field
for this — Legendary Resistance is one of the several recurring
traits authored as free text — so we check for the trait name
case-insensitively. The substring check matches both the bare
"Legendary Resistance" and the more usual "Legendary Resistance
(3/Day, or 4/Day in Lair)" forms.
-}
sourceHasLegendaryResistance : Creature -> Bool
sourceHasLegendaryResistance c =
    List.any
        (\t -> String.contains "legendary resistance" (String.toLower t.name))
        c.traits


{-| Build the human-readable "kind" line shown under the name on
the card. Mirrors the convention of the existing seed creatures
(e.g. "Half-elf rogue, lvl 5", "Giant"). For compendium-spawned
instances we synthesize from race + subrace + alignment when
each is set.
-}
instanceKindLine : Creature -> String
instanceKindLine c =
    let
        subraced =
            if String.isEmpty c.subrace then
                c.race

            else
                c.race ++ " (" ++ c.subrace ++ ")"

        withAlignment =
            if String.isEmpty c.alignment then
                subraced

            else
                subraced ++ ", " ++ c.alignment
    in
    withAlignment


{-| Convert a CR string ("1/4", "12", "—") to a float for sorting.
Unknown / dash entries land at -1 so they sort to the very end of
ascending CR sort.
-}
crToFloat : String -> Float
crToFloat raw =
    case String.split "/" (String.trim raw) of
        [ num, den ] ->
            Maybe.map2 (/)
                (String.toFloat num)
                (String.toFloat den)
                |> Maybe.withDefault -1

        [ single ] ->
            String.toFloat single |> Maybe.withDefault -1

        _ ->
            -1
