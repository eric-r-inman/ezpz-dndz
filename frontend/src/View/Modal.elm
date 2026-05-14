module View.Modal exposing (view)

{-| Shared modal chrome.

Every modal in the app — dice, HP change, initiative, note, memo,
timer, condition — wraps its body in the same backdrop / dialog
shell with a header bar carrying a title and a close button.
This helper extracts that shell so per-modal view code only
declares the body content.

The Esc-key handler is the caller's responsibility (see
`subscriptions` in `Main.elm`); the modal chrome here only
handles backdrop click + the `×` button.

@docs view

-}

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import View.Tooltips as Tooltips


{-| Render a modal with the given title, body content, and
close-Msg. The `noOp` argument is used to swallow click events
inside the modal body so they don't propagate to the backdrop
and accidentally close the dialog.

  - `close` — Msg dispatched when the user clicks the backdrop
    or the × button.
  - `noOp` — a no-op Msg used by the inner-click swallower.
  - `title` — heading text shown in the modal header.
  - `extraClass` — extra class on the inner `.modal` div, used
    for per-modal sizing (`"modal--initiative"`,
    `"modal--condition"`, etc.).
  - `body` — the per-modal content placed inside `.modal__body`.

-}
view :
    { close : msg
    , noOp : msg
    , title : String
    , extraClass : String
    , body : List (Html msg)
    }
    -> Html msg
view config =
    div
        [ class "modal-backdrop"
        , onClick config.close
        ]
        [ div
            [ class ("modal " ++ config.extraClass)
            , stopPropagationOn "click" (Decode.succeed ( config.noOp, True ))
            , attribute "role" "dialog"
            , attribute "aria-modal" "true"
            , attribute "aria-label" config.title
            ]
            [ div [ class "modal__header" ]
                [ div [ class "modal__title" ] [ text config.title ]
                , button
                    [ class "modal__close"
                    , onClick config.close
                    , Tooltips.attr Tooltips.modalClose
                    , attribute "aria-label" "Close"
                    ]
                    [ text "×" ]
                ]
            , div [ class "modal__body" ] config.body
            ]
        ]
