module View.Login exposing (view)

{-| Login / register screen, shown when `Auth` says
`AuthAnonymous`. Replaces the entire app body until the user
authenticates; the rest of the SPA is hidden behind this screen
because no API call would succeed without a session anyway.

The form is mode-toggleable in place: clicking "Need an
account?" / "Have an account?" flips between Sign in (email +
password) and Create account (email + password + display name).
The currently-typed values survive the toggle.

Styling lives under `.auth-login` in `style.css`.

-}

import Auth exposing (LoginMode(..))
import Html exposing (Html, button, div, form, h1, input, label, p, text)
import Html.Attributes
    exposing
        ( attribute
        , autocomplete
        , autofocus
        , class
        , disabled
        , id
        , name
        , placeholder
        , required
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput, onSubmit)
import Msg exposing (Msg(..))
import Ui.Login exposing (LoginUi)


view : LoginUi -> Html Msg
view ui =
    div [ class "auth-login" ]
        [ div [ class "auth-login__panel" ]
            [ h1 [ class "auth-login__title" ] [ text "eZpZ-dndZ" ]
            , p [ class "auth-login__tagline" ]
                [ text (taglineFor ui.mode) ]
            , form
                [ class "auth-login__form"
                , onSubmit AuthLoginSubmit
                ]
                (formFields ui ++ [ submitRow ui, modeToggleRow ui ])
            ]
        ]


taglineFor : LoginMode -> String
taglineFor mode =
    case mode of
        Login ->
            "Sign in to keep your encounters and saved compendiums."

        Register ->
            "Create an account.  Free, no email verification."


formFields : LoginUi -> List (Html Msg)
formFields ui =
    let
        emailField =
            field "email"
                "Email"
                "auth-email"
                [ type_ "email"
                , autocomplete True
                , autofocus True
                , value ui.email
                , onInput AuthLoginEmailChanged
                , required True
                ]

        passwordField =
            field "password"
                "Password"
                "auth-password"
                [ type_ "password"
                , value ui.password
                , onInput AuthLoginPasswordChanged
                , attribute "minlength" "8"
                , autocomplete (ui.mode == Login)
                , required True
                ]

        displayNameField =
            field "displayName"
                "Display name"
                "auth-display-name"
                [ type_ "text"
                , value ui.displayName
                , onInput AuthLoginDisplayNameChanged
                , placeholder "what you'd like to be called at the table"
                , required True
                ]
    in
    case ui.mode of
        Login ->
            [ emailField, passwordField ]

        Register ->
            [ emailField, passwordField, displayNameField ]


field : String -> String -> String -> List (Html.Attribute Msg) -> Html Msg
field idValue labelText className extras =
    div [ class "auth-login__field" ]
        [ label [ Html.Attributes.for idValue ] [ text labelText ]
        , input
            ([ id idValue
             , name idValue
             , class ("auth-login__input " ++ className)
             ]
                ++ extras
            )
            []
        ]


submitRow : LoginUi -> Html Msg
submitRow ui =
    div [ class "auth-login__submit-row" ]
        [ button
            [ class "auth-login__submit"
            , type_ "submit"
            , disabled ui.submitting
            ]
            [ text (submitLabel ui) ]
        , case ui.error of
            Just message ->
                p [ class "auth-login__error" ] [ text message ]

            Nothing ->
                text ""
        ]


submitLabel : LoginUi -> String
submitLabel ui =
    case ( ui.mode, ui.submitting ) of
        ( Login, True ) ->
            "Signing in…"

        ( Login, False ) ->
            "Sign in"

        ( Register, True ) ->
            "Creating account…"

        ( Register, False ) ->
            "Create account"


modeToggleRow : LoginUi -> Html Msg
modeToggleRow ui =
    let
        ( prompt, action, target ) =
            case ui.mode of
                Login ->
                    ( "Don't have an account? "
                    , "Create one"
                    , Register
                    )

                Register ->
                    ( "Already have an account? "
                    , "Sign in"
                    , Login
                    )
    in
    p [ class "auth-login__mode-toggle" ]
        [ text prompt
        , button
            [ type_ "button"
            , class "auth-login__mode-link"
            , onClick (AuthLoginModeChanged target)
            ]
            [ text action ]
        ]
