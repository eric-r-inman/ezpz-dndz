module View.Inline.Field exposing (checkbox, radio, radioWith)

{-| The two plain choice controls the editors share: a bare radio
dot with its label, and a checkbox with its label. One shape for
every editor keeps the drawer reading as one form rather than
several.

@docs checkbox, radio, radioWith

-}

import Html exposing (Html, input, span, text)
import Html.Attributes as Attr exposing (checked, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg)


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
