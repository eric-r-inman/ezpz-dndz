module Ui.QueueDrag exposing (QueueDrag, start, aim, leave)

{-| A creature card on its way to a new place in the queue.

@docs QueueDrag, start, aim, leave

-}

import Encounter.Roster


{-| Where the card started, where it would land if let go now, and
the queue entry the pointer was last seen over, which is what tells
a pointer moving on to the next entry from one leaving the queue.
-}
type alias QueueDrag =
    { from : Int
    , over : Maybe Int
    , entry : Maybe Int
    }


{-| The card at `from`, just picked up.
-}
start : Int -> QueueDrag
start from =
    { from = from, over = Nothing, entry = Nothing }


{-| The pointer is over `entry`, meaning the gap `gap`.
-}
aim : Int -> Int -> QueueDrag -> QueueDrag
aim entry gap drag =
    { drag
        | over = Just (Encounter.Roster.landingIndex drag.from gap)
        , entry = Just entry
    }


{-| The pointer left `entry`. When that is the entry it was last
seen over, it is off the queue, where letting go moves nothing, and
the landing goes; a leave arriving after the next entry has already
reported the pointer changes nothing.
-}
leave : Int -> QueueDrag -> QueueDrag
leave entry drag =
    if drag.entry == Just entry then
        { drag | over = Nothing, entry = Nothing }

    else
        drag
