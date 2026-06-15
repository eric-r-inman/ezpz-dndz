module Encounter.Treasure.Budget exposing (expectedGpFor)

{-| SRD-derived expected total gp per Hoard / Individual roll
by bracket. Powers the "Expected ~X gp" hint shown near the
Roll button. Numbers are coin-table averages from the SRD 5.1
treasure tables, rounded to the nearest sensible chunk.

For Individual rolls, the expected gp scales with the number of
creatures rolled — the per-creature baselines below get
multiplied by the encounter's enemy count at call time.

-}

import Encounter.Treasure exposing (Bracket(..), Kind(..))


{-| Expected coin gp per single Hoard roll, or per Individual
creature roll, before any non-coin categories kick in. SRD-
derived from `6d6 × 100 cp + 3d6 × 100 sp + …` etc. at the
documented bracket multipliers.
-}
expectedGpFor : Kind -> Bracket -> Int
expectedGpFor kind bracket =
    case ( kind, bracket ) of
        ( Hoard, B1to4 ) ->
            200

        ( Hoard, B5to10 ) ->
            4000

        ( Hoard, B11to16 ) ->
            30000

        ( Hoard, B17plus ) ->
            -- 12d6×1000 gp avg = 42,000; 8d6×1000 pp avg =
            -- 28,000 pp = 280,000 gp.  SRD baseline ≈ 322,000;
            -- round to a clean 320,000.
            320000

        ( Individual, B1to4 ) ->
            25

        ( Individual, B5to10 ) ->
            150

        ( Individual, B11to16 ) ->
            1500

        ( Individual, B17plus ) ->
            5000
