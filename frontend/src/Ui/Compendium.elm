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
    , closeMenus, currentCreatures, markSaved
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
import Compendium.Parser
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



-- ── BROWSER MODAL ────────────────────────────────────────────────────────────


{-| Compendium browser state. Always present (we fetch the
library on app boot regardless of whether the modal is open
yet); the `open` flag controls visibility.

`db` is `RemoteData`-shaped because the boot fetch can fail or
still be in flight when the user clicks "Open". The browser
modal shows a loading skeleton in those states rather than
rendering an empty list.

`searchText`, `kindFilter`, `sort` are the filter-bar inputs;
they apply to a derived `Db` view at render time, not to the
canonical list.

`selectedId` tracks which creature's stat block is in the right
pane. Defaults to the first item in the rendered list on open;
a click on a row updates it.

-}
type alias CompendiumUi =
    { open : Bool
    , db : CompendiumDb
    , searchText : String
    , kindFilter : Set String
    , sort : CompendiumSort
    , selectedId : Maybe String
    , showOnlyAdded : Bool
    , pending : Maybe PendingAction

    -- Bulk-selection state for the row checkboxes that drive
    -- the Clear-Selected action.  Independent of `selectedId`
    -- (which picks the right-pane stat block).
    , selectedIds : Set String

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
    }


{-| Two-step confirmation for destructive bulk operations.
Click once on Reset / Import to set the pending action +
inline banner; click "Confirm" in the banner to fire the
actual Cmd.

`PendingImport` carries the parsed creature list so the
confirmation re-uses it without re-reading the file.
`PendingDelete` carries `(creatureId, displayName)` for the
confirmation message.

-}
type PendingAction
    = PendingReset
    | PendingImport (List Compendium.Creature) Int
    | PendingDelete String String


type CompendiumDb
    = CompendiumDbLoading
    | CompendiumDbLoaded Compendium.Db
    | CompendiumDbFailed Http.Error


emptyCompendium : CompendiumUi
emptyCompendium =
    { open = False
    , db = CompendiumDbLoading
    , searchText = ""
    , kindFilter = Set.empty
    , sort = SortName
    , selectedId = Nothing
    , showOnlyAdded = False
    , pending = Nothing
    , selectedIds = Set.empty
    , bulkMenu = Nothing
    , compendiumDirty = False
    , bulkBusy = False
    , bulkError = Nothing
    , savedAs = Nothing
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
                |> compendiumSort ui.sort
                |> Compendium.toList

        _ ->
            []


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
modal that can be opened on top of the browser modal (or
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
                    , createdAt = createdAt
                    , updatedAt = 0
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


creatureKindLabel : Compendium.CreatureKind -> String
creatureKindLabel k =
    case k of
        Compendium.Player ->
            "Player"

        Compendium.Enemy ->
            "Enemy"

        Compendium.Npc ->
            "NPC"
