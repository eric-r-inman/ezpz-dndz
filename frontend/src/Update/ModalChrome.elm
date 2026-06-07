module Update.ModalChrome exposing
    ( reset, toEdge
    , dragStart, dragMove, dragEnd
    , resizeStart, resizeMove, resizeEnd
    )

{-| Update branches for modal drag-and-resize gestures. Pure
state shuffling on `model.modalChrome` — no Cmds.

The viewport-clamp / size-clamp passes intentionally use a
generous viewport approximation (1600 × 900) when no `Window`
size is plumbed through. The CSS `max-width: 95vw` /
`max-height: 95vh` rules act as a second backstop, so a
mismatch here doesn't let the modal escape — it just lets the
JS-driven resize pretend the viewport is bigger than it is for a
beat until the next browser repaint.

@docs reset, toEdge
@docs dragStart, dragMove, dragEnd
@docs resizeStart, resizeMove, resizeEnd

-}

import Model exposing (Model)
import Msg exposing (ModalChromeEdge(..), Msg)
import Ui.ModalChrome as Chrome


{-| Reset chrome to a fresh, centered, default-sized state. Fired
on every `Nothing → Just _` modal transition (see the top-level
update wrapper in `Main.elm`).
-}
reset : Model -> Model
reset model =
    { model | modalChrome = Chrome.fresh }


{-| Map the wire-friendly `Msg.ModalChromeEdge` (defined in
`Msg.elm` to avoid a chrome-module dependency on `Msg`) over to
the chrome module's own enum.
-}
toEdge : ModalChromeEdge -> Chrome.Edge
toEdge wire =
    case wire of
        ModalEdgeN ->
            Chrome.N

        ModalEdgeS ->
            Chrome.S

        ModalEdgeE ->
            Chrome.E

        ModalEdgeW ->
            Chrome.W

        ModalEdgeNW ->
            Chrome.NW

        ModalEdgeNE ->
            Chrome.NE

        ModalEdgeSW ->
            Chrome.SW

        ModalEdgeSE ->
            Chrome.SE


dragStart : Int -> Int -> Model -> ( Model, Cmd Msg )
dragStart mouseX mouseY model =
    ( { model
        | modalChrome =
            Chrome.beginDrag { mouseX = mouseX, mouseY = mouseY } model.modalChrome
      }
    , Cmd.none
    )


dragMove : Int -> Int -> Model -> ( Model, Cmd Msg )
dragMove mouseX mouseY model =
    let
        ( vpW, vpH ) =
            assumedViewport

        ( modalW, modalH ) =
            measuredSize model
    in
    ( { model
        | modalChrome =
            model.modalChrome
                |> Chrome.dragStep { mouseX = mouseX, mouseY = mouseY }
                |> Chrome.clampOffset
                    { viewportW = vpW
                    , viewportH = vpH
                    , modalW = modalW
                    , modalH = modalH
                    , peekMargin = peekMargin
                    }
      }
    , Cmd.none
    )


dragEnd : Model -> ( Model, Cmd Msg )
dragEnd model =
    ( { model | modalChrome = Chrome.endDrag model.modalChrome }, Cmd.none )


resizeStart :
    ModalChromeEdge
    -> Int
    -> Int
    -> Int
    -> Int
    -> Model
    -> ( Model, Cmd Msg )
resizeStart edgeMsg mouseX mouseY width height model =
    ( { model
        | modalChrome =
            Chrome.beginResize
                { edge = toEdge edgeMsg
                , mouseX = mouseX
                , mouseY = mouseY
                , width = width
                , height = height
                }
                model.modalChrome
      }
    , Cmd.none
    )


resizeMove : Int -> Int -> Model -> ( Model, Cmd Msg )
resizeMove mouseX mouseY model =
    let
        ( vpW, vpH ) =
            assumedViewport
    in
    ( { model
        | modalChrome =
            model.modalChrome
                |> Chrome.resizeStep { mouseX = mouseX, mouseY = mouseY }
                |> Chrome.clampSize { viewportW = vpW, viewportH = vpH }
      }
    , Cmd.none
    )


resizeEnd : Model -> ( Model, Cmd Msg )
resizeEnd model =
    ( { model | modalChrome = Chrome.endResize model.modalChrome }, Cmd.none )



-- ── INTERNAL ────────────────────────────────────────────────────────────────


{-| Viewport approximation. The chrome math wants viewport
dimensions for clamp, but Elm doesn't subscribe to window-size
changes here. The CSS `max-width: 95vw` rule acts as the real
backstop; this is just a sanity bound. 1600 × 900 covers the
common laptop / desktop targets.
-}
assumedViewport : ( Int, Int )
assumedViewport =
    ( 1600, 900 )


{-| Best-guess current modal size, used by `dragMove`'s
viewport-clamp pass. When the user has resized the modal,
`chrome.size` holds the truth; otherwise fall back to a
mid-range default that's wider than typical CSS defaults so the
clamp never accidentally over-restricts a tall narrow modal.
-}
measuredSize : Model -> ( Int, Int )
measuredSize model =
    case model.modalChrome.size of
        Just s ->
            ( s.w, s.h )

        Nothing ->
            ( 640, 600 )


peekMargin : Int
peekMargin =
    48
