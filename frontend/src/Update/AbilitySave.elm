module Update.AbilitySave exposing (trigger)

{-| An ability-check or saving-throw click in a compendium stat
block. Both fire the same triple-roll (standard + advantage +
disadvantage together) as an attack-roll link — see
`Update.Dice.tripleRollCmd` — differing only in the dice-history
label `RollKind` produces ("STR check" vs "STR saving throw").
-}

import Model exposing (Model)
import Msg exposing (Msg)
import Ui.AbilitySave exposing (RollKind, kindWord)
import Update.Dice


{-| `ability` is the label shown in the stat block (e.g. `"STR"`);
`bonus` is the flat ability modifier for a check or the
proficient save bonus for a save, captured at the call site so
this doesn't have to re-derive it. `x` / `y` are the triggering
click's position, carried through so the floating popups anchor
at the cell.
-}
trigger : RollKind -> String -> String -> Int -> Int -> Int -> Model -> ( Model, Cmd Msg )
trigger kind creatureName ability bonus x y model =
    ( model
    , Update.Dice.tripleRollCmd (ability ++ " " ++ kindWord kind) creatureName bonus x y
    )
