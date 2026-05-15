module Update.Shell exposing
    ( controlMenuClose
    , controlMenuToggle
    , encounterLoaded
    , encounterPersisted
    , gotMe
    , noOp
    , settingsClose
    , settingsToggle
    , urlChanged
    , urlRequested
    )

{-| Application-shell Msg handlers: URL routing, identity (`/me`),
encounter load + persist response, and the `NoOp` fallback.

These branches sit at the boundary between the Elm runtime and the
domain modules — they receive Cmds the runtime fired off (HTTP
responses, navigation events) and either fold them back into model
state or re-dispatch.

-}

import Browser
import Browser.Navigation as Nav
import Effects
import Encounter exposing (Encounter)
import Http
import Model exposing (Model)
import Msg exposing (MeInfo, MeStatus(..), Msg)
import Route
import Ui.Toast exposing (ToastKind(..))
import Update.Account
import Update.Toast
import Url exposing (Url)
import Util.Http


{-| Internal navigation goes through `pushUrl` (the runtime then
fires `UrlChanged`); external navigation uses `Nav.load` which
unloads the SPA.
-}
urlRequested : Nav.Key -> Browser.UrlRequest -> Model -> ( Model, Cmd Msg )
urlRequested key req model =
    case req of
        Browser.Internal url ->
            ( model, Nav.pushUrl key (Url.toString url) )

        Browser.External url ->
            ( model, Nav.load url )


{-| URL changed — re-derive the route, reset the identity badge to
loading (the new page may need to refetch), and ask `Effects` what
Cmd to fire for the route.
-}
urlChanged : Url -> Model -> ( Model, Cmd Msg )
urlChanged url model =
    let
        route =
            Route.fromUrl url

        withRoute =
            { model | url = url, route = route, me = Loading }

        -- Some routes need a one-shot side-effect on entry — the
        -- Account page seeds its display-name input from the
        -- authenticated user, for instance.  Keep this list flat
        -- and route-shaped rather than scattering Cmd-emitting
        -- effects across handlers.
        ( finalModel, sideCmd ) =
            case route of
                Route.Me ->
                    Update.Account.open withRoute

                _ ->
                    ( withRoute, Cmd.none )
    in
    ( finalModel
    , Cmd.batch [ Effects.cmdForRoute route, sideCmd ]
    )


{-| `/me` response landed. Success populates the badge; failure
flips to `Failed` so the view can show "Sign in" or similar.
-}
gotMe : Result Http.Error MeInfo -> Model -> ( Model, Cmd Msg )
gotMe result model =
    case result of
        Ok info ->
            ( { model | me = Loaded info }, Cmd.none )

        Err _ ->
            ( { model | me = Failed }, Cmd.none )


{-| Initial encounter fetch landed. `Just` adopts the persisted
encounter; `Nothing` keeps whatever the empty default we initialized
into. Errors are silent — fresh server / no JSON yet should still
let the user start fresh.
-}
encounterLoaded : Result Http.Error (Maybe Encounter) -> Model -> ( Model, Cmd Msg )
encounterLoaded result model =
    case result of
        Ok (Just encounter) ->
            ( { model | encounter = encounter }, Cmd.none )

        Ok Nothing ->
            ( model, Cmd.none )

        Err _ ->
            ( model, Cmd.none )


{-| Persist response. Success is silent (the user's edit just
flowed through); failure raises a toast so they know the change
won't survive a reload.
-}
encounterPersisted : Result Http.Error () -> Model -> ( Model, Cmd Msg )
encounterPersisted result model =
    case result of
        Ok () ->
            ( model, Cmd.none )

        Err err ->
            Update.Toast.push ToastError
                ("Save failed: " ++ Util.Http.errorToString err)
                model


noOp : Model -> ( Model, Cmd Msg )
noOp model =
    ( model, Cmd.none )


{-| Flip the AppBar settings popover open / closed. Pure UI
state — no persistence — so it lives here in the application
shell rather than in `Update.Preferences`.
-}
settingsToggle : Model -> ( Model, Cmd Msg )
settingsToggle model =
    ( { model | settingsOpen = not model.settingsOpen }, Cmd.none )


{-| Close the AppBar settings popover. Fired by the global
Esc-key + click-outside subscriptions in `Main.subscriptions`
when the popover is open.
-}
settingsClose : Model -> ( Model, Cmd Msg )
settingsClose model =
    ( { model | settingsOpen = False }, Cmd.none )


{-| Open or toggle one of the Encounter-Controls split-button
dropdowns (Save / Load). Clicking the same button again
closes; clicking the other swaps to it.
-}
controlMenuToggle : Msg.ControlMenu -> Model -> ( Model, Cmd Msg )
controlMenuToggle which model =
    let
        next =
            if model.controlMenu == Just which then
                Nothing

            else
                Just which
    in
    ( { model | controlMenu = next }, Cmd.none )


{-| Close whichever control-menu dropdown is open. Fired by
Esc + click-outside subs in `Main.subscriptions`, and by any
dropdown-item handler so the menu doesn't linger after the user
commits.
-}
controlMenuClose : Model -> ( Model, Cmd Msg )
controlMenuClose model =
    ( { model | controlMenu = Nothing }, Cmd.none )
