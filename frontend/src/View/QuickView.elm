module View.QuickView exposing (view)

{-| The quick view: a column beside the queue listing each
creature's name and hit points, and nothing else, so the GM can
see at a glance who is still in the fight.

A name struck through in red is down or dead; struck through in
grey, still standing but held by a condition. Clicking a name
scrolls the queue to that creature's card.

@docs view

-}

import Encounter exposing (Creature, Encounter, Standing(..))
import Html exposing (Html, button, div, section, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.QuickView exposing (QuickViewUi)
import View.Card
import View.Tooltips as Tooltips


view : QuickViewUi -> Encounter -> Html Msg
view ui enc =
    let
        listed =
            if ui.enemiesOnly then
                List.filter Encounter.isEnemy enc.creatures

            else
                enc.creatures
    in
    section [ class "panel panel--quick-view" ]
        [ div [ class "panel__header" ]
            [ span [ class "panel__title" ] [ text "Quick view" ]
            , filterToggle ui.enemiesOnly
            ]
        , div [ class "panel__body quick-view__body" ]
            (if List.isEmpty listed then
                [ div [ class "quick-view__empty" ]
                    [ text
                        (if ui.enemiesOnly then
                            "No enemies in the queue."

                         else
                            "No creatures in the queue."
                        )
                    ]
                ]

             else
                List.map row listed
            )
        ]


{-| Switches the list between every creature and the enemies alone,
wearing the open-editor ring while it lists the enemies alone. The
tooltip names the list a click will show.

A label that followed the tooltip would have a screen reader
announce "All creatures, pressed" while the list shows the enemies
alone, so the label names the switch and `aria-pressed` carries its
state.

-}
filterToggle : Bool -> Html Msg
filterToggle enemiesOnly =
    button
        [ class (View.Card.editorTriggerClass "quick-view__filter" enemiesOnly)
        , type_ "button"
        , onClick QuickViewEnemiesOnlyToggle
        , Tooltips.attr
            (if enemiesOnly then
                Tooltips.quickViewAllCreatures

             else
                Tooltips.quickViewEnemiesOnly
            )
        , attribute "aria-label" Tooltips.quickViewEnemiesOnly
        , attribute "aria-pressed"
            (if enemiesOnly then
                "true"

             else
                "false"
            )
        ]
        [ text "👁️" ]


row : Creature -> Html Msg
row creature =
    div [ class "quick-view__row" ]
        [ button
            [ class (nameClass (Encounter.standing creature))
            , type_ "button"
            , onClick (ScrollCardIntoView creature.name)
            , Tooltips.attr (Tooltips.queueScrollTo creature.name)
            , attribute "aria-label" (Tooltips.queueScrollTo creature.name)
            ]
            [ text creature.name ]
        , hitPoints creature
        ]


nameClass : Standing -> String
nameClass standing =
    case standing of
        Fighting ->
            "quick-view__name"

        Held ->
            "quick-view__name quick-view__name--held"

        Down ->
            "quick-view__name quick-view__name--down"


{-| Current over maximum, and any temporary hit points after them,
in the colours the card uses for the same numbers.
-}
hitPoints : Creature -> Html Msg
hitPoints creature =
    span [ class "hp-display quick-view__hp" ]
        [ span
            [ class
                (if creature.bloodied then
                    "hp-display__current hp-display__current--bloodied"

                 else
                    "hp-display__current"
                )
            ]
            [ text (String.fromInt creature.currentHp) ]
        , span [ class "hp-display__sep" ] [ text "/" ]
        , span [ class "hp-display__max" ] [ text (String.fromInt creature.maxHp) ]
        , if creature.tempHp > 0 then
            span [ class "hp-display__temp", Tooltips.attr Tooltips.tempHp ]
                [ text ("+" ++ String.fromInt creature.tempHp) ]

          else
            text ""
        ]
