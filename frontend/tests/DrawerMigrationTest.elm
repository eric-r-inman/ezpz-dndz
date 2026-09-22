module DrawerMigrationTest exposing (suite)

{-| These cover what the editor column boots as, and the
rearrangements a saved layout picks up when the build's rules
version has moved past the one it was saved under.
-}

import Expect
import Model exposing (DrawerPanel, Surface(..))
import Test exposing (Test, describe, test)
import Ui.HpChange
import Ui.SaveChain
import Ui.Status


hp : Bool -> DrawerPanel
hp pinned =
    { surface = SurfaceHpChange (Ui.HpChange.fresh ""), collapsed = True, pinned = pinned }


status : DrawerPanel
status =
    { surface = SurfaceStatus (Ui.Status.fresh ""), collapsed = True, pinned = False }


saveChain : Bool -> DrawerPanel
saveChain pinned =
    { surface = SurfaceSaveChain (Ui.SaveChain.fresh ""), collapsed = True, pinned = pinned }


keys : List DrawerPanel -> List String
keys =
    List.map (.surface >> Model.surfaceKey)


pins : List DrawerPanel -> List ( String, Bool )
pins =
    List.map (\panel -> ( Model.surfaceKey panel.surface, panel.pinned ))


suite : Test
suite =
    describe "saved drawer layout migrations"
        [ describe "version 2: the beta panels settle at the bottom"
            [ test "a version 1 layout has them moved" <|
                \_ ->
                    Model.settleBeta 1 [ saveChain False, status, hp False ]
                        |> keys
                        |> Expect.equal [ "status", "hp-change", "save-chain" ]
            , test "a pinned beta panel stays where the GM put it" <|
                \_ ->
                    Model.settleBeta 1 [ saveChain True, status, hp False ]
                        |> keys
                        |> Expect.equal [ "save-chain", "status", "hp-change" ]
            , test "a layout already at version 2 is left alone" <|
                \_ ->
                    Model.settleBeta 2 [ saveChain False, status, hp False ]
                        |> keys
                        |> Expect.equal [ "save-chain", "status", "hp-change" ]
            , test "a layout saved under a later version is left alone too" <|
                \_ ->
                    Model.settleBeta 3 [ saveChain False, status, hp False ]
                        |> keys
                        |> Expect.equal [ "save-chain", "status", "hp-change" ]
            ]
        , describe "version 3: Manage HP is pinned to the top"
            [ test "an older layout has it pinned and moved to the front" <|
                \_ ->
                    Model.holdHpChange 2 [ status, saveChain False, hp False ]
                        |> pins
                        |> Expect.equal
                            [ ( "hp-change", True ), ( "status", False ), ( "save-chain", False ) ]
            , test "a layout already at version 3 keeps the GM's own pin" <|
                \_ ->
                    -- A GM who unpinned Manage HP under these rules
                    -- meant it; re-pinning every boot would be the
                    -- app arguing with them.
                    Model.holdHpChange 3 [ status, hp False ]
                        |> pins
                        |> Expect.equal [ ( "status", False ), ( "hp-change", False ) ]
            , test "a column with no Manage HP panel is unchanged" <|
                \_ ->
                    Model.holdHpChange 1 [ status, saveChain False ]
                        |> pins
                        |> Expect.equal [ ( "status", False ), ( "save-chain", False ) ]
            ]
        , describe "the boot column"
            [ test "opens with Manage HP first, pinned and unfolded" <|
                \_ ->
                    List.head Model.defaultDrawer
                        |> Maybe.map
                            (\panel ->
                                ( Model.surfaceKey panel.surface, panel.pinned, panel.collapsed )
                            )
                        |> Expect.equal (Just ( "hp-change", True, False ))
            , test "every other editor boots folded and unpinned" <|
                \_ ->
                    List.drop 1 Model.defaultDrawer
                        |> List.filter (\panel -> panel.pinned || not panel.collapsed)
                        |> keys
                        |> Expect.equal []
            ]
        ]
