module Ui.GroupEdit exposing
    ( GroupEditUi, GroupEditMode(..), EntryDraft
    , fresh, freshFromSelected, fromGroup
    , validate, maxNameLength
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
    }


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
