module View.Inline.Field exposing (checkbox, foldHead, radio, radioWith, spin)

{-| The small controls the editors share. One shape for every
editor keeps the drawer reading as one form rather than several.

@docs checkbox, foldHead, radio, radioWith, spin

-}

import Html exposing (Html, button, div, input, span, text)
import Html.Attributes as Attr exposing (attribute, checked, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


{-| One option of a radio group: `group` keeps it apart from every
other group in the document.
-}
radio : { group : String, selected : Bool, msg : Msg, label : String } -> Html Msg
radio =
    radioWith []


{-| `radio` with attributes for the label to wear — a tooltip that
says more than the label's few words can.
-}
radioWith : List (Html.Attribute Msg) -> { group : String, selected : Bool, msg : Msg, label : String } -> Html Msg
radioWith extra cfg =
    Html.label (class "cond-radio-plain" :: extra)
        [ input
            [ type_ "radio"
            , Attr.name cfg.group
            , class
                (if cfg.selected then
                    "cond-radio-plain__dot cond-radio-plain__dot--selected"

                 else
                    "cond-radio-plain__dot"
                )
            , checked cfg.selected
            , onClick cfg.msg
            ]
            []
        , span [ class "cond-radio__label" ] [ text cfg.label ]
        ]


{-| The heading row of a section that folds: a caret and the title
as one button, with `trail` — a control the row also holds, such
as a log's Clear — after it.
-}
foldHead : { open : Bool, title : String, msg : Msg, trail : List (Html Msg) } -> Html Msg
foldHead cfg =
    div [ class "fold-head" ]
        (button
            [ class "fold-toggle"
            , type_ "button"
            , onClick cfg.msg
            , Tooltips.attr Tooltips.foldToggle
            , attribute "aria-expanded"
                (if cfg.open then
                    "true"

                 else
                    "false"
                )
            ]
            [ span [ class "fold-toggle__caret" ]
                [ text
                    (if cfg.open then
                        "▼"

                     else
                        "▶"
                    )
                ]
            , span [ class "fold-toggle__title" ] [ text cfg.title ]
            ]
            :: cfg.trail
        )


{-| The ▲ / ▼ pair beside a number field, for a click path that
reaches any value the field takes. `what` names the number for a
reader that cannot see the field.
-}
spin : { up : Msg, down : Msg, what : String } -> Html Msg
spin cfg =
    span [ class "cond-spin" ]
        [ button
            [ class "cond-spin__btn"
            , type_ "button"
            , onClick cfg.up
            , Tooltips.attr "Increase by 1"
            , attribute "aria-label" ("Increase " ++ cfg.what ++ " by 1")
            ]
            [ text "▲" ]
        , button
            [ class "cond-spin__btn"
            , type_ "button"
            , onClick cfg.down
            , Tooltips.attr "Decrease by 1"
            , attribute "aria-label" ("Decrease " ++ cfg.what ++ " by 1")
            ]
            [ text "▼" ]
        ]


{-| A checkbox and its label; `extra` carries a tooltip or any
other attribute the label should wear.
-}
checkbox : { checked : Bool, msg : Msg, label : String, extra : List (Html.Attribute Msg) } -> Html Msg
checkbox cfg =
    Html.label (class "cond-checkbox" :: cfg.extra)
        [ input
            [ type_ "checkbox"
            , class "cond-checkbox__box"
            , checked cfg.checked
            , onClick cfg.msg
            ]
            []
        , span [ class "cond-radio__label" ] [ text cfg.label ]
        ]
