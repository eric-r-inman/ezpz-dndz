module ProfileTest exposing (suite)

{-| These cover what each profile lets the editor column show,
and what picking one folds away.
-}

import Expect
import Model exposing (DrawerPanel, Surface(..))
import Msg exposing (Profile(..))
import Test exposing (Test, describe, test)
import Ui.HpChange
import Ui.Initiative
import Ui.QuickAdd


panel : Surface -> Bool -> DrawerPanel
panel surface collapsed =
    { surface = surface, collapsed = collapsed, pinned = False }


hp : Bool -> DrawerPanel
hp collapsed =
    panel (SurfaceHpChange (Ui.HpChange.fresh "")) collapsed


quickAdd : Bool -> DrawerPanel
quickAdd collapsed =
    panel (SurfaceQuickAdd Ui.QuickAdd.fresh) collapsed


initiative : Bool -> DrawerPanel
initiative collapsed =
    panel (SurfaceInitiative (Ui.Initiative.fresh "")) collapsed


suite : Test
suite =
    describe "column profiles"
        [ describe "what each profile shows"
            [ test "Session hides a folded Quick Add" <|
                \_ ->
                    Model.profileShows Session (quickAdd True)
                        |> Expect.equal False
            , test "Session shows a Quick Add something has unfolded" <|
                \_ ->
                    Model.profileShows Session (quickAdd False)
                        |> Expect.equal True
            , test "Session shows the editors a fight needs" <|
                \_ ->
                    Model.profileShows Session (hp True)
                        |> Expect.equal True
            , test "Builder hides a folded Manage HP" <|
                \_ ->
                    Model.profileShows Builder (hp True)
                        |> Expect.equal False
            , test "Builder shows a Manage HP a card has unfolded" <|
                \_ ->
                    Model.profileShows Builder (hp False)
                        |> Expect.equal True
            , test "Builder hides a folded Dice Roller" <|
                \_ ->
                    Model.profileShows Builder (panel SurfaceDice True)
                        |> Expect.equal False
            , test "Beta shows everything, folded or not" <|
                \_ ->
                    Model.defaultDrawer
                        |> List.filter (Model.profileShows Beta >> not)
                        |> Expect.equal []
            ]
        , describe "picking a profile folds what it hides"
            [ test "a fresh column boots with Manage HP open" <|
                \_ ->
                    Model.defaultDrawer
                        |> List.filter (\p -> not p.collapsed)
                        |> List.map (.surface >> Model.surfaceKey)
                        |> Expect.equal [ "hp-change" ]
            , test "so a fresh column shows no Manage HP under Builder" <|
                \_ ->
                    Model.defaultDrawer
                        |> Model.foldProfileHidden Builder
                        |> List.filter (Model.profileShows Builder)
                        |> List.map (.surface >> Model.surfaceKey)
                        |> Expect.equal
                            [ "initiative", "duplicate", "replace", "cr-calculator", "xp", "quick-add" ]
            , test "an open editor a profile does not hide is left open" <|
                \_ ->
                    [ initiative False, hp False ]
                        |> Model.foldProfileHidden Builder
                        |> List.map .collapsed
                        |> Expect.equal [ False, True ]
            ]
        ]
