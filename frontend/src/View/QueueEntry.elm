module View.QueueEntry exposing (view)

{-| One place in the queue: a creature's card, with whatever the GM
has unfolded under it, since a reorder carries the two together.

The entry, not the card, is where a dragged card lands. While a
drag is on, nothing inside an entry takes the pointer; the entry
answers for it across its card and stat block and out to the middle
of the gap on either side, so a card let go between two others
lands there as surely as one let go on a card.

-}

import Html exposing (Html, div)
import Html.Attributes exposing (class)
import Html.Events exposing (on, preventDefaultOn)
import Json.Decode as Decode
import Msg exposing (Msg(..))
import Ui.QueueDrag exposing (QueueDrag)


{-| The entry at `index`: its card, then what hangs beneath it.
-}
view : Maybe QueueDrag -> Int -> Html Msg -> List (Html Msg) -> Html Msg
view drag index card beneath =
    div
        (class (String.join " " ("queue-entry" :: cueClasses index drag))
            :: dropTarget index
        )
        (card :: beneath)


{-| During a drag every entry catches the pointer for itself, and the
one the card would land beside wears the line on that side of it:
below when the card came from above, above when it came from below.
The dragged card's own entry never wears it, since landing there
moves nothing.
-}
cueClasses : Int -> Maybe QueueDrag -> List String
cueClasses index drag =
    case drag of
        Just { from, over } ->
            "queue-entry--catching"
                :: (if over == Just index && from < index then
                        [ "queue-entry--drop-below" ]

                    else if over == Just index && from > index then
                        [ "queue-entry--drop-above" ]

                    else
                        []
                   )

        Nothing ->
            []


{-| Both `dragenter` and `dragover` are cancelled, since the
drag-and-drop standard lets a drop land only on an element that
cancelled both.
-}
dropTarget : Int -> List (Html.Attribute Msg)
dropTarget index =
    [ preventDefaultOn "dragenter" (aim index)
    , preventDefaultOn "dragover" (aim index)
    , on "dragleave" (Decode.succeed (QueueDragLeave index))
    , preventDefaultOn "drop" (Decode.succeed ( QueueDrop, True ))
    ]


aim : Int -> Decode.Decoder ( Msg, Bool )
aim index =
    Decode.map (\gap -> ( QueueDragOver index gap, True )) (gapUnderPointer index)


{-| The gap the pointer means: the one above this entry while the
pointer is above the middle of its card, and the one below it from
there down, since a stat block hangs off its card and letting go on
one means after the card. `offsetY` is measured from the entry
itself because nothing inside it takes the pointer during a drag.
-}
gapUnderPointer : Int -> Decode.Decoder Int
gapUnderPointer index =
    Decode.map2
        (\y cardHeight ->
            if y < cardHeight / 2 then
                index

            else
                index + 1
        )
        (Decode.field "offsetY" Decode.float)
        (Decode.at [ "currentTarget", "firstElementChild", "offsetHeight" ] Decode.float)
