module View.Page.CompendiumStandalone exposing (view)

{-| Standalone single-creature stat-block view at
`/compendium/creatures/:id`. Used as the deep link for the side
panel's ↗️ "open in new window" button — gives the GM a clean
reference page they can keep open in another window or print.

While the compendium fetch is in flight, render a loading
placeholder. If the fetch completes and the id isn't found,
render a 404-style message.

@docs view

-}

import Compendium
import Html exposing (Html, div, p, section, text)
import Html.Attributes exposing (class)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.StatBlock


view : CompendiumDb -> String -> Html Msg
view compendiumDb id =
    let
        body =
            case compendiumDb of
                CompendiumDbLoading ->
                    p [ class "empty" ] [ text "Loading…" ]

                CompendiumDbFailed _ ->
                    p [ class "empty" ]
                        [ text "Couldn't load the compendium." ]

                CompendiumDbLoaded db ->
                    case Compendium.find id db of
                        Just creature ->
                            View.StatBlock.view RollFromStatBlock AbilityCheckOpen AbilitySaveOpen View.StatBlock.TagBadges creature

                        Nothing ->
                            p [ class "empty" ]
                                [ text "Creature not found in the compendium." ]
    in
    div [ class "workspace workspace--standalone" ]
        [ section [ class "panel panel--standalone" ]
            [ div [ class "panel__body" ] [ body ] ]
        ]
