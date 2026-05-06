module Util.Http exposing (errorToString, urlPathSegment)

{-| Common HTTP helpers shared across the app.

`errorToString` is used by every Update branch that surfaces an HTTP
failure to the user (toasts, modal-error fields, etc.) so message
bodies stay consistent. `urlPathSegment` is the single percent-
encoder used by Wire modules; centralizing it keeps domain-adjacent
modules (`Encounter.Wire` etc.) from importing `Url` directly.

@docs errorToString, urlPathSegment

-}

import Http
import Url


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


{-| Percent-encode a single URL path segment. Wraps
`Url.percentEncode` so domain-adjacent modules don't depend on `Url`
themselves.
-}
urlPathSegment : String -> String
urlPathSegment =
    Url.percentEncode
