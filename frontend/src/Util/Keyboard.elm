module Util.Keyboard exposing (buttonKeys, enterKey, escKey, listboxOptionKeys, neighbours)

{-| Tiny keyboard-decoder helpers shared across modal forms.
`enterKey` and `escKey` produce a `Decoder msg` for
`Html.Events.on "keydown"` or `Browser.Events.onKeyDown`.
`buttonKeys` and `listboxOptionKeys` produce a
`Decoder ( msg, Bool )` for `Html.Events.preventDefaultOn
"keydown"`.

@docs buttonKeys, enterKey, escKey, listboxOptionKeys, neighbours

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


{-| This decodes the keys a native button answers. An element
with `role="button"` gets none of them from the browser.
-}
buttonKeys : msg -> Decode.Decoder ( msg, Bool )
buttonKeys msg =
    listboxOptionKeys { pick = msg, previous = Nothing, next = Nothing }


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


{-| Pairs each listbox option with the options above and below it,
for the arrow keys.
-}
neighbours : List a -> List { previous : Maybe a, option : a, next : Maybe a }
neighbours options =
    let
        present =
            List.map Just options
    in
    List.map3 (\previous option next -> { previous = previous, option = option, next = next })
        (Nothing :: present)
        options
        (List.drop 1 present ++ [ Nothing ])
