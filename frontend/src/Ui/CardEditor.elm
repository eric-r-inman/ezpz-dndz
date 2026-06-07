module Ui.CardEditor exposing
    ( CardEditorUi
    , fresh, fromCurrent
    )

{-| **Prototype** state for the Creature Card Editor modal.

The editor holds an _in-progress_ `CardLayout` (which the
preview pane renders) plus the chosen `QueueView`. Both fields
are diffed against the live `model.cardLayout` /
`model.queueView` to decide whether the Save button shows as
"dirty".

When the user clicks Save, `Update.CardEditor.save` copies these
fields back onto the model (and, in Phase 2, fires the
persistence Cmd). When the user clicks Close without saving,
the in-progress state is discarded.

@docs CardEditorUi
@docs fresh, fromCurrent

-}

import Card.Layout exposing (CardLayout, QueueView(..), defaultLayout)


type alias CardEditorUi =
    { layout : CardLayout
    , queueView : QueueView

    -- Which row in the editor is currently "focused" for
    -- widget addition.  `Nothing` means the GM hasn't chosen
    -- a row yet — the Add Widget controls render in a disabled
    -- state until they do.
    , focusRow : Maybe Int

    -- Save-as input.  The user types into this and the Save
    -- button PUTs `/api/card-layouts/{name}?overwrite=true`,
    -- which acts as a server-side upsert.
    , saveName : String

    -- True while a HTTP cycle is in flight (Save / Load /
    -- Delete).  Disables the editor's persistence controls
    -- so a double-click can't fire two PUTs.
    , busy : Bool

    -- Inline banner shown after a failed HTTP cycle.  Cleared
    -- on the next user action.
    , error : Maybe String

    -- When `Just name`, the editor is asking the user to
    -- confirm an overwrite of an existing saved layout.  Set
    -- by `Update.CardEditor.saveAs` when the typed name
    -- collides with one of `model.savedCardLayouts`; cleared
    -- by Confirm / Cancel.  Detection is client-side so we
    -- skip the 409 round-trip dance.
    , confirmOverwrite : Maybe String
    }


fresh : CardEditorUi
fresh =
    { layout = defaultLayout
    , queueView = ListView
    , focusRow = Just 0
    , saveName = ""
    , busy = False
    , error = Nothing
    , confirmOverwrite = Nothing
    }


{-| Open the editor pre-populated with the user's current
layout + queue-view preference, rather than the bundled
defaults. Used by `Update.CardEditor.open` when the modal
fires.
-}
fromCurrent : CardLayout -> QueueView -> CardEditorUi
fromCurrent layout queueView =
    { layout = layout
    , queueView = queueView
    , focusRow =
        if List.isEmpty layout.centerRows then
            Nothing

        else
            Just 0
    , saveName = ""
    , busy = False
    , error = Nothing
    , confirmOverwrite = Nothing
    }
