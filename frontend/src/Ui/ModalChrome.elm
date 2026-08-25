module Ui.ModalChrome exposing
    ( Edge(..), ModalChrome, fresh
    , beginDrag, dragStep, endDrag
    , beginResize, resizeStep, endResize
    , clampOffset, clampSize, minWidth, minHeight
    )

{-| Cross-cutting state for the draggable + edge-resizable modal
chrome.

Every modal in the app shares a single chrome record on the
top-level `Model`. The record holds:

  - `offset` — pixel translation from the modal's CSS-default
    (viewport-centered) position. `(0, 0)` means "use the
    backdrop's grid-centering"; non-zero means "translate by
    these pixels".
  - `size` — `Just { w, h }` when the user has resized the
    modal at least once; `Nothing` means "use the CSS default
    width / max-height".
  - `drag` / `resize` — `Just _` while a gesture is in flight.
    The presence of either tells `subscriptions` to attach the
    Browser.Events mousemove / mouseup listeners.

The chrome is reset to [`fresh`](#fresh) on every
`Nothing → Just _` modal transition so each freshly-opened
dialog starts centered at its CSS-default size; users don't
inherit a previous modal's "I dragged this off-screen" state.

@docs Edge, ModalChrome, fresh
@docs beginDrag, dragStep, endDrag
@docs beginResize, resizeStep, endResize
@docs clampOffset, clampSize, minWidth, minHeight

-}


{-| Which edge / corner of the modal is being dragged during a
resize gesture. Pure resize-handle vocabulary — these don't map
1-to-1 to CSS cursors, but the view layer chooses a cursor per
edge.
-}
type Edge
    = N
    | S
    | E
    | W
    | NW
    | NE
    | SW
    | SE


{-| Shared modal-chrome state. Single instance lives on the
top-level `Model`; reset whenever a new modal opens.
-}
type alias ModalChrome =
    { offset : { x : Int, y : Int }
    , size : Maybe { w : Int, h : Int }
    , drag : Maybe DragState
    , resize : Maybe ResizeState
    }


{-| Anchor data captured at drag-start so each mousemove can
compute the new offset as `start_offset + (current_mouse -
start_mouse)`. Tracking the start mouse position avoids drift
from delta accumulation.
-}
type alias DragState =
    { startMouseX : Int
    , startMouseY : Int
    , startOffsetX : Int
    , startOffsetY : Int
    }


{-| Same idea as `DragState`, but for a resize gesture. The edge
identifies which handle was grabbed (and therefore which axes
respond to mouse movement and whether the modal grows toward the
mouse or recedes from it).

The `startOffsetX/Y` are tracked because north / west edges
shift the modal's anchor when growing — the upper-left corner
must move so the lower-right stays put.

-}
type alias ResizeState =
    { edge : Edge
    , startMouseX : Int
    , startMouseY : Int
    , startWidth : Int
    , startHeight : Int
    , startOffsetX : Int
    , startOffsetY : Int
    }


{-| Floor for resize. Mirrors the CSS `min-width` / `min-height`
on `.surface` — keeps the resize handles reachable and the header
content from collapsing into illegibility.
-}
minWidth : Int
minWidth =
    320


minHeight : Int
minHeight =
    200


{-| Default chrome: centered, default-sized, idle.
-}
fresh : ModalChrome
fresh =
    { offset = { x = 0, y = 0 }
    , size = Nothing
    , drag = Nothing
    , resize = Nothing
    }


{-| Open a drag gesture. Records the current mouse position and
the current offset; subsequent `dragStep` calls reference these.
-}
beginDrag : { mouseX : Int, mouseY : Int } -> ModalChrome -> ModalChrome
beginDrag { mouseX, mouseY } chrome =
    { chrome
        | drag =
            Just
                { startMouseX = mouseX
                , startMouseY = mouseY
                , startOffsetX = chrome.offset.x
                , startOffsetY = chrome.offset.y
                }
    }


{-| Apply a mousemove during drag. New offset = start\_offset +
(current\_mouse - start\_mouse). No-op when no drag is in flight.
The caller is responsible for clamping the result to the viewport
via [`clampOffset`](#clampOffset).
-}
dragStep : { mouseX : Int, mouseY : Int } -> ModalChrome -> ModalChrome
dragStep { mouseX, mouseY } chrome =
    case chrome.drag of
        Just s ->
            { chrome
                | offset =
                    { x = s.startOffsetX + (mouseX - s.startMouseX)
                    , y = s.startOffsetY + (mouseY - s.startMouseY)
                    }
            }

        Nothing ->
            chrome


endDrag : ModalChrome -> ModalChrome
endDrag chrome =
    { chrome | drag = Nothing }


{-| Open a resize gesture. The caller supplies the current modal
dimensions (read via `Browser.Dom` or, in our case, derived from
chrome.size + CSS defaults inside the Update layer).
-}
beginResize :
    { edge : Edge, mouseX : Int, mouseY : Int, width : Int, height : Int }
    -> ModalChrome
    -> ModalChrome
beginResize { edge, mouseX, mouseY, width, height } chrome =
    { chrome
        | resize =
            Just
                { edge = edge
                , startMouseX = mouseX
                , startMouseY = mouseY
                , startWidth = width
                , startHeight = height
                , startOffsetX = chrome.offset.x
                , startOffsetY = chrome.offset.y
                }
    }


{-| Apply a mousemove during resize.

The modal is positioned via a CSS transform applied on top of a
viewport-centered backdrop. Its rendered box spans:

    left =
        vp_center_x - w / 2 + offset.x

    right =
        vp_center_x + w / 2 + offset.x

    top =
        vp_center_y - h / 2 + offset.y

    bottom =
        vp_center_y + h / 2 + offset.y

Each edge resize keeps the OPPOSITE edge planted in screen
coordinates. For E (right edge), the LEFT edge stays put → the
center shifts right by (newW - oldW) / 2. For W, the right edge
stays put → center shifts left by the same delta. Vertical edges
work analogously.

Caller clamps the resulting size via [`clampSize`](#clampSize).

-}
resizeStep : { mouseX : Int, mouseY : Int } -> ModalChrome -> ModalChrome
resizeStep { mouseX, mouseY } chrome =
    case chrome.resize of
        Just s ->
            let
                dx =
                    mouseX - s.startMouseX

                dy =
                    mouseY - s.startMouseY

                xAxis =
                    -- (deltaW, anchorSign) where anchorSign is +1
                    -- for "left edge fixed, center moves right as
                    -- we grow" and -1 for the reverse; 0 for
                    -- edges that don't touch the X axis.
                    case s.edge of
                        E ->
                            ( dx, 1 )

                        NE ->
                            ( dx, 1 )

                        SE ->
                            ( dx, 1 )

                        W ->
                            ( -dx, -1 )

                        NW ->
                            ( -dx, -1 )

                        SW ->
                            ( -dx, -1 )

                        N ->
                            ( 0, 0 )

                        S ->
                            ( 0, 0 )

                yAxis =
                    case s.edge of
                        S ->
                            ( dy, 1 )

                        SE ->
                            ( dy, 1 )

                        SW ->
                            ( dy, 1 )

                        N ->
                            ( -dy, -1 )

                        NE ->
                            ( -dy, -1 )

                        NW ->
                            ( -dy, -1 )

                        E ->
                            ( 0, 0 )

                        W ->
                            ( 0, 0 )

                ( dW, xSign ) =
                    xAxis

                ( dH, ySign ) =
                    yAxis

                newW =
                    max minWidth (s.startWidth + dW)

                newH =
                    max minHeight (s.startHeight + dH)

                -- Actual deltas (after the min-size floor).  If
                -- the floor blocked the resize, the offset stops
                -- moving too — otherwise the modal would scoot
                -- off-screen without shrinking.
                actualDw =
                    newW - s.startWidth

                actualDh =
                    newH - s.startHeight
            in
            { chrome
                | size = Just { w = newW, h = newH }
                , offset =
                    { x = s.startOffsetX + (xSign * actualDw) // 2
                    , y = s.startOffsetY + (ySign * actualDh) // 2
                    }
            }

        Nothing ->
            chrome


endResize : ModalChrome -> ModalChrome
endResize chrome =
    { chrome | resize = Nothing }


{-| Clamp the drag offset so the modal stays at least
`peekMargin` pixels visible on every side. `viewportW/H` are the
inner window dimensions; `modalW/H` are the modal's current
rendered size; `peekMargin` is how much of the modal must stay
on-screen so the user can grab the header to drag it back.
-}
clampOffset :
    { viewportW : Int
    , viewportH : Int
    , modalW : Int
    , modalH : Int
    , peekMargin : Int
    }
    -> ModalChrome
    -> ModalChrome
clampOffset { viewportW, viewportH, modalW, modalH, peekMargin } chrome =
    let
        -- Default modal position is viewport-centered.  Offset is
        -- relative to that center.  The modal's rendered box
        -- spans from (centerX - modalW/2 + offset.x) to
        -- (centerX + modalW/2 + offset.x).  We want at least
        -- `peekMargin` of the modal inside [0, viewportW] on the
        -- X axis (and similarly for Y).
        halfW =
            modalW // 2

        halfH =
            modalH // 2

        centerX =
            viewportW // 2

        centerY =
            viewportH // 2

        minOffsetX =
            peekMargin - centerX - halfW + peekMargin

        maxOffsetX =
            viewportW - centerX + halfW - peekMargin - peekMargin

        minOffsetY =
            -- The header bar must stay on-screen so the user can
            -- drag the modal back; clamp Y up so the top of the
            -- modal sits at least `peekMargin` below the top edge.
            peekMargin - centerY + halfH

        maxOffsetY =
            viewportH - centerY + halfH - peekMargin - peekMargin
    in
    { chrome
        | offset =
            { x = clampInt minOffsetX maxOffsetX chrome.offset.x
            , y = clampInt minOffsetY maxOffsetY chrome.offset.y
            }
    }


{-| Clamp the rendered size to viewport caps. Mirrors the CSS
`max-width: 95vw` / `max-height: 95vh` so the JS-driven resize
path can't push past what the CSS would allow.
-}
clampSize : { viewportW : Int, viewportH : Int } -> ModalChrome -> ModalChrome
clampSize { viewportW, viewportH } chrome =
    case chrome.size of
        Just s ->
            { chrome
                | size =
                    Just
                        { w = clampInt minWidth ((viewportW * 95) // 100) s.w
                        , h = clampInt minHeight ((viewportH * 95) // 100) s.h
                        }
            }

        Nothing ->
            chrome



-- ── INTERNAL ────────────────────────────────────────────────────────────────


clampInt : Int -> Int -> Int -> Int
clampInt lo hi n =
    if n < lo then
        lo

    else if n > hi then
        hi

    else
        n
