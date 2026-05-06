module View.Workspace exposing (view)

{-| Three-pane workspace layout for the Home route: encounter pane
on the left (creature cards under the encounter title bar), control
buttons in the middle, compendium / detail pane on the right.

Each pane is a separate `View/` module — this module just wires
them together with the model fragments each one needs.

-}

import Encounter exposing (Encounter)
import Encounter.Xp exposing (XpScope)
import Html exposing (Html, div, main_, section)
import Html.Attributes exposing (class)
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumDb)
import Ui.HpChange exposing (HpEdit)
import View.Card
import View.EncounterBar
import View.PanelControls
import View.PanelDetail


view : Model -> Html Msg
view model =
    main_ [ class "workspace" ]
        [ panelMain
            model.encounter
            model.hpEdit
            model.savedAs
            model.compendium.db
            model.xpScope
            model.xpFilterOpen
        , View.PanelControls.view model.dice model.pendingControl model.encounter.round
        , View.PanelDetail.view model
        ]


{-| The encounter pane. `hpEdit` is threaded through so any open
inline-edit input (current/max HP) renders on the right card.
`savedAs` lights up the title-bar info icon with the source
filename when the encounter was loaded from / saved to a name.
The compendium DB + XP scope let the title bar's right cluster
compute the real XP total; `xpFilterOpen` controls the
hand-rolled XP-scope dropdown's visibility so the global
Esc / click-outside handlers in `Main.subscriptions` can close
it without touching DOM state.
-}
panelMain :
    Encounter
    -> Maybe HpEdit
    -> Maybe String
    -> CompendiumDb
    -> XpScope
    -> Bool
    -> Html Msg
panelMain enc hpEdit savedAs db xpScope xpFilterOpen =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ View.EncounterBar.view enc savedAs db xpScope xpFilterOpen ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (View.Card.view enc.activeName hpEdit) enc.creatures)
            ]
        ]
