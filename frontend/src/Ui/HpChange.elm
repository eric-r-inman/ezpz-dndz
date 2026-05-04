module Ui.HpChange exposing (HpChangeUi, HpChangeEntry, HpEdit, maxHpLogEntries, fresh)

{-| HP-change modal state plus the inline-HP edit and the
recent-changes log entries.

The HP-modal `Open ↔ closed` distinction lives at the
`Model.hpChange : Maybe HpChangeUi` field rather than as a flag
inside this record, so `Encounter.mapCreature` deleting the
targeted creature can't leave a stale modal pointing at
something that no longer exists.

`amountText` mirrors the `<input>` characters (same trick as
`DiceUi.modifierText`) so transient typing states like a bare
`-` while the user is mid-typing don't get clobbered by the
controlled input.

@docs HpChangeUi, HpChangeEntry, HpEdit, maxHpLogEntries, fresh

-}

import Dice
import Msg exposing (HpField(..), HpInputMode(..), HpKind)


type alias HpChangeUi =
    { target : String
    , kind : HpKind
    , mode : HpInputMode
    , amount : Int
    , amountText : String
    , expression : String
    , parseError : Maybe Dice.Error
    , ignoreTemp : Bool
    , applyToSelected : Bool
    }


{-| One row in the recent-HP-changes log shown at the bottom of
the Damage / Heal / Temp HP modals. Captures who, what kind,
the input amount, and the before/after HP+temp snapshots so the
row can render "27/59 (+0) → 14/59 (+0)" without re-querying
the encounter state.
-}
type alias HpChangeEntry =
    { kind : HpKind
    , target : String
    , amount : Int
    , beforeHp : Int
    , beforeTemp : Int
    , afterHp : Int
    , afterTemp : Int
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


{-| Initial state for opening the HP-change modal targeted at a
creature. The kind picks Damage / Heal / Temp HP; the rest
defaults to a 0-amount manual entry.
-}
fresh : String -> HpKind -> HpChangeUi
fresh target kind =
    { target = target
    , kind = kind
    , mode = ManualMode
    , amount = 0
    , amountText = "0"
    , expression = ""
    , parseError = Nothing
    , ignoreTemp = False
    , applyToSelected = False
    }
