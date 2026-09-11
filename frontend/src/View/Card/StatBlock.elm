module View.Card.StatBlock exposing (view)

{-| The stat block a card unfolds beneath itself.

Lookup is id-then-name: `Compendium.find` on the card's compendium
id, and on a miss `Compendium.findByName` on the display name with
its instance suffix stripped, because an old saved encounter can
carry an id the bundled compendium no longer has. When neither
matches, the block says so rather than showing another creature.

@docs view

-}

import Compendium
import Encounter exposing (Creature)
import Encounter.Roster
import Html exposing (Html, a, button, div, p, section, span, text)
import Html.Attributes exposing (attribute, class, href, target, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.StatBlock
import View.Tooltips as Tooltips


{-| `active` follows the card above, so the block wears the same
accent while it is that creature's turn.
-}
view : Bool -> CompendiumDb -> Creature -> Html Msg
view active db creature =
    let
        source =
            resolve creature db
    in
    section
        [ class
            (if active then
                "card-statblock card-statblock--active"

             else
                "card-statblock"
            )
        ]
        [ bar creature source
        , div [ class "card-statblock__body" ]
            [ source
                |> Maybe.map statBlock
                |> Maybe.withDefault (notFound creature db)
            ]
        ]


{-| The strip that ties the block to its card.
-}
bar : Creature -> Maybe Compendium.Creature -> Html Msg
bar creature source =
    div [ class "card-statblock__bar" ]
        [ span [ class "card-statblock__elbow" ] []
        , span [ class "card-statblock__title" ]
            [ text creature.name
            , span [ class "card-statblock__title-kind" ] [ text "information" ]
            ]
        , div [ class "card-statblock__tools" ]
            (Maybe.withDefault [] (Maybe.map (\c -> jumpLinks c.id) source)
                ++ [ minimizeButton creature.name ]
            )
        ]


{-| Hand the creature off to the full browser, in this tab's
Compendium page or a window of its own.
-}
jumpLinks : String -> List (Html Msg)
jumpLinks id =
    [ button
        [ class "card-statblock__open"
        , type_ "button"
        , onClick (CompendiumShowCreature id)
        , Tooltips.attr Tooltips.statBlockShowInCompendium
        , attribute "aria-label" Tooltips.statBlockShowInCompendium
        ]
        [ text "📖" ]
    , a
        [ class "card-statblock__open"
        , href ("/compendium/creatures/" ++ id)
        , target "_blank"
        , attribute "rel" "noopener"
        , Tooltips.attr Tooltips.statBlockNewTab
        , attribute "aria-label" Tooltips.statBlockNewTab
        ]
        [ text "↗" ]
    ]


minimizeButton : String -> Html Msg
minimizeButton name =
    button
        [ class "card-statblock__minimize"
        , type_ "button"
        , onClick (StatBlockMinimize name)
        , Tooltips.attr Tooltips.statBlockMinimize
        , attribute "aria-label" Tooltips.statBlockMinimize
        ]
        [ span [ class "card-statblock__minimize-glyph" ] [ text "−" ] ]


resolve : Creature -> CompendiumDb -> Maybe Compendium.Creature
resolve creature db =
    case db of
        CompendiumDbLoaded loaded ->
            case Maybe.andThen (\id -> Compendium.find id loaded) creature.creatureId of
                Just c ->
                    Just c

                Nothing ->
                    -- Encounter creatures named like "Adult Blue
                    -- Dragon 2" come from `uniqueInstanceName`,
                    -- which suffixes a numeric instance index.
                    -- Strip it before the name lookup so duplicates
                    -- still match the canonical compendium entry.
                    Compendium.findByName (Encounter.Roster.instanceBaseName creature.name) loaded

        _ ->
            Nothing


statBlock : Compendium.Creature -> Html Msg
statBlock source =
    View.StatBlock.view RollFromStatBlock AttackRollTriggered AbilityCheckTriggered AbilitySaveTriggered View.StatBlock.TagBadges source


notFound : Creature -> CompendiumDb -> Html Msg
notFound creature db =
    let
        message =
            case db of
                CompendiumDbLoading ->
                    "Loading the compendium…"

                CompendiumDbFailed _ ->
                    "Couldn't load the compendium."

                CompendiumDbLoaded _ ->
                    "\""
                        ++ creature.name
                        ++ "\" isn't in your compendium yet. "
                        ++ "To see this creature's stat block, import the "
                        ++ "compendium save file that contains this creature."
    in
    p [ class "empty" ] [ text message ]
