module Update.Auth exposing
    ( displayNameChanged
    , emailChanged
    , localCardLayoutMigrated
    , localCompendiumMigrated
    , localEncounterMigrated
    , logout
    , logoutDone
    , meReceived
    , modeChanged
    , passwordChanged
    , response
    , submit
    )

{-| Per-Msg branches for the authentication flow.

Each function takes the inputs the matching `Msg` carries and the
current `Model`, and returns `( Model, Cmd Msg )`. Main.elm just
dispatches the Msg to the right branch — no inline auth logic in
the shell.

The login + register paths share `submit` and `response` because
the wire shape is identical (both POST a body and get back a
`User`); the form mode decides which Cmd to emit.

-}

import Auth exposing (AuthState(..), LoginMode(..))
import Browser.Navigation as Nav
import Card.Layout
import Card.Wire as CardWire
import Compendium
import Compendium.GroupWire
import Compendium.Wire
import Dice
import Dict
import Effects
import Encounter
import Encounter.Wire
import Http
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ports
import Ui.Compendium as CompendiumUi
import Ui.Login as LoginUi
import Ui.Toast exposing (ToastKind(..))
import Update.Toast


{-| Boot probe response. Two paths:

  - Ok user → switch to authenticated and kick off the
    authenticated data fetches (encounter, compendium creatures,
    compendium groups, card layouts). The init batch deliberately
    held these back because we didn't yet know whether to hit the
    server endpoints or the public bundled fallbacks.
  - Err 401 / other → switch to anonymous, then adopt the local
    encounter snapshot held in `localEncounterRaw` (passed in via
    flags from `index.html`'s `localStorage` read), and fetch the
    public bundled compendium (`/bundled-creatures.json`) so the
    GM can still browse creatures without an account. Groups +
    card layouts stay empty until anonymous-CRUD support lands
    in a later phase.

In both branches we clear `localEncounterRaw` afterwards — it's a
one-shot bootstrap stash, not ongoing state.

-}
meReceived : Result Http.Error Auth.User -> Model -> ( Model, Cmd Msg )
meReceived result model =
    case result of
        Ok user ->
            let
                -- Did the anonymous session have a live encounter
                -- they were actively building?  Empty default
                -- doesn't count — that's just a freshly-booted
                -- tab with nothing typed yet, in which case the
                -- server's last-active encounter is the right
                -- thing to fetch.
                localLiveEncounter =
                    decodeLocalEncounterIfPopulated model.localEncounterRaw

                ( liveEncounter, fetchOrSeedActiveCmd ) =
                    case localLiveEncounter of
                        Just enc ->
                            -- Keep the GM's in-progress encounter as
                            -- the live one and immediately push it to
                            -- /api/encounter so the server's "current
                            -- active" matches what they see.  Skips
                            -- the GET that would otherwise overwrite
                            -- their work with the previous device's
                            -- last save.
                            ( enc
                            , Encounter.Wire.persistEncounterCmd
                                EncounterPersisted
                                enc
                            )

                        Nothing ->
                            ( model.encounter
                            , Encounter.Wire.fetchEncounterCmd EncounterLoaded
                            )

                encounterMigrationCmd =
                    migrateLocalEncounterCmd
                        model.localEncounterRaw
                        model.migrationDateLabel

                cardLayoutMigrationCmd =
                    migrateLocalCardLayoutCmd
                        model.localCardLayoutRaw
                        model.migrationDateLabel

                compendiumMigrationCmd =
                    migrateLocalCompendiumCmd model.localCompendiumRaw
            in
            ( { model
                | auth = AuthAuthenticated user
                , encounter = liveEncounter
                , localEncounterRaw = Nothing
                , localCardLayoutRaw = Nothing
                , localDiceHistoryRaw = Nothing
                , localCompendiumRaw = Nothing
              }
            , Cmd.batch
                [ fetchOrSeedActiveCmd
                , Compendium.Wire.fetchAll CompendiumLoaded
                , Compendium.GroupWire.fetchAll CompendiumGroupsLoaded
                , CardWire.fetchList CardEditorLayoutsLoaded
                , Effects.fetchDiceHistory
                , encounterMigrationCmd
                , cardLayoutMigrationCmd
                , compendiumMigrationCmd
                ]
            )

        Err _ ->
            let
                withEncounter =
                    { model
                        | auth = AuthAnonymous
                        , loginUi = LoginUi.empty
                        , encounter = adoptLocalEncounter model.localEncounterRaw model.encounter
                        , localEncounterRaw = Nothing
                        , localCardLayoutRaw = Nothing
                        , localDiceHistoryRaw = Nothing
                        , localCompendiumRaw = Nothing
                        , savedCardLayouts =
                            model.localCardLayoutSaves
                                |> Dict.toList
                                |> List.map CardWire.localSaveToMeta
                                |> List.sortBy (\m -> -m.updatedAt)
                    }

                withDice =
                    applyLocalDiceHistory model.localDiceHistoryRaw withEncounter

                ( withCompendium, compendiumBootCmd ) =
                    applyLocalCompendium model.localCompendiumRaw withDice
            in
            ( applyLocalCardLayout model.localCardLayoutRaw withCompendium
            , compendiumBootCmd
            )


{-| Decode the local encounter from flags only when it has at
least one creature. Used by the sign-in flow to detect "the
user was actively building an encounter when they signed in"
— in that case we keep their work as the live encounter
instead of fetching the server's last-saved active one and
replacing it.

`Nothing` means either there was no flag, the JSON didn't
parse, or the snapshot was the empty default — all three
cases fall through to the existing server-fetch behaviour.

-}
decodeLocalEncounterIfPopulated : Maybe Decode.Value -> Maybe Encounter.Encounter
decodeLocalEncounterIfPopulated raw =
    raw
        |> Maybe.andThen
            (\value ->
                Decode.decodeValue Encounter.Wire.decodeEncounter value
                    |> Result.toMaybe
            )
        |> Maybe.andThen
            (\enc ->
                if List.isEmpty enc.creatures then
                    Nothing

                else
                    Just enc
            )


{-| Try to decode the raw local-encounter JSON from flags; if it
parses, use it, otherwise keep whatever we have (the empty
default). Anonymous users with no prior session get a clean
slate — same as a fresh server install.
-}
adoptLocalEncounter : Maybe Decode.Value -> Encounter.Encounter -> Encounter.Encounter
adoptLocalEncounter raw fallback =
    case raw of
        Just value ->
            case Decode.decodeValue Encounter.Wire.decodeEncounter value of
                Ok encounter ->
                    encounter

                Err _ ->
                    fallback

        Nothing ->
            fallback


{-| Same pattern as `adoptLocalEncounter` for the card-layout
snapshot. Replaces `cardLayout`, `queueView`, and
`useCustomCardLayout` on the model when the flag JSON parses,
leaving them untouched otherwise. Anonymous users with no
prior session keep the bundled default.
-}
applyLocalCardLayout : Maybe Decode.Value -> Model -> Model
applyLocalCardLayout raw model =
    case raw of
        Just value ->
            case Decode.decodeValue CardWire.decodeLocalLayoutSnapshot value of
                Ok snap ->
                    { model
                        | cardLayout =
                            -- One-shot migration: anonymous users
                            -- who never customised their card
                            -- layout get upgraded from the legacy
                            -- 4-row default to the current
                            -- everything-included default.  Custom
                            -- layouts pass through untouched.
                            Card.Layout.migrateLegacyDefault snap.layout
                        , queueView = snap.queueView
                        , useCustomCardLayout = snap.useCustomCardLayout
                    }

                Err _ ->
                    model

        Nothing ->
            model


{-| Adopt the locally-stashed dice history into `model.dice.history`.
Same shape as `applyLocalCardLayout` — decode failures fall
through silently and leave the existing (empty) history.
-}
applyLocalDiceHistory : Maybe Decode.Value -> Model -> Model
applyLocalDiceHistory raw model =
    case raw of
        Just value ->
            case Decode.decodeValue (Decode.list Dice.decodeRoll) value of
                Ok entries ->
                    let
                        dice =
                            model.dice
                    in
                    { model
                        | dice =
                            { dice
                                | history =
                                    { entries = entries
                                    , max = Dice.maxHistoryEntries
                                    }
                            }
                    }

                Err _ ->
                    model

        Nothing ->
            model


{-| Apply the local compendium snapshot to the anonymous boot
state. Returns `(model, Cmd)`:

  - Snapshot present + decodes + recorded `bundledVersion` is
    current → install the creatures into `model.compendium.db`,
    restore the next-id counter, and the Cmd is `Cmd.none` (the
    local snapshot is the truth).
  - Snapshot present + decodes + recorded `bundledVersion` is
    OLDER than `Compendium.Wire.currentBundledVersion` → adopt
    the snapshot as initial state, set `pendingBundleMerge = True`,
    and fire `fetchAllPublic`. When the fetch lands, the
    `CompendiumLoaded` handler replaces bundled-id creatures
    with the fresh data while preserving user-created creatures
    whose ids aren't in the bundle. This is what unsticks
    anonymous users who built up a snapshot before a data fix
    landed in `bundled-creatures.json`.
  - Snapshot absent or undecodable → leave the compendium in its
    initial state and fire `fetchAllPublic` so the GM sees the
    bundled defaults.

-}
applyLocalCompendium : Maybe Decode.Value -> Model -> ( Model, Cmd Msg )
applyLocalCompendium raw model =
    let
        fallback =
            ( model, Compendium.Wire.fetchAllPublic CompendiumLoaded )
    in
    case raw of
        Just value ->
            case Decode.decodeValue Compendium.Wire.decodeLocalCompendiumSnapshot value of
                Ok snap ->
                    let
                        compendium =
                            model.compendium

                        -- Post-split snapshots store only user-
                        -- created creatures, so every entry is
                        -- definitionally NOT bundled.  Stamping
                        -- here protects us if an older snapshot
                        -- (written before the split) carried mixed
                        -- data: any creature whose id collides
                        -- with the fetched bundle gets replaced
                        -- by the canonical bundle entry during the
                        -- pending-bundle-merge step.
                        userOnlyCreatures =
                            snap.creatures
                                |> List.map (\c -> { c | isBundled = False })

                        adopted =
                            { model
                                | compendium =
                                    { compendium
                                        | db =
                                            CompendiumUi.CompendiumDbLoaded
                                                (Compendium.fromList userOnlyCreatures)
                                    }
                                , nextLocalCreatureId = snap.nextLocalId
                            }
                    in
                    -- Always fetch the bundle and merge: the
                    -- snapshot no longer carries bundled creatures,
                    -- and the bundled file may have been updated
                    -- (data fix, new monster) since the user last
                    -- visited.  `pendingBundleMerge = True` makes
                    -- the CompendiumLoaded handler union the fetch
                    -- with the user-created creatures we just
                    -- adopted instead of replacing the whole DB.
                    ( { adopted | pendingBundleMerge = True }
                    , Compendium.Wire.fetchAllPublic CompendiumLoaded
                    )

                Err _ ->
                    fallback

        Nothing ->
            fallback


{-| Build a Cmd that PUTs the locally-stashed encounter into a
named server save slot if and only if the local snapshot:

  - decodes cleanly, and
  - contains at least one creature (i.e. isn't the empty default
    a fresh anonymous session starts with).

The save name is `Local — <date label>` so it's easy to spot in
the Load modal alongside the user's own saves. We pass
`overwrite = True` so a second migration on the same day quietly
replaces the earlier one instead of returning a 409 — better
than the user thinking the migration silently failed.

On success the `LocalEncounterMigrated` handler clears
`localStorage.encounter` so the next reload doesn't re-migrate
the same data.

-}
migrateLocalEncounterCmd : Maybe Decode.Value -> String -> Cmd Msg
migrateLocalEncounterCmd raw dateLabel =
    case raw of
        Just value ->
            case Decode.decodeValue Encounter.Wire.decodeEncounter value of
                Ok encounter ->
                    if List.isEmpty encounter.creatures then
                        Cmd.none

                    else
                        let
                            name =
                                "Local — " ++ dateLabel
                        in
                        Encounter.Wire.putSaveCmd
                            (LocalEncounterMigrated name)
                            { name = name, overwrite = True }
                            encounter

                Err _ ->
                    Cmd.none

        Nothing ->
            Cmd.none


{-| Replace the user's server compendium with the locally-stored
list when the anonymous session had any changes. Uses the bare-
array `POST /api/compendium/import` body so the server keeps the
caller's groups intact — groups migration is handled separately
in Round 7's flow.

For brand-new accounts (just signed up after an anonymous trial)
this populates the user's compendium with whatever they were
working with anonymously. For pre-existing accounts who happened
to use anonymous mode on this device first, this DOES replace
their server compendium with the local one — that's the
documented behavior of the import endpoint; users who want both
can Export their server data first.

-}
migrateLocalCompendiumCmd : Maybe Decode.Value -> Cmd Msg
migrateLocalCompendiumCmd raw =
    case raw of
        Just value ->
            case Decode.decodeValue Compendium.Wire.decodeLocalCompendiumSnapshot value of
                Ok snap ->
                    Compendium.Wire.importCmd
                        (LocalCompendiumMigrated (List.length snap.creatures))
                        snap.creatures
                        snap.groups

                Err _ ->
                    Cmd.none

        Nothing ->
            Cmd.none


{-| Card-layout analogue of `migrateLocalEncounterCmd`.

Only fires when the anonymous user had `useCustomCardLayout = True`
— that's the signal they actively used a non-default layout. When
the bundled default has been showing the whole time we skip the
migration to avoid creating a useless "Local — <date>" entry in
the user's saved-layouts list.

-}
migrateLocalCardLayoutCmd : Maybe Decode.Value -> String -> Cmd Msg
migrateLocalCardLayoutCmd raw dateLabel =
    case raw of
        Just value ->
            case Decode.decodeValue CardWire.decodeLocalLayoutSnapshot value of
                Ok snap ->
                    if snap.useCustomCardLayout then
                        let
                            name =
                                "Local — " ++ dateLabel
                        in
                        CardWire.save
                            { name = name
                            , overwrite = True
                            , layout = snap.layout
                            , queueView = snap.queueView
                            }
                            (LocalCardLayoutMigrated name)

                    else
                        Cmd.none

                Err _ ->
                    Cmd.none

        Nothing ->
            Cmd.none


emailChanged : String -> Model -> ( Model, Cmd Msg )
emailChanged value model =
    let
        ui =
            model.loginUi
    in
    ( { model | loginUi = { ui | email = value } }, Cmd.none )


passwordChanged : String -> Model -> ( Model, Cmd Msg )
passwordChanged value model =
    let
        ui =
            model.loginUi
    in
    ( { model | loginUi = { ui | password = value } }, Cmd.none )


displayNameChanged : String -> Model -> ( Model, Cmd Msg )
displayNameChanged value model =
    let
        ui =
            model.loginUi
    in
    ( { model | loginUi = { ui | displayName = value } }, Cmd.none )


modeChanged : LoginMode -> Model -> ( Model, Cmd Msg )
modeChanged mode model =
    ( { model | loginUi = LoginUi.fromMode mode model.loginUi }
    , Cmd.none
    )


submit : Model -> ( Model, Cmd Msg )
submit model =
    let
        ui =
            model.loginUi
    in
    ( { model | loginUi = LoginUi.withSubmitting True ui }
    , case ui.mode of
        Login ->
            Effects.submitLogin
                { email = ui.email
                , password = ui.password
                }

        Register ->
            Effects.submitRegister
                { email = ui.email
                , password = ui.password
                , displayName = ui.displayName
                }
    )


{-| Reused for both register and login responses. Success →
navigate to `/` (hard load) so the rest of the app re-runs `init`
with the cookie attached and all data-load Cmds fire
authenticated. Going to `/` instead of reloading the current URL
matters since the user submitted from `/login`, which we don't
want them to land back on after the auth probe flips them to
authenticated.
-}
response : Result Http.Error Auth.User -> Model -> ( Model, Cmd Msg )
response result model =
    case result of
        Ok _ ->
            ( model, Nav.load "/" )

        Err err ->
            ( { model
                | loginUi =
                    LoginUi.fromError (humanize err model.loginUi.mode) model.loginUi
              }
            , Cmd.none
            )


{-| Response handler for the login-time migration `PUT` that
copies a pre-sign-in encounter into a named server save. On
success we fire the `clearLocalEncounter` port so the browser's
`localStorage.encounter` is wiped (preventing a re-migration on
the next boot) and surface a success toast with the slot name so
the GM knows where to find it. Failures get a toast too — the
authenticated server encounter is still loaded normally, the
user just won't have the local copy archived.
-}
localEncounterMigrated : String -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
localEncounterMigrated name result model =
    case result of
        Ok () ->
            let
                ( withToast, toastCmd ) =
                    Update.Toast.push
                        ToastSuccess
                        ("Saved your pre-sign-in encounter as “" ++ name ++ "”.")
                        model
            in
            ( withToast
            , Cmd.batch [ toastCmd, Ports.clearLocalEncounter () ]
            )

        Err _ ->
            Update.Toast.push
                ToastError
                "Couldn't archive your pre-sign-in encounter on the server. It's still in this browser."
                model


{-| Card-layout analogue of `localEncounterMigrated`. Success →
clear the localStorage card-layout snapshot + toast with the
slot name + refresh the saved-layouts list so the new entry
shows up in the Card Editor's "Saved layouts" panel without a
reload. Failure → toast; the local snapshot stays.
-}
localCardLayoutMigrated : String -> Result Http.Error CardWire.SavedLayout -> Model -> ( Model, Cmd Msg )
localCardLayoutMigrated name result model =
    case result of
        Ok _ ->
            let
                ( withToast, toastCmd ) =
                    Update.Toast.push
                        ToastSuccess
                        ("Saved your pre-sign-in card layout as “" ++ name ++ "”.")
                        model
            in
            ( withToast
            , Cmd.batch
                [ toastCmd
                , Ports.clearLocalCardLayout ()
                , CardWire.fetchList CardEditorLayoutsLoaded
                ]
            )

        Err _ ->
            Update.Toast.push
                ToastError
                "Couldn't archive your pre-sign-in card layout on the server. It's still in this browser."
                model


{-| Compendium analogue of the migration handlers above. On
success → clear the localStorage compendium snapshot, toast with
the imported count, and re-fetch the server's list to re-sync
the in-memory model. On failure → toast; local stays.
-}
localCompendiumMigrated : Int -> Result Http.Error () -> Model -> ( Model, Cmd Msg )
localCompendiumMigrated count result model =
    case result of
        Ok () ->
            let
                ( withToast, toastCmd ) =
                    Update.Toast.push
                        ToastSuccess
                        ("Imported "
                            ++ String.fromInt count
                            ++ " creatures from your pre-sign-in session."
                        )
                        model
            in
            ( withToast
            , Cmd.batch
                [ toastCmd
                , Ports.clearLocalCompendium ()
                , Compendium.Wire.fetchAll CompendiumLoaded
                ]
            )

        Err _ ->
            Update.Toast.push
                ToastError
                "Couldn't import your pre-sign-in compendium changes. They're still in this browser."
                model


logout : Model -> ( Model, Cmd Msg )
logout model =
    ( model, Effects.submitLogout )


logoutDone : Result Http.Error () -> Model -> ( Model, Cmd Msg )
logoutDone _ model =
    -- Navigate to `/` regardless of the response status: the user
    -- pressed logout, the cookie is now stale or about to be, and a
    -- fresh boot at the root URL gives us the consistent post-logout
    -- state. Going to `/` (instead of just reloading the current URL)
    -- means a sign-out from `/me` doesn't leave the URL bar pointing
    -- at the now-inaccessible account page.
    --
    -- `localStorage.encounter` and `localStorage.cardLayout` are
    -- deliberately NOT cleared here: a user who had anonymous-mode
    -- customizations before signing in should get them back on
    -- logout instead of starting from scratch.  (The encounter
    -- localStorage was cleared at sign-in IF a successful migration
    -- archived it to the server, so this only matters when the
    -- migration didn't fire / hadn't happened yet.)
    ( { model | auth = AuthAnonymous, loginUi = LoginUi.empty }
    , Nav.load "/"
    )


{-| Translate an `Http.Error` from a login / register submission
into a one-line message the form can show. 401 / 409 / 400 each
get a tailored line; everything else is a generic fallback.
-}
humanize : Http.Error -> LoginMode -> String
humanize err mode =
    case err of
        Http.BadStatus 401 ->
            "Invalid email or password."

        Http.BadStatus 409 ->
            "That email is already registered."

        Http.BadStatus 400 ->
            case mode of
                Register ->
                    "Check your email shape, password length (≥8), and display name."

                Login ->
                    "Bad request."

        Http.NetworkError ->
            "Couldn't reach the server.  Try again."

        Http.Timeout ->
            "Request timed out.  Try again."

        _ ->
            "Something went wrong.  Try again."
