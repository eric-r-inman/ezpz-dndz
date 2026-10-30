module Update.Tabs exposing (compendiumFromOtherTab, encounterFromOtherTab)

{-| Cross-tab sync handlers — the receive side of the
BroadcastChannel ports.

The app can run in several tabs at once. The JS side bridges
them with BroadcastChannels; the handlers here consume what a
peer tab posted. The send side stays with the top-level update
wrapper, where the mutation happens.

@docs compendiumFromOtherTab, encounterFromOtherTab

-}

import Auth
import Compendium
import Compendium.Wire
import Dict
import Encounter.Wire
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumDb(..))


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


{-| `CompendiumFromOtherTab` handler. This tab keeps its bundled
creatures and takes the sender's own creatures and groups. A tab
whose library has not loaded yet will load it fresh. A payload from
another owner is dropped, so one account's creatures never reach a
tab signed in as someone else or signed out.
-}
compendiumFromOtherTab : Decode.Value -> Model -> ( Model, Cmd Msg )
compendiumFromOtherTab raw model =
    case ( Decode.decodeValue Compendium.Wire.decodeTabSync raw, model.compendium.db ) of
        ( Ok ( owner, snapshot ), CompendiumDbLoaded db ) ->
            if Just owner == Auth.owner model.auth then
                ( withSnapshot snapshot db model, Cmd.none )

            else
                ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


withSnapshot : Compendium.Wire.LocalCompendiumSnapshot -> Compendium.Db -> Model -> Model
withSnapshot snapshot db model =
    let
        compendium =
            model.compendium
    in
    { model
        | compendium =
            { compendium
                | db =
                    CompendiumDbLoaded
                        (Compendium.fromList
                            ((Compendium.toList db |> List.filter .isBundled)
                                ++ snapshot.creatures
                            )
                        )
                , groups =
                    snapshot.groups
                        |> List.map (\group -> ( group.id, group ))
                        |> Dict.fromList
            }
        , nextLocalCreatureId = max model.nextLocalCreatureId snapshot.nextLocalId
    }
