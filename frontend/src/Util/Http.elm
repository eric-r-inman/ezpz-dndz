module Util.Http exposing (errorToString)

{-| Common HTTP error → human-readable string.

Used by every Update branch that surfaces an HTTP failure to the
user (toasts, modal-error fields, etc.). Keeps the message bodies
consistent across the app instead of letting each call site format
its own.

@docs errorToString

-}

import Http


{-| Convert an `Http.Error` into a short human-readable message
suitable for a toast or an inline error field.
-}
errorToString : Http.Error -> String
errorToString err =
    case err of
        Http.BadUrl u ->
            "Bad URL: " ++ u

        Http.Timeout ->
            "Request timed out."

        Http.NetworkError ->
            "Network error — check the server."

        Http.BadStatus code ->
            "Server returned " ++ String.fromInt code ++ "."

        Http.BadBody body ->
            "Couldn't parse response: " ++ body
