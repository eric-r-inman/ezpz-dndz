module DrawerPinTest exposing (suite)

{-| The pinned block holds the top of the editor column, and a
drag that would cross the boundary clamps to it instead. These
cover the clamp itself; the stack it runs against is built here
rather than from `Model.defaultDrawer` so the cases stay legible
when the drawer's contents change.
-}

import Expect
import Model exposing (DrawerPanel, Surface(..))
import Test exposing (Test, describe, test)


panel : Bool -> DrawerPanel
panel pinned =
    { surface = SurfaceDice, collapsed = True, pinned = pinned }


{-| Two pinned panels above three loose ones.
-}
stack : List DrawerPanel
stack =
    [ panel True, panel True, panel False, panel False, panel False ]


suite : Test
suite =
    describe "drawer pinning"
        [ describe "a pinned panel cannot land below the block"
            [ test "a drop deep in the loose panels clamps to the boundary" <|
                \_ ->
                    Model.drawerDropIndex 0 4 stack
                        |> Expect.equal 1
            , test "the boundary excludes the panel being moved" <|
                \_ ->
                    -- One other pinned panel remains, so the
                    -- deepest a pinned panel can land is index 1.
                    Model.drawerDropIndex 1 3 stack
                        |> Expect.equal 1
            , test "a move within the block is left alone" <|
                \_ ->
                    Model.drawerDropIndex 1 0 stack
                        |> Expect.equal 0
            ]
        , describe "a loose panel cannot land above the block"
            [ test "a drop at the very top clamps below the pinned ones" <|
                \_ ->
                    Model.drawerDropIndex 3 0 stack
                        |> Expect.equal 2
            , test "a move within the loose panels is left alone" <|
                \_ ->
                    Model.drawerDropIndex 2 4 stack
                        |> Expect.equal 4
            ]
        , describe "degenerate stacks"
            [ test "nothing pinned leaves every drop alone" <|
                \_ ->
                    Model.drawerDropIndex 0 2 (List.repeat 3 (panel False))
                        |> Expect.equal 2
            , test "everything pinned leaves every drop alone" <|
                \_ ->
                    Model.drawerDropIndex 0 2 (List.repeat 3 (panel True))
                        |> Expect.equal 2
            , test "an out-of-range source is a no-op" <|
                \_ ->
                    Model.drawerDropIndex 9 0 stack
                        |> Expect.equal 0
            ]
        ]
