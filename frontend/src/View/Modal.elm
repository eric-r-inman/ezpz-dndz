module View.Modal exposing
    ( view, closeBtnId, focusInitial
    , viewWithExtras
    )

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

The modal is also draggable (mousedown on the header) and
edge-resizable (mousedown on one of eight invisible handles
along the perimeter). Drag and resize state lives on
`model.modalChrome`; the view consumes the chrome to apply the
transform / inline width / height. The chrome-Msg constructors
are imported directly from `Msg` rather than threaded through
the config record because every modal needs the same handlers —
threading them through 20 call sites would be pure noise.

@docs view, closeBtnId, focusInitial

-}

import Browser.Dom
import Html exposing (Html, button, div, h2, text)
import Html.Attributes exposing (attribute, class, id, style, tabindex)
import Html.Events exposing (onClick, preventDefaultOn, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (ModalChromeEdge(..), Msg(..))
import Task
import Ui.ModalChrome exposing (ModalChrome)
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
  - `chrome` — drag / resize state. Use `Ui.ModalChrome.fresh`
    or the model's `modalChrome` field. The view applies the
    chrome's offset as a CSS transform and the chrome's size
    as inline width / height.

-}
view :
    { close : Msg
    , noOp : Msg
    , title : String
    , extraClass : String
    , body : List (Html Msg)
    , chrome : ModalChrome
    }
    -> Html Msg
view config =
    viewWithExtras config []


{-| Like `view`, but accepts extra header buttons that render
to the left of the × close button. The Compendium modal uses
this to slot a ↗ "open in new tab" button without every other
modal having to grow a new config field.
-}
viewWithExtras :
    { close : Msg
    , noOp : Msg
    , title : String
    , extraClass : String
    , body : List (Html Msg)
    , chrome : ModalChrome
    }
    -> List (Html Msg)
    -> Html Msg
viewWithExtras config headerExtras =
    div
        [ class "modal-backdrop"
        , onClick config.close
        ]
        [ div
            ([ class ("modal " ++ config.extraClass)
             , stopPropagationOn "click" (Decode.succeed ( config.noOp, True ))
             , attribute "role" "dialog"
             , attribute "aria-modal" "true"
             , attribute "aria-labelledby" "modal-title"
             ]
                ++ chromeStyle config.chrome
            )
            (List.concat
                [ [ div
                        [ class "modal__header modal__drag-handle"
                        , preventDefaultOn "mousedown" (dragStartDecoder ModalChromeDragStart)
                        ]
                        ([ h2
                            [ class "modal__title"
                            , id "modal-title"
                            ]
                            [ text config.title ]
                         ]
                            ++ headerExtras
                            ++ [ button
                                    [ class "modal__close"
                                    , id closeBtnId
                                    , onClick config.close
                                    , Tooltips.attr Tooltips.modalClose
                                    , attribute "aria-label" "Close"
                                    ]
                                    [ text "×" ]
                               ]
                        )
                  , div [ class "modal__body" ] config.body
                  , div
                        [ class "modal__focus-sentinel"
                        , tabindex 0
                        , attribute "aria-hidden" "true"
                        ]
                        []
                  ]
                , resizeHandles config.chrome
                ]
            )
        ]


{-| Inline `transform` + `width` / `height` for the modal,
derived from chrome state. When the user hasn't dragged or
resized, the resulting style list is empty — CSS defaults apply
exactly as before the chrome was wired in.
-}
chromeStyle : ModalChrome -> List (Html.Attribute Msg)
chromeStyle chrome =
    let
        offsetStyle =
            if chrome.offset.x == 0 && chrome.offset.y == 0 then
                []

            else
                [ style "transform"
                    ("translate("
                        ++ String.fromInt chrome.offset.x
                        ++ "px, "
                        ++ String.fromInt chrome.offset.y
                        ++ "px)"
                    )
                ]

        sizeStyle =
            case chrome.size of
                Just s ->
                    [ style "width" (String.fromInt s.w ++ "px")
                    , style "height" (String.fromInt s.h ++ "px")
                    ]

                Nothing ->
                    []
    in
    offsetStyle ++ sizeStyle


{-| Eight invisible handles, one per edge / corner, that capture
mousedown and fire the appropriate resize-start Msg. Positioning
and cursors live in CSS (`.modal__resize-*`).

The handle's mousedown decoder reads `currentTarget.parentElement.
offsetWidth / offsetHeight` to capture the LIVE rendered size of
the parent `.modal` element. Doing it this way (instead of
passing a guess from the Elm side) is what keeps the modal from
snapping to a fallback size the moment the user clicks a handle
on a freshly-opened modal — `chrome.size` is `Nothing` until the
user resizes once, but `offsetWidth` always reflects the CSS-
computed size at the click instant.

-}
resizeHandles : ModalChrome -> List (Html Msg)
resizeHandles _ =
    let
        handle edge cls =
            div
                [ class ("modal__resize " ++ cls)
                , preventDefaultOn "mousedown" (resizeStartDecoder edge)
                ]
                []
    in
    [ handle ModalEdgeN "modal__resize--n"
    , handle ModalEdgeS "modal__resize--s"
    , handle ModalEdgeE "modal__resize--e"
    , handle ModalEdgeW "modal__resize--w"
    , handle ModalEdgeNW "modal__resize--nw"
    , handle ModalEdgeNE "modal__resize--ne"
    , handle ModalEdgeSW "modal__resize--sw"
    , handle ModalEdgeSE "modal__resize--se"
    ]


{-| Decode a mousedown event into the `dragStart` Msg carrying
`clientX, clientY`. `preventDefault = True` stops the browser
from initiating a text-selection drag.
-}
dragStartDecoder : (Int -> Int -> Msg) -> Decode.Decoder ( Msg, Bool )
dragStartDecoder toMsg =
    Decode.map2 toMsg
        (Decode.field "clientX" Decode.int)
        (Decode.field "clientY" Decode.int)
        |> Decode.map (\msg -> ( msg, True ))


{-| Decode a mousedown event on a resize handle into a
`ModalChromeResizeStart` Msg carrying the edge, the mouse
position, and the modal's LIVE rendered size (read from the DOM
via `currentTarget.parentElement.offsetWidth / offsetHeight`).

The parent-element walk depends on the markup contract that
each `.modal__resize` handle is a direct child of the `.modal`
div (see `resizeHandles`). `offsetWidth / offsetHeight` give the
rounded integer pixel size including padding+border, which is
what the resize math wants.

`preventDefault = True` so the drag doesn't initiate a text
selection or scroll.

-}
resizeStartDecoder : ModalChromeEdge -> Decode.Decoder ( Msg, Bool )
resizeStartDecoder edge =
    Decode.map4 (\x y w h -> ModalChromeResizeStart edge x y w h)
        (Decode.field "clientX" Decode.int)
        (Decode.field "clientY" Decode.int)
        (Decode.at [ "currentTarget", "parentElement", "offsetWidth" ] Decode.int)
        (Decode.at [ "currentTarget", "parentElement", "offsetHeight" ] Decode.int)
        |> Decode.map (\msg -> ( msg, True ))
