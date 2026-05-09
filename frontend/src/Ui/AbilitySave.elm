module Ui.AbilitySave exposing (AbilitySaveUi, fresh)

{-| Saving-throw roll modal triggered from clicking an ability
cell (STR, DEX, …) in the compendium stat block. Three buttons
inside (Roll / Advantage / Disadvantage) all fire a save with the
captured bonus and tag the resulting dice-history entry with the
creature's name.

@docs AbilitySaveUi, fresh

-}


{-| Carries everything the modal's three roll buttons need to
fire a save without re-deriving it from the stat block: the
creature's display name (for the dice-history "target" label),
the ability label like `"STR"` (for the modal heading and the
history "feature" label), the save bonus (proficient if the
creature has a saving-throw entry for this ability, otherwise
just the ability modifier), and the screen position of the
original ability-cell click (carried through so the floating
roll-result popup spawns at the cell when the dice land).
-}
type alias AbilitySaveUi =
    { creatureName : String
    , ability : String
    , bonus : Int
    , clickX : Int
    , clickY : Int
    }


fresh : String -> String -> Int -> Int -> Int -> AbilitySaveUi
fresh creatureName ability bonus clickX clickY =
    { creatureName = creatureName
    , ability = ability
    , bonus = bonus
    , clickX = clickX
    , clickY = clickY
    }
