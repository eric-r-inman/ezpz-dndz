module Ui.CrCalculator exposing (CrCalculatorUi, fresh)

{-| State for the **CR Calculator** modal.

The party itself lives on `Model` (so edits survive a modal
close), but the scope picker and a few transient UI flags are
modal-local — that's what's here.

@docs CrCalculatorUi, fresh

-}

import Encounter.Xp exposing (XpScope(..))


type alias CrCalculatorUi =
    { scope : XpScope
    }


fresh : CrCalculatorUi
fresh =
    { scope = ScopeXpEnemiesAndNpcs
    }
