module View.Inline.QueueReference exposing (legendaryActions, specialReactions)

{-| Read-only drop-downs under the queue's legendary-action and
special-reaction strips.

Each strip names who has the feature; these panels say what the
feature does, so the GM can resolve it without leaving the queue
or pinning a whole stat block. Creature names stay clickable for
the times the whole block is what's wanted.

@docs legendaryActions, specialReactions

-}

import Compendium
import Encounter exposing (Creature, Encounter)
import Html exposing (Html, button, div, h3, p, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Tooltips as Tooltips


{-| One entry per queue creature whose source declares legendary
actions: the preamble naming how many it gets, then each option
with its cost.
-}
legendaryActions : Encounter -> CompendiumDb -> Html Msg
legendaryActions enc db =
    panel db
        (\loaded ->
            enc.creatures
                |> List.filterMap (withSource loaded)
                |> List.filterMap
                    (\( c, source ) ->
                        Maybe.map (legendarySection c) source.legendaryActions
                    )
        )
        "No legendary actions in this encounter."


legendarySection : Creature -> Compendium.LegendaryActions -> Html Msg
legendarySection c la =
    div [ class "queue-panel__entry" ]
        [ entryHeader c (usesLabel la)
        , div [ class "queue-panel__items" ]
            (List.map legendaryOption la.options)
        ]


usesLabel : Compendium.LegendaryActions -> String
usesLabel la =
    if la.usesInLair > la.uses then
        String.fromInt la.uses
            ++ " uses ("
            ++ String.fromInt la.usesInLair
            ++ " in lair)"

    else
        String.fromInt la.uses ++ " uses"


legendaryOption : Compendium.LegendaryOption -> Html Msg
legendaryOption opt =
    item
        (if opt.cost > 1 then
            opt.name ++ " (costs " ++ String.fromInt opt.cost ++ ")"

         else
            opt.name
        )
        opt.description


{-| One entry per queue creature flagged for special reactions,
listing the features behind the flag.
-}
specialReactions : Encounter -> CompendiumDb -> Html Msg
specialReactions enc db =
    panel db
        (\loaded ->
            enc.creatures
                |> List.filter .hasSpecialReactions
                |> List.filterMap (withSource loaded)
                |> List.map
                    (\( c, source ) ->
                        div [ class "queue-panel__entry" ]
                            [ entryHeader c ""
                            , div [ class "queue-panel__items" ]
                                (List.map
                                    (\f -> item f.name f.description)
                                    (Compendium.specialReactions source)
                                )
                            ]
                    )
        )
        "No special reactions in this encounter."


{-| Shared chrome: the loading / failed / empty states every
reference panel shows, wrapped around whatever the caller builds
from a loaded compendium.
-}
panel : CompendiumDb -> (Compendium.Db -> List (Html Msg)) -> String -> Html Msg
panel db build emptyText =
    div [ class "queue-panel" ]
        (case db of
            CompendiumDbLoaded loaded ->
                case build loaded of
                    [] ->
                        [ p [ class "queue-panel__empty" ] [ text emptyText ] ]

                    entries ->
                        entries

            CompendiumDbLoading ->
                [ p [ class "queue-panel__empty" ] [ text "Loading compendium…" ] ]

            CompendiumDbFailed _ ->
                [ p [ class "queue-panel__empty" ]
                    [ text "Couldn't load the compendium — details unavailable." ]
                ]
        )


{-| Pair a queue creature with its compendium source, by id and
then by name for instances that predate compendium ids.
-}
withSource : Compendium.Db -> Creature -> Maybe ( Creature, Compendium.Creature )
withSource db c =
    (case c.creatureId of
        Just id ->
            case Compendium.find id db of
                Just hit ->
                    Just hit

                Nothing ->
                    Compendium.findByName c.name db

        Nothing ->
            Compendium.findByName c.name db
    )
        |> Maybe.map (\source -> ( c, source ))


entryHeader : Creature -> String -> Html Msg
entryHeader c meta =
    h3 [ class "queue-panel__header" ]
        [ nameNode c
        , if String.isEmpty meta then
            text ""

          else
            span [ class "queue-panel__meta" ] [ text (" — " ++ meta) ]
        ]


nameNode : Creature -> Html Msg
nameNode c =
    case c.creatureId of
        Just creatureId ->
            button
                [ class "queue-panel__name"
                , type_ "button"
                , onClick (PanelShowCreature creatureId c.name)
                , Tooltips.attr ("Pin " ++ c.name ++ "'s stat block to the side panel")
                , attribute "aria-label" ("Show stat block for " ++ c.name)
                ]
                [ text c.name ]

        Nothing ->
            span [ class "queue-panel__name queue-panel__name--plain" ]
                [ text c.name ]


item : String -> String -> Html Msg
item name body =
    div [ class "queue-panel__item" ]
        [ span [ class "queue-panel__item-name" ] [ text name ]
        , span [ class "queue-panel__item-body" ] [ text body ]
        ]
