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
import Effects
import Http
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Login as LoginUi


{-| Boot probe response. On 200 → switch to authenticated and
let the rest of the init Cmds (cmdForRoute, fetchDiceHistory, …)
load data with the cookie attached. On 401 → switch to anonymous
and render the login screen.
-}
meReceived : Result Http.Error Auth.User -> Model -> ( Model, Cmd Msg )
meReceived result model =
    case result of
        Ok user ->
            ( { model | auth = AuthAuthenticated user }, Cmd.none )

        Err _ ->
            ( { model | auth = AuthAnonymous, loginUi = LoginUi.empty }
            , Cmd.none
            )


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
hard-reload the page so the rest of the app re-runs `init` with
the cookie attached and all data-load Cmds fire authenticated.
The reload is the cheapest correct path; a "rerun init" message
would also work but would mean refactoring every existing init
Cmd to be re-entrant.
-}
response : Result Http.Error Auth.User -> Model -> ( Model, Cmd Msg )
response result model =
    case result of
        Ok _ ->
            ( model, Nav.reload )

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
    -- Reload regardless of the response status: the user pressed
    -- logout, the cookie is now stale or about to be, and a fresh
    -- boot is what gives us the consistent post-logout state.
    ( { model | auth = AuthAnonymous, loginUi = LoginUi.empty }
    , Nav.reload
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
