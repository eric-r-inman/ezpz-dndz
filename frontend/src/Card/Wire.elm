module Card.Wire exposing
    ( SavedLayoutMeta, SavedLayout
    , fetchList, fetchOne, save, delete_
    , encodeLayoutBody, decodeLayoutBody
    , LocalLayoutSnapshot, decodeLocalLayoutSnapshot, encodeLocalLayoutSnapshot
    )

{-| JSON wire format + HTTP client for saved card layouts.

The frontend's `Card.Layout` types are encoded into a single
`body` blob — the server treats it as opaque so the schema can
evolve frontend-only. The body shape is:

    { "rows": [
        { "widgets": ["name", "hit_points", ...]
        , "alignment": "left" | "center" | "right" | "space_between"
        }
      ]
    , "queue_view": "list" | "grid"
    }

Widget keys are produced by [`Card.Layout.widgetKey`](Card-Layout#widgetKey);
alignments and queue-view keys come from the matching helpers
in that module so encoder and decoder stay in lockstep.

@docs SavedLayoutMeta, SavedLayout
@docs fetchList, fetchOne, save, delete_
@docs encodeLayoutBody, decodeLayoutBody

-}

import Card.Layout as Layout
    exposing
        ( CardLayout
        , CardRow
        , CardWidget
        , QueueView(..)
        , RowAlignment(..)
        )
import Http
import Json.Decode as D
import Json.Encode as E
import Url



-- ── TYPES ────────────────────────────────────────────────────────────────────


type alias SavedLayoutMeta =
    { name : String
    , createdAt : Int
    , updatedAt : Int
    }


type alias SavedLayout =
    { name : String
    , layout : CardLayout
    , queueView : QueueView
    , createdAt : Int
    , updatedAt : Int
    }



-- ── DECODERS ─────────────────────────────────────────────────────────────────


decodeMeta : D.Decoder SavedLayoutMeta
decodeMeta =
    D.map3 SavedLayoutMeta
        (D.field "name" D.string)
        (D.field "created_at" D.int)
        (D.field "updated_at" D.int)


decodeRecord : D.Decoder SavedLayout
decodeRecord =
    D.map5 SavedLayout
        (D.field "name" D.string)
        (D.field "body" decodeLayoutBody)
        (D.field "body" decodeQueueView)
        (D.field "created_at" D.int)
        (D.field "updated_at" D.int)


decodeLayoutBody : D.Decoder CardLayout
decodeLayoutBody =
    D.map CardLayout
        (D.field "rows" (D.list decodeRow))


decodeRow : D.Decoder CardRow
decodeRow =
    D.map2 CardRow
        (D.field "widgets" (D.list decodeWidget))
        (D.field "alignment" decodeAlignment)


decodeWidget : D.Decoder CardWidget
decodeWidget =
    D.string
        |> D.andThen
            (\raw ->
                case Layout.widgetFromKey raw of
                    Just w ->
                        D.succeed w

                    Nothing ->
                        D.fail ("Unknown widget key: " ++ raw)
            )


decodeAlignment : D.Decoder RowAlignment
decodeAlignment =
    D.string
        |> D.andThen
            (\raw ->
                case Layout.rowAlignmentFromKey raw of
                    Just a ->
                        D.succeed a

                    Nothing ->
                        D.fail ("Unknown alignment: " ++ raw)
            )


decodeQueueView : D.Decoder QueueView
decodeQueueView =
    D.field "queue_view" D.string
        |> D.andThen
            (\raw ->
                case Layout.queueViewFromKey raw of
                    Just q ->
                        D.succeed q

                    Nothing ->
                        D.fail ("Unknown queue view: " ++ raw)
            )



-- ── ENCODER ──────────────────────────────────────────────────────────────────


encodeLayoutBody : CardLayout -> QueueView -> E.Value
encodeLayoutBody layout queueView =
    E.object
        [ ( "rows", E.list encodeRow layout.rows )
        , ( "queue_view", E.string (Layout.queueViewKey queueView) )
        ]


encodeRow : CardRow -> E.Value
encodeRow row =
    E.object
        [ ( "widgets"
          , E.list (\w -> E.string (Layout.widgetKey w)) row.widgets
          )
        , ( "alignment", E.string (Layout.rowAlignmentKey row.alignment) )
        ]



-- ── HTTP ─────────────────────────────────────────────────────────────────────


fetchList :
    (Result Http.Error (List SavedLayoutMeta) -> msg)
    -> Cmd msg
fetchList toMsg =
    Http.get
        { url = "/api/card-layouts"
        , expect = Http.expectJson toMsg (D.list decodeMeta)
        }


fetchOne :
    String
    -> (Result Http.Error SavedLayout -> msg)
    -> Cmd msg
fetchOne name toMsg =
    Http.get
        { url = "/api/card-layouts/" ++ Url.percentEncode name
        , expect = Http.expectJson toMsg decodeRecord
        }


{-| Save (create or overwrite) a named layout. `overwrite=False`
returns 409 when the name already exists so the GM can confirm
the destructive replace.
-}
save :
    { name : String
    , overwrite : Bool
    , layout : CardLayout
    , queueView : QueueView
    }
    -> (Result Http.Error SavedLayout -> msg)
    -> Cmd msg
save args toMsg =
    let
        query =
            if args.overwrite then
                "?overwrite=true"

            else
                ""
    in
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/card-layouts/" ++ Url.percentEncode args.name ++ query
        , body =
            Http.jsonBody (encodeLayoutBody args.layout args.queueView)
        , expect = Http.expectJson toMsg decodeRecord
        , timeout = Nothing
        , tracker = Nothing
        }


delete_ :
    String
    -> (Result Http.Error () -> msg)
    -> Cmd msg
delete_ name toMsg =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/card-layouts/" ++ Url.percentEncode name
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }



-- ── LOCAL (ANONYMOUS) SNAPSHOT ───────────────────────────────────────────────
--
-- Anonymous sessions don't have named saved layouts (those are
-- server-backed and gated in `View.AuthGate`); instead the live
-- card layout, queue view, and `useCustomCardLayout` toggle are
-- persisted as a single snapshot in `localStorage`.  The shape
-- mirrors the server's `body` blob with one extra boolean.


type alias LocalLayoutSnapshot =
    { layout : CardLayout
    , queueView : QueueView
    , useCustomCardLayout : Bool
    }


encodeLocalLayoutSnapshot : LocalLayoutSnapshot -> E.Value
encodeLocalLayoutSnapshot snap =
    E.object
        [ ( "layout", encodeLayoutBody snap.layout snap.queueView )
        , ( "useCustomCardLayout", E.bool snap.useCustomCardLayout )
        ]


decodeLocalLayoutSnapshot : D.Decoder LocalLayoutSnapshot
decodeLocalLayoutSnapshot =
    D.map3 LocalLayoutSnapshot
        (D.field "layout" decodeLayoutBody)
        (D.field "layout" decodeQueueView)
        (D.field "useCustomCardLayout" D.bool)
