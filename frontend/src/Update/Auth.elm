module Update.Auth exposing
    ( displayNameChanged
    , emailChanged
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
import Card.Wire as CardWire
import Compendium.GroupWire
import Compendium.Wire
import Effects
import Encounter
import Encounter.Wire
import Http
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Login as LoginUi


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
            ( { model
                | auth = AuthAuthenticated user
                , localEncounterRaw = Nothing
              }
            , Cmd.batch
                [ Encounter.Wire.fetchEncounterCmd EncounterLoaded
                , Compendium.Wire.fetchAll CompendiumLoaded
                , Compendium.GroupWire.fetchAll CompendiumGroupsLoaded
                , CardWire.fetchList CardEditorLayoutsLoaded
                ]
            )

        Err _ ->
            let
                anon =
                    { model
                        | auth = AuthAnonymous
                        , loginUi = LoginUi.empty
                        , encounter = adoptLocalEncounter model.localEncounterRaw model.encounter
                        , localEncounterRaw = Nothing
                        , localCardLayoutRaw = Nothing
                    }
            in
            ( applyLocalCardLayout model.localCardLayoutRaw anon
            , Compendium.Wire.fetchAllPublic CompendiumLoaded
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
                        | cardLayout = snap.layout
                        , queueView = snap.queueView
                        , useCustomCardLayout = snap.useCustomCardLayout
                    }

                Err _ ->
                    model

        Nothing ->
            model


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
