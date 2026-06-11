module Ui.TreasureTable exposing
    ( Section(..)
    , TreasureTableUi
    , fresh
    , isDirty
    , toggleSection
    , withDraft
    )

{-| UI substate for the (singular) Treasure Table editor.

There's exactly one treasure table per user — bundled by
default, mutated through this editor. The modal renders a
collection of collapsible sections (individual rows by bracket,
hoard rows by bracket, gem name lists by tier, art lists by
tier, magic lists per SRD table letter).

The substate now also owns a /draft/ copy of the table that all
edits flow into; the live `model.userTreasureTable` is only
overwritten when the GM clicks Save. Closing the modal without
saving discards the draft — the on-disk / server copy stays
untouched. A `baseline` snapshot of the table at open time lets
the UI surface a "(unsaved changes)" indicator without
recomputing equality from scratch.

-}

import Encounter.Treasure exposing (TreasureTable)
import Set exposing (Set)


{-| Discriminator for a collapsible section in the editor.
Each section knows its own key string ("ind:1to4",
"gem:50gp", "magic:A", etc.); rendering iterates the table
data and matches up the expanded set.
-}
type Section
    = IndividualSection String
    | HoardSection String
    | GemSection String
    | ArtSection String
    | MagicSection String


type alias TreasureTableUi =
    { expanded : Set String
    , draft : TreasureTable
    , baseline : TreasureTable
    }


{-| Snapshot the live table into the editor. Both `draft` and
`baseline` start equal; subsequent edits diverge `draft` from
`baseline`, which the dirty check compares against.
-}
fresh : TreasureTable -> TreasureTableUi
fresh snapshot =
    { expanded = Set.empty
    , draft = snapshot
    , baseline = snapshot
    }


{-| Apply a pure transformation to the in-flight draft. Every
row / coin / name / subroll handler in `Update.TreasureTable`
routes through this so the underlying `model.userTreasureTable`
stays untouched until Save.
-}
withDraft : (TreasureTable -> TreasureTable) -> TreasureTableUi -> TreasureTableUi
withDraft fn ui =
    { ui | draft = fn ui.draft }


{-| Has the user edited anything since opening the modal? The
view uses this to gate the Save button and surface the unsaved
marker. Reference-equality would be cheaper, but Elm doesn't
expose it and structural equality on a TreasureTable is fast.
-}
isDirty : TreasureTableUi -> Bool
isDirty ui =
    ui.draft /= ui.baseline


sectionKey : Section -> String
sectionKey s =
    case s of
        IndividualSection k ->
            -- Must match the discriminator string the view uses in
            -- View.Modal.TreasureTable.individualGroup (`kind = "individual"`).
            -- Was "ind:" and silently desynced — bracketGroup wrote
            -- "individual:0to4" into `expanded` and read back "ind:0to4",
            -- so the panel could never expand.
            "individual:" ++ k

        HoardSection k ->
            "hoard:" ++ k

        GemSection k ->
            "gem:" ++ k

        ArtSection k ->
            "art:" ++ k

        MagicSection k ->
            "magic:" ++ k


toggleSection : Section -> TreasureTableUi -> TreasureTableUi
toggleSection section ui =
    let
        key =
            sectionKey section
    in
    if Set.member key ui.expanded then
        { ui | expanded = Set.remove key ui.expanded }

    else
        { ui | expanded = Set.insert key ui.expanded }
