module Encounter.Concentration exposing (SaveOwed, saveDc, savesOwed)

{-| Concentration under damage follows the 2024 rules. A creature
that takes damage while concentrating makes a Constitution save to
keep it. A creature dropped to 0 hit points loses it
outright. `HpChange` handles that.

@docs SaveOwed, saveDc, savesOwed

-}

import Encounter exposing (Encounter)


type alias SaveOwed =
    { name : String
    , dc : Int
    }


saveDc : Int -> Int
saveDc damage =
    clamp 10 30 (damage // 2)


{-| The save each creature still concentrating owes for the damage it
took between two states of the encounter. Damage that temporary hit
points soaked still counts.
-}
savesOwed : Encounter -> Encounter -> List SaveOwed
savesOwed before after =
    after.creatures
        |> List.filter .concentrating
        |> List.filterMap
            (\now ->
                let
                    taken =
                        Encounter.damageTaken before now
                in
                if taken > 0 then
                    Just { name = now.name, dc = saveDc taken }

                else
                    Nothing
            )
