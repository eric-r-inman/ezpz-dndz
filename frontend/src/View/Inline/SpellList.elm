module View.Inline.SpellList exposing (view)

{-| Read-only "what spells are in this encounter?" panel, docked
under the queue's spellcaster strip.

Walks the encounter queue through `Compendium.Casters` and
prints every caster's at-will / per-day / slot spells in one
scannable list grouped by creature. When no caster is in the
queue at all, an empty-state line tells the GM so they don't
think the panel is broken.

@docs view

-}

import Compendium exposing (Ability(..), Spellcasting)
import Compendium.Casters as Casters exposing (CasterSummary)
import Encounter exposing (Creature, Encounter)
import Html exposing (Html, button, div, h3, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Tooltips as Tooltips


view : Encounter -> CompendiumDb -> Html Msg
view enc compendiumDb =
    div [ class "spell-list-panel" ] (body enc compendiumDb)


body : Encounter -> CompendiumDb -> List (Html Msg)
body enc compendiumDb =
    case compendiumDb of
        CompendiumDbLoaded db ->
            let
                casters =
                    enc.creatures
                        |> List.filterMap (Casters.resolve db)
            in
            if List.isEmpty casters then
                [ p [ class "spell-list__empty" ]
                    [ text "No spellcasters in this encounter." ]
                ]

            else
                List.map casterSection casters

        CompendiumDbLoading ->
            [ p [ class "spell-list__empty" ] [ text "Loading compendium…" ] ]

        CompendiumDbFailed _ ->
            [ p [ class "spell-list__empty" ]
                [ text "Couldn't load the compendium — spells unavailable." ]
            ]



-- ── View ──────────────────────────────────────────────────────────


casterSection : CasterSummary -> Html Msg
casterSection { creature, spellcasting } =
    div [ class "spell-list__caster" ]
        [ casterHeader creature spellcasting
        , spellGroupList (spellGroupsFor spellcasting)
        ]


casterHeader : Creature -> Spellcasting -> Html Msg
casterHeader c sc =
    let
        nameNode =
            case c.creatureId of
                Just creatureId ->
                    button
                        [ class "spell-list__name"
                        , type_ "button"
                        , onClick (PanelShowCreature creatureId c.name)
                        , Tooltips.attr ("Pin " ++ c.name ++ "'s stat block to the side panel")
                        , attribute "aria-label"
                            ("Show stat block for " ++ c.name)
                        ]
                        [ text c.name ]

                Nothing ->
                    span [ class "spell-list__name spell-list__name--plain" ]
                        [ text c.name ]

        bits =
            List.filterMap identity
                [ Just (abilityLabel sc.ability)
                , if sc.saveDc > 0 then
                    Just ("DC " ++ String.fromInt sc.saveDc)

                  else
                    Nothing
                , if sc.attackBonus /= 0 then
                    Just (signed sc.attackBonus ++ " to hit")

                  else
                    Nothing
                ]

        metaSuffix =
            if List.isEmpty bits then
                text ""

            else
                span [ class "spell-list__meta" ]
                    [ text (" — " ++ String.join " · " bits) ]
    in
    h3 [ class "spell-list__caster-header" ]
        [ nameNode, metaSuffix ]


spellGroupList : List SpellGroup -> Html Msg
spellGroupList groups =
    if List.isEmpty groups then
        p [ class "spell-list__empty-spells" ]
            [ text "(no spell list parsed for this creature)" ]

    else
        div [ class "spell-list__groups" ] (List.concatMap renderGroup groups)


{-| A group contributes its heading and its spells as two cells
of the caster's shared grid rather than nesting its own, so
every heading in that caster's block ends at one column edge.
-}
renderGroup : SpellGroup -> List (Html Msg)
renderGroup g =
    [ div [ class "spell-list__group-label" ] [ text g.label ]
    , ul [ class "spell-list__spells" ]
        (List.map
            (\s -> li [ class "spell-list__spell" ] [ text s ])
            g.spells
        )
    ]


type alias SpellGroup =
    { label : String, spells : List String }


spellGroupsFor : Spellcasting -> List SpellGroup
spellGroupsFor sc =
    let
        atWill =
            if List.isEmpty sc.atWill then
                []

            else
                [ { label = "At will", spells = sc.atWill } ]

        innate =
            List.map
                (\g ->
                    { label = String.fromInt g.uses ++ "/day each"
                    , spells = g.spells
                    }
                )
                sc.innatePerDay

        slots =
            List.map
                (\g ->
                    { label = slotLabel g.level g.slots
                    , spells = g.spells
                    }
                )
                sc.slots
    in
    atWill ++ innate ++ slots


slotLabel : Int -> Int -> String
slotLabel level slots =
    if level == 0 then
        "Cantrips (at will)"

    else
        ordinal level ++ " level (" ++ String.fromInt slots ++ " slot" ++ plural slots ++ ")"


plural : Int -> String
plural n =
    if n == 1 then
        ""

    else
        "s"


ordinal : Int -> String
ordinal n =
    case n of
        1 ->
            "1st"

        2 ->
            "2nd"

        3 ->
            "3rd"

        _ ->
            String.fromInt n ++ "th"


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


abilityLabel : Ability -> String
abilityLabel a =
    case a of
        Str ->
            "STR"

        Dex ->
            "DEX"

        Con ->
            "CON"

        Int_ ->
            "INT"

        Wis ->
            "WIS"

        Cha ->
            "CHA"
