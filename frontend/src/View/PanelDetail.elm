module View.PanelDetail exposing (view)

{-| Right pane: compendium toolbar + the pinned-creature stat
block.

The stat-block area has three states (in priority order):

  - User clicked a creature with a compendium link AND the
    library's loaded → render the matched entry via
    `View.StatBlock.view` (clickable inline dice and all).
  - Compendium isn't loaded yet (rare race: the user clicks a
    name before the boot fetch lands) → fall through to the
    bundled mock so the panel isn't empty.
  - Nothing pinned → fall back to the bundled mock as a
    placeholder. Preserves the pre-Phase-3 default and gives
    users SOMETHING to look at on first load.

-}

import Compendium
import Html exposing (Html, a, button, div, section, text)
import Html.Attributes as Attr exposing (attribute, class, href, target, title)
import Html.Events exposing (onClick)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.StatBlock
import View.StatBlockEmbed


view : Model -> Html Msg
view model =
    section [ class "panel panel--detail" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Compendium" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid compendium-toolbar" ]
                [ button
                    [ class "action-btn action-btn--blue"
                    , onClick CompendiumOpen
                    , title "Open the creature library"
                    ]
                    [ text "📖 Open" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , Attr.disabled True
                    , attribute "aria-disabled" "true"
                    , title "CR Calculator (not yet available)"
                    ]
                    [ text "⚔️ CR Calculator" ]
                ]
            , statBlock model
            ]
        ]


statBlock : Model -> Html Msg
statBlock model =
    let
        pinned =
            case ( model.panelCreatureId, model.compendium.db ) of
                ( Just id, CompendiumDbLoaded db ) ->
                    Compendium.find id db

                _ ->
                    Nothing
    in
    case pinned of
        Just creature ->
            div [ class "panel-statblock" ]
                [ a
                    [ class "panel-statblock__open"
                    , href ("/compendium/creatures/" ++ creature.id)
                    , target "_blank"
                    , attribute "rel" "noopener"
                    , title "Open this creature's stat block in a new window"
                    , attribute "aria-label" "Open in new window"
                    ]
                    [ text "↗" ]
                , View.StatBlock.view RollFromStatBlock creature
                ]

        Nothing ->
            View.StatBlockEmbed.view View.StatBlockEmbed.mockStatBlock
