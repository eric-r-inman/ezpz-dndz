module View.Panel.StatBlock exposing (view)

{-| The pinned creature's stat block.

Three states, in priority order:

  - Found by id → render the matched entry via
    `View.StatBlock.view` (clickable inline dice and all).
  - Found by name fallback → same renderer. This catches the
    case where an old saved encounter's `creatureId` is no
    longer in the bundled compendium — the right stat block is
    still found by display name, so the panel doesn't silently
    revert to a placeholder.
  - Unresolvable (compendium still loading, or no match by id
    or name) → an empty-state message naming the creature, so
    the panel can't read as stuck on a different one.

-}

import Compendium
import Encounter.Roster
import Html exposing (Html, a, div, p, text)
import Html.Attributes as Attr exposing (attribute, class, href, target)
import Model exposing (PanelPin)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Panel
import View.StatBlock
import View.Tooltips as Tooltips


view : CompendiumDb -> PanelPin -> Html Msg
view db pin =
    View.Panel.view
        { close = PanelClearCreature
        , title = pin.name
        , subtitle = Nothing
        , extraClass = "panel-drawer--statblock"
        , body =
            [ resolvePin pin db
                |> Maybe.map pinnedStatBlock
                |> Maybe.withDefault (notFound pin db)
            ]
        }


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
