module View.Modal exposing (view, closeBtnId, focusInitial)

{-| Shared modal chrome.

Every modal in the app — dice, HP change, initiative, note, memo,
timer, condition — wraps its body in the same backdrop / dialog
shell with a header bar carrying a title and a close button.
This helper extracts that shell so per-modal view code only
declares the body content.

The Esc-key handler is the caller's responsibility (see
`subscriptions` in `Main.elm`); the modal chrome here also adds
a focus-management contract:

  - `closeBtnId` — stable id for the modal `×` button. `Main`
    wraps `update` to fire `focusInitial` whenever
    `model.modal` transitions from `Nothing` to `Just _`, so
    keyboard / SR users land inside the dialog the moment it
    appears.
  - A focus sentinel `<div class="modal__focus-sentinel">` at
    the end of the modal body. When Tab moves keyboard focus
    past the last interactive descendant it lands on the
    sentinel. An inline-script focus listener in `index.html`
    detects this and redirects focus back to the close button,
    so Tab wraps within the modal without escaping to the
    underlying page. The sentinel lives in the view layer; the
    redirect logic lives in JS so we don't have to plumb a Msg
    through every modal's update path.

@docs view, closeBtnId, focusInitial

-}

import Browser.Dom
import Html exposing (Html, button, div, h2, text)
import Html.Attributes exposing (attribute, class, id, tabindex)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Task
import View.Tooltips as Tooltips


{-| Stable id for the modal close (`×`) button. The Main
update wrapper focuses this on modal-open, and the JS sentinel
handler in `index.html` redirects focus here when Tab walks
past the last focusable element in the modal body.
-}
closeBtnId : String
closeBtnId =
    "modal-close-btn"


{-| Cmd that focuses the modal close button. Fires
asynchronously, so by the time the focus task runs the new
modal view is already in the DOM. Failures (the element doesn't
exist yet, focus stolen by another element) are silently
discarded — initial focus is best-effort polish.
-}
focusInitial : (Result Browser.Dom.Error () -> msg) -> Cmd msg
focusInitial toMsg =
    Task.attempt toMsg (Browser.Dom.focus closeBtnId)


{-| Render a modal with the given title, body content, and
close-Msg. The `noOp` argument is used to swallow click events
inside the modal body so they don't propagate to the backdrop
and accidentally close the dialog.

  - `close` — Msg dispatched when the user clicks the backdrop
    or the × button.
  - `noOp` — a no-op Msg used by the inner-click swallower AND
    by the focus-sentinel handler (`Browser.Dom.focus` of the
    close button is fired through `noOp` since the dispatch is a
    no-Cmd-needed side effect from the caller's POV; see the
    sentinel decoder below for details).
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
            , -- `aria-labelledby` points at the visible heading so
              -- SR users hear the modal title when focus enters,
              -- instead of duplicating it in a hidden `aria-label`.
              attribute "aria-labelledby" "modal-title"
            ]
            [ div [ class "modal__header" ]
                [ -- Title promoted from a `<div>` to a real `<h2>`
                  -- so the document heading hierarchy stays valid
                  -- (Workspace is the `<h1>` host).  The id pairs
                  -- with `aria-labelledby` above.
                  h2
                    [ class "modal__title"
                    , id "modal-title"
                    ]
                    [ text config.title ]
                , button
                    [ class "modal__close"
                    , id closeBtnId
                    , onClick config.close
                    , Tooltips.attr Tooltips.modalClose
                    , attribute "aria-label" "Close"
                    ]
                    [ text "×" ]
                ]
            , div [ class "modal__body" ] config.body
            , -- END focus sentinel.  Invisible `<div tabindex="0">`
              -- at the tail of the modal.  When Tab moves focus
              -- past the last interactive element inside the body,
              -- focus lands here; the inline-script focus listener
              -- in `index.html` (matching
              -- `.modal__focus-sentinel`) immediately redirects
              -- focus back to the close button, so the keyboard
              -- user wraps within the modal instead of escaping
              -- to the underlying page.  Visually hidden via the
              -- existing CSS — the sentinel reserves no layout.
              div
                [ class "modal__focus-sentinel"
                , tabindex 0
                , attribute "aria-hidden" "true"
                ]
                []
            ]
        ]
