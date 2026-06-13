module Encounter.Treasure.ProfileWire exposing
    ( decodeProfiles
    , encodeProfiles
    )

{-| JSON wire codec for the user-saved "Tune your rolls" profile
dictionary. Mirrors the encoder / decoder used for
`Encounter.Wire.encodeTreasureSettings` so a saved profile
round-trips identically to a live in-encounter settings record.

The on-disk shape is a flat object keyed by GM-given names:

    { "Dragon hoard":  { ...settings... }
    , "Pocket bounty": { ...settings... }
    }

The server treats the body as opaque JSON.

-}

import Dict exposing (Dict)
import Encounter.Treasure
import Encounter.Wire as Wire
import Json.Decode as D
import Json.Encode as E


encodeProfiles : Dict String Encounter.Treasure.TreasureSettings -> E.Value
encodeProfiles profiles =
    profiles
        |> Dict.toList
        |> List.map (\( name, settings ) -> ( name, Wire.encodeTreasureSettings settings ))
        |> E.object


decodeProfiles : D.Decoder (Dict String Encounter.Treasure.TreasureSettings)
decodeProfiles =
    D.oneOf
        [ D.null Dict.empty
        , D.dict Wire.decodeTreasureSettings
        ]
