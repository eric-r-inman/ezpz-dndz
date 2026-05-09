module View.RollPopup exposing (list)

{-| Floating "+N" popups spawned at the cursor when an inline
dice-link in a creature stat block is clicked. Each popup
animates upward + fades to nothing via a CSS keyframe animation
on `.roll-popup` (see `style.css`); the model entry is removed
on a matching `Process.sleep`-driven `RollPopupExpired` Msg.

Renders nothing when no popups are active.

-}

import Html exposing (Html, div, text)
import Html.Attributes exposing (class, style)
import Model exposing (RollPopup)
import Msg exposing (Msg)


list : List RollPopup -> Html Msg
list popups =
    if List.isEmpty popups then
        text ""

    else
        div [ class "roll-popup-layer" ]
            (List.map one popups)


{-| Each popup is `position: fixed` at its captured `(x, y)`.
The keyframe on `.roll-popup` translates the element up by
~60px and fades opacity to 0 over the lifetime defined in
`Update.Dice.popupLifetimeMs`.

The wrapper supplies the per-popup positioning; the inner span
carries the styled text so the keyframe's transform doesn't
fight a positioning transform on the same element.

-}
one : RollPopup -> Html Msg
one popup =
    div
        [ class "roll-popup"
        , style "left" (String.fromInt popup.x ++ "px")
        , style "top" (String.fromInt popup.y ++ "px")
        ]
        [ text ("+" ++ String.fromInt popup.total) ]
