module View.PanelDetail exposing (view)

{-| Right pane: compendium toolbar + the pinned-creature stat
block.

The stat-block area has four states (in priority order):

  - Pinned creature found by id → render the matched entry via
    `View.StatBlock.view` (clickable inline dice and all).
  - Pinned creature found by name fallback → same renderer.
    This catches the case where an old saved encounter's
    `creatureId` is no longer in the bundled compendium — we
    still find the right stat block by display name so the
    panel doesn't silently revert to a placeholder.
  - Pinned creature exists but the compendium can't resolve it
    (still loading, or no match by id or name) → render an
    empty-state message naming the creature. The previous
    behaviour fell through to a hardcoded "Brakka, Ogre Brute"
    mock which read as if the panel were stuck on the wrong
    creature.
  - Nothing pinned → render a friendly "click a creature name"
    hint. No more bundled mock.

-}

import Compendium
import Encounter.Roster
import Html exposing (Html, a, button, div, p, section, text)
import Html.Attributes as Attr exposing (attribute, class, href, target)
import Html.Events exposing (onClick)
import Model exposing (Model, PanelPin)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.StatBlock
import View.Tooltips as Tooltips


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
                    , Tooltips.attr Tooltips.panelOpenCompendium
                    ]
                    [ text "📖 Open" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , onClick RandomEncounterOpen
                    , Tooltips.attr Tooltips.panelRandomEncounter
                    ]
                    [ text "🎲 Random Encounter" ]
                ]
            , statBlock model
            ]
        ]


statBlock : Model -> Html Msg
statBlock model =
    case model.panelCreaturePin of
        Just pin ->
            case resolvePin pin model.compendium.db of
                Just creature ->
                    pinnedStatBlock creature

                Nothing ->
                    notFound pin model.compendium.db

        Nothing ->
            emptyState


resolvePin : PanelPin -> CompendiumDb -> Maybe Compendium.Creature
resolvePin pin db =
    case db of
        CompendiumDbLoaded loaded ->
            case Compendium.find pin.id loaded of
                Just c ->
                    Just c

                Nothing ->
                    -- Encounter creatures named like "Adult Blue
                    -- Dragon 2" come from `uniqueInstanceName`,
                    -- which suffixes a numeric instance index.
                    -- Strip it before the name lookup so duplicates
                    -- still match the canonical compendium entry.
                    Compendium.findByName (Encounter.Roster.instanceBaseName pin.name) loaded

        _ ->
            Nothing


pinnedStatBlock : Compendium.Creature -> Html Msg
pinnedStatBlock creature =
    div [ class "panel-statblock" ]
        [ a
            [ class "panel-statblock__open"
            , href ("/compendium/creatures/" ++ creature.id)
            , target "_blank"
            , attribute "rel" "noopener"
            , Tooltips.attr Tooltips.panelStatBlockNewWindow
            , attribute "aria-label" "Open in new window"
            ]
            [ text "↗" ]
        , View.StatBlock.view RollFromStatBlock AbilityCheckOpen AbilitySaveOpen View.StatBlock.TagIconTooltip creature
        ]


notFound : PanelPin -> CompendiumDb -> Html Msg
notFound pin db =
    let
        message =
            case db of
                CompendiumDbLoading ->
                    "Loading the compendium…"

                CompendiumDbFailed _ ->
                    "Couldn't load the compendium."

                CompendiumDbLoaded _ ->
                    "\""
                        ++ pin.name
                        ++ "\" isn't in your compendium yet. "
                        ++ "To see this creature's stat block, import the "
                        ++ "compendium save file that contains this creature."
    in
    div [ class "panel-statblock panel-statblock--empty" ]
        [ p [ class "empty" ] [ text message ] ]


emptyState : Html Msg
emptyState =
    div [ class "panel-statblock panel-statblock--empty" ]
        [ p [ class "empty" ]
            [ text "Click a creature's name on a card to pin its stat block here." ]
        ]
