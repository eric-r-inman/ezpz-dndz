module Ui.AbilitySave exposing (RollKind(..), kindWord)

{-| Labelling for the two ability-related triple-roll triggers in
the compendium stat block: an ability cell (STR, DEX, …) or a
Saving Throws chip. Both fire the same `1d20 + bonus` triple-roll
(standard + advantage + disadvantage at once); `RollKind` only
drives the dice-history `feature` label so the two read
distinctly ("STR check" vs "STR saving throw").

@docs RollKind, kindWord

-}


{-| Which D&D 5e roll a click represents.

  - `AbilityCheck` — the GM clicked one of the six STR/DEX/...
    ability cells. `1d20 + ability modifier`.
  - `SavingThrow` — the GM clicked one of the inline chips in
    the Saving Throws property line. `1d20 + save bonus`
    (proficient).

-}
type RollKind
    = AbilityCheck
    | SavingThrow


{-| Lowercase word for the dice-history `feature` tag, e.g.
"STR check" / "STR saving throw".
-}
kindWord : RollKind -> String
kindWord k =
    case k of
        AbilityCheck ->
            "check"

        SavingThrow ->
            "saving throw"
