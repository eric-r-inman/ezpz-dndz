module Ui.GroupEdit exposing
    ( GroupEditUi, GroupEditMode(..), EntryDraft
    , fresh, freshFromSelected, fromGroup
    , validate, maxNameLength
    , LoreDraft, LoreMemberDraft, LoreSection, freshLoreDraft, loreDraftFromGroup, validateLoreDraft
    )

{-| Modal state for the **Create / Edit Group** modal.

The form mirrors [`Compendium.Group.Group`](Compendium-Group)
field-for-field, but with string-typed numeric inputs (count,
manual initiative) so transient typing states (empty input,
partial number) aren't clobbered between renders. Validation
runs on submit, not per keystroke.

@docs GroupEditUi, GroupEditMode, EntryDraft
@docs fresh, freshFromSelected, fromGroup
@docs validate, maxNameLength

-}

import Compendium.Group as Group
    exposing
        ( Group
        , InitiativeMode(..)
        , MinionType(..)
        )
import Encounter.RandomEncounter.Lore as Lore
import Set exposing (Set)



-- ── TYPES ────────────────────────────────────────────────────────────────────


type alias GroupEditUi =
    { mode : GroupEditMode
    , name : String

    -- `initiativeMode` is decoupled from `manualInitiative` so
    -- the GM can flip back and forth between modes without
    -- losing the manually-typed value.  The value is only used
    -- (and validated) when the mode is `InitiativeSharedManual`.
    , initiativeMode : InitiativeMode
    , manualInitiative : String
    , entries : List EntryDraft
    , submitting : Bool
    , submitError : Maybe String

    -- Lore section sits below the regular Group editor.
    -- See `LoreSection` for the substate the section manages
    -- (expand toggles, inline draft, delete confirm).
    , lore : LoreSection
    }


{-| State for the Lore-groups section embedded in the
Create/Edit Group modal. Tracks which top-level group
("User" / "Bundled") is expanded, which individual lore groups
have their member list revealed, and the inline draft (if any)
the GM is currently authoring.
-}
type alias LoreSection =
    { userExpanded : Bool
    , bundledExpanded : Bool
    , expandedGroups : Set String
    , editing : Maybe LoreDraft
    , confirmDelete : Maybe String
    , addSearch : String
    }


{-| In-progress lore-group draft. `id = Nothing` for a brand-
new group; `Just id` when editing an existing user-authored
group (so Save replaces in place instead of double-adding).
-}
type alias LoreDraft =
    { id : Maybe String
    , name : String
    , weight : Int
    , members : List LoreMemberDraft
    }


type alias LoreMemberDraft =
    { creatureName : String
    , role : Lore.Role
    , countMin : String
    , countMax : String
    }


type GroupEditMode
    = GroupCreateMode
    | GroupEditExisting { id : String, createdAt : Int }


{-| Per-row draft. `count` is string-typed so the user can
clear the field while editing; `validate` parses on submit.
-}
type alias EntryDraft =
    { creatureId : String
    , count : String
    , minionType : MinionType
    }


{-| Cap names at a length that fits comfortably in the list row
without truncation. Matches the save-encounter modal's limit so
the GM gets consistent input affordances across the app.
-}
maxNameLength : Int
maxNameLength =
    60



-- ── CONSTRUCTORS ─────────────────────────────────────────────────────────────


fresh : GroupEditUi
fresh =
    { mode = GroupCreateMode
    , name = ""
    , initiativeMode = InitiativeEachRolls
    , manualInitiative = "10"
    , entries = []
    , submitting = False
    , submitError = Nothing
    , lore = freshLore
    }


freshLore : LoreSection
freshLore =
    { userExpanded = True
    , bundledExpanded = False
    , expandedGroups = Set.empty
    , editing = Nothing
    , confirmDelete = Nothing
    , addSearch = ""
    }


{-| Build an empty lore draft for "+ New lore group". `id`
stays `Nothing` so Save knows to allocate a fresh one.
-}
freshLoreDraft : LoreDraft
freshLoreDraft =
    { id = Nothing
    , name = ""
    , weight = 3
    , members = []
    }


{-| Pre-fill a lore draft from an existing user-authored
group. Numeric fields go to strings so the inline form can
hold transient typing states without clobbering them.
-}
loreDraftFromGroup : Lore.Group -> LoreDraft
loreDraftFromGroup g =
    { id = Just g.id
    , name = g.name
    , weight = g.weight
    , members =
        List.map
            (\m ->
                { creatureName = m.name
                , role = m.role
                , countMin = String.fromInt m.countMin
                , countMax = String.fromInt m.countMax
                }
            )
            g.members
    }


{-| Validate a lore draft into a `Lore.Group`.

  - Name must be non-empty.
  - At least one member with a non-empty creature name.
  - Each member's count\_min / count\_max parse as integers,
    `0 ≤ min ≤ max ≤ 50` (the 50 cap matches the bundled
    materialiser's working range — anything higher will be
    scaled down by the generator anyway).

Returns `Err msg` for the first failure (caller surfaces it
on the form); `Ok g` carries the canonical group.

The returned id is the draft's id when editing, otherwise a
new id derived from the name. Caller is responsible for
ensuring uniqueness if needed.

-}
validateLoreDraft : LoreDraft -> Result String Lore.Group
validateLoreDraft draft =
    if String.isEmpty (String.trim draft.name) then
        Err "Lore group needs a name."

    else if List.isEmpty draft.members then
        Err "Add at least one creature to the lore group."

    else
        validateLoreMembers draft.members
            |> Result.map
                (\members ->
                    { id =
                        Maybe.withDefault
                            ("user-"
                                ++ slugify draft.name
                            )
                            draft.id
                    , name = String.trim draft.name
                    , weight = clamp 1 10 draft.weight
                    , source = Lore.UserCurated
                    , members = members
                    }
                )


validateLoreMembers : List LoreMemberDraft -> Result String (List Lore.Slot)
validateLoreMembers drafts =
    drafts
        |> List.foldl
            (\d acc ->
                case acc of
                    Err e ->
                        Err e

                    Ok ms ->
                        case validateLoreMember d of
                            Ok m ->
                                Ok (m :: ms)

                            Err e ->
                                Err e
            )
            (Ok [])
        |> Result.map List.reverse


validateLoreMember : LoreMemberDraft -> Result String Lore.Slot
validateLoreMember d =
    let
        name =
            String.trim d.creatureName
    in
    if String.isEmpty name then
        Err "Every lore member needs a creature name."

    else
        case ( String.toInt (String.trim d.countMin), String.toInt (String.trim d.countMax) ) of
            ( Just lo, Just hi ) ->
                if lo < 0 || hi < lo || hi > 50 then
                    Err ("\"" ++ name ++ "\" has an invalid count range (need 0 ≤ min ≤ max ≤ 50).")

                else
                    Ok
                        { name = name
                        , role = d.role
                        , countMin = lo
                        , countMax = hi
                        }

            _ ->
                Err ("\"" ++ name ++ "\" count must be whole numbers.")


slugify : String -> String
slugify s =
    s
        |> String.toLower
        |> String.toList
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    '-'
            )
        |> String.fromList
        |> String.split "-"
        |> List.filter (not << String.isEmpty)
        |> String.join "-"


{-| Pre-fill the form with the GM's checkbox-selected creatures.
Each selected creature becomes a single-instance entry with no
minion override; the GM tunes the counts and minion settings
afterwards.

We sort the entries alphabetically so the seeded list is
predictable regardless of selection order — the underlying
`Set` doesn't preserve click order anyway.

-}
freshFromSelected : List String -> GroupEditUi
freshFromSelected creatureIds =
    let
        sorted =
            List.sort creatureIds
    in
    { fresh
        | entries =
            List.map
                (\id ->
                    { creatureId = id, count = "1", minionType = MinionNone }
                )
                sorted
    }


fromGroup : Group -> GroupEditUi
fromGroup group =
    let
        ( mode_, manual ) =
            case group.initiativeMode of
                InitiativeSharedManual n ->
                    ( InitiativeSharedManual n, String.fromInt n )

                other ->
                    ( other, "10" )
    in
    { mode = GroupEditExisting { id = group.id, createdAt = group.createdAt }
    , name = group.name
    , initiativeMode = mode_
    , manualInitiative = manual
    , entries =
        List.map
            (\e ->
                { creatureId = e.creatureId
                , count = String.fromInt e.count
                , minionType = e.minionType
                }
            )
            group.entries
    , submitting = False
    , submitError = Nothing
    , lore = freshLore
    }



-- ── VALIDATION ───────────────────────────────────────────────────────────────


{-| Produce the final `Group` value to persist + render. Returns
an error string for the inline banner if the GM left something
required blank (empty name, empty entry list) or typed nonsense
into a numeric field.

A `createdAt` of 0 marks a fresh group — the persistence layer
substitutes the current timestamp on save.

-}
validate : GroupEditUi -> Result String Group
validate ui =
    let
        trimmedName =
            String.trim ui.name
    in
    if String.isEmpty trimmedName then
        Err "Name is required."

    else if List.isEmpty ui.entries then
        Err "Add at least one creature to the group."

    else
        case parseInitiativeMode ui of
            Err err ->
                Err err

            Ok initiativeMode ->
                case parseEntries ui.entries of
                    Err err ->
                        Err err

                    Ok parsedEntries ->
                        let
                            ( id, createdAt ) =
                                case ui.mode of
                                    GroupCreateMode ->
                                        ( "", 0 )

                                    GroupEditExisting e ->
                                        ( e.id, e.createdAt )
                        in
                        Ok
                            { id = id
                            , name = trimmedName
                            , initiativeMode = initiativeMode
                            , entries = parsedEntries
                            , createdAt = createdAt
                            , updatedAt = 0
                            }


parseInitiativeMode : GroupEditUi -> Result String InitiativeMode
parseInitiativeMode ui =
    case ui.initiativeMode of
        InitiativeSharedManual _ ->
            case String.toInt (String.trim ui.manualInitiative) of
                Just n ->
                    Ok (InitiativeSharedManual n)

                Nothing ->
                    Err "Manual initiative must be a whole number."

        other ->
            Ok other


parseEntries : List EntryDraft -> Result String (List Group.GroupEntry)
parseEntries drafts =
    List.foldr
        (\draft acc ->
            case acc of
                Err err ->
                    Err err

                Ok rest ->
                    case parseEntry draft of
                        Err err ->
                            Err err

                        Ok parsed ->
                            Ok (parsed :: rest)
        )
        (Ok [])
        drafts


parseEntry : EntryDraft -> Result String Group.GroupEntry
parseEntry draft =
    if String.isEmpty draft.creatureId then
        Err "Pick a creature for every row."

    else
        case String.toInt (String.trim draft.count) of
            Just n ->
                if n < 1 then
                    Err "Each entry must have at least 1 instance."

                else
                    Ok
                        { creatureId = draft.creatureId
                        , count = n
                        , minionType = draft.minionType
                        }

            Nothing ->
                Err "Instance count must be a whole number."
