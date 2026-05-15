module Update.Account exposing
    ( open
    , displayNameChanged
    , currentPasswordChanged, newPasswordChanged, confirmPasswordChanged
    , submitProfile, profileSaved
    , submitPassword, passwordChanged
    )

{-| Update branches for the `/me` Account page.

Profile and Password are two independent forms on the same
page; each has its own `submit*` dispatcher and response
handler. The forms persist server-side through
`PUT /api/auth/me` and `POST /api/auth/password` (see
[`Effects.updateProfile`](Effects#updateProfile) and
[`Effects.changePassword`](Effects#changePassword)).

@docs open
@docs displayNameChanged
@docs currentPasswordChanged, newPasswordChanged, confirmPasswordChanged
@docs submitProfile, profileSaved
@docs submitPassword, passwordChanged

-}

import Auth exposing (AuthState(..), User)
import Effects
import Http
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Account as Account
import Util.Http



-- ── OPEN ─────────────────────────────────────────────────────────────────────


{-| Sync the editable display-name field to the user's current
display name when the page first renders (or after a `Sign out
→ Sign in` cycle). Cheap and idempotent; called from
`Update.Shell.urlChanged` whenever the route resolves to `Me`.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    case model.auth of
        AuthAuthenticated user ->
            ( withAccount
                (\ui ->
                    { ui
                        | profile =
                            { displayName = user.displayName
                            , busy = False
                            , error = Nothing
                            , success = Nothing
                            }
                        , password =
                            { current = ""
                            , new = ""
                            , confirm = ""
                            , busy = False
                            , error = Nothing
                            , success = Nothing
                            }
                    }
                )
                model
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )



-- ── FIELD HANDLERS ───────────────────────────────────────────────────────────


displayNameChanged : String -> Model -> ( Model, Cmd Msg )
displayNameChanged raw model =
    let
        clamped =
            String.left Account.maxDisplayNameLength raw
    in
    ( withAccount
        (\ui ->
            let
                p =
                    ui.profile
            in
            { ui
                | profile =
                    { p | displayName = clamped, error = Nothing, success = Nothing }
            }
        )
        model
    , Cmd.none
    )


currentPasswordChanged : String -> Model -> ( Model, Cmd Msg )
currentPasswordChanged raw model =
    ( withAccount
        (\ui ->
            let
                p =
                    ui.password
            in
            { ui
                | password =
                    { p | current = raw, error = Nothing, success = Nothing }
            }
        )
        model
    , Cmd.none
    )


newPasswordChanged : String -> Model -> ( Model, Cmd Msg )
newPasswordChanged raw model =
    ( withAccount
        (\ui ->
            let
                p =
                    ui.password
            in
            { ui
                | password = { p | new = raw, error = Nothing, success = Nothing }
            }
        )
        model
    , Cmd.none
    )


confirmPasswordChanged : String -> Model -> ( Model, Cmd Msg )
confirmPasswordChanged raw model =
    ( withAccount
        (\ui ->
            let
                p =
                    ui.password
            in
            { ui
                | password =
                    { p | confirm = raw, error = Nothing, success = Nothing }
            }
        )
        model
    , Cmd.none
    )



-- ── PROFILE SUBMIT ───────────────────────────────────────────────────────────


submitProfile : Model -> ( Model, Cmd Msg )
submitProfile model =
    let
        trimmed =
            String.trim model.accountUi.profile.displayName
    in
    if String.isEmpty trimmed then
        ( withAccount
            (\ui ->
                let
                    p =
                        ui.profile
                in
                { ui
                    | profile =
                        { p | error = Just "Display name must not be empty." }
                }
            )
            model
        , Cmd.none
        )

    else
        ( withAccount
            (\ui ->
                let
                    p =
                        ui.profile
                in
                { ui
                    | profile =
                        { p | busy = True, error = Nothing, success = Nothing }
                }
            )
            model
        , Effects.updateProfile { displayName = trimmed } AccountProfileSaved
        )


profileSaved : Result Http.Error User -> Model -> ( Model, Cmd Msg )
profileSaved result model =
    case result of
        Ok user ->
            ( { model | auth = AuthAuthenticated user }
                |> withAccount
                    (\ui ->
                        let
                            p =
                                ui.profile
                        in
                        { ui
                            | profile =
                                { p
                                    | displayName = user.displayName
                                    , busy = False
                                    , error = Nothing
                                    , success = Just "Display name saved."
                                }
                        }
                    )
            , Cmd.none
            )

        Err err ->
            ( withAccount
                (\ui ->
                    let
                        p =
                            ui.profile
                    in
                    { ui
                        | profile =
                            { p
                                | busy = False
                                , error = Just (Util.Http.errorToString err)
                                , success = Nothing
                            }
                    }
                )
                model
            , Cmd.none
            )



-- ── PASSWORD SUBMIT ──────────────────────────────────────────────────────────


submitPassword : Model -> ( Model, Cmd Msg )
submitPassword model =
    let
        p =
            model.accountUi.password

        validation =
            if String.isEmpty p.current then
                Err "Enter your current password."

            else if String.length p.new < 8 then
                Err "New password must be at least 8 characters."

            else if p.new /= p.confirm then
                Err "New password and confirmation don't match."

            else
                Ok ()
    in
    case validation of
        Err msg ->
            ( withAccount
                (\ui ->
                    let
                        pw =
                            ui.password
                    in
                    { ui
                        | password =
                            { pw | error = Just msg, success = Nothing }
                    }
                )
                model
            , Cmd.none
            )

        Ok () ->
            ( withAccount
                (\ui ->
                    let
                        pw =
                            ui.password
                    in
                    { ui
                        | password =
                            { pw | busy = True, error = Nothing, success = Nothing }
                    }
                )
                model
            , Effects.changePassword
                { currentPassword = p.current, newPassword = p.new }
                AccountPasswordChanged
            )


passwordChanged : Result Http.Error () -> Model -> ( Model, Cmd Msg )
passwordChanged result model =
    case result of
        Ok () ->
            ( withAccount
                (\ui ->
                    { ui
                        | password =
                            { current = ""
                            , new = ""
                            , confirm = ""
                            , busy = False
                            , error = Nothing
                            , success = Just "Password updated."
                            }
                    }
                )
                model
            , Cmd.none
            )

        Err err ->
            ( withAccount
                (\ui ->
                    let
                        pw =
                            ui.password
                    in
                    { ui
                        | password =
                            { pw
                                | busy = False
                                , error = Just (Util.Http.errorToString err)
                                , success = Nothing
                            }
                    }
                )
                model
            , Cmd.none
            )



-- ── INTERNAL ─────────────────────────────────────────────────────────────────


withAccount : (Account.AccountUi -> Account.AccountUi) -> Model -> Model
withAccount fn model =
    { model | accountUi = fn model.accountUi }
