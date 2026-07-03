module Compendium exposing
    ( Creature, CreatureKind(..), Size(..)
    , Speed, Abilities, Ability(..), AbilitySave, SkillBonus
    , Senses, Feature, Usage(..)
    , LegendaryActions, LegendaryOption, LairActions, RegionalEffects
    , Spellcasting, SpellSlotLevel, InnatePerDay, CustomSection
    , Habitat(..), allHabitats, habitatLabel, habitatToWire, habitatFromWire, isPlanarHabitat
    , Treasure(..), allTreasures, treasureLabel, treasureToWire, treasureFromWire
    , Db, fromList, toList, count, upsert, remove
    , find, findByName, search, filterByKind, sortByName, sortByCr, sortByRecency
    , crToFloat
    , stripTrailingRecharge, appendRechargeSuffix
    , draftToInstance
    , instanceKindLine, sourceLegendaryResistanceBase, sourceLegendaryResistanceLairBonus, syncLegendaryFields
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
@docs Habitat, allHabitats, habitatLabel, habitatToWire, habitatFromWire, isPlanarHabitat
@docs Treasure, allTreasures, treasureLabel, treasureToWire, treasureFromWire


# Database

@docs Db, fromList, toList, count, upsert, remove


# Lookup / filter / sort

@docs find, findByName, search, filterByKind, sortByName, sortByCr, sortByRecency


# Helpers

@docs crToFloat
@docs stripTrailingRecharge, appendRechargeSuffix


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
    , habitats : List Habitat
    , treasures : List Treasure
    , tags : List String

    -- Free-text loot list — one entry per item the creature
    -- carries.  Surfaces at the bottom of the stat block and
    -- gets aggregated into the Treasure roller's output (one
    -- "Loot" row per item, no gp value computed — these are
    -- DM-flavor descriptions, not table values).  Empty by
    -- default on bundled SRD creatures; users can edit it via
    -- the Edit/Create creature modal.
    , loot : List String
    , createdAt : Int
    , updatedAt : Int
    , isBundled : Bool

    -- GM-set flag — when True, the creature has reaction
    -- mechanics worth a heads-up beyond the standard "one
    -- reaction per round" UX (Hydra's extra heads, Marilith's
    -- per-turn reaction, Vampire's Misty Escape, mephit Death
    -- Bursts, …).  Drives a visual swap on the card's reaction
    -- pip; toggled via a checkbox in the creature editor.
    , hasSpecialReactions : Bool
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


{-| 2024 Monster Manual habitat tag. The Material-Plane block
(Arctic … Urban) and the Planar block (Abyss … Upper Planes) sit
in one ADT so the editor can render them as a flat checklist and
the wire format is a single `List Habitat`.
-}
type Habitat
    = Arctic
    | Coastal
    | Desert
    | Forest
    | Grassland
    | Hill
    | Mountain
    | Swamp
    | Underdark
    | Underwater
    | Urban
    | Abyss
    | Acheron
    | AstralPlane
    | Beastlands
    | ElementalChaos
    | ElementalPlaneOfAir
    | ElementalPlaneOfEarth
    | ElementalPlaneOfFire
    | ElementalPlaneOfWater
    | Feywild
    | Limbo
    | LowerPlanes
    | NineHells
    | UpperPlanes


{-| Every `Habitat` constructor in display order: the Material-
Plane group first, then the Planar group. Used by the editor to
build the checkbox grid.
-}
allHabitats : List Habitat
allHabitats =
    [ Arctic
    , Coastal
    , Desert
    , Forest
    , Grassland
    , Hill
    , Mountain
    , Swamp
    , Underdark
    , Underwater
    , Urban
    , Abyss
    , Acheron
    , AstralPlane
    , Beastlands
    , ElementalChaos
    , ElementalPlaneOfAir
    , ElementalPlaneOfEarth
    , ElementalPlaneOfFire
    , ElementalPlaneOfWater
    , Feywild
    , Limbo
    , LowerPlanes
    , NineHells
    , UpperPlanes
    ]


{-| Human-readable label as it appears in the 2024 Monster Manual.
-}
habitatLabel : Habitat -> String
habitatLabel h =
    case h of
        Arctic ->
            "Arctic"

        Coastal ->
            "Coastal"

        Desert ->
            "Desert"

        Forest ->
            "Forest"

        Grassland ->
            "Grassland"

        Hill ->
            "Hill"

        Mountain ->
            "Mountain"

        Swamp ->
            "Swamp"

        Underdark ->
            "Underdark"

        Underwater ->
            "Underwater"

        Urban ->
            "Urban"

        Abyss ->
            "Abyss"

        Acheron ->
            "Acheron"

        AstralPlane ->
            "Astral Plane"

        Beastlands ->
            "Beastlands"

        ElementalChaos ->
            "Elemental Chaos"

        ElementalPlaneOfAir ->
            "Elemental Plane of Air"

        ElementalPlaneOfEarth ->
            "Elemental Plane of Earth"

        ElementalPlaneOfFire ->
            "Elemental Plane of Fire"

        ElementalPlaneOfWater ->
            "Elemental Plane of Water"

        Feywild ->
            "Feywild"

        Limbo ->
            "Limbo"

        LowerPlanes ->
            "Lower Planes"

        NineHells ->
            "Nine Hells"

        UpperPlanes ->
            "Upper Planes"


{-| Kebab-case wire token. Matches `#[serde(rename_all =
"kebab-case")]` on the Rust enum so the JSON round-trips.
-}
habitatToWire : Habitat -> String
habitatToWire h =
    case h of
        Arctic ->
            "arctic"

        Coastal ->
            "coastal"

        Desert ->
            "desert"

        Forest ->
            "forest"

        Grassland ->
            "grassland"

        Hill ->
            "hill"

        Mountain ->
            "mountain"

        Swamp ->
            "swamp"

        Underdark ->
            "underdark"

        Underwater ->
            "underwater"

        Urban ->
            "urban"

        Abyss ->
            "abyss"

        Acheron ->
            "acheron"

        AstralPlane ->
            "astral-plane"

        Beastlands ->
            "beastlands"

        ElementalChaos ->
            "elemental-chaos"

        ElementalPlaneOfAir ->
            "elemental-plane-of-air"

        ElementalPlaneOfEarth ->
            "elemental-plane-of-earth"

        ElementalPlaneOfFire ->
            "elemental-plane-of-fire"

        ElementalPlaneOfWater ->
            "elemental-plane-of-water"

        Feywild ->
            "feywild"

        Limbo ->
            "limbo"

        LowerPlanes ->
            "lower-planes"

        NineHells ->
            "nine-hells"

        UpperPlanes ->
            "upper-planes"


{-| Inverse of `habitatToWire`. Returns `Nothing` for unknown
tokens so wire decoding can drop them silently rather than
failing the whole creature payload — habitats are a low-stakes
field and forward-compat tags shouldn't break the load path.
-}
habitatFromWire : String -> Maybe Habitat
habitatFromWire s =
    case s of
        "arctic" ->
            Just Arctic

        "coastal" ->
            Just Coastal

        "desert" ->
            Just Desert

        "forest" ->
            Just Forest

        "grassland" ->
            Just Grassland

        "hill" ->
            Just Hill

        "mountain" ->
            Just Mountain

        "swamp" ->
            Just Swamp

        "underdark" ->
            Just Underdark

        "underwater" ->
            Just Underwater

        "urban" ->
            Just Urban

        "abyss" ->
            Just Abyss

        "acheron" ->
            Just Acheron

        "astral-plane" ->
            Just AstralPlane

        "beastlands" ->
            Just Beastlands

        "elemental-chaos" ->
            Just ElementalChaos

        "elemental-plane-of-air" ->
            Just ElementalPlaneOfAir

        "elemental-plane-of-earth" ->
            Just ElementalPlaneOfEarth

        "elemental-plane-of-fire" ->
            Just ElementalPlaneOfFire

        "elemental-plane-of-water" ->
            Just ElementalPlaneOfWater

        "feywild" ->
            Just Feywild

        "limbo" ->
            Just Limbo

        "lower-planes" ->
            Just LowerPlanes

        "nine-hells" ->
            Just NineHells

        "upper-planes" ->
            Just UpperPlanes

        _ ->
            Nothing


{-| Predicate used by the editor view to split the checkbox grid
into the Material-Plane column and the Planar column.
-}
isPlanarHabitat : Habitat -> Bool
isPlanarHabitat h =
    case h of
        Arctic ->
            False

        Coastal ->
            False

        Desert ->
            False

        Forest ->
            False

        Grassland ->
            False

        Hill ->
            False

        Mountain ->
            False

        Swamp ->
            False

        Underdark ->
            False

        Underwater ->
            False

        Urban ->
            False

        _ ->
            True


{-| 2024 Monster Manual treasure tag. The four buckets describe
the _kind_ of magic items a creature's hoard is likely to seed.
Like `Habitat`, the field is decorative — the wire format is a
flat `List Treasure` and unknown tokens drop on decode.
-}
type Treasure
    = Arcana
    | Armaments
    | Implements
    | Relics


allTreasures : List Treasure
allTreasures =
    [ Arcana, Armaments, Implements, Relics ]


treasureLabel : Treasure -> String
treasureLabel t =
    case t of
        Arcana ->
            "Arcana"

        Armaments ->
            "Armaments"

        Implements ->
            "Implements"

        Relics ->
            "Relics"


treasureToWire : Treasure -> String
treasureToWire t =
    case t of
        Arcana ->
            "arcana"

        Armaments ->
            "armaments"

        Implements ->
            "implements"

        Relics ->
            "relics"


treasureFromWire : String -> Maybe Treasure
treasureFromWire s =
    case s of
        "arcana" ->
            Just Arcana

        "armaments" ->
            Just Armaments

        "implements" ->
            Just Implements

        "relics" ->
            Just Relics

        _ ->
            Nothing



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


{-| Insert-or-replace a creature by id. Used by anonymous-mode
local CRUD: every create / edit submits through here so the
in-memory store is the source of truth that the localStorage
persistence layer mirrors.

If a creature with the same id already exists it's replaced in
place (preserving list order); otherwise the new creature is
appended.

-}
upsert : Creature -> Db -> Db
upsert creature (Db cs) =
    let
        replaced =
            List.map
                (\c ->
                    if c.id == creature.id then
                        creature

                    else
                        c
                )
                cs
    in
    if List.any (\c -> c.id == creature.id) cs then
        Db replaced

    else
        Db (cs ++ [ creature ])


{-| Remove a creature by id. No-op if the id isn't found.
Anonymous-mode delete path uses this; the authenticated path goes
through the server and the response handler does the equivalent
in-memory mutation.
-}
remove : String -> Db -> Db
remove id (Db cs) =
    Db (List.filter (\c -> c.id /= id) cs)


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
    , originalMaxHp = c.maxHp
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
    , acceptingDeathSaves = False
    , reactionUsed = False
    , rechargeAbilities = rechargeAbilitiesFor c
    , readied = False
    , inactive = False
    , note = ""
    , memo = ""
    , timer = Nothing
    , creatureId = Just c.id
    , legendaryActionsCount =
        case c.legendaryActions of
            Just la ->
                la.uses

            Nothing ->
                0
    , legendaryActionsLairBonus =
        case c.legendaryActions of
            Just la ->
                max 0 (la.usesInLair - la.uses)

            Nothing ->
                0
    , legendaryActionsUsed = Set.empty
    , legendaryResistanceCount = sourceLegendaryResistanceBase c
    , legendaryResistanceLairBonus = sourceLegendaryResistanceLairBonus c
    , legendaryResistanceUsed = Set.empty
    , isPlaceholder = False
    , creatureKind = kindKey c.kind
    , race = c.race
    , alignment = c.alignment
    , surprised = False
    , hasSpecialReactions = c.hasSpecialReactions
    }


{-| Refresh the stat-block-derived legendary fields on an
in-encounter creature from the latest compendium source.

The four legendary counts (`legendaryActionsCount`,
`legendaryActionsLairBonus`, `legendaryResistanceCount`,
`legendaryResistanceLairBonus`) are constants that come from the
stat block, not encounter state — they should track whatever the
compendium currently says. The "used" sets are NOT touched; they
belong to the encounter run and the GM owns them.

This is called after the compendium DB loads so encounters that
were saved before a creature's stat block grew lair-bonus data
pick up the new values automatically, instead of waiting for the
GM to remove and re-add the creature.

Creatures with no `creatureId` (anonymous-mode adds, custom
inline blocks) are left untouched — there's no source to sync
against.

-}
syncLegendaryFields : Db -> Encounter.Creature -> Encounter.Creature
syncLegendaryFields db ec =
    case ec.creatureId |> Maybe.andThen (\id -> find id db) of
        Nothing ->
            ec

        Just src ->
            let
                ( laCount, laLairBonus ) =
                    case src.legendaryActions of
                        Just la ->
                            ( la.uses, max 0 (la.usesInLair - la.uses) )

                        Nothing ->
                            ( 0, 0 )
            in
            { ec
                | legendaryActionsCount = laCount
                , legendaryActionsLairBonus = laLairBonus
                , legendaryResistanceCount = sourceLegendaryResistanceBase src
                , legendaryResistanceLairBonus = sourceLegendaryResistanceLairBonus src
            }


{-| Lowercase wire token for a creature kind. Matches the value
written into `Encounter.Creature.creatureKind` so the Kind Badge
in the Custom Card renderer can branch on the same string in
either spawn path (compendium-spawned creatures, anonymous-mode
localStorage round-trips, server saves).
-}
kindKey : CreatureKind -> String
kindKey k =
    case k of
        Player ->
            "player"

        Enemy ->
            "enemy"

        Npc ->
            "npc"


{-| The first integer in the creature's Legendary Resistance
trait name — the base per-day count. Returns 0 when the
creature has no Legendary Resistance trait, since that's the
signal the view uses ("no LR column").

The trait name conventionally encodes the count in one of two
forms:

    "Legendary Resistance (3/Day)"

    "Legendary Resistance (4/Day, or 5/Day in Lair)"

We scan the name for digits and take the first run as base.
A creature whose trait is named just "Legendary Resistance"
(no parenthetical) defaults to 3 — the 5e historical norm.

-}
sourceLegendaryResistanceBase : Creature -> Int
sourceLegendaryResistanceBase c =
    case findLegendaryResistanceTrait c of
        Nothing ->
            0

        Just trait ->
            case collectIntegers trait.name of
                base :: _ ->
                    base

                [] ->
                    3


{-| The lair bonus pip count — how many EXTRA pips appear when
the creature is in its lair, on top of `sourceLegendaryResistanceBase`.
Returns 0 when there is no Legendary Resistance trait, when
the trait doesn't encode an "or M/Day in Lair" clause, or when
the lair count isn't higher than the base.
-}
sourceLegendaryResistanceLairBonus : Creature -> Int
sourceLegendaryResistanceLairBonus c =
    case findLegendaryResistanceTrait c of
        Nothing ->
            0

        Just trait ->
            case collectIntegers trait.name of
                base :: inLair :: _ ->
                    max 0 (inLair - base)

                _ ->
                    0


findLegendaryResistanceTrait : Creature -> Maybe Feature
findLegendaryResistanceTrait c =
    c.traits
        |> List.filter
            (\t -> String.contains "legendary resistance" (String.toLower t.name))
        |> List.head


{-| Pull every run of consecutive digit characters out of a
string and parse them as integers in order. Non-digit
characters act as separators. Used by the Legendary Resistance
parsers to extract `(N/Day, or M/Day in Lair)` counts.
-}
collectIntegers : String -> List Int
collectIntegers s =
    s
        |> String.map
            (\c ->
                if Char.isDigit c then
                    c

                else
                    ' '
            )
        |> String.words
        |> List.filterMap String.toInt


{-| Walk every Feature on a compendium creature (traits, actions,
bonus actions, reactions) and emit one `Encounter.RechargeAbility`
per feature whose `usage` is `Recharge`. Spawned instances start
with all recharge abilities `ready = True`. Legendary-action
options are excluded — they have their own pip-strip mechanism
(`legendaryActionsUsed`) and don't use the recharge model.
-}
rechargeAbilitiesFor : Creature -> List Encounter.RechargeAbility
rechargeAbilitiesFor c =
    [ c.traits, c.actions, c.bonusActions, c.reactions ]
        |> List.concat
        |> List.filterMap rechargeAbilityFromFeature


{-| Extract a `RechargeAbility` from a Feature when possible.

Two paths are tried, in order:

  - **Structured**: the feature's `usage` is `Recharge { low, high }`.
    The canonical shape, but the bundled SRD 5.2.1 data doesn't
    populate it — those features carry `usage = null` and bake the
    recharge into the name instead.
  - **Name fallback**: parse a trailing `(Recharge N)` or
    `(Recharge N-M)` suffix on the feature name (e.g.
    "Petrifying Gaze (Recharge 4-6)" → 4–6). Handles both `-` and
    `–` (en-dash) since stat-block prose varies. Strip the suffix
    from the stored name so the chip reads "Petrifying Gaze"
    instead of repeating the range.

`(Recharge after a Short or Long Rest)` and similar phrasings
fall through to `Nothing` — those aren't d6-recharge mechanics
and don't fit this tracker.

-}
rechargeAbilityFromFeature : Feature -> Maybe Encounter.RechargeAbility
rechargeAbilityFromFeature f =
    case f.usage of
        Just (Recharge { low, high }) ->
            Just { name = f.name, low = low, high = high, ready = True, awaitingRoll = False }

        _ ->
            parseRechargeFromName f.name


parseRechargeFromName : String -> Maybe Encounter.RechargeAbility
parseRechargeFromName fullName =
    let
        ( before, suffix ) =
            splitOnLastOpenParen fullName

        cleanedName =
            String.trimRight before
    in
    rangeFromSuffix suffix
        |> Maybe.map
            (\( low, high ) ->
                { name = cleanedName, low = low, high = high, ready = True, awaitingRoll = False }
            )


{-| Split a string into `(before-last-paren, parenthetical-content)`.
For `"Petrifying Gaze (Recharge 4-6)"` returns `("Petrifying Gaze ",
"Recharge 4-6)")`. When no `(` is present, returns the input and an
empty string so the caller skips the parse.
-}
splitOnLastOpenParen : String -> ( String, String )
splitOnLastOpenParen s =
    case String.indexes "(" s |> List.reverse |> List.head of
        Just idx ->
            ( String.left idx s
            , String.dropLeft (idx + 1) s
            )

        Nothing ->
            ( s, "" )


{-| Pull `(low, high)` out of a parenthetical like
`"Recharge 4-6)"` or `"Recharge 5)"`. Accepts ASCII `-` and the
en-dash `–` as the range separator; ignores trailing characters
after the closing paren (or its absence).
-}
rangeFromSuffix : String -> Maybe ( Int, Int )
rangeFromSuffix suffix =
    let
        trimmed =
            suffix
                |> String.replace ")" ""
                |> String.trim
    in
    case String.words trimmed of
        [ "Recharge", range ] ->
            parseRechargeRange range

        _ ->
            Nothing


parseRechargeRange : String -> Maybe ( Int, Int )
parseRechargeRange range =
    let
        normalised =
            String.replace "–" "-" range
    in
    case String.split "-" normalised of
        [ singleVal ] ->
            String.toInt singleVal
                |> Maybe.map (\n -> ( n, n ))

        [ low, high ] ->
            Maybe.map2 Tuple.pair (String.toInt low) (String.toInt high)

        _ ->
            Nothing


{-| Drop a trailing `(Recharge N)` / `(Recharge N-M)` /
`(Recharge N–M)` parenthetical from a feature name, returning the
input unchanged if no such suffix is present. Used by the
Compendium Edit form to keep the canonical mechanic in the
structured `usage` field instead of duplicated in the name — see
the comment at `rechargeAbilityFromFeature` for the back-story on
why the two sources can otherwise diverge.

`(Recharge after a Short or Long Rest)` and other non-d6 phrasings
intentionally fall through (they don't parse as a range), so the
helper only strips the d6-recharge form that the tracker
understands.

-}
stripTrailingRecharge : String -> String
stripTrailingRecharge name =
    let
        ( before, suffix ) =
            splitOnLastOpenParen name
    in
    case rangeFromSuffix suffix of
        Just _ ->
            String.trimRight before

        Nothing ->
            name


{-| Inverse of `stripTrailingRecharge`: append a
`(Recharge N-M)` (or `(Recharge N)` when low == high)
parenthetical to a name. If the name already carries a
trailing recharge parenthetical it's replaced rather than
duplicated.
-}
appendRechargeSuffix : { low : Int, high : Int } -> String -> String
appendRechargeSuffix { low, high } name =
    let
        rangeText =
            if low == high then
                String.fromInt low

            else
                String.fromInt low ++ "-" ++ String.fromInt high

        stripped =
            stripTrailingRecharge name
    in
    stripped ++ " (Recharge " ++ rangeText ++ ")"


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
