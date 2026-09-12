module Ui.Account exposing
    ( AccountUi, ProfileDraft, PasswordDraft
    , empty
    , maxDisplayNameLength
    )

{-| State for the `/me` Account page.

The Account page is a _route_, not a modal, so its UI substate
lives on `Model` directly (like `loginUi`) rather than inside the
`Surface` ADT. Two independent form sections:

  - **Profile** — read-only email + member-since, editable display
    name. Save dispatches `PUT /api/auth/me`.
  - **Password** — current + new + confirm; submit dispatches
    `POST /api/auth/password`.

Each section tracks its own `busy` + `error` + `success` flags so
they don't interfere; the GM could (in theory) edit their display
name and start typing a new password at the same time.

@docs AccountUi, ProfileDraft, PasswordDraft
@docs empty
@docs maxDisplayNameLength

-}


type alias AccountUi =
    { profile : ProfileDraft
    , password : PasswordDraft
    }


type alias ProfileDraft =
    { displayName : String
    , busy : Bool
    , error : Maybe String
    , success : Maybe String
    }


type alias PasswordDraft =
    { current : String
    , new : String
    , confirm : String
    , busy : Bool
    , error : Maybe String
    , success : Maybe String
    }


empty : AccountUi
empty =
    { profile =
        { displayName = ""
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


{-| Cap display names so the AppBar nav doesn't get hijacked by a
40-character handle. Matches the value the backend's
`UserStore::update_display_name` accepts (no upper bound there
today, but we cap on the client side for layout sanity).
-}
maxDisplayNameLength : Int
maxDisplayNameLength =
    60
