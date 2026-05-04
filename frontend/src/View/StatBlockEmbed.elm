module View.StatBlockEmbed exposing (mockStatBlock, view)

{-| In-card / side-panel embedded stat block.

This is the placeholder stat block rendered in the right-hand
panel when no compendium creature is pinned (i.e. on first load).
The full compendium stat-block view (rendering a
`Compendium.Creature`) lives in `View.StatBlock`.

The hard-coded mock data and the ad-hoc record alias here are
holdovers from the pre-compendium MVP — they'll go away once the
panel always defaults to a compendium creature.

-}

import Dice
import Html exposing (Html, button, div, hr, p, span, strong, text)
import Html.Attributes exposing (class, title)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))


type alias StatBlock =
    { name : String
    , size : String
    , kind : String
    , alignment : String
    , armorClass : Int
    , hitPoints : String
    , speed : String
    , abilities : Abilities
    , traits : List ( String, String )
    }


type alias Abilities =
    { str : Int
    , dex : Int
    , con : Int
    , int : Int
    , wis : Int
    , cha : Int
    }


view : StatBlock -> Html Msg
view sb =
    div [ class "statblock" ]
        [ div [ class "statblock__head" ]
            [ div [ class "statblock__name" ] [ text sb.name ]
            , div [ class "statblock__type" ]
                [ text (sb.size ++ " " ++ sb.kind ++ ", " ++ sb.alignment) ]
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__meta" ]
            [ stat "AC" (String.fromInt sb.armorClass)
            , stat "HP" sb.hitPoints
            , stat "Speed" sb.speed
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "ability-row" ]
            [ ability "STR" sb.abilities.str
            , ability "DEX" sb.abilities.dex
            , ability "CON" sb.abilities.con
            , ability "INT" sb.abilities.int
            , ability "WIS" sb.abilities.wis
            , ability "CHA" sb.abilities.cha
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__traits" ]
            (List.map (trait sb.name) sb.traits)
        ]


stat : String -> String -> Html Msg
stat label value =
    div [ class "stat" ]
        [ div [ class "stat__label" ] [ text label ]
        , div [ class "stat__value" ] [ text value ]
        ]


ability : String -> Int -> Html Msg
ability label score =
    let
        modifier =
            (score - 10) // 2
    in
    div [ class "ability" ]
        [ div [ class "ability__label" ] [ text label ]
        , div [ class "ability__value" ] [ text (String.fromInt score) ]
        , div [ class "ability__mod" ] [ text ("(" ++ signed modifier ++ ")") ]
        ]


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


trait : String -> ( String, String ) -> Html Msg
trait creatureName ( name, body ) =
    p []
        (strong [] [ text (name ++ ". ") ]
            :: List.map (segment creatureName) (Dice.scan body)
        )


{-| Render one segment of scanned trait body. `Literal` runs render
as plain text; `DiceLink` segments render as clickable inline buttons
that fire a roll via the dice modal. `creatureName` is threaded
through so the resulting roll's `source` records which stat block
the formula came from.
-}
segment : String -> Dice.Segment -> Html Msg
segment creatureName seg =
    case seg of
        Dice.Literal s ->
            text s

        Dice.DiceLink shown expr ->
            button
                [ class "dice-link"
                , onClick (RollFromStatBlock creatureName expr)
                , title ("Roll " ++ shown)
                ]
                [ text shown ]


mockStatBlock : StatBlock
mockStatBlock =
    { name = "Brakka, Ogre Brute"
    , size = "Large"
    , kind = "giant"
    , alignment = "chaotic evil"
    , armorClass = 11
    , hitPoints = "59 (7d10 + 21)"
    , speed = "40 ft."
    , abilities =
        { str = 19
        , dex = 8
        , con = 16
        , int = 5
        , wis = 7
        , cha = 7
        }
    , traits =
        [ ( "Multiattack", "Brakka makes two greatclub attacks, or one greatclub attack and one javelin attack." )
        , ( "Greatclub", "Melee Weapon Attack: +6 to hit, reach 5 ft. Hit: 13 (2d8 + 4) bludgeoning damage." )
        , ( "Javelin", "Melee or Ranged Weapon Attack: +6 to hit, reach 5 ft. or range 30/120 ft. Hit: 11 (2d6 + 4) piercing damage." )
        , ( "Reckless", "At the start of its turn, Brakka can gain advantage on all melee weapon attack rolls during that turn, but attack rolls against it have advantage until the start of its next turn." )
        , ( "Brutish Charge", "If Brakka moves at least 10 feet straight toward a target and then hits it with a greatclub attack on the same turn, the target takes an extra 9 (2d8) bludgeoning damage and must succeed on a DC 14 Strength saving throw or be knocked prone." )
        , ( "Furious Roar", "Brakka unleashes a guttural roar. Each creature within 30 feet that can hear it must make a DC 13 Wisdom saving throw or be frightened until the end of Brakka's next turn." )
        , ( "Thick Hide", "Brakka has resistance to bludgeoning, piercing, and slashing damage from nonmagical attacks not made with silvered weapons." )
        ]
    }
