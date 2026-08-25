module Ui.HpChange exposing (HpChangeUi, HpChangeEntry, HpEdit, maxHpLogEntries, fresh)

{-| HP-change modal state plus the inline-HP edit and the
recent-changes log entries.

The HP-modal `Open ↔ closed` distinction lives at the
`Model.hpChange : Maybe HpChangeUi` field rather than as a flag
inside this record, so `Encounter.mapCreature` deleting the
targeted creature can't leave a stale modal pointing at
something that no longer exists.

`amountText` mirrors the `<input>` characters so a transient
mid-typing state (a bare `-` or the `2d` prefix of a formula
in flight) doesn't get clobbered by the controlled input.
The single field accepts either a plain integer or a dice
formula; the apply handler parses it at commit time.

@docs HpChangeUi, HpChangeEntry, HpEdit, maxHpLogEntries, fresh

-}

import Dice
import Msg exposing (HpField(..), HpKind(..))


type alias HpChangeUi =
    { target : String

    -- Tracks the last-committed kind so a keyboard-cancelled
    -- modal can still be reopened at whatever kind the GM
    -- was last dabbling with.  Starts at `DamageKind` on
    -- fresh open; only mutates when one of the four footer
    -- action buttons commits.
    , kind : HpKind

    -- Raw input text — parsed at apply time into either an
    -- integer (applied directly) or a dice expression
    -- (rolled, then the total is applied).  See
    -- `Update.HpChange.applyAs` for the parse-then-apply
    -- routing.
    , amountText : String
    , parseError : Maybe Dice.Error
    , ignoreTemp : Bool
    , applyToSelected : Bool

    -- When applying a dice formula to a selection, roll fresh
    -- per creature instead of one shared total.  Only consulted
    -- on the formula path with `applyToSelected` set; the
    -- default False keeps 5e's single-roll AOE convention.
    , freshRollPerTarget : Bool
    }


{-| One row in the recent-HP-changes log shown at the bottom of
the Manage HP modal. Captures who, what kind, the input amount,
and the before/after snapshot so the row can render
"27/59 (+0) → 14/59 (+0)" without re-querying the encounter
state, and so undo can walk maxHp back too when a `MaxHpKind`
entry gets reverted.
-}
type alias HpChangeEntry =
    { kind : HpKind
    , target : String
    , amount : Int
    , beforeHp : Int
    , beforeTemp : Int
    , beforeMax : Int
    , afterHp : Int
    , afterTemp : Int
    , afterMax : Int
    }


{-| Active inline-HP edit on a creature card. When set, the
corresponding `<span>` on the matching card renders as an
`<input>` instead. Only one edit at a time so we don't have to
disambiguate keyboard focus.
-}
type alias HpEdit =
    { target : String
    , field : HpField
    , text : String
    }


{-| Cap on the HP-change log size. Matches the user's request
for "last 10 applications".
-}
maxHpLogEntries : Int
maxHpLogEntries =
    10


{-| Initial state for opening the Manage HP modal targeted at a
creature. Kind defaults to `DamageKind` — the most-common
first action; the four footer buttons let the GM commit as
whichever kind actually applies without a mid-flow radio pick.
-}
fresh : String -> HpChangeUi
fresh target =
    { target = target
    , kind = DamageKind
    , amountText = ""
    , parseError = Nothing
    , ignoreTemp = False
    , applyToSelected = False
    , freshRollPerTarget = False
    }
