module DrawerLayout exposing (Entry, decoder, encode)

{-| How the GM has arranged the editor column: the order they
dragged the panels into, and which ones they pinned to the top.

Kept as a list of stable string keys rather than the `Surface`
values themselves, so a release that adds, removes, or renames an
editor doesn't invalidate what every GM has already arranged. A
key the current build no longer knows is dropped on the way in,
and an editor the saved layout never mentioned falls in at the
end — see `Model.applyDrawerLayout`.

The fold state is deliberately absent. The column is designed to
open with every editor collapsed to its heading row, so restoring
a session's open panels would fight that.

@docs Entry, decoder, encode

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


{-| One panel's place in the column.
-}
type alias Entry =
    { key : String
    , pinned : Bool
    }


encode : List Entry -> Encode.Value
encode entries =
    Encode.list
        (\entry ->
            Encode.object
                [ ( "key", Encode.string entry.key )
                , ( "pinned", Encode.bool entry.pinned )
                ]
        )
        entries


{-| Lenient by design: a stored entry missing its `pinned` flag
reads as unpinned rather than failing the whole layout, because
losing one panel's pin is a smaller cost to the GM than losing
the arrangement.
-}
decoder : Decoder (List Entry)
decoder =
    Decode.list
        (Decode.map2 Entry
            (Decode.field "key" Decode.string)
            (Decode.oneOf
                [ Decode.field "pinned" Decode.bool
                , Decode.succeed False
                ]
            )
        )
