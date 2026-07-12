module Update.Tabs exposing
    ( encounterFromOtherTab
    , panelShowFromOtherTab, incomingPanelShow
    )

{-| Cross-tab sync handlers — the receive side of the
BroadcastChannel ports.

The app can run in several tabs at once (main workspace,
QuickList, standalone stat-block pages). The JS side bridges
them with BroadcastChannels; the handlers here consume what a
peer tab posted. The send side stays where the mutation happens:
the top-level update wrapper broadcasts encounter changes, and
`QuickListRowClick` broadcasts panel-show requests.

@docs encounterFromOtherTab
@docs panelShowFromOtherTab, incomingPanelShow

-}

import Browser.Navigation as Nav
import Effects
import Encounter.Wire
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg(..))
import Route exposing (Route(..))
import Update.Compendium.Browser


{-| `EncounterFromOtherTab` handler — drop the broadcast straight
into `model.encounter`. Decoder failures are silently ignored
(the payload always comes from another tab running the same
build, so a mismatch would mean the wire format had diverged).
-}
encounterFromOtherTab : Decode.Value -> Model -> ( Model, Cmd Msg )
encounterFromOtherTab raw model =
    case Decode.decodeValue Encounter.Wire.decodeEncounter raw of
        Ok encounter ->
            ( { model | encounter = encounter }, Cmd.none )

        Err _ ->
            ( model, Cmd.none )


{-| Decode the panel-show payload broadcast by a QuickList tab.
Same-build wire format, so a decode failure is dropped
silently (would only happen if a stale tab from a different
build survived across a deploy).
-}
panelShowFromOtherTab : Decode.Value -> Msg
panelShowFromOtherTab raw =
    let
        decoder =
            Decode.map2 IncomingPanelShow
                (Decode.field "id" Decode.string)
                (Decode.field "name" Decode.string)
    in
    Decode.decodeValue decoder raw
        |> Result.withDefault NoOp


{-| `IncomingPanelShow` handler — fires on the main tab when a
QuickList tab clicked a row. Pin the stat block + scroll the
creature's card into view. If the main tab is currently parked
on some other route (Compendium, Donate, …), also navigate back
to the encounter workspace so the pin + scroll actually land
somewhere the GM sees.
-}
incomingPanelShow : String -> String -> Model -> ( Model, Cmd Msg )
incomingPanelShow creatureId creatureName model =
    let
        ( pinned, pinCmd ) =
            Update.Compendium.Browser.panelShowCreature
                creatureId
                creatureName
                model

        navCmd =
            if pinned.route == Home then
                Cmd.none

            else
                Nav.pushUrl pinned.key "/"
    in
    ( pinned
    , Cmd.batch
        [ pinCmd
        , navCmd
        , Effects.scrollActiveIntoView creatureName
        ]
    )
