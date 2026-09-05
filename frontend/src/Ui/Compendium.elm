module Ui.Compendium exposing
    ( CompendiumDb(..), CompendiumUi, PendingAction(..)
    , CompendiumPasteUi, emptyPaste
    , CompendiumEditUi, EditMode(..), FeatureDraft, blankEdit
    , editFromCreature, featureToDraft, emptyFeatureDraft
    , validateEdit
    , emptyCompendium, compendiumVisible
    , kindFilterAsList, compendiumSort, kindFromString, kindToString
    , creatureKindLabel
    , parseIntOr, parseCsv, saveRowToValue, skillRowToValue
    , draftToFeature, customSectionRowToValue
    , TagFilter(..), addGroup, closeMenus, currentCreatures, groupsList, markSaved, removeGroup, tagFilterFromWire, tagFilterToWire, userTagsInDb, visibleGroups
    )

{-| Compendium browser + paste + edit modal state, plus helpers
that derive views over the loaded `Db` and project the edit
form back into a `Compendium.Creature` on submit.

This is the largest of the per-feature `Ui/*` modules — it owns
the browser, paste, and edit modals, plus the bulk-action
pending state.

@docs CompendiumDb, CompendiumUi, PendingAction
@docs CompendiumPasteUi, emptyPaste
@docs CompendiumEditUi, EditMode, FeatureDraft, blankEdit
@docs editFromCreature, featureToDraft, emptyFeatureDraft
@docs validateEdit
@docs emptyCompendium, compendiumVisible
@docs kindFilterAsList, compendiumSort, kindFromString, kindToString
@docs creatureKindLabel
@docs parseIntOr, parseCsv, saveRowToValue, skillRowToValue
@docs draftToFeature, customSectionRowToValue

-}

import Compendium
import Compendium.Group as Group exposing (Group)
import Compendium.Parser
import Dict exposing (Dict)
import Http
import Msg exposing (CompendiumBulkMenu, CompendiumSort(..))
import Set exposing (Set)



-- ── PASTE MODAL ──────────────────────────────────────────────────────────────


{-| Paste-stat-block modal. The textarea is `text`; the parsed
result lives in `parseResult` and is recomputed on every change
so the live preview stays in sync. The "Apply to Form" handoff
just plucks the `Ok` creature, populates a fresh
`CompendiumEditUi` via `editFromCreature`, flips it to
`CreateMode` (so the GM can review/save), and closes this modal.
-}
type alias CompendiumPasteUi =
    { text : String
    , parseResult : Result Compendium.Parser.ParseError Compendium.Creature
    }


emptyPaste : CompendiumPasteUi
emptyPaste =
    { text = ""
    , parseResult = Err Compendium.Parser.EmptyInput
    }



-- ── BROWSER ──────────────────────────────────────────────────────────────────


{-| Compendium browser state. Always present — the library is
fetched on app boot, and the browser itself renders as the
standalone /compendium tab.

`db` is `RemoteData`-shaped because the boot fetch can fail or
still be in flight when the user clicks "Open". The browser
modal shows a loading skeleton in those states rather than
rendering an empty list.

`searchText`, `kindFilter`, `sort` are the filter-bar inputs;
they apply to a derived `Db` view at render time, not to the
canonical list.

`selectedId` tracks which creature's stat block is in the right
pane. Nothing is selected until the GM clicks a row.

-}
type alias CompendiumUi =
    { db : CompendiumDb
    , searchText : String
    , kindFilter : Set String
    , sort : CompendiumSort
    , tagFilter : Maybe TagFilter
    , selectedId : Maybe String
    , showOnlyAdded : Bool
    , pending : Maybe PendingAction

    -- Bulk-selection state for the row checkboxes that drive
    -- the Clear-Selected action.  Independent of `selectedId`
    -- (which picks the right-pane stat block).
    , selectedIds : Set String

    -- Compendium id whose "[N] in Encounter" badge is mid-flash.
    -- Set by an add, cleared by a timed message, so the count
    -- change is visibly acknowledged where the eye already is.
    , badgeFlashFor : Maybe String

    -- Bulk-action split-button popover state.  At most one of
    -- the Clear / Import / Export dropdowns is open at a time;
    -- `Nothing` collapses all three.  Replaces the older
    -- per-menu `clearMenuOpen : Bool` so the "only one open"
    -- invariant lives in the type system.
    , bulkMenu : Maybe CompendiumBulkMenu

    -- Library-altered flag.  Goes True on any add / edit /
    -- delete, clears on reset / import / export so the GM sees
    -- a yellow border on Export when there's something worth
    -- saving.  Session-only — resets on page reload.
    , compendiumDirty : Bool
    , bulkBusy : Bool
    , bulkError : Maybe String

    -- Last server-side compendium snapshot name the user saved
    -- to / loaded from.  Pre-fills the Save modal's filename
    -- input and lets the toast / banner identify the snapshot.
    -- Session-only.
    , savedAs : Maybe String

    -- Show / hide creature groups in the browser list.  Toggled
    -- by the "Groups" chip on the right of the kind filters.
    , showGroups : Bool

    -- In-memory group store.  Will move to a server-side
    -- `JsonFileStore<Group>` per user in a follow-up; for now
    -- groups live until the page reloads.  Keyed by `Group.id`
    -- so updates / deletes are O(1).
    , groups : Dict String Group

    -- Which groups are expanded in the compendium list (their
    -- per-entry rows are visible underneath the group header
    -- row).  Set rather than `Bool` per group so the canonical
    -- group record stays purely about the group's *contents*.
    , expandedGroupIds : Set String

    -- Which group is selected in the right-pane stat block.
    -- Mutually exclusive with `selectedId` (creature selection);
    -- clicking a group row clears `selectedId` and vice versa.
    , selectedGroupId : Maybe String

    -- Top-level disclosure for the new "Lore groups" section
    -- that sits above the user-created groups in the list.
    -- Collapsed by default to keep the list tidy on first
    -- open — the GM expands when they want to browse / pick.
    , loreGroupsExpanded : Bool

    -- Per-row member-list expansion state for lore groups —
    -- mirrors `expandedGroupIds` but addresses lore-group ids
    -- (bundled or user-curated).
    , expandedLoreIds : Set String

    -- Selected lore group (drives the right-pane action bar
    -- and members detail). Mutually exclusive with both
    -- `selectedId` (creature) and `selectedGroupId` (regular
    -- group) — at most one selection lives at a time across
    -- the three axes.
    , selectedLoreId : Maybe String
    }


{-| Two-step confirmation for destructive bulk operations.
Click once on Reset / Import to set the pending action +
inline banner; click "Confirm" in the banner to fire the
actual Cmd.

`PendingImport` carries the parsed creature list and the
caller's groups (if the export file included them) so the
confirmation banner re-uses both without re-reading the file.
The third field is the creature count we surface in the
confirm message; groups don't get their own count line because
they're a secondary detail.

`PendingDelete` carries `(creatureId, displayName)` for the
confirmation message.

-}
type PendingAction
    = PendingReset
    | PendingClear
    | PendingImport (List Compendium.Creature) (List Group) Int
    | PendingDelete String String


type CompendiumDb
    = CompendiumDbLoading
    | CompendiumDbLoaded Compendium.Db
    | CompendiumDbFailed Http.Error


emptyCompendium : CompendiumUi
emptyCompendium =
    { db = CompendiumDbLoading
    , searchText = ""
    , kindFilter = Set.empty
    , sort = SortName
    , tagFilter = Nothing
    , selectedId = Nothing
    , showOnlyAdded = False
    , pending = Nothing
    , selectedIds = Set.empty
    , badgeFlashFor = Nothing
    , bulkMenu = Nothing
    , compendiumDirty = False
    , bulkBusy = False
    , bulkError = Nothing
    , savedAs = Nothing
    , showGroups = True
    , groups = Dict.empty
    , expandedGroupIds = Set.empty
    , selectedGroupId = Nothing
    , loreGroupsExpanded = False
    , expandedLoreIds = Set.empty
    , selectedLoreId = Nothing
    }


{-| Pull the canonical creature list out of the loading-state
`Db` wrapper. Returns `[]` while the initial `GET
/api/compendium/creatures` is in flight or has errored — the
Save modal disables submit in that case via its `busy` flag,
so the empty result is never persisted.
-}
currentCreatures : CompendiumUi -> List Compendium.Creature
currentCreatures ui =
    case ui.db of
        CompendiumDbLoaded db ->
            Compendium.toList db

        _ ->
            []


{-| Apply the post-save bookkeeping: clear the dirty flag (the
on-disk snapshot is now in sync) and remember the snapshot name
so the next open of the Save modal pre-fills it. Mirrors the
encounter modal's `savedAs` / `savedSnapshot` discipline.
-}
markSaved : String -> CompendiumUi -> CompendiumUi
markSaved name ui =
    { ui
        | compendiumDirty = False
        , savedAs = Just name
    }


{-| Close any compendium-modal popovers (Clear dropdown today;
Import / Export dropdowns when Phase D lands). Called when a
modal-on-top-of-the-modal opens so the popover doesn't linger
behind it.
-}
closeMenus : CompendiumUi -> CompendiumUi
closeMenus ui =
    { ui | bulkMenu = Nothing }


{-| The browser "Tag" dropdown filters by either a Habitat or a
user-authored tag. Encoded as a sum so the wire token decode
returns a closed value rather than a raw string.
-}
type TagFilter
    = TagFilterHabitat Compendium.Habitat
    | TagFilterTag String


{-| Filter / sort pipeline against the loaded `Db`. Empty
search and empty kind filter are no-ops, so a freshly opened
modal shows the full library.
-}
compendiumVisible : CompendiumUi -> List Compendium.Creature
compendiumVisible ui =
    case ui.db of
        CompendiumDbLoaded db ->
            db
                |> Compendium.search ui.searchText
                |> Compendium.filterByKind (kindFilterAsList ui.kindFilter)
                |> filterByTag ui.tagFilter
                |> compendiumSort ui.sort
                |> Compendium.toList

        _ ->
            []


filterByTag : Maybe TagFilter -> Compendium.Db -> Compendium.Db
filterByTag maybeFilter db =
    case maybeFilter of
        Nothing ->
            db

        Just (TagFilterHabitat h) ->
            db
                |> Compendium.toList
                |> List.filter (\c -> List.member h c.habitats)
                |> Compendium.fromList

        Just (TagFilterTag t) ->
            db
                |> Compendium.toList
                |> List.filter (\c -> List.member t c.tags)
                |> Compendium.fromList


{-| Distinct user-authored tags across every creature in the
loaded compendium, sorted alphabetically. The browser's Tag
dropdown reads from this to build its second optgroup; the list
goes empty when no creature carries a tag, which is the
"no separate tag DB" invariant the feature is designed around.
-}
userTagsInDb : CompendiumUi -> List String
userTagsInDb ui =
    case ui.db of
        CompendiumDbLoaded db ->
            db
                |> Compendium.toList
                |> List.concatMap .tags
                |> List.sort
                |> dedupOrdered

        _ ->
            []


{-| Wire token used by the `<select>` `<option>` value attribute.
A leading prefix distinguishes habitat tokens from user tags so a
habitat named identically to a user tag doesn't collide.
-}
tagFilterToWire : TagFilter -> String
tagFilterToWire f =
    case f of
        TagFilterHabitat h ->
            "habitat:" ++ Compendium.habitatToWire h

        TagFilterTag t ->
            "tag:" ++ t


tagFilterFromWire : String -> Maybe TagFilter
tagFilterFromWire s =
    if String.startsWith "habitat:" s then
        Compendium.habitatFromWire (String.dropLeft 8 s)
            |> Maybe.map TagFilterHabitat

    else if String.startsWith "tag:" s then
        Just (TagFilterTag (String.dropLeft 4 s))

    else
        Nothing


kindFilterAsList : Set String -> List Compendium.CreatureKind
kindFilterAsList set =
    List.filterMap kindFromString (Set.toList set)


compendiumSort : CompendiumSort -> Compendium.Db -> Compendium.Db
compendiumSort sort =
    case sort of
        SortName ->
            Compendium.sortByName

        SortCr ->
            Compendium.sortByCr

        SortRecency ->
            Compendium.sortByRecency


kindFromString : String -> Maybe Compendium.CreatureKind
kindFromString s =
    case s of
        "player" ->
            Just Compendium.Player

        "enemy" ->
            Just Compendium.Enemy

        "npc" ->
            Just Compendium.Npc

        _ ->
            Nothing


kindToString : Compendium.CreatureKind -> String
kindToString k =
    case k of
        Compendium.Player ->
            "player"

        Compendium.Enemy ->
            "enemy"

        Compendium.Npc ->
            "npc"



-- ── EDIT MODAL ───────────────────────────────────────────────────────────────


{-| Edit / create modal state. Lives at the model root rather
than inside `CompendiumUi` because the form is a self-contained
modal that can be opened from the compendium page (or
directly).

`mode` carries the path the modal will follow on submit:
`CreateMode` POSTs a draft, `EditExisting` PUTs against the
captured id (and preserves `createdAt` so the server-side
timestamp doesn't get clobbered).

Most fields are `String` even when the underlying schema is
`Int`, because numeric `<input>`s round-trip through strings
anyway and we want transient typing states (empty input, partial
number) to be preserved across re-renders. Validation runs on
submit, not per keystroke.

The four advanced sections (`legendaryActions`, `lairActions`,
`regionalEffects`, `spellcasting`) are pass-through-only in this
MVP form: opening an existing creature with those populated
keeps them, the form just doesn't expose editors for them yet.

-}
type alias CompendiumEditUi =
    { mode : EditMode
    , name : String
    , kind : Compendium.CreatureKind
    , size : Compendium.Size
    , race : String
    , subrace : String
    , alignment : String
    , source : String
    , description : String
    , armorClass : String
    , armorClassNote : String
    , maxHp : String
    , hpFormula : String
    , initiativeBonus : String
    , speedWalk : String
    , speedFly : String
    , speedSwim : String
    , speedClimb : String
    , speedBurrow : String
    , speedHover : Bool
    , abilityStr : String
    , abilityDex : String
    , abilityCon : String
    , abilityInt : String
    , abilityWis : String
    , abilityCha : String
    , savingThrows : List ( Compendium.Ability, String )
    , skills : List ( String, String )
    , damageVulnerabilities : List String
    , damageResistances : List String
    , damageImmunities : List String
    , conditionImmunities : List String
    , sensesBlindsight : String
    , sensesDarkvision : String
    , sensesTremorsense : String
    , sensesTruesight : String
    , sensesPassivePerception : String
    , languages : String
    , challengeRating : String
    , xp : String
    , xpInLair : String
    , proficiencyBonus : String
    , traits : List FeatureDraft
    , actions : List FeatureDraft
    , bonusActions : List FeatureDraft
    , reactions : List FeatureDraft
    , customSections : List ( String, String )
    , legendaryActions : Maybe Compendium.LegendaryActions
    , lairActions : Maybe Compendium.LairActions
    , regionalEffects : Maybe Compendium.RegionalEffects
    , spellcasting : Maybe Compendium.Spellcasting
    , habitats : List Compendium.Habitat
    , treasures : List Compendium.Treasure
    , tags : List String

    -- Free-text loot items the GM has typed in for this
    -- creature.  Surfaces at the bottom of the stat block and
    -- aggregates into Treasure-roller output (one "Loot" row per
    -- item, no gp computed).
    , loot : List String

    -- GM-set checkbox in the editor.  Mirrors
    -- `Compendium.Creature.hasSpecialReactions` — flipping it
    -- changes the card's reaction-pip glyph to a bold yellow
    -- `!` for instances of this creature.
    , hasSpecialReactions : Bool
    , submitting : Bool
    , submitError : Maybe String
    }


type EditMode
    = CreateMode
    | EditExisting { id : String, createdAt : Int }


type alias FeatureDraft =
    { name : String
    , description : String
    , usage : Maybe Compendium.Usage
    }


blankEdit : CompendiumEditUi
blankEdit =
    { mode = CreateMode
    , name = ""
    , kind = Compendium.Enemy
    , size = Compendium.Medium
    , race = ""
    , subrace = ""
    , alignment = ""
    , source = "Custom"
    , description = ""
    , armorClass = "10"
    , armorClassNote = ""
    , maxHp = "1"
    , hpFormula = ""
    , initiativeBonus = "0"
    , speedWalk = "30"
    , speedFly = "0"
    , speedSwim = "0"
    , speedClimb = "0"
    , speedBurrow = "0"
    , speedHover = False
    , abilityStr = "10"
    , abilityDex = "10"
    , abilityCon = "10"
    , abilityInt = "10"
    , abilityWis = "10"
    , abilityCha = "10"
    , savingThrows = []
    , skills = []
    , damageVulnerabilities = []
    , damageResistances = []
    , damageImmunities = []
    , conditionImmunities = []
    , sensesBlindsight = "0"
    , sensesDarkvision = "0"
    , sensesTremorsense = "0"
    , sensesTruesight = "0"
    , sensesPassivePerception = "10"
    , languages = ""
    , challengeRating = ""
    , xp = "0"
    , xpInLair = "0"
    , proficiencyBonus = "2"
    , traits = []
    , actions = []
    , bonusActions = []
    , reactions = []
    , customSections = []
    , legendaryActions = Nothing
    , lairActions = Nothing
    , regionalEffects = Nothing
    , spellcasting = Nothing
    , habitats = []
    , treasures = []
    , tags = []
    , loot = []
    , hasSpecialReactions = False
    , submitting = False
    , submitError = Nothing
    }


{-| Pre-fill the form with an existing creature's fields.

Numeric fields stringify; lists become comma-separated strings;
saves/skills/features stay as structured rows; the four advanced
sections pass through verbatim.

-}
editFromCreature : Compendium.Creature -> CompendiumEditUi
editFromCreature c =
    { mode = EditExisting { id = c.id, createdAt = c.createdAt }
    , name = c.name
    , kind = c.kind
    , size = c.size
    , race = c.race
    , subrace = c.subrace
    , alignment = c.alignment
    , source = c.source
    , description = c.description
    , armorClass = String.fromInt c.armorClass
    , armorClassNote = c.armorClassNote
    , maxHp = String.fromInt c.maxHp
    , hpFormula = c.hpFormula
    , initiativeBonus = String.fromInt c.initiativeBonus
    , speedWalk = String.fromInt c.speed.walk
    , speedFly = String.fromInt c.speed.fly
    , speedSwim = String.fromInt c.speed.swim
    , speedClimb = String.fromInt c.speed.climb
    , speedBurrow = String.fromInt c.speed.burrow
    , speedHover = c.speed.hover
    , abilityStr = String.fromInt c.abilities.str
    , abilityDex = String.fromInt c.abilities.dex
    , abilityCon = String.fromInt c.abilities.con
    , abilityInt = String.fromInt c.abilities.int
    , abilityWis = String.fromInt c.abilities.wis
    , abilityCha = String.fromInt c.abilities.cha
    , savingThrows = List.map (\s -> ( s.ability, String.fromInt s.bonus )) c.savingThrows
    , skills = List.map (\s -> ( s.name, String.fromInt s.bonus )) c.skills
    , damageVulnerabilities = c.damageVulnerabilities
    , damageResistances = c.damageResistances
    , damageImmunities = c.damageImmunities
    , conditionImmunities = c.conditionImmunities
    , sensesBlindsight = String.fromInt c.senses.blindsight
    , sensesDarkvision = String.fromInt c.senses.darkvision
    , sensesTremorsense = String.fromInt c.senses.tremorsense
    , sensesTruesight = String.fromInt c.senses.truesight
    , sensesPassivePerception = String.fromInt c.senses.passivePerception
    , languages = String.join ", " c.languages
    , challengeRating = c.challengeRating
    , xp = String.fromInt c.xp
    , xpInLair = String.fromInt c.xpInLair
    , proficiencyBonus = String.fromInt c.proficiencyBonus
    , traits = List.map featureToDraft c.traits
    , actions = List.map featureToDraft c.actions
    , bonusActions = List.map featureToDraft c.bonusActions
    , reactions = List.map featureToDraft c.reactions
    , customSections = List.map (\s -> ( s.name, s.body )) c.customSections
    , legendaryActions = c.legendaryActions
    , lairActions = c.lairActions
    , regionalEffects = c.regionalEffects
    , spellcasting = c.spellcasting
    , habitats = c.habitats
    , treasures = c.treasures
    , tags = c.tags
    , loot = c.loot
    , hasSpecialReactions = c.hasSpecialReactions
    , submitting = False
    , submitError = Nothing
    }


featureToDraft : Compendium.Feature -> FeatureDraft
featureToDraft f =
    { name = f.name, description = f.description, usage = f.usage }


emptyFeatureDraft : FeatureDraft
emptyFeatureDraft =
    { name = "", description = "", usage = Nothing }


{-| Run validation and produce the final `Compendium.Creature`
to ship over the wire. Required fields: name, AC, max HP.
Numeric fields default to a sensible base if empty; list fields
split on commas with empty entries discarded. The result is a
`Creature` even for `CreateMode` (with empty id / 0 timestamps)
so the same encoder covers both POST (`encodeDraft`) and PUT
(`encodeCreature`).
-}
validateEdit : CompendiumEditUi -> Result String Compendium.Creature
validateEdit ui =
    if String.isEmpty (String.trim ui.name) then
        Err "Name is required."

    else
        case ( String.toInt ui.armorClass, String.toInt ui.maxHp ) of
            ( Nothing, _ ) ->
                Err "Armor Class must be a whole number."

            ( _, Nothing ) ->
                Err "Max HP must be a whole number."

            ( Just ac, Just maxHp ) ->
                let
                    ( id, createdAt ) =
                        case ui.mode of
                            CreateMode ->
                                ( "", 0 )

                            EditExisting e ->
                                ( e.id, e.createdAt )
                in
                Ok
                    { id = id
                    , name = String.trim ui.name
                    , kind = ui.kind
                    , size = ui.size
                    , race = String.trim ui.race
                    , subrace = String.trim ui.subrace
                    , alignment = String.trim ui.alignment
                    , source = String.trim ui.source
                    , description = ui.description
                    , armorClass = ac
                    , armorClassNote = String.trim ui.armorClassNote
                    , maxHp = maxHp
                    , hpFormula = String.trim ui.hpFormula
                    , initiativeBonus = parseIntOr 0 ui.initiativeBonus
                    , speed =
                        { walk = parseIntOr 0 ui.speedWalk
                        , fly = parseIntOr 0 ui.speedFly
                        , swim = parseIntOr 0 ui.speedSwim
                        , climb = parseIntOr 0 ui.speedClimb
                        , burrow = parseIntOr 0 ui.speedBurrow
                        , hover = ui.speedHover
                        }
                    , abilities =
                        { str = parseIntOr 10 ui.abilityStr
                        , dex = parseIntOr 10 ui.abilityDex
                        , con = parseIntOr 10 ui.abilityCon
                        , int = parseIntOr 10 ui.abilityInt
                        , wis = parseIntOr 10 ui.abilityWis
                        , cha = parseIntOr 10 ui.abilityCha
                        }
                    , savingThrows = List.filterMap saveRowToValue ui.savingThrows
                    , skills = List.filterMap skillRowToValue ui.skills
                    , damageVulnerabilities = ui.damageVulnerabilities
                    , damageResistances = ui.damageResistances
                    , damageImmunities = ui.damageImmunities
                    , conditionImmunities = ui.conditionImmunities
                    , senses =
                        { blindsight = parseIntOr 0 ui.sensesBlindsight
                        , darkvision = parseIntOr 0 ui.sensesDarkvision
                        , tremorsense = parseIntOr 0 ui.sensesTremorsense
                        , truesight = parseIntOr 0 ui.sensesTruesight
                        , passivePerception = parseIntOr 10 ui.sensesPassivePerception
                        }
                    , languages = parseCsv ui.languages
                    , challengeRating = String.trim ui.challengeRating
                    , xp = parseIntOr 0 ui.xp
                    , xpInLair = parseIntOr 0 ui.xpInLair
                    , proficiencyBonus = parseIntOr 2 ui.proficiencyBonus
                    , traits = List.filterMap draftToFeature ui.traits
                    , actions = List.filterMap draftToFeature ui.actions
                    , bonusActions = List.filterMap draftToFeature ui.bonusActions
                    , reactions = List.filterMap draftToFeature ui.reactions
                    , legendaryActions = ui.legendaryActions
                    , lairActions = ui.lairActions
                    , regionalEffects = ui.regionalEffects
                    , spellcasting = ui.spellcasting
                    , customSections = List.filterMap customSectionRowToValue ui.customSections
                    , habitats = ui.habitats
                    , treasures = ui.treasures
                    , tags =
                        ui.tags
                            |> List.map String.trim
                            |> List.filter isOneWord
                            |> dedupOrdered
                    , loot =
                        ui.loot
                            |> List.map String.trim
                            |> List.filter (not << String.isEmpty)
                    , createdAt = createdAt
                    , updatedAt = 0
                    , isBundled = False
                    , hasSpecialReactions = ui.hasSpecialReactions
                    }


parseIntOr : Int -> String -> Int
parseIntOr default raw =
    String.toInt (String.trim raw) |> Maybe.withDefault default


parseCsv : String -> List String
parseCsv raw =
    raw
        |> String.split ","
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)


saveRowToValue : ( Compendium.Ability, String ) -> Maybe Compendium.AbilitySave
saveRowToValue ( ability, bonusText ) =
    String.toInt (String.trim bonusText)
        |> Maybe.map (\bonus -> { ability = ability, bonus = bonus })


skillRowToValue : ( String, String ) -> Maybe Compendium.SkillBonus
skillRowToValue ( name, bonusText ) =
    let
        trimmed =
            String.trim name
    in
    if String.isEmpty trimmed then
        Nothing

    else
        Just { name = trimmed, bonus = parseIntOr 0 bonusText }


draftToFeature : FeatureDraft -> Maybe Compendium.Feature
draftToFeature d =
    let
        trimmedName =
            String.trim d.name
    in
    if String.isEmpty trimmedName then
        Nothing

    else
        Just { name = trimmedName, description = d.description, usage = d.usage }


customSectionRowToValue : ( String, String ) -> Maybe Compendium.CustomSection
customSectionRowToValue ( name, body ) =
    let
        trimmed =
            String.trim name
    in
    if String.isEmpty trimmed then
        Nothing

    else
        Just { name = trimmed, body = body }


{-| A tag is a single non-empty word — no internal whitespace.
Underscores are explicitly allowed; everything else is permitted
too (digits, hyphens, etc.) as long as the token contains no
whitespace.
-}
isOneWord : String -> Bool
isOneWord s =
    not (String.isEmpty s) && not (String.contains " " s || String.contains "\t" s || String.contains "\n" s)


{-| First-occurrence-wins deduplication that preserves order.
Lets the validator collapse `["fire", "fire"]` to `["fire"]`
without sorting (which would scramble the user's intentional
ordering of tags).
-}
dedupOrdered : List String -> List String
dedupOrdered xs =
    dedupOrderedHelp xs []


dedupOrderedHelp : List String -> List String -> List String
dedupOrderedHelp xs seenRev =
    case xs of
        [] ->
            List.reverse seenRev

        x :: rest ->
            if List.member x seenRev then
                dedupOrderedHelp rest seenRev

            else
                dedupOrderedHelp rest (x :: seenRev)


creatureKindLabel : Compendium.CreatureKind -> String
creatureKindLabel k =
    case k of
        Compendium.Player ->
            "Player"

        Compendium.Enemy ->
            "Enemy"

        Compendium.Npc ->
            "NPC"



-- ── GROUPS ───────────────────────────────────────────────────────────────────


{-| Return the groups dict as a list, sorted by name so the
visible order is deterministic regardless of insertion order.
The compendium list renderer puts groups above creatures, so
this ordering only governs intra-group sorting.
-}
groupsList : CompendiumUi -> List Group
groupsList ui =
    Dict.values ui.groups
        |> List.sortBy (.name >> String.toLower)


{-| Filter the groups list down to those that survive the
current search box / kind-filter / "Added" toggle settings.
Re-using the creature filters here keeps the GM's filtering
model consistent: typing "goblin" narrows BOTH creatures
matching that text and groups whose name matches.

Currently a name-only search. CR / kind don't apply because a
group isn't a single creature with a CR or a kind; the GM
filters by group name and that's that.

-}
visibleGroups : CompendiumUi -> List Group
visibleGroups ui =
    let
        needle =
            String.toLower (String.trim ui.searchText)
    in
    if not ui.showGroups then
        []

    else
        groupsList ui
            |> List.filter
                (\g ->
                    if String.isEmpty needle then
                        True

                    else
                        String.contains needle (String.toLower g.name)
                )


addGroup : Group -> CompendiumUi -> CompendiumUi
addGroup group ui =
    { ui | groups = Dict.insert group.id group ui.groups }


removeGroup : String -> CompendiumUi -> CompendiumUi
removeGroup groupId ui =
    { ui
        | groups = Dict.remove groupId ui.groups
        , expandedGroupIds = Set.remove groupId ui.expandedGroupIds
        , selectedGroupId =
            if ui.selectedGroupId == Just groupId then
                Nothing

            else
                ui.selectedGroupId
    }
