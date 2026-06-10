module Util.Number exposing (formatThousands)

{-| Number-formatting helpers.

@docs formatThousands

-}


{-| Pretty-print a signed integer with `,` thousands separators.

    formatThousands 0 == "0"

    formatThousands 42 == "42"

    formatThousands 1600 == "1,600"

    formatThousands 19000 == "19,000"

    formatThousands 100000 == "100,000"

    formatThousands 1000000 == "1,000,000"

    formatThousands -1234 == "-1,234"

The trick: walk the digits least-significant-first (via
`List.reverse`), and at every i ≡ 0 (mod 3) past zero emit a
comma BEFORE the current digit (which, after the final
`List.reverse`, lands in the correct group-boundary slot).
The previous "comma AFTER the digit" version produced bugs
like ",1600" (comma at the front) and "1,9000" (comma one
position too high) on 4- and 5-digit values.

-}
formatThousands : Int -> String
formatThousands n =
    let
        digits =
            n |> abs |> String.fromInt |> String.toList

        grouped =
            digits
                |> List.reverse
                |> List.indexedMap
                    (\i c ->
                        if i > 0 && modBy 3 i == 0 then
                            [ ',', c ]

                        else
                            [ c ]
                    )
                |> List.concat
                |> List.reverse
                |> String.fromList
    in
    if n < 0 then
        "-" ++ grouped

    else
        grouped
