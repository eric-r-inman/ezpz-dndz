module View.Workspace exposing (view)

{-| Three-pane workspace layout for the Home route: encounter pane
on the left (creature cards under the encounter title bar), control
buttons in the middle, compendium / detail pane on the right.

Each pane is a separate `View/` module — this module just wires
them together with the model fragments each one needs.

-}

import Encounter exposing (Encounter)
import Html exposing (Html, div, main_, section)
import Html.Attributes exposing (class)
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.HpChange exposing (HpEdit)
import View.Card
import View.EncounterBar
import View.PanelControls
import View.PanelDetail


view : Model -> Html Msg
view model =
    main_ [ class "workspace" ]
        [ panelMain model.encounter model.hpEdit
        , View.PanelControls.view model.dice
        , View.PanelDetail.view model
        ]


{-| The encounter pane. `hpEdit` is threaded through so any open
inline-edit input (current/max HP) renders on the right card.
-}
panelMain : Encounter -> Maybe HpEdit -> Html Msg
panelMain enc hpEdit =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ View.EncounterBar.view enc ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (View.Card.view enc.activeName hpEdit) enc.creatures)
            ]
        ]
