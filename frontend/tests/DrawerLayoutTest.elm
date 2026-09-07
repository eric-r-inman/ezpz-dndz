module DrawerLayoutTest exposing (suite)

{-| The saved editor-column arrangement. These cover the decoder's
leniency and the rules that let a saved layout survive a release
that changes which editors exist.
-}

import DrawerLayout
import Expect
import Json.Decode as Decode
import Json.Encode as Encode
import Test exposing (Test, describe, test)


entries : List DrawerLayout.Entry
entries =
    [ { key = "treasure", pinned = True }
    , { key = "dice", pinned = False }
    ]


suite : Test
suite =
    describe "DrawerLayout"
        [ test "round-trips through the wire format" <|
            \_ ->
                DrawerLayout.encode entries
                    |> Decode.decodeValue DrawerLayout.decoder
                    |> Expect.equal (Ok entries)
        , test "an entry with no pinned flag reads as unpinned" <|
            \_ ->
                -- Losing one panel's pin costs the GM less than
                -- failing the decode and losing the arrangement.
                Encode.list identity
                    [ Encode.object [ ( "key", Encode.string "dice" ) ] ]
                    |> Decode.decodeValue DrawerLayout.decoder
                    |> Expect.equal (Ok [ { key = "dice", pinned = False } ])
        , test "an empty layout decodes to no entries" <|
            \_ ->
                Encode.list identity []
                    |> Decode.decodeValue DrawerLayout.decoder
                    |> Expect.equal (Ok [])
        , test "an entry with no key fails rather than guessing one" <|
            \_ ->
                Encode.list identity
                    [ Encode.object [ ( "pinned", Encode.bool True ) ] ]
                    |> Decode.decodeValue DrawerLayout.decoder
                    |> Expect.err
        ]
