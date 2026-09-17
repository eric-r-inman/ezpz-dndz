module View.LogRow exposing (foldGap, foldToggle, openable, sentence)

{-| The parts the editors' log rows share.

@docs foldGap, foldToggle, openable, sentence

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


{-| Stands in the caret's place on a row that reads whole already,
so the rows above and below it still line up on their text.
-}
foldGap : Html Msg
foldGap =
    span [ class "log-row__fold log-row__fold--none" ] [ text "▶" ]


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
    , kindClass : String
    , names : String
    , detail : String
    , flash : Bool
    , trail : List (Html Msg)
    }
    -> Html Msg
sentence row =
    li
        [ class
            (String.join " "
                (List.filterMap identity
                    [ Just "hp-change__log-entry hp-change__log-entry--sentence"
                    , if row.expanded then
                        Just "hp-change__log-entry--open"

                      else
                        Nothing
                    , if row.flash then
                        Just "hp-change__log-entry--flash"

                      else
                        Nothing
                    ]
                )
            )
        ]
        (foldToggle row.key row.expanded
            :: span [ class (openable "hp-change__log-text" row.expanded) ]
                [ span [ class (openable "hp-change__log-kind" row.expanded ++ " " ++ row.kindClass) ]
                    [ text row.kind ]
                , text " "
                , span [ class (openable "hp-change__log-target" row.expanded) ] [ text row.names ]
                , text " "
                , span [ class (openable "hp-change__log-trans" row.expanded) ] [ text row.detail ]
                ]
            :: row.trail
        )
