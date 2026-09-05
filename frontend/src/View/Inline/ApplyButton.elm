module View.Inline.ApplyButton exposing (row, view)

{-| One editor's Apply button.

Chrome swallows mouse events on a disabled control, so the
unavailable state hangs its tooltip on a wrapper span and opts
the button out of pointer events — otherwise the hover text
explaining why the button is dead could never appear, which is
the one message a dead button owes the reader.

-}

import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, disabled)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


view :
    { enabled : Bool
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
            [ class "inline-btn-wrap"
            , Tooltips.attr cfg.tip
            ]
            [ button
                [ class (cfg.cls ++ " inline-btn-inert")
                , disabled True
                , attribute "aria-disabled" "true"
                ]
                [ text cfg.label ]
            ]


{-| An editor's scope row: the verb once, as a lead-in, then one
button per scope. Repeating the verb in each button costs the
width a third scope needs, which a drawer panel does not have to
spare.
-}
row : String -> List (Html Msg) -> Html Msg
row lead buttons =
    div [ class "note-edit__buttons note-edit__buttons--start" ]
        (span [ class "apply-row__lead" ] [ text lead ] :: buttons)
