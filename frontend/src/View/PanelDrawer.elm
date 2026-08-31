module View.PanelDrawer exposing (view)

{-| The panel the Actions column slides open over the queue.

An empty frame for now, wearing the compendium panel's chrome
because that is the shape the editors and the compendium are
being moved into. The queue keeps scrolling and taking clicks
beside it — the drawer covers part of the pane, not the app.

-}

import Html exposing (Html, button, div, p, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.ActionsDrawer exposing (ActionsDrawerUi)
import View.Tooltips as Tooltips


view : ActionsDrawerUi -> Html Msg
view ui =
    let
        title =
            Ui.ActionsDrawer.title ui.target
    in
    section [ class "panel panel--drawer" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text title ]
            , button
                [ class "panel-drawer__close"
                , type_ "button"
                , onClick (ActionsDrawerToggle ui.target)
                , Tooltips.attr Tooltips.drawerClose
                , attribute "aria-label" Tooltips.drawerClose
                ]
                [ text "✕" ]
            ]
        , div [ class "panel__body" ]
            [ p [ class "empty" ]
                [ text (title ++ " will live here once it moves out of its current pane.") ]
            ]
        ]
