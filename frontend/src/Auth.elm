module Auth exposing
    ( AuthState(..)
    , LoginMode(..)
    , User
    , isAuthenticated
    , userDecoder
    )

{-| Authentication domain types — pure (no Html, no Browser).

`AuthState` is the three-way "what does the app know about the
current user?" status. `User` is the slim public projection
returned by `/api/auth/me` and the register / login endpoints —
no password hash, no internal-only fields.

The wire decoder lives here so the Effects layer can decode HTTP
responses without pulling in any view code.

-}

import Json.Decode as Decode exposing (Decoder)


{-| Boot status:

  - `AuthLoading` — the initial `/api/auth/me` request is in
    flight; render a placeholder.
  - `AuthAnonymous` — no session; render the login / register
    view.
  - `AuthAuthenticated user` — session is good; render the app.

-}
type AuthState
    = AuthLoading
    | AuthAnonymous
    | AuthAuthenticated User


{-| Login form mode toggle. Persisted as part of the form
substate so toggling between Sign in and Create account doesn't
clear the email the user already typed.
-}
type LoginMode
    = Login
    | Register


{-| Public user projection. Mirrors the server's
`UserPublic` record — the password hash never crosses the wire.
-}
type alias User =
    { id : String
    , email : String
    , displayName : String
    , createdAt : Int
    }


isAuthenticated : AuthState -> Bool
isAuthenticated state =
    case state of
        AuthAuthenticated _ ->
            True

        _ ->
            False


userDecoder : Decoder User
userDecoder =
    Decode.map4 User
        (Decode.field "id" Decode.string)
        (Decode.field "email" Decode.string)
        (Decode.field "display_name" Decode.string)
        (Decode.field "created_at" Decode.int)
