module Ui.Treasure exposing (TreasureUi, fresh)

{-| UI substate for the Treasure modal.

The user-facing flow:

  - Open the modal from the "Treasure" button in the encounter
    title bar.
  - Pick a Kind (Sum-all-Enemies / Hoard).
  - Hit Roll — the generator derives each enemy's CR bracket
    from the encounter automatically; the materialised
    `TreasureRoll` lands on the encounter so subsequent re-opens
    show the same loot. Hitting Roll again replaces it with a
    fresh draw.

This record carries only the modal's UI state. The actual
treasure data lives on `model.encounter.treasure : Maybe
TreasureRoll`.

-}

import Encounter.Treasure exposing (Kind)


type alias TreasureUi =
    { kind : Kind
    , contributionsExpanded : Bool
    }


{-| Default UI state when the modal opens. Kind defaults to
Hoard because the GM almost always wants the itemised version
when they reach for this tool; `contributionsExpanded` defaults
to `True` so the per-creature breakdown for a Sum roll is
visible without an extra click.
-}
fresh : TreasureUi
fresh =
    { kind = Encounter.Treasure.Hoard
    , contributionsExpanded = True
    }
