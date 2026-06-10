module Ui.Treasure exposing (TreasureUi, fresh)

{-| UI substate for the Treasure modal.

The user-facing flow:

  - Open the modal from the "Treasure" button in the encounter
    title bar.
  - Pick a Kind (Individual / Hoard) and a Bracket (auto-
    suggested from the encounter's toughest creature).
  - Hit Roll — the generator produces a `TreasureRoll` which is
    stored on the encounter so subsequent re-opens show the
    same loot.
  - Toggle the "distributed" checkmark per row as the GM hands
    out the spoils.
  - Hit Re-roll to dump the current loot and roll a fresh batch
    — the modal warns first if anything's been marked
    distributed, because re-rolling discards the existing list.

This record carries only the modal's UI state (the dropdown
selections and the re-roll-confirmation flag). The actual
treasure data lives on
`model.encounter.treasure : Maybe Encounter.TreasureState`.

-}

import Encounter.Treasure exposing (Bracket, Kind)


type alias TreasureUi =
    { kind : Kind
    , bracket : Bracket
    , confirmingRereroll : Bool
    }


{-| Default UI state when the modal opens. Caller computes the
suggested bracket from the encounter and passes it in; the kind
defaults to Hoard because the GM almost always wants the
itemised version when they reach for this tool.
-}
fresh : Bracket -> TreasureUi
fresh bracket =
    { kind = Encounter.Treasure.Hoard
    , bracket = bracket
    , confirmingRereroll = False
    }
