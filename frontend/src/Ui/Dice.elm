module Ui.Dice exposing (DiceUi, empty)

{-| Dice-roller modal state. Holds presentation-only fields
(open/closed, current text input, count/modifier sliders) plus
the persisted-this-session roll history. The actual rules and
random-roll logic live in `Dice`; this record exists in the UI
layer so it stays adjacent to the view code that consumes it.

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
    { open : Bool
    , input : String
    , inputError : Maybe Dice.Error
    , count : Int
    , modifier : Int
    , modifierText : String
    , history : Dice.History
    , unread : Bool
    }


empty : DiceUi
empty =
    { open = False
    , input = ""
    , inputError = Nothing
    , count = 1
    , modifier = 0
    , modifierText = "0"
    , history = Dice.emptyHistory
    , unread = False
    }
