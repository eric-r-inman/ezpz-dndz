module Encounter.Treasure.Budget exposing
    ( WealthBand(..)
    , bandFor
    , bandLabel
    , expectedGpFor
    )

{-| SRD-derived expected total gp per Hoard / Individual roll
by bracket. Powers the "Expected ~X gp" hint shown near the
Roll button and the colour-coded wealth chip on the rolled
result. The numbers are coin-table averages from the SRD 5.1
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
            250000

        ( Individual, B1to4 ) ->
            25

        ( Individual, B5to10 ) ->
            150

        ( Individual, B11to16 ) ->
            1500

        ( Individual, B17plus ) ->
            5000


{-| Verdict the wealth chip surfaces after a roll lands. The
band is decided from the rolled total gp / expected gp ratio:

  - **InBand** — within ±50% of the SRD baseline (the typical
    spread the un-tuned generator produces).
  - **Tuned** — 0.5× to 2× off the baseline, in either direction.
    Reads as "the GM clearly tuned this."
  - **WayOff** — 4× or further off the baseline. Sometimes the
    GM meant to, sometimes a knob slipped — the band gives them
    a chance to notice.

-}
type WealthBand
    = InBand
    | Tuned
    | WayOff


bandFor : Int -> Int -> WealthBand
bandFor actual expected =
    if expected <= 0 then
        InBand

    else
        let
            ratio =
                toFloat actual / toFloat expected
        in
        if ratio >= 0.5 && ratio <= 2 then
            InBand

        else if ratio >= 0.25 && ratio <= 4 then
            Tuned

        else
            WayOff


bandLabel : WealthBand -> String
bandLabel b =
    case b of
        InBand ->
            "🟢 in band"

        Tuned ->
            "🟡 tuned"

        WayOff ->
            "🔴 way out of band"
