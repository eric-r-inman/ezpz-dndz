module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Json.Decode as Decode
import Url exposing (Url)
import Url.Parser exposing (Parser, oneOf, top)



-- ROUTING


type Route
    = Home
    | Me
    | NotFound


routeParser : Parser (Route -> a) a
routeParser =
    oneOf
        [ Url.Parser.map Home top
        , Url.Parser.map Me (Url.Parser.s "me")
        ]


routeFromUrl : Url -> Route
routeFromUrl url =
    Url.Parser.parse routeParser url
        |> Maybe.withDefault NotFound



-- MODEL


type alias MeInfo =
    { name : String
    , authEnabled : Bool
    }


type MeStatus
    = Loading
    | Loaded MeInfo
    | Failed


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    }


type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | GotMe (Result Http.Error MeInfo)


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


init : () -> Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            routeFromUrl url
    in
    ( { key = key, url = url, route = route, me = Loading }
    , cmdForRoute route
    )


cmdForRoute : Route -> Cmd Msg
cmdForRoute route =
    case route of
        Me ->
            fetchMe

        _ ->
            Cmd.none


fetchMe : Cmd Msg
fetchMe =
    Http.get
        { url = "/me"
        , expect = Http.expectJson GotMe meDecoder
        }


meDecoder : Decode.Decoder MeInfo
meDecoder =
    Decode.map2 MeInfo
        (Decode.field "name" Decode.string)
        (Decode.field "auth_enabled" Decode.bool)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlRequested (Browser.Internal url) ->
            ( model, Nav.pushUrl model.key (Url.toString url) )

        UrlRequested (Browser.External url) ->
            ( model, Nav.load url )

        UrlChanged url ->
            let
                route =
                    routeFromUrl url
            in
            ( { model | url = url, route = route, me = Loading }
            , cmdForRoute route
            )

        GotMe result ->
            case result of
                Ok info ->
                    ( { model | me = Loaded info }, Cmd.none )

                Err _ ->
                    ( { model | me = Failed }, Cmd.none )



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "EZPZ-DnDZ"
    , body =
        [ div [ class "app-shell" ]
            [ viewAppBar
            , viewPage model
            ]
        ]
    }


viewAppBar : Html Msg
viewAppBar =
    header [ class "app-bar" ]
        [ div [ class "app-bar__brand" ]
            [ div [ class "app-bar__mark" ] [ text "d20" ]
            , div [ class "app-bar__title" ] [ text "EZPZ-DnDZ" ]
            ]
        , nav [ class "app-bar__nav" ]
            [ a [ href "/" ] [ text "Encounter" ]
            , a [ href "/me" ] [ text "Me" ]
            , a [ href "/scalar" ] [ text "API" ]
            ]
        ]


viewPage : Model -> Html Msg
viewPage model =
    case model.route of
        Home ->
            viewWorkspace

        Me ->
            div [ class "workspace" ]
                [ section [ class "panel panel--main" ]
                    [ div [ class "panel__header" ]
                        [ div [ class "panel__title" ] [ text "Account" ] ]
                    , div [ class "panel__body" ] [ viewMe model.me ]
                    ]
                ]

        NotFound ->
            div [ class "workspace" ]
                [ section [ class "panel panel--main" ]
                    [ div [ class "panel__header" ]
                        [ div [ class "panel__title" ] [ text "Not Found" ] ]
                    , div [ class "panel__body" ]
                        [ p [ class "empty" ]
                            [ text "The page you requested does not exist." ]
                        ]
                    ]
                ]


viewMe : MeStatus -> Html Msg
viewMe status =
    case status of
        Loading ->
            p [ class "empty" ] [ text "Loading…" ]

        Failed ->
            p [ class "empty" ] [ text "Failed to load user information." ]

        Loaded info ->
            div []
                [ h2 [] [ text info.name ]
                , p []
                    [ text
                        ("Authentication: "
                            ++ (if info.authEnabled then
                                    "enabled"

                                else
                                    "disabled"
                               )
                        )
                    ]
                ]



-- WORKSPACE (mock)


viewWorkspace : Html Msg
viewWorkspace =
    main_ [ class "workspace" ]
        [ viewPanelMain
        , viewPanelControls
        , viewPanelDetail
        ]


viewPanelMain : Html Msg
viewPanelMain =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ viewEncounterBar ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (viewCreatureCard mockSelectedName) mockCreatures)
            ]
        ]


viewEncounterBar : Html Msg
viewEncounterBar =
    div [ class "encounter-bar" ]
        [ div [ class "encounter-bar__group" ]
            [ span
                [ class "encounter-bar__info"
                , title "from file: "
                , attribute "aria-label" "Encounter file"
                , tabindex 0
                ]
                [ text "ⓘ" ]
            , span [ class "encounter-bar__round" ] [ text "Round X" ]
            , span [ class "encounter-bar__sep" ] [ text "|" ]
            , span [ class "encounter-bar__active" ] [ text "Creature Name" ]
            , span [ class "encounter-bar__hp" ] [ text "100/100" ]
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , div [ class "encounter-bar__states" ]
                [ span [ class "encounter-bar__state", title "State 1 (placeholder)" ] [ text "✊" ]
                , span [ class "encounter-bar__state", title "State 2 (placeholder)" ] [ text "◕" ]
                , span [ class "encounter-bar__state", title "State 3 (placeholder)" ] [ text "🧠" ]
                , span [ class "encounter-bar__state", title "State 4 (placeholder)" ] [ text "🪽" ]
                ]
            ]
        , div [ class "encounter-bar__group encounter-bar__right" ]
            [ span [ class "encounter-bar__xp" ] [ text "93,000 XP" ]
            , span [ class "encounter-bar__xp-lair" ] [ text "(115,200 w/Lair)" ]
            , viewXpFilter
            ]
        ]


viewXpFilter : Html Msg
viewXpFilter =
    details [ class "xp-filter" ]
        [ summary
            [ class "xp-filter__summary"
            , attribute "aria-label" "Filter XP total"
            , title "Filter XP total"
            ]
            [ text "▾" ]
        , ul [ class "xp-filter__menu" ]
            [ li
                [ class "xp-filter__item"
                , attribute "aria-selected" "true"
                ]
                [ text "Enemies & NPCs" ]
            , li [ class "xp-filter__item" ] [ text "Enemies Only" ]
            , li [ class "xp-filter__item" ] [ text "NPCs Only" ]
            , li [ class "xp-filter__item" ] [ text "Selected Only" ]
            ]
        ]


viewPanelControls : Html Msg
viewPanelControls =
    section [ class "panel panel--controls" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Encounter Controls" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid btn-grid--two-rows" ]
                [ button [ class "btn btn--primary" ] [ text "Add Monster" ]
                , button [ class "btn" ] [ text "Roll Initiative" ]
                , button [ class "btn" ] [ text "Next Turn" ]
                , button [ class "btn" ] [ text "Save" ]
                , button [ class "btn" ] [ text "Load" ]
                , button [ class "btn btn--ghost" ] [ text "Reset" ]
                ]
            ]
        ]


viewPanelDetail : Html Msg
viewPanelDetail =
    section [ class "panel panel--detail" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Selected Stat Block" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid" ]
                [ button [ class "btn btn--danger" ] [ text "Damage" ]
                , button [ class "btn btn--success" ] [ text "Heal" ]
                , button [ class "btn" ] [ text "Condition" ]
                ]
            , viewStatBlock mockStatBlock
            ]
        ]



-- MOCK DATA TYPES


type alias Creature =
    { name : String
    , kind : String
    , initiative : Int
    , currentHp : Int
    , maxHp : Int
    , armorClass : Int
    , speed : Int
    , conditions : List String
    , selected : Bool
    }


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


mockSelectedName : String
mockSelectedName =
    "Brakka, Ogre Brute"


mockCreatures : List Creature
mockCreatures =
    [ { name = "Lyra Vale (PC)"
      , kind = "Half-elf rogue, lvl 5"
      , initiative = 22
      , currentHp = 38
      , maxHp = 42
      , armorClass = 16
      , speed = 30
      , conditions = [ "Hidden" ]
      , selected = False
      }
    , { name = "Brakka, Ogre Brute"
      , kind = "Large giant, chaotic evil"
      , initiative = 18
      , currentHp = 27
      , maxHp = 59
      , armorClass = 11
      , speed = 40
      , conditions = [ "Bloodied", "Frightened" ]
      , selected = True
      }
    , { name = "Goblin Skirmisher"
      , kind = "Small humanoid, neutral evil"
      , initiative = 15
      , currentHp = 7
      , maxHp = 7
      , armorClass = 15
      , speed = 30
      , conditions = []
      , selected = False
      }
    , { name = "Goblin Boss"
      , kind = "Small humanoid, neutral evil"
      , initiative = 12
      , currentHp = 21
      , maxHp = 21
      , armorClass = 17
      , speed = 30
      , conditions = []
      , selected = False
      }
    , { name = "Thornwhip Shaman"
      , kind = "Small humanoid, druid"
      , initiative = 9
      , currentHp = 4
      , maxHp = 27
      , armorClass = 13
      , speed = 30
      , conditions = [ "Concentrating" ]
      , selected = True
      }
    ]


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
        [ ( "Greatclub", "Melee Weapon Attack: +6 to hit, reach 5 ft. Hit: 13 (2d8 + 4) bludgeoning damage." )
        , ( "Javelin", "Melee or Ranged: +6 to hit, reach 5 ft. or range 30/120 ft. Hit: 11 (2d6 + 4) piercing." )
        ]
    }



-- CREATURE CARD


viewCreatureCard : String -> Creature -> Html Msg
viewCreatureCard activeName creature =
    let
        isActive =
            creature.name == activeName

        cardClass =
            if isActive then
                "creature-card creature-card--active"

            else
                "creature-card"
    in
    article [ class cardClass ]
        [ div [ class "creature-card__rail creature-card__rail--left" ]
            [ div [ class "creature-card__rail-group" ]
                [ input
                    [ type_ "checkbox"
                    , class "creature-card__select"
                    , checked creature.selected
                    , attribute "aria-label" ("Select " ++ creature.name)
                    ]
                    []
                , button
                    [ class "icon-btn"
                    , title "Move up in initiative"
                    , attribute "aria-label" "Move up"
                    ]
                    [ text "↑" ]
                , button
                    [ class "icon-btn"
                    , title "Move down in initiative"
                    , attribute "aria-label" "Move down"
                    ]
                    [ text "↓" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--accent"
                    , title "Make active creature"
                    , attribute "aria-label" "Make active"
                    ]
                    [ text "→" ]
                ]
            ]
        , div [ class "creature-card__center" ]
            [ div [ class "creature-card__row" ] [ text "row 1 — to be mocked" ]
            , div [ class "creature-card__row" ] [ text "row 2 — to be mocked" ]
            , div [ class "creature-card__row" ] [ text "row 3 — to be mocked" ]
            ]
        , div [ class "creature-card__rail creature-card__rail--right" ]
            [ div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn icon-btn--danger"
                    , title "Remove from queue"
                    , attribute "aria-label" "Remove"
                    ]
                    [ text "×" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn"
                    , title "Convert to minion"
                    , attribute "aria-label" "Convert to minion"
                    ]
                    [ text "👿" ]
                , button
                    [ class "icon-btn"
                    , title "Duplicate creature"
                    , attribute "aria-label" "Duplicate"
                    ]
                    [ text "⧉" ]
                ]
            ]
        ]


viewStat : String -> String -> Html Msg
viewStat label value =
    div [ class "stat" ]
        [ div [ class "stat__label" ] [ text label ]
        , div [ class "stat__value" ] [ text value ]
        ]


signed : Int -> String
signed n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n



-- STAT BLOCK


viewStatBlock : StatBlock -> Html Msg
viewStatBlock sb =
    div [ class "statblock" ]
        [ div [ class "statblock__head" ]
            [ div [ class "statblock__name" ] [ text sb.name ]
            , div [ class "statblock__type" ]
                [ text (sb.size ++ " " ++ sb.kind ++ ", " ++ sb.alignment) ]
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__meta" ]
            [ viewStat "AC" (String.fromInt sb.armorClass)
            , viewStat "HP" sb.hitPoints
            , viewStat "Speed" sb.speed
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "ability-row" ]
            [ viewAbility "STR" sb.abilities.str
            , viewAbility "DEX" sb.abilities.dex
            , viewAbility "CON" sb.abilities.con
            , viewAbility "INT" sb.abilities.int
            , viewAbility "WIS" sb.abilities.wis
            , viewAbility "CHA" sb.abilities.cha
            ]
        , hr [ class "statblock__divider" ] []
        , div [ class "statblock__traits" ]
            (List.map viewTrait sb.traits)
        ]


viewAbility : String -> Int -> Html Msg
viewAbility label score =
    let
        modifier =
            (score - 10) // 2
    in
    div [ class "ability" ]
        [ div [ class "ability__label" ] [ text label ]
        , div [ class "ability__value" ] [ text (String.fromInt score) ]
        , div [ class "ability__mod" ] [ text ("(" ++ signed modifier ++ ")") ]
        ]


viewTrait : ( String, String ) -> Html Msg
viewTrait ( name, body ) =
    p []
        [ strong [] [ text (name ++ ". ") ]
        , text body
        ]
