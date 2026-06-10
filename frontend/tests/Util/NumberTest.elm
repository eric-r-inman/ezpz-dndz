module Util.NumberTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Util.Number exposing (formatThousands)


suite : Test
suite =
    describe "Util.Number.formatThousands"
        [ test "zero" <|
            \_ -> formatThousands 0 |> Expect.equal "0"
        , test "single digit" <|
            \_ -> formatThousands 7 |> Expect.equal "7"
        , test "two digits" <|
            \_ -> formatThousands 42 |> Expect.equal "42"
        , test "three digits stays unseparated" <|
            \_ -> formatThousands 999 |> Expect.equal "999"
        , test "four digits — regression: was ',1600'" <|
            \_ -> formatThousands 1600 |> Expect.equal "1,600"
        , test "five digits — regression: was '1,9000'" <|
            \_ -> formatThousands 19000 |> Expect.equal "19,000"
        , test "six digits" <|
            \_ -> formatThousands 100000 |> Expect.equal "100,000"
        , test "seven digits — two separators" <|
            \_ -> formatThousands 1000000 |> Expect.equal "1,000,000"
        , test "mixed digits across two groups" <|
            \_ -> formatThousands 1234567 |> Expect.equal "1,234,567"
        , test "small negative" <|
            \_ -> formatThousands -42 |> Expect.equal "-42"
        , test "negative four-digit" <|
            \_ -> formatThousands -1234 |> Expect.equal "-1,234"
        ]
