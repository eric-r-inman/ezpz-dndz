module Util.Keyboard exposing (enterKey, escKey)

{-| Tiny keyboard-decoder helpers shared across modal forms.
Both produce a `Decoder msg` that can be wired to
`Html.Events.on "keydown"` (for Enter-on-input) or to
`Browser.Events.onKeyDown` (for Esc subscriptions).

@docs enterKey, escKey

-}

import Json.Decode as Decode


{-| Decode the Enter key into the given Msg; fail (i.e., ignore)
on every other key so the runtime doesn't fire the handler.
-}
enterKey : msg -> Decode.Decoder msg
enterKey msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                if key == "Enter" then
                    Decode.succeed msg

                else
                    Decode.fail "ignore"
            )


{-| Symmetric to [`enterKey`](#enterKey) for Esc-to-cancel.
-}
escKey : msg -> Decode.Decoder msg
escKey msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                if key == "Escape" then
                    Decode.succeed msg

                else
                    Decode.fail "ignore"
            )
