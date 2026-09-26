module Hotkeys exposing (Hotkey, all, listener, subscription)

{-| The app's keyboard shortcuts, and the keys that fire them.

Browsers claim Ctrl and ⌘ combinations, and on Windows Alt with a
letter, for their own commands. So each shortcut is Alt+Shift and a
letter: the combination Firefox leaves to pages, and one that
Chrome, Edge, and Safari bind to none of the letters used here.

The shortcuts act on the editor column, so they fire on the
encounter page alone.

@docs Hotkey, all, listener, subscription

-}

import Browser.Events
import Html
import Html.Events
import Json.Decode as Decode exposing (Decoder)
import Msg exposing (Msg(..))
import Route exposing (Route(..))


{-| One shortcut, as the listeners match it and the About page
lists it.
-}
type alias Hotkey =
    { code : String
    , keys : String
    , does : String
    , msg : Msg
    }


all : List Hotkey
all =
    [ { code = "KeyC"
      , keys = "Alt+Shift+C"
      , does = "Collapse every editor in the editor column."
      , msg = DrawerFoldAll
      }
    , { code = "KeyP"
      , keys = "Alt+Shift+P"
      , does = "Open only the pinned editors."
      , msg = DrawerShowPinned
      }
    , { code = "KeyH"
      , keys = "Alt+Shift+H"
      , does = "Open only the Manage HP editor."
      , msg = DrawerShowHpChange
      }
    ]


{-| Fires the shortcuts from inside the element it sits on, the
app's shell.

A Mac types a character for Option+Shift and a letter into a
focused field — Ç for C — so the listener prevents the keydown's
default. `subscription` would fire the same shortcut a second time
once the keydown bubbled up to the document, so the listener also
stops it there.

-}
listener : Route -> List (Html.Attribute Msg)
listener route =
    if route == Home then
        [ Html.Events.custom "keydown"
            (Decode.map
                (\msg -> { message = msg, stopPropagation = True, preventDefault = True })
                decoder
            )
        ]

    else
        []


{-| A keydown with nothing focused goes to the page's body, outside
the shell `listener` sits on, so the document has to catch it.
-}
subscription : Route -> Sub Msg
subscription route =
    if route == Home then
        Browser.Events.onKeyDown decoder

    else
        Sub.none


{-| The message a keydown fires, or a failure for every key that is
not a shortcut, so the listeners built on it let those keys be.
-}
decoder : Decoder Msg
decoder =
    Decode.map4 fired
        (Decode.field "code" Decode.string)
        (Decode.field "altKey" Decode.bool)
        (Decode.field "shiftKey" Decode.bool)
        (Decode.map2 (||)
            (Decode.field "ctrlKey" Decode.bool)
            (Decode.field "metaKey" Decode.bool)
        )
        |> Decode.andThen
            (Maybe.map Decode.succeed
                >> Maybe.withDefault (Decode.fail "not a shortcut")
            )


{-| With Option held, a Mac reports the character it would type as
the keydown's `key` — Ç for C — so a shortcut matches the `code`,
which names the key itself.
-}
fired : String -> Bool -> Bool -> Bool -> Maybe Msg
fired code alt shift otherModifier =
    if alt && shift && not otherModifier then
        all
            |> List.filter (\hotkey -> hotkey.code == code)
            |> List.head
            |> Maybe.map .msg

    else
        Nothing
