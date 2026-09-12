module Update.Tabs exposing
    ( encounterFromOtherTab
    , panelShowFromOtherTab, incomingPanelShow, broadcastShow
    )

{-| Cross-tab sync handlers — the receive side of the
BroadcastChannel ports.

The app can run in several tabs at once (main workspace,
QuickList, standalone stat-block pages). The JS side bridges
them with BroadcastChannels; the handlers here consume what a
peer tab posted. The encounter's send side stays with the
top-level update wrapper, where the mutation happens; the
QuickList's show request mutates nothing, so both its sides live
here.

@docs encounterFromOtherTab
@docs panelShowFromOtherTab, incomingPanelShow, broadcastShow

-}

import Browser.Navigation as Nav
import Encounter.Wire
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ports
import Route exposing (Route(..))
import Update.StatBlock


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


{-| Decode the show request broadcast by a QuickList tab.
Same-build wire format, so a decode failure is dropped
silently (would only happen if a stale tab from a different
build survived across a deploy).
-}
panelShowFromOtherTab : Decode.Value -> Msg
panelShowFromOtherTab raw =
    Decode.decodeValue (Decode.map IncomingPanelShow (Decode.field "name" Decode.string)) raw
        |> Result.withDefault NoOp


{-| `IncomingPanelShow` handler — fires on the main tab when a
QuickList tab clicked a row. Unfold the stat block under the
creature's card and scroll the card into view. If the main tab
is currently parked on some other route (Compendium, Donate, …),
also navigate back to the encounter workspace so the block lands
somewhere the GM sees.
-}
incomingPanelShow : String -> Model -> ( Model, Cmd Msg )
incomingPanelShow creatureName model =
    let
        ( shown, showCmd ) =
            Update.StatBlock.show creatureName model

        navCmd =
            if shown.route == Home then
                Cmd.none

            else
                Nav.pushUrl shown.key "/"
    in
    ( shown, Cmd.batch [ showCmd, navCmd ] )


{-| `QuickListRowClick` handler — fires in the QuickList tab.
Broadcast the name so the main tab unfolds the stat block under
its card and scrolls there; the JS side of the port also tries
`window.opener.focus()` so the main tab comes to front. This tab
itself has nothing to update — the GM is done with it.
-}
broadcastShow : String -> Model -> ( Model, Cmd Msg )
broadcastShow creatureName model =
    ( model
    , Ports.broadcastPanelShow (Encode.object [ ( "name", Encode.string creatureName ) ])
    )
