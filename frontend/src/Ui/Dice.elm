module Ui.Dice exposing (DiceUi, empty)

{-| Dice-roller panel state: presentation-only fields plus the
persisted-this-session roll history. The actual rules and
random-roll logic live in `Dice`; this record exists in the UI
layer so it stays adjacent to the view code that consumes it.
Openness isn't here — it is the `SurfaceDice` marker's presence
in the drawer stack.

The parsed `modifier` is what generators consume; `modifierText`
mirrors the literal characters in the `<input>`. The two
diverge during transient typing — e.g. while the user is typing
"-5", the field briefly contains just "-", which doesn't parse
as an Int. We keep the raw text in the model so re-renders
don't overwrite the "-" with a stringified previous value, which
used to make negative input feel impossible.

@docs DiceUi, empty

-}

import Dice


type alias DiceUi =
    { input : String
    , inputError : Maybe Dice.Error
    , count : Int
    , modifier : Int
    , modifierText : String
    , history : Dice.History
    , unread : Bool

    -- Which roll-history entry (by index) has its re-roll
    -- dropdown menu open.  Single-open-at-a-time, so `Maybe Int`
    -- rather than a `Set`.  The menu lets the GM choose between
    -- "Reroll" (existing behaviour) and "Reroll, no modifier"
    -- (strip the constant before rolling).
    , rerunMenuOpenFor : Maybe Int

    -- Whether the Recent-rolls list is showing.  Folded by
    -- default so a freshly-opened roller leads with the dice
    -- themselves; the GM unfolds it once there's something to
    -- read.
    , historyOpen : Bool

    -- The rail's badge strip normally shows the last 3 rolls from
    -- `history`, newest emphasized. A triple-roll (an attack,
    -- ability check, or saving throw fired at standard +
    -- advantage + disadvantage together) overrides that with its
    -- own 3 results instead, colour-coded by roll kind rather
    -- than recency. Any single roll landing afterward — from any
    -- source — clears the override, so the strip falls back to
    -- the ordinary recency view until the next triple-roll.
    , rollBadgeOverride : Maybe (List Dice.Roll)
    }


empty : DiceUi
empty =
    { input = ""
    , inputError = Nothing
    , count = 1
    , modifier = 0
    , modifierText = "0"
    , history = Dice.emptyHistory
    , unread = False
    , rerunMenuOpenFor = Nothing
    , historyOpen = False
    , rollBadgeOverride = Nothing
    }
