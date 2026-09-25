module Ui.QueueDragTest exposing (suite)

{-| These cover where a dragged queue card would land as the pointer
moves between entries and off the queue.
-}

import Expect
import Test exposing (Test, describe, test)
import Ui.QueueDrag as QueueDrag


suite : Test
suite =
    describe "Ui.QueueDrag"
        [ test "a gap further down lands the card just above it" <|
            \_ ->
                QueueDrag.start 0
                    |> QueueDrag.aim 2 3
                    |> .over
                    |> Expect.equal (Just 2)
        , test "moving on to the next entry keeps the landing when the old one reports leaving last" <|
            \_ ->
                QueueDrag.start 3
                    |> QueueDrag.aim 1 2
                    |> QueueDrag.aim 0 1
                    |> QueueDrag.leave 1
                    |> .over
                    |> Expect.equal (Just 1)
        , test "and when the old one reports leaving first" <|
            \_ ->
                QueueDrag.start 3
                    |> QueueDrag.aim 1 2
                    |> QueueDrag.leave 1
                    |> QueueDrag.aim 0 1
                    |> .over
                    |> Expect.equal (Just 1)
        , test "leaving the entry the pointer was over takes the landing away" <|
            \_ ->
                QueueDrag.start 3
                    |> QueueDrag.aim 1 1
                    |> QueueDrag.leave 1
                    |> .over
                    |> Expect.equal Nothing
        ]
