module Util.Keyboard exposing (enterKey, escKey, listboxOptionKeys)

{-| Tiny keyboard-decoder helpers shared across modal forms.
`enterKey` and `escKey` produce a `Decoder msg` for
`Html.Events.on "keydown"` or `Browser.Events.onKeyDown`.
`listboxOptionKeys` produces a `Decoder ( msg, Bool )` for
`Html.Events.preventDefaultOn "keydown"`.

@docs enterKey, escKey, listboxOptionKeys

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


{-| This decodes the keys one listbox option handles. Enter and
Space pick the option. The arrow keys pick a neighbour when there
is one. A handled key never also scrolls the page.
-}
listboxOptionKeys :
    { pick : msg, previous : Maybe msg, next : Maybe msg }
    -> Decode.Decoder ( msg, Bool )
listboxOptionKeys { pick, previous, next } =
    let
        handled maybeMsg =
            maybeMsg
                |> Maybe.map (\msg -> Decode.succeed ( msg, True ))
                |> Maybe.withDefault (Decode.fail "ignore")
    in
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        handled (Just pick)

                    " " ->
                        handled (Just pick)

                    "ArrowUp" ->
                        handled previous

                    "ArrowDown" ->
                        handled next

                    _ ->
                        Decode.fail "ignore"
            )
