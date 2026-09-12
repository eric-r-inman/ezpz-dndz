module View.LogRow exposing (foldToggle, openable)

{-| The parts a log row in either panel shares.

@docs foldToggle, openable

-}

import Html exposing (Html, button, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import View.Tooltips as Tooltips


{-| The caret at the row's left edge. `key` is the row's identity
in `Model.expandedLogRows`, so the fold survives the row moving
down the list as newer ones land above it.
-}
foldToggle : String -> Bool -> Html Msg
foldToggle key expanded =
    button
        [ class "log-row__fold"
        , type_ "button"
        , onClick (LogRowToggle key)
        , Tooltips.attr
            (if expanded then
                Tooltips.logRowFold

             else
                Tooltips.logRowUnfold
            )
        , attribute "aria-label"
            (if expanded then
                Tooltips.logRowFold

             else
                Tooltips.logRowUnfold
            )
        , attribute "aria-expanded"
            (if expanded then
                "true"

             else
                "false"
            )
        ]
        [ text
            (if expanded then
                "▼"

             else
                "▶"
            )
        ]


{-| A text span's class, with the wrapping modifier once the row
is unfolded. Folded rows clip to one line with an ellipsis.
-}
openable : String -> Bool -> String
openable base expanded =
    if expanded then
        base ++ " " ++ base ++ "--open"

    else
        base
