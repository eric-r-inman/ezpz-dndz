module Ui.LoreEdit exposing (LoreEditUi, freshForNew, freshForExisting, withDraft, clearTestResult)

{-| Substate for the standalone **Edit Lore Group** modal.

Previously the lore-group CRUD lived inside the Create/Edit Group
modal as an inline section. The compendium now surfaces lore
groups as a peer of regular groups, and the editor opens as its
own modal — this is the modal's UI state.

The draft mirrors `Ui.GroupEdit.LoreDraft` field-for-field; the
existing `LoreDraft` type is shared between this modal and the
soon-to-be-removed inline editor, so callers continue to use one
canonical draft shape. The `addSearch` field carries the "add
member" picker's filter text. `testResult` caches the Suggest
back-solver's output for the panel rendered below Save/Cancel —
cleared on every edit so the panel never lags behind the form.

@docs LoreEditUi, freshForNew, freshForExisting, withDraft, clearTestResult

-}

import Encounter.RandomEncounter.Lore as Lore
import Encounter.RandomEncounter.Lore.Suggest as Suggest
import Ui.GroupEdit as GroupEdit exposing (LoreDraft)


type alias LoreEditUi =
    { draft : LoreDraft
    , addSearch : String
    , submitError : Maybe String
    , testResult : Maybe Suggest.Suggestion
    }


{-| Open the modal in "create new" mode — empty draft, no
prior test result.
-}
freshForNew : LoreEditUi
freshForNew =
    { draft = GroupEdit.freshLoreDraft
    , addSearch = ""
    , submitError = Nothing
    , testResult = Nothing
    }


{-| Pre-populate the modal from an existing user-authored lore
group. The id is preserved on the draft so Save replaces in
place rather than appending a duplicate.
-}
freshForExisting : Lore.Group -> LoreEditUi
freshForExisting g =
    { draft = GroupEdit.loreDraftFromGroup g
    , addSearch = ""
    , submitError = Nothing
    , testResult = Nothing
    }


{-| Apply a pure transformation to the in-flight draft. Always
clears `testResult` and `submitError` because an edit invalidates
both — a stale recommendation alongside fresh changes is more
confusing than no recommendation, and the error banner should
disappear as soon as the GM starts addressing whatever it
flagged.
-}
withDraft : (LoreDraft -> LoreDraft) -> LoreEditUi -> LoreEditUi
withDraft fn ui =
    { ui
        | draft = fn ui.draft
        , testResult = Nothing
        , submitError = Nothing
    }


{-| Drop the test panel without touching the draft — used by
the Cancel-test affordance if we ever surface one. Currently
only the implicit "edit" path clears testResult, so this is
provided for completeness.
-}
clearTestResult : LoreEditUi -> LoreEditUi
clearTestResult ui =
    { ui | testResult = Nothing }
