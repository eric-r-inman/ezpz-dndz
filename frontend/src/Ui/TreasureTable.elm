module Ui.TreasureTable exposing
    ( Mode(..)
    , TreasureTableUi
    , fresh
    , opening
    , withDraft
    , withEditing
    )

{-| UI substate for the user-authored Treasure Tables editor.

The editor is a stand-alone modal opened from the main Treasure
modal ("Manage tables ..." link beneath the Custom section).
It owns:

  - Which mode the modal is in — a list view of the user's
    tables, or the editor pane for one specific table.
  - The in-progress draft of the table currently being edited
    (separate from the persisted list so a hit-Cancel discards
    cleanly).
  - The currently-selected entry index inside the draft, so the
    inline editing affordances know which row to mutate.

The persisted table list itself lives on
`model.userTreasureTables`; the editor only holds the _draft_
and the navigation state.

-}

import Encounter.Treasure.UserTable as UserTable exposing (UserTable)


{-| Editor "page" inside the modal.

  - `Listing` — the table list (default open state). Empty list
    surfaces an inline "No tables yet — create one" prompt.
  - `Editing table` — the per-table editor. `table` is the
    in-progress draft (not yet committed to the model).

-}
type Mode
    = Listing
    | Editing UserTable


type alias TreasureTableUi =
    { mode : Mode
    }


{-| Initial state when the modal first opens — the Listing view.
-}
fresh : TreasureTableUi
fresh =
    { mode = Listing }


{-| Convenience for opening straight to the editor pane on a
specific table. Used by the "Edit" affordance on a list row.
-}
opening : UserTable -> TreasureTableUi
opening table =
    { mode = Editing table }


{-| Flip to the editor mode for the given table.
-}
withEditing : UserTable -> TreasureTableUi -> TreasureTableUi
withEditing table ui =
    { ui | mode = Editing table }


{-| Replace the in-progress draft. Caller computes the next
draft (e.g. by mapping over entries); this is the lens-style
setter the update branches lean on. No-op when the modal isn't
in `Editing` mode.
-}
withDraft : (UserTable -> UserTable) -> TreasureTableUi -> TreasureTableUi
withDraft fn ui =
    case ui.mode of
        Editing table ->
            { ui | mode = Editing (fn table) }

        Listing ->
            ui
