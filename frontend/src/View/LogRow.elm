module View.LogRow exposing (foldToggle, openable, sentence)

{-| The parts the editors' log rows share.

@docs foldToggle, openable, sentence

-}

import Html exposing (Html, button, li, span, text)
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


{-| A row that reads as one sentence, clipped to a single line
until the GM unfolds it. `trail` sits beside the text either way.
-}
sentence :
    { key : String
    , expanded : Bool
    , kind : String
    , names : String
    , detail : String
    , trail : List (Html Msg)
    }
    -> Html Msg
sentence row =
    li
        [ class
            (if row.expanded then
                "hp-change__log-entry hp-change__log-entry--sentence hp-change__log-entry--open"

             else
                "hp-change__log-entry hp-change__log-entry--sentence"
            )
        ]
        (foldToggle row.key row.expanded
            :: span [ class (openable "hp-change__log-text" row.expanded) ]
                [ span [ class (openable "hp-change__log-kind" row.expanded ++ " hp-change__log-kind--cond") ]
                    [ text row.kind ]
                , text " "
                , span [ class (openable "hp-change__log-target" row.expanded) ] [ text row.names ]
                , text " "
                , span [ class (openable "hp-change__log-trans" row.expanded) ] [ text row.detail ]
                ]
            :: row.trail
        )
