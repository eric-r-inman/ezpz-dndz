module Update.Tabs exposing (encounterFromOtherTab)

{-| Cross-tab sync handlers — the receive side of the
BroadcastChannel ports.

The app can run in several tabs at once. The JS side bridges
them with BroadcastChannels; the handlers here consume what a
peer tab posted. The encounter's send side stays with the
top-level update wrapper, where the mutation happens.

@docs encounterFromOtherTab

-}

import Encounter.Wire
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg)


{-| `EncounterFromOtherTab` handler — drop the broadcast straight
into `model.encounter`. Decoder failures are silently ignored
(the payload always comes from another tab running the same
build, so a mismatch would mean the wire format had diverged).
-}
encounterFromOtherTab : Decode.Value -> Model -> ( Model, Cmd Msg )
encounterFromOtherTab raw model =
    case Decode.decodeValue Encounter.Wire.decodeEncounter raw of
        Ok encounter ->
            ( Model.reaimStale { model | encounter = encounter }, Cmd.none )

        Err _ ->
            ( model, Cmd.none )
