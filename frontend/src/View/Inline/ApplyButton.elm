module View.Inline.ApplyButton exposing (view)

{-| One docked editor's Apply button.

Chrome swallows mouse events on a disabled control, so the
unavailable state hangs its tooltip on a wrapper span and opts
the button out of pointer events — otherwise the hover text
explaining why the button is dead could never appear, which is
the one message a dead button owes the reader.

`grow` marks the callers whose button fills its share of a flex
row; the wrapper has to carry that, since it stands in for the
button as the row's item.

-}

import Html exposing (Html, button, span, text)
import Html.Attributes exposing (attribute, class, disabled)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


view :
    { enabled : Bool
    , grow : Bool
    , cls : String
    , msg : Msg
    , tip : String
    , label : String
    }
    -> Html Msg
view cfg =
    if cfg.enabled then
        button
            [ class cfg.cls
            , onClick cfg.msg
            , Tooltips.attr cfg.tip
            ]
            [ text cfg.label ]

    else
        span
            [ class
                (if cfg.grow then
                    "inline-btn-wrap inline-btn-wrap--grow"

                 else
                    "inline-btn-wrap"
                )
            , Tooltips.attr cfg.tip
            ]
            [ button
                [ class (cfg.cls ++ " inline-btn-inert")
                , disabled True
                , attribute "aria-disabled" "true"
                ]
                [ text cfg.label ]
            ]
