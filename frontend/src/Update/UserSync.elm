module Update.UserSync exposing
    ( loreGroupsLoaded, loreGroupsPersisted
    , conditionPresetsLoaded, conditionPresetsPersisted
    , saveChainPresetsLoaded, saveChainPresetsPersisted
    , treasureProfilesLoaded, treasureProfilesPersisted, treasureTableLoaded, treasureTablePersisted
    )

{-| Msg handlers for the per-user server-stored Lore groups,
condition presets, and Save Chain presets.

All three stores follow the same boot+migrate dance:

  - On the authenticated boot path (`Update.Auth.meReceived
    (Ok _)`), `Effects.fetchLoreGroups`,
    `Effects.fetchConditionPresets`, and
    `Effects.fetchSaveChainPresets` fire.
  - When the response lands in [`loreGroupsLoaded`](#loreGroupsLoaded),
    [`conditionPresetsLoaded`](#conditionPresetsLoaded), or
    [`saveChainPresetsLoaded`](#saveChainPresetsLoaded), one
    of three things happens:
    1.  Server returned non-empty → adopt as the live state,
        dropping whatever the boot flag from localStorage had
        loaded. This is how a second device gets the GM's
        existing groups / presets.
    2.  Server returned empty AND the GM has local data from
        their anonymous-mode use → the local data wins (we
        already adopted it at init), and we PUT it up so the
        server records the migration. One-shot: the next boot
        sees the server-side copy and takes path 1.
    3.  Both empty → no-op.

Errors are surfaced as toasts so a flaky network doesn't silently
drop the GM's work. Anonymous sessions never reach these
handlers — the localStorage ports keep handling persistence the
old way.

@docs loreGroupsLoaded, loreGroupsPersisted
@docs conditionPresetsLoaded, conditionPresetsPersisted
@docs saveChainPresetsLoaded, saveChainPresetsPersisted

-}

import Dict
import Effects
import Encounter.RandomEncounter.Lore as Lore
import Encounter.SaveChain
import Encounter.SaveChain.Bundled
import Encounter.SaveChain.Wire
import Encounter.Treasure
import Encounter.Treasure.ProfileWire
import Http
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Condition
import Ui.Condition.Wire
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http


loreGroupsLoaded :
    Result Http.Error (List Lore.Group)
    -> Model
    -> ( Model, Cmd Msg )
loreGroupsLoaded result model =
    case result of
        Ok serverGroups ->
            if not (List.isEmpty serverGroups) then
                ( { model | userLoreGroups = serverGroups }, Cmd.none )

            else if not (List.isEmpty model.userLoreGroups) then
                -- Empty server, populated client → migrate.
                ( model, Effects.putLoreGroups model.userLoreGroups )

            else
                ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't load your Lore groupings: " ++ Util.Http.errorToString err)
                model


loreGroupsPersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
loreGroupsPersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Saving your Lore groupings failed: " ++ Util.Http.errorToString err)
                model


conditionPresetsLoaded :
    Result Http.Error Decode.Value
    -> Model
    -> ( Model, Cmd Msg )
conditionPresetsLoaded result model =
    case result of
        Ok raw ->
            case Decode.decodeValue Ui.Condition.Wire.decodePresets raw of
                Ok serverPresets ->
                    if not (Dict.isEmpty serverPresets) then
                        ( { model | conditionPresets = serverPresets }
                        , Cmd.none
                        )

                    else if not (Dict.isEmpty (userAuthoredOnly model.conditionPresets)) then
                        -- Empty server, populated client →
                        -- migrate.  We send the full local map,
                        -- bundled defaults included, so the
                        -- server's copy survives a re-boot
                        -- without depending on the bundle.
                        ( model
                        , Effects.putConditionPresets model.conditionPresets
                        )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    Update.Toast.push ToastError
                        "Couldn't decode the condition-preset payload from the server."
                        model

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't load your condition presets: "
                    ++ Util.Http.errorToString err
                )
                model


{-| Strip out the bundled SRD presets so the migration test
"do we have anything worth uploading?" only fires on
user-authored entries. Bundled presets carry a non-empty
~category~; user-saved presets are flagged with `category = ""`
per the comment in [`Ui.Condition`](Ui-Condition).
-}
userAuthoredOnly :
    Dict.Dict String Ui.Condition.ConditionPreset
    -> Dict.Dict String Ui.Condition.ConditionPreset
userAuthoredOnly presets =
    Dict.filter (\_ p -> String.isEmpty p.category) presets


conditionPresetsPersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
conditionPresetsPersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Saving your condition presets failed: "
                    ++ Util.Http.errorToString err
                )
                model


{-| Handler for `GET /api/save-chain-presets` — mirror of
`conditionPresetsLoaded`. Save Chain presets are a
`Dict String SaveChain`; the wire is opaque JSON.

Three-way branch matching the sibling stores:

1.  Non-empty server response → adopt as the live state
    (drops whatever localStorage seeded at boot). This is how
    a second device picks up presets authored elsewhere.
2.  Empty server response BUT the anonymous-boot code loaded
    user-authored presets from localStorage → migrate up. We
    send the full local map, bundled defaults included, so
    the server's copy survives a re-boot without depending on
    whichever bundled catalogue happens to ship in a future
    binary.
3.  Both empty → no-op.

-}
saveChainPresetsLoaded :
    Result Http.Error Decode.Value
    -> Model
    -> ( Model, Cmd Msg )
saveChainPresetsLoaded result model =
    case result of
        Ok raw ->
            case Decode.decodeValue Encounter.SaveChain.Wire.decodePresets raw of
                Ok serverPresets ->
                    if not (Dict.isEmpty serverPresets) then
                        ( { model | saveChainPresets = serverPresets }
                        , Cmd.none
                        )

                    else if not (Dict.isEmpty (userAuthoredSaveChainOnly model.saveChainPresets)) then
                        ( model
                        , Effects.putSaveChainPresets model.saveChainPresets
                        )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    Update.Toast.push ToastError
                        "Couldn't decode the Save Chain preset payload from the server."
                        model

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't load your Save Chain presets: "
                    ++ Util.Http.errorToString err
                )
                model


{-| Strip out the bundled Save Chain presets so the migration
test "do we have anything worth uploading?" only fires on
user-authored entries. Bundled entries live under the exact
keys in `Encounter.SaveChain.Bundled.defaults` — anything else
is user-authored (either freshly created or a bundled preset
the GM edited under a new name).
-}
userAuthoredSaveChainOnly :
    Dict.Dict String Encounter.SaveChain.SaveChain
    -> Dict.Dict String Encounter.SaveChain.SaveChain
userAuthoredSaveChainOnly presets =
    let
        bundledKeys =
            Encounter.SaveChain.Bundled.defaults
    in
    Dict.filter (\k _ -> not (Dict.member k bundledKeys)) presets


saveChainPresetsPersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
saveChainPresetsPersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Saving your Save Chain presets failed: "
                    ++ Util.Http.errorToString err
                )
                model


treasureTableLoaded :
    Result Http.Error (Maybe Encounter.Treasure.TreasureTable)
    -> Model
    -> ( Model, Cmd Msg )
treasureTableLoaded result model =
    case result of
        Ok (Just serverTable) ->
            ( { model | userTreasureTable = Just serverTable }, Cmd.none )

        Ok Nothing ->
            case model.userTreasureTable of
                Just localTable ->
                    -- Empty server, populated client (anon-mode
                    -- migration on sign-in).
                    ( model, Effects.putTreasureTable localTable )

                Nothing ->
                    ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't load your treasure table: " ++ Util.Http.errorToString err)
                model


treasureTablePersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
treasureTablePersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Saving your treasure table failed: " ++ Util.Http.errorToString err)
                model


{-| GET /api/treasure-profiles returned. Decodes into the
profiles dict on the model. Server returns `null` when the
user has nothing saved; we treat that as an empty dict.
-}
treasureProfilesLoaded :
    Result Http.Error Decode.Value
    -> Model
    -> ( Model, Cmd Msg )
treasureProfilesLoaded result model =
    case result of
        Ok raw ->
            case Decode.decodeValue Encounter.Treasure.ProfileWire.decodeProfiles raw of
                Ok profiles ->
                    ( { model | userTreasureProfiles = profiles }, Cmd.none )

                Err _ ->
                    Update.Toast.push ToastError
                        "Couldn't decode the treasure-profiles payload from the server."
                        model

        Err err ->
            Update.Toast.push ToastError
                ("Couldn't load your treasure profiles: " ++ Util.Http.errorToString err)
                model


treasureProfilesPersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
treasureProfilesPersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Saving your treasure profiles failed: " ++ Util.Http.errorToString err)
                model
