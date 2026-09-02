module Ui.Treasure exposing (TreasureUi, fresh)

{-| UI substate for the Treasure modal.

The user-facing flow:

  - Open it from the "Treasure" trigger in the Actions column.
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
    , settingsExpanded : Bool
    }


{-| Default UI state when the modal opens. Kind defaults to
Hoard because the GM almost always wants the itemised version
when they reach for this tool; `contributionsExpanded` defaults
to `False` so the per-creature breakdown sits collapsed next to
the rolled-loot list — the GM can click it open when they want
to attribute who's carrying what.
-}
fresh : TreasureUi
fresh =
    { kind = Encounter.Treasure.Hoard
    , contributionsExpanded = False
    , settingsExpanded = False
    }
