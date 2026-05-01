module Encounter.SaveNotice exposing
    ( SaveNotice
    , create
    , tickList
    )

{-| Transient "Saved: <Condition>" notice shown on a creature card
after an auto-roll save successfully ends a condition. Manual
chip 🎲 successes do NOT post these — those just remove silently
since the GM is already looking at the card.

`turnsRemaining` decrements on the bearer's end-of-turn hook.
A fresh notice has `turnsRemaining = 1`, so it lasts through one
bearer end-of-turn pass and is then removed automatically. The
GM can also dismiss it manually via the × on the notice chip.

The Encounter-level wrappers (`Encounter.addSaveNotice`,
`Encounter.removeSaveNotice`) live in the parent module because
they need encounter-wide id allocation and per-creature mutation;
this module is the pure data layer.


# Type

@docs SaveNotice


# Construction

@docs create


# Mutation

@docs tickList

-}


{-| One save-notice record. `id` is encounter-wide unique so
the × button on a chip can target the right notice on the right
creature.
-}
type alias SaveNotice =
    { id : Int
    , conditionName : String
    , turnsRemaining : Int
    }


{-| Build a fresh notice with `turnsRemaining = 1`. Caller
supplies the encounter-wide unique id.
-}
create : Int -> String -> SaveNotice
create id conditionName =
    { id = id
    , conditionName = conditionName
    , turnsRemaining = 1
    }


{-| Decrement every notice in the list by 1; drop any whose
counter would reach 0. Pure list-on-list operation; the parent
encounter applies this to each affected creature's notice list.
-}
tickList : List SaveNotice -> List SaveNotice
tickList =
    List.filterMap tick


tick : SaveNotice -> Maybe SaveNotice
tick notice =
    let
        next =
            notice.turnsRemaining - 1
    in
    if next <= 0 then
        Nothing

    else
        Just { notice | turnsRemaining = next }
