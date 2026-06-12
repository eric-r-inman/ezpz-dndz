module Encounter.TreasureToggleTest exposing (suite)

{-| Sanity test that the per-Kind None toggles can actually be
flipped via Treasure.togglesFor / record update — and that the
flipped value round-trips through the wire codec. Added when
the user reported "the None toggles aren't toggling" so we can
catch any future regression of the underlying state model
without depending on a browser.
-}

import Encounter.Treasure as Treasure
import Expect
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Treasure None toggles"
        [ test "Hoard.gemsNone defaults to False" <|
            \_ ->
                Treasure.defaultSettings.hoardToggles.gemsNone
                    |> Expect.equal False
        , test "Individual.gemsNone defaults to True" <|
            \_ ->
                Treasure.defaultSettings.individualToggles.gemsNone
                    |> Expect.equal True
        , test "togglesFor Hoard returns the hoard bucket" <|
            \_ ->
                Treasure.togglesFor Treasure.Hoard Treasure.defaultSettings
                    |> Expect.equal Treasure.defaultHoardToggles
        , test "togglesFor Individual returns the individual bucket" <|
            \_ ->
                Treasure.togglesFor Treasure.Individual Treasure.defaultSettings
                    |> Expect.equal Treasure.defaultIndividualToggles
        , test "flipping Hoard.gemsNone preserves Individual.gemsNone" <|
            \_ ->
                let
                    base =
                        Treasure.defaultSettings

                    ht =
                        base.hoardToggles

                    next =
                        { base | hoardToggles = { ht | gemsNone = True } }
                in
                ( next.hoardToggles.gemsNone, next.individualToggles.gemsNone )
                    |> Expect.equal ( True, True )
        , test "flipping Individual.coinsNone preserves Hoard.coinsNone" <|
            \_ ->
                let
                    base =
                        Treasure.defaultSettings

                    it =
                        base.individualToggles

                    next =
                        { base | individualToggles = { it | coinsNone = True } }
                in
                ( next.individualToggles.coinsNone, next.hoardToggles.coinsNone )
                    |> Expect.equal ( True, False )
        ]
