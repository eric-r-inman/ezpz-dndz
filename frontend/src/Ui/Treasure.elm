module Ui.Treasure exposing (TreasureUi, fresh)

{-| UI substate for the Treasure modal.

The user-facing flow:

  - Open the modal from the "Treasure" button in the encounter
    title bar.
  - Pick a Kind (Individual / Hoard) and a Bracket (auto-
    suggested from the encounter's toughest creature).
  - Hit Roll — the generator produces a `TreasureRoll` which is
    stored on the encounter so subsequent re-opens show the
    same loot. Hitting Roll again replaces it with a fresh draw.

This record carries only the modal's UI state (the two
dropdown selections). The actual treasure data lives on
`model.encounter.treasure : Maybe TreasureRoll`.

-}

import Encounter.Treasure exposing (Bracket, Kind)


type alias TreasureUi =
    { kind : Kind
    , bracket : Bracket
    , contributionsExpanded : Bool
    }


{-| Default UI state when the modal opens. Caller computes the
suggested bracket from the encounter and passes it in; the kind
defaults to Hoard because the GM almost always wants the
itemised version when they reach for this tool.

`contributionsExpanded` defaults to `True` so the
per-creature breakdown for a Sum (all Enemies) roll is visible
without an extra click — that's the data the GM actually wants
to see when the encounter wraps.

-}
fresh : Bracket -> TreasureUi
fresh bracket =
    { kind = Encounter.Treasure.Hoard
    , bracket = bracket
    , contributionsExpanded = True
    }
