module Ui.AbilitySave exposing
    ( AbilitySaveUi, RollKind(..), fresh
    , kindLabel, kindWord
    )

{-| Roll modal triggered from clicking either an ability cell
(STR, DEX, …) or a Saving Throws chip in the compendium stat
block. Three buttons inside (Roll / Advantage / Disadvantage)
all fire a `1d20 + bonus` and tag the resulting dice-history
entry with the creature's name. The modal differentiates the
two paths by `RollKind` so the title + dice-history `feature`
label read honestly ("STR check" vs "STR saving throw").

@docs AbilitySaveUi, RollKind, fresh
@docs kindLabel, kindWord

-}


{-| Which D&D 5e roll spawned this modal.

  - `AbilityCheck` — the GM clicked one of the six STR/DEX/...
    ability cells. `1d20 + ability modifier`.
  - `SavingThrow` — the GM clicked one of the inline chips in
    the Saving Throws property line. `1d20 + save bonus`
    (proficient).

The bonus is captured at the call site so the modal doesn't
have to re-derive it; the kind only drives labelling.

-}
type RollKind
    = AbilityCheck
    | SavingThrow


{-| Carries everything the modal's three roll buttons need to
fire a roll without re-deriving it from the stat block: the
creature's display name (for the dice-history "target" label),
the ability label like `"STR"` (for the modal heading and the
history "feature" label), the bonus (flat ability modifier for
checks, proficient save bonus for saves), the screen position of
the original ability-cell click (carried through so the floating
roll-result popup spawns at the cell when the dice land), and
the `RollKind` discriminating "ability check" vs "saving throw"
for labelling.
-}
type alias AbilitySaveUi =
    { creatureName : String
    , ability : String
    , bonus : Int
    , clickX : Int
    , clickY : Int
    , kind : RollKind
    }


fresh : RollKind -> String -> String -> Int -> Int -> Int -> AbilitySaveUi
fresh kind creatureName ability bonus clickX clickY =
    { creatureName = creatureName
    , ability = ability
    , bonus = bonus
    , clickX = clickX
    , clickY = clickY
    , kind = kind
    }


{-| Capitalised label for the modal title, e.g. "STR Check"
or "STR Save".
-}
kindLabel : RollKind -> String
kindLabel k =
    case k of
        AbilityCheck ->
            "Check"

        SavingThrow ->
            "Save"


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
