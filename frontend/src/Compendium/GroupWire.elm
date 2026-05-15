module Compendium.GroupWire exposing
    ( decodeGroup, encodeGroup, encodeDraft
    , fetchAll, create, update, delete
    , Draft
    )

{-| JSON encoders / decoders + HTTP client for the per-user
[`Compendium.Group`](Compendium-Group) store.

Wire format matches the Rust types in
`crates/lib/src/compendium/group.rs`. In particular
[`InitiativeMode`](Compendium-Group#InitiativeMode) serialises
with an internally tagged discriminator (`{ "type": "each_rolls" }`,
`{ "type": "shared_manual", "value": 12 }`) — keep the encoder and
decoder in sync with the Rust `#[serde(tag = "type", rename_all =
"snake_case")]` attribute on the enum.

@docs decodeGroup, encodeGroup, encodeDraft
@docs fetchAll, create, update, delete
@docs Draft

-}

import Compendium.Group as Group
    exposing
        ( Group
        , GroupEntry
        , InitiativeMode(..)
        , MinionType(..)
        )
import Http
import Json.Decode as D
import Json.Encode as E



-- ── DRAFT ────────────────────────────────────────────────────────────────────


{-| Client-supplied shape for POSTing a new group: same fields as
`Group` minus the server-issued id + timestamps.
-}
type alias Draft =
    { name : String
    , initiativeMode : InitiativeMode
    , entries : List GroupEntry
    }



-- ── DECODERS ─────────────────────────────────────────────────────────────────


decodeGroup : D.Decoder Group
decodeGroup =
    D.map6 Group
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "initiative_mode" decodeInitiativeMode)
        (D.field "entries" (D.list decodeEntry))
        (D.field "created_at" D.int)
        (D.field "updated_at" D.int)


decodeEntry : D.Decoder GroupEntry
decodeEntry =
    D.map3 GroupEntry
        (D.field "creature_id" D.string)
        (D.field "count" D.int)
        (D.oneOf
            [ D.field "minion_type" decodeMinionType
            , D.succeed MinionNone
            ]
        )


decodeInitiativeMode : D.Decoder InitiativeMode
decodeInitiativeMode =
    D.field "type" D.string
        |> D.andThen
            (\tag ->
                case tag of
                    "each_rolls" ->
                        D.succeed InitiativeEachRolls

                    "shared_rolled" ->
                        D.succeed InitiativeSharedRolled

                    "shared_manual" ->
                        D.map InitiativeSharedManual (D.field "value" D.int)

                    other ->
                        D.fail ("Unknown initiative mode: " ++ other)
            )


decodeMinionType : D.Decoder MinionType
decodeMinionType =
    D.string
        |> D.andThen
            (\raw ->
                case raw of
                    "none" ->
                        D.succeed MinionNone

                    "half" ->
                        D.succeed MinionHalfHp

                    "one" ->
                        D.succeed MinionOneHp

                    other ->
                        D.fail ("Unknown minion type: " ++ other)
            )



-- ── ENCODERS ─────────────────────────────────────────────────────────────────


encodeGroup : Group -> E.Value
encodeGroup g =
    E.object
        [ ( "id", E.string g.id )
        , ( "name", E.string g.name )
        , ( "initiative_mode", encodeInitiativeMode g.initiativeMode )
        , ( "entries", E.list encodeEntry g.entries )
        , ( "created_at", E.int g.createdAt )
        , ( "updated_at", E.int g.updatedAt )
        ]


encodeDraft : Draft -> E.Value
encodeDraft d =
    E.object
        [ ( "name", E.string d.name )
        , ( "initiative_mode", encodeInitiativeMode d.initiativeMode )
        , ( "entries", E.list encodeEntry d.entries )
        ]


encodeEntry : GroupEntry -> E.Value
encodeEntry e =
    E.object
        [ ( "creature_id", E.string e.creatureId )
        , ( "count", E.int e.count )
        , ( "minion_type", encodeMinionType e.minionType )
        ]


encodeInitiativeMode : InitiativeMode -> E.Value
encodeInitiativeMode mode =
    case mode of
        InitiativeEachRolls ->
            E.object [ ( "type", E.string "each_rolls" ) ]

        InitiativeSharedRolled ->
            E.object [ ( "type", E.string "shared_rolled" ) ]

        InitiativeSharedManual value ->
            E.object
                [ ( "type", E.string "shared_manual" )
                , ( "value", E.int value )
                ]


encodeMinionType : MinionType -> E.Value
encodeMinionType minionType =
    E.string (Group.minionTypeKey minionType)



-- ── HTTP ─────────────────────────────────────────────────────────────────────


fetchAll : (Result Http.Error (List Group) -> msg) -> Cmd msg
fetchAll toMsg =
    Http.get
        { url = "/api/compendium/groups"
        , expect = Http.expectJson toMsg (D.list decodeGroup)
        }


create : Draft -> (Result Http.Error Group -> msg) -> Cmd msg
create draft toMsg =
    Http.post
        { url = "/api/compendium/groups"
        , body = Http.jsonBody (encodeDraft draft)
        , expect = Http.expectJson toMsg decodeGroup
        }


update : Group -> (Result Http.Error Group -> msg) -> Cmd msg
update group toMsg =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/compendium/groups/" ++ group.id
        , body = Http.jsonBody (encodeGroup group)
        , expect = Http.expectJson toMsg decodeGroup
        , timeout = Nothing
        , tracker = Nothing
        }


delete : String -> (Result Http.Error () -> msg) -> Cmd msg
delete groupId toMsg =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/compendium/groups/" ++ groupId
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }
