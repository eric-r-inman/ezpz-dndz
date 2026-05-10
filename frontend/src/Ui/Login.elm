module Ui.Login exposing (LoginUi, empty, fromError, fromMode, withSubmitting)

{-| UI substate for the login / register view.

Lives outside `Model.Modal` because the login screen replaces
the entire app, not just a modal overlay. Persisted on the
top-level Model when the user is `AuthAnonymous`.

-}

import Auth exposing (LoginMode(..))


type alias LoginUi =
    { mode : LoginMode
    , email : String
    , password : String
    , displayName : String
    , submitting : Bool
    , error : Maybe String
    }


empty : LoginUi
empty =
    { mode = Login
    , email = ""
    , password = ""
    , displayName = ""
    , submitting = False
    , error = Nothing
    }


{-| Produce a UI in the requested mode, preserving whatever the
user has typed so far. Used by the mode-toggle handler.
-}
fromMode : LoginMode -> LoginUi -> LoginUi
fromMode mode ui =
    { ui | mode = mode, error = Nothing, submitting = False }


{-| Mark the form as in-flight (disable submit + show spinner).
-}
withSubmitting : Bool -> LoginUi -> LoginUi
withSubmitting submitting ui =
    { ui | submitting = submitting }


{-| Surface an error message under the form. Also un-flags
`submitting` so the button re-enables for a retry.
-}
fromError : String -> LoginUi -> LoginUi
fromError message ui =
    { ui | error = Just message, submitting = False }
