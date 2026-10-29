module Update.Shell exposing
    ( encounterLoaded
    , encounterMenuClose
    , encounterMenuToggle
    , encounterPersisted
    , noOp
    , settingsClose
    , settingsToggle
    , urlChanged
    , urlRequested
    )

{-| Application-shell Msg handlers: URL routing, encounter load +
persist response, and the `NoOp` fallback.

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
import Msg exposing (Msg)
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
            ( model
            , -- The runtime takes the skip link before the browser can
              -- move focus.  Focus moves here instead.
              if url.fragment == Just Effects.mainRegionId then
                Cmd.batch
                    [ Nav.pushUrl key (Url.toString url)
                    , Effects.focusField Effects.mainRegionId
                    ]

              else
                Nav.pushUrl key (Url.toString url)
            )

        Browser.External url ->
            ( model, Nav.load url )


{-| URL changed. Re-derive the route and run the one-shot step a
route needs on entry.
-}
urlChanged : Url -> Model -> ( Model, Cmd Msg )
urlChanged url model =
    let
        route =
            Route.fromUrl url

        withRoute =
            { model | url = url, route = route }
    in
    -- Some routes need a one-shot step on entry.  The Account page
    -- seeds its display-name field from the signed-in user.  Keep
    -- this list flat and route-shaped rather than scattering such
    -- steps across handlers.
    case route of
        Route.Account ->
            Update.Account.open withRoute

        _ ->
            ( withRoute, Cmd.none )


{-| Initial encounter fetch landed. `Just` adopts the persisted
encounter; `Nothing` keeps whatever the empty default we initialized
into. Errors are silent — fresh server / no JSON yet should still
let the user start fresh.
-}
encounterLoaded : Result Http.Error (Maybe Encounter) -> Model -> ( Model, Cmd Msg )
encounterLoaded result model =
    case result of
        Ok (Just encounter) ->
            ( Model.reaimStale { model | encounter = encounter }, Cmd.none )

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


{-| The Encounter nav item; `View.AppBar` has what it is for.
-}
encounterMenuToggle : Model -> ( Model, Cmd Msg )
encounterMenuToggle model =
    ( { model | encounterMenuOpen = not model.encounterMenuOpen }
    , if model.route == Route.Home then
        Cmd.none

      else
        Nav.pushUrl model.key "/"
    )


encounterMenuClose : Model -> ( Model, Cmd Msg )
encounterMenuClose model =
    ( { model | encounterMenuOpen = False }, Cmd.none )
