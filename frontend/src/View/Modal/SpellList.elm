module View.Modal.SpellList exposing (view)

{-| Read-only "what spells are in this encounter?" popup.

Triggered by the 📜 icon in the encounter title bar. Walks the
encounter queue, looks each creature up in the compendium, and
prints every caster's at-will / per-day / slot spells in one
scannable list grouped by creature.

Creatures with no `spellcasting` block are skipped. When no
caster is in the queue at all, an empty-state line tells the GM
so they don't think the modal is broken.

@docs view

-}

import Compendium exposing (Ability(..), InnatePerDay, SpellSlotLevel, Spellcasting)
import Encounter exposing (Creature, Encounter)
import Html exposing (Html, button, div, h3, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just ModalSpellList ->
            View.Modal.view
                { close = SpellListClose
                , noOp = NoOp
                , title = "Spells in encounter"
                , extraClass = "modal--spell-list"
                , chrome = model.modalChrome
                , body = body model
                }

        _ ->
            text ""


body : Model -> List (Html Msg)
body model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                casters =
                    model.encounter.creatures
                        |> List.filterMap (resolveCaster db)
            in
            if List.isEmpty casters then
                [ p [ class "spell-list__empty" ]
                    [ text "No spellcasters in this encounter."
                    , text " Creatures need a Spellcasting block in the compendium to appear here."
                    ]
                ]

            else
                List.map casterSection casters

        CompendiumDbLoading ->
            [ p [ class "spell-list__empty" ]
                [ text "Loading compendium…" ]
            ]

        CompendiumDbFailed _ ->
            [ p [ class "spell-list__empty" ]
                [ text "Couldn't load the compendium — spells unavailable." ]
            ]


{-| Pair a queue entry with its compendium Spellcasting block, or
drop it. Falls back to name lookup the same way the rest of the
app does, so paste-in creatures whose `creatureId` drifted out of
sync still resolve.
-}
resolveCaster :
    Compendium.Db
    -> Creature
    ->
        Maybe
            { creature : Creature
            , spellcasting : Spellcasting
            }
resolveCaster db c =
    let
        lookup =
            case c.creatureId of
                Just id ->
                    case Compendium.find id db of
                        Just hit ->
                            Just hit

                        Nothing ->
                            Compendium.findByName c.name db

                Nothing ->
                    Compendium.findByName c.name db
    in
    case Maybe.andThen .spellcasting lookup of
        Just sc ->
            Just { creature = c, spellcasting = sc }

        Nothing ->
            Nothing


casterSection :
    { creature : Creature, spellcasting : Spellcasting }
    -> Html Msg
casterSection { creature, spellcasting } =
    div [ class "spell-list__caster" ]
        [ casterHeader creature spellcasting
        , spellGroups spellcasting
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
            -- Save DC and attack bonus only render when the
            -- creature actually has them; spell-attack-only casters
            -- (and at-will-only ones) shouldn't get a `+0` or
            -- `DC 0` slug.
            List.filterMap identity
                [ if sc.saveDc > 0 then
                    Just ("DC " ++ String.fromInt sc.saveDc)

                  else
                    Nothing
                , if sc.attackBonus /= 0 then
                    Just (signed sc.attackBonus ++ " to hit")

                  else
                    Nothing
                ]

        meta =
            abilityLabel sc.ability
                :: bits
                |> String.join " · "
    in
    h3 [ class "spell-list__caster-header" ]
        [ nameNode
        , span [ class "spell-list__meta" ] [ text (" — " ++ meta) ]
        ]


spellGroups : Spellcasting -> Html Msg
spellGroups sc =
    let
        groups =
            List.concat
                [ atWillGroup sc.atWill
                , innateGroups sc.innatePerDay
                , slotGroups sc.slots
                ]
    in
    if List.isEmpty groups then
        p [ class "spell-list__empty-spells" ]
            [ text "(no spell list parsed for this creature)" ]

    else
        div [ class "spell-list__groups" ] groups


atWillGroup : List String -> List (Html Msg)
atWillGroup spells =
    if List.isEmpty spells then
        []

    else
        [ spellGroup "At will" spells ]


innateGroups : List InnatePerDay -> List (Html Msg)
innateGroups =
    List.map
        (\g ->
            spellGroup
                (String.fromInt g.uses ++ "/day each")
                g.spells
        )


slotGroups : List SpellSlotLevel -> List (Html Msg)
slotGroups =
    List.map
        (\g ->
            spellGroup
                (slotLabel g.level g.slots)
                g.spells
        )


spellGroup : String -> List String -> Html Msg
spellGroup label spells =
    div [ class "spell-list__group" ]
        [ div [ class "spell-list__group-label" ] [ text label ]
        , ul [ class "spell-list__spells" ]
            (List.map
                (\s -> li [ class "spell-list__spell" ] [ text s ])
                spells
            )
        ]


slotLabel : Int -> Int -> String
slotLabel level slots =
    let
        levelText =
            if level == 0 then
                "Cantrips (at will)"

            else
                ordinal level ++ " level (" ++ String.fromInt slots ++ " slot" ++ plural slots ++ ")"
    in
    levelText


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
