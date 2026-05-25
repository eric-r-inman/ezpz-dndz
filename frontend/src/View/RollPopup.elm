module View.RollPopup exposing (list)

{-| Floating "+N" popups spawned at the cursor when an inline
dice-link in a creature stat block is clicked. Each popup
animates upward + fades to nothing via a CSS keyframe animation
on `.roll-popup` (see `style.css`); the model entry is removed
on a matching `Process.sleep`-driven `RollPopupExpired` Msg.

Renders nothing when no popups are active.

-}

import Html exposing (Html, div, text)
import Html.Attributes exposing (attribute, class, style)
import Model exposing (RollPopup)
import Msg exposing (Msg)


{-| Container is always present in the DOM (no empty-list short-
circuit) and carries `aria-live="polite"` so each new popup's
total is announced to screen readers as it lands. Without this,
SR users get no signal that a roll happened — the visual "+N"
chip floats and fades but is otherwise silent. An always-present
container is what `aria-live` needs to observe reliably; freshly
created live regions are inconsistent across SR clients.
-}
list : List RollPopup -> Html Msg
list popups =
    div
        [ class "roll-popup-layer"
        , attribute "role" "status"
        , attribute "aria-live" "polite"
        , attribute "aria-atomic" "true"
        , attribute "aria-label" "Dice roll results"
        ]
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
        [ text (String.fromInt popup.total) ]
