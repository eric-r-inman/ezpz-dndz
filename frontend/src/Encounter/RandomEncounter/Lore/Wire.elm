module Encounter.RandomEncounter.Lore.Wire exposing (encodeGroups, decodeGroups)

{-| JSON wire format for user-authored lore groups, persisted
under `localStorage.userLoreGroups` and re-loaded on every
boot. The bundled groups in
[`Encounter.RandomEncounter.Lore`](Encounter-RandomEncounter-Lore)
are stable Elm values and don't round-trip through this
encoder; only the player's additions do.

  - Members reference creatures by **name** so a saved lore
    group survives a compendium-id reshuffle. The generator
    resolves names against the loaded compendium at roll time.
  - Unknown role / source strings on the decode side fall back
    to `Member` / `UserCurated` rather than failing the whole
    blob; user data takes precedence over strict validation.
  - `source` always serialises (even though user-saved groups
    are always `UserCurated`) so a future bundle-into-store
    flow can round-trip bundled groups through the same dict
    without losing provenance.

@docs encodeGroups, decodeGroups

-}

import Encounter.RandomEncounter.Lore as Lore exposing (Group, Role(..), Slot, Source(..))
import Json.Decode as D
import Json.Encode as E


encodeGroups : List Group -> E.Value
encodeGroups groups =
    E.list encodeGroup groups


encodeGroup : Group -> E.Value
encodeGroup g =
    E.object
        [ ( "id", E.string g.id )
        , ( "name", E.string g.name )
        , ( "weight", E.int g.weight )
        , ( "source", E.string (encodeSource g.source) )
        , ( "members", E.list encodeSlot g.members )
        , ( "description", E.string g.description )
        ]


encodeSlot : Slot -> E.Value
encodeSlot s =
    E.object
        [ ( "name", E.string s.name )
        , ( "role", E.string (encodeRole s.role) )
        , ( "count_min", E.int s.countMin )
        , ( "count_max", E.int s.countMax )
        ]


encodeRole : Role -> String
encodeRole r =
    case r of
        Leader ->
            "leader"

        Member ->
            "member"

        Minion ->
            "minion"

        Pet ->
            "pet"


encodeSource : Source -> String
encodeSource s =
    case s of
        Bundled ->
            "bundled"

        UserCurated ->
            "user"


decodeGroups : D.Decoder (List Group)
decodeGroups =
    D.list decodeGroup


decodeGroup : D.Decoder Group
decodeGroup =
    D.map6
        (\id name weight source members description ->
            { id = id
            , name = name
            , weight = weight
            , source = source
            , members = members
            , description = description
            }
        )
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.oneOf [ D.field "weight" D.int, D.succeed 3 ])
        (D.oneOf
            [ D.field "source" D.string |> D.map decodeSource
            , D.succeed UserCurated
            ]
        )
        (D.field "members" (D.list decodeSlot))
        (D.oneOf [ D.field "description" D.string, D.succeed "" ])


decodeSlot : D.Decoder Slot
decodeSlot =
    D.map4
        (\name role lo hi ->
            { name = name, role = role, countMin = lo, countMax = hi }
        )
        (D.field "name" D.string)
        (D.oneOf
            [ D.field "role" D.string |> D.map decodeRole
            , D.succeed Member
            ]
        )
        (D.oneOf [ D.field "count_min" D.int, D.succeed 1 ])
        (D.oneOf [ D.field "count_max" D.int, D.succeed 1 ])


decodeRole : String -> Role
decodeRole s =
    case s of
        "leader" ->
            Leader

        "minion" ->
            Minion

        "pet" ->
            Pet

        _ ->
            Member


decodeSource : String -> Source
decodeSource s =
    case s of
        "bundled" ->
            Bundled

        _ ->
            UserCurated
