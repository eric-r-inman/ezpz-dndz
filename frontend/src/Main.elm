module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
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
    , creatures : List Creature
    }


type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | GotMe (Result Http.Error MeInfo)
    | ToggleSurprised String
    | CycleCover String
    | ToggleConcentration String
    | ToggleHiding String
    | ToggleFlying String
    | AdjustFlyHeight String Int
    | ToggleDeathSave String Int
    | ToggleHolding String


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
    ( { key = key
      , url = url
      , route = route
      , me = Loading
      , creatures = initialCreatures
      }
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

        ToggleSurprised name ->
            ( mapCreature name (\c -> { c | surprised = not c.surprised }) model
            , Cmd.none
            )

        CycleCover name ->
            ( mapCreature name (\c -> { c | cover = nextCover c.cover }) model
            , Cmd.none
            )

        ToggleConcentration name ->
            ( mapCreature name (\c -> { c | concentrating = not c.concentrating }) model
            , Cmd.none
            )

        ToggleHiding name ->
            ( mapCreature name (\c -> { c | hiding = not c.hiding }) model
            , Cmd.none
            )

        ToggleFlying name ->
            ( mapCreature name (\c -> { c | flying = not c.flying }) model
            , Cmd.none
            )

        AdjustFlyHeight name delta ->
            ( mapCreature name (\c -> { c | flyHeight = Basics.max 0 (c.flyHeight + delta) }) model
            , Cmd.none
            )

        ToggleDeathSave name idx ->
            ( mapCreature name (\c -> { c | deathSaves = toggleSlot idx c.deathSaves }) model
            , Cmd.none
            )

        ToggleHolding name ->
            ( mapCreature name (\c -> { c | holding = not c.holding }) model
            , Cmd.none
            )


mapCreature : String -> (Creature -> Creature) -> Model -> Model
mapCreature name fn model =
    let
        apply c =
            if c.name == name then
                fn c

            else
                c
    in
    { model | creatures = List.map apply model.creatures }


nextCover : Cover -> Cover
nextCover c =
    case c of
        NoCover ->
            HalfCover

        HalfCover ->
            ThreeQuartersCover

        ThreeQuartersCover ->
            FullCover

        FullCover ->
            NoCover


toggleSlot : Int -> ( Bool, Bool, Bool ) -> ( Bool, Bool, Bool )
toggleSlot idx ( a, b, c ) =
    case idx of
        0 ->
            ( not a, b, c )

        1 ->
            ( a, not b, c )

        _ ->
            ( a, b, not c )



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
            viewWorkspace model

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


viewWorkspace : Model -> Html Msg
viewWorkspace model =
    main_ [ class "workspace" ]
        [ viewPanelMain model.creatures
        , viewPanelControls
        , viewPanelDetail
        ]


viewPanelMain : List Creature -> Html Msg
viewPanelMain creatures =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ viewEncounterBar ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (viewCreatureCard mockSelectedName) creatures)
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
            [ div [ class "panel__title" ] [ text "Encounter Controls" ]
            , button
                [ class "action-btn action-btn--green"
                , title "Roll dice"
                , attribute "aria-label" "Roll dice"
                ]
                [ text "🎲 Roll" ]
            ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid btn-grid--two-rows" ]
                [ button [ class "action-btn action-btn--blue" ] [ text "➕ Add Creature" ]
                , button [ class "action-btn action-btn--blue" ] [ text "💾 Save" ]
                , button [ class "action-btn action-btn--blue" ] [ text "📁 Load" ]
                , button [ class "action-btn action-btn--green" ] [ text "⏭ Next Turn" ]
                , button [ class "action-btn action-btn--orange" ] [ text "⟲ Reset" ]
                , button [ class "action-btn action-btn--red" ] [ text "🗑 Clear" ]
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


type Cover
    = NoCover
    | HalfCover
    | ThreeQuartersCover
    | FullCover


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
    , surprised : Bool
    , cover : Cover
    , concentrating : Bool
    , hiding : Bool
    , flying : Bool
    , flyHeight : Int
    , bloodied : Bool
    , inDeathSaves : Bool
    , deathSaves : ( Bool, Bool, Bool )
    , holding : Bool
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


initialCreatures : List Creature
initialCreatures =
    [ { name = "Lyra Vale (PC)"
      , kind = "Half-elf rogue, lvl 5"
      , initiative = 22
      , currentHp = 38
      , maxHp = 42
      , armorClass = 16
      , speed = 30
      , conditions = [ "Hidden" ]
      , selected = False
      , surprised = False
      , cover = HalfCover
      , concentrating = False
      , hiding = True
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = True
      , deathSaves = ( True, False, False )
      , holding = False
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
      , surprised = True
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
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
      , surprised = False
      , cover = ThreeQuartersCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
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
      , surprised = False
      , cover = FullCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = True
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
      , surprised = False
      , cover = NoCover
      , concentrating = True
      , hiding = False
      , flying = True
      , flyHeight = 30
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Captain Vex"
      , kind = "Medium humanoid (human), bandit captain"
      , initiative = 17
      , currentHp = 34
      , maxHp = 65
      , armorClass = 15
      , speed = 30
      , conditions = []
      , selected = False
      , surprised = False
      , cover = NoCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = True
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = True
      }
    , { name = "Stone Sentinel"
      , kind = "Large construct, unaligned"
      , initiative = 8
      , currentHp = 78
      , maxHp = 78
      , armorClass = 18
      , speed = 25
      , conditions = []
      , selected = False
      , surprised = False
      , cover = HalfCover
      , concentrating = False
      , hiding = False
      , flying = False
      , flyHeight = 0
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
      }
    , { name = "Shadow Wisp"
      , kind = "Tiny undead, neutral evil"
      , initiative = 6
      , currentHp = 12
      , maxHp = 18
      , armorClass = 12
      , speed = 0
      , conditions = []
      , selected = False
      , surprised = False
      , cover = NoCover
      , concentrating = False
      , hiding = True
      , flying = True
      , flyHeight = 15
      , bloodied = False
      , inDeathSaves = False
      , deathSaves = ( False, False, False )
      , holding = False
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
        [ ( "Multiattack", "Brakka makes two greatclub attacks, or one greatclub attack and one javelin attack." )
        , ( "Greatclub", "Melee Weapon Attack: +6 to hit, reach 5 ft. Hit: 13 (2d8 + 4) bludgeoning damage." )
        , ( "Javelin", "Melee or Ranged Weapon Attack: +6 to hit, reach 5 ft. or range 30/120 ft. Hit: 11 (2d6 + 4) piercing damage." )
        , ( "Reckless", "At the start of its turn, Brakka can gain advantage on all melee weapon attack rolls during that turn, but attack rolls against it have advantage until the start of its next turn." )
        , ( "Brutish Charge", "If Brakka moves at least 10 feet straight toward a target and then hits it with a greatclub attack on the same turn, the target takes an extra 9 (2d8) bludgeoning damage and must succeed on a DC 14 Strength saving throw or be knocked prone." )
        , ( "Furious Roar", "Brakka unleashes a guttural roar. Each creature within 30 feet that can hear it must make a DC 13 Wisdom saving throw or be frightened until the end of Brakka's next turn." )
        , ( "Thick Hide", "Brakka has resistance to bludgeoning, piercing, and slashing damage from nonmagical attacks not made with silvered weapons." )
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
            [ viewCardRowTop creature
            , viewCardRowMid creature
            , viewCardRowBot creature
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


viewCardRowTop : Creature -> Html Msg
viewCardRowTop creature =
    div [ class "creature-card__row creature-card__row--top" ]
        [ span
            [ class "init-circle"
            , title ("Initiative roll: " ++ String.fromInt creature.initiative)
            ]
            [ text (String.fromInt creature.initiative) ]
        , viewSurprisedToggle creature
        , span [ class "creature-name creature-name--default" ]
            [ text creature.name ]
        , button
            [ class "icon-btn icon-btn--sm"
            , title "Edit note"
            , attribute "aria-label" "Edit note"
            ]
            [ text "✏️" ]
        , span [ class "ac-readout" ]
            [ text ("AC: " ++ String.fromInt creature.armorClass) ]
        , span [ class "condition-list" ]
            [ span [ class "condition-list__item" ] [ text "Paralyzed" ]
            , span [ class "condition-list__sep" ] [ text "|" ]
            , span [ class "condition-list__item" ] [ text "Poisoned" ]
            ]
        ]


viewSurprisedToggle : Creature -> Html Msg
viewSurprisedToggle creature =
    let
        ( emoji, label ) =
            if creature.surprised then
                ( "😲", "Surprised — click for normal" )

            else
                ( "😠", "Normal — click for surprised" )
    in
    button
        [ class "surprise-btn"
        , onClick (ToggleSurprised creature.name)
        , title label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if creature.surprised then
                "true"

             else
                "false"
            )
        ]
        [ text emoji ]


viewCardRowMid : Creature -> Html Msg
viewCardRowMid creature =
    div [ class "creature-card__row creature-card__row--mid" ]
        [ viewHpDisplay
        , viewBloodied creature
        , viewDeathSaves creature
        , viewCoverToggle creature
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "🧠"
            "concentrating"
            creature.concentrating
            (ToggleConcentration creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "👤"
            "hiding"
            creature.hiding
            (ToggleHiding creature.name)
        , span [ class "status-toggles__sep" ] [ text "|" ]
        , viewBoolToggle "🪽"
            "flying"
            creature.flying
            (ToggleFlying creature.name)
        , viewFlyHeight creature
        ]


viewHpDisplay : Html Msg
viewHpDisplay =
    span [ class "hp-display" ]
        [ span [ class "hp-display__current" ] [ text "100" ]
        , span [ class "hp-display__sep" ] [ text "/" ]
        , span [ class "hp-display__max" ] [ text "100" ]
        ]


viewBloodied : Creature -> Html Msg
viewBloodied creature =
    if creature.bloodied then
        span
            [ class "bloodied"
            , title "Bloodied — below half hit points"
            , attribute "aria-label" "Bloodied"
            ]
            [ text "🩸" ]

    else
        text ""


viewDeathSaves : Creature -> Html Msg
viewDeathSaves creature =
    if creature.inDeathSaves then
        let
            ( a, b, c ) =
                creature.deathSaves
        in
        span
            [ class "death-saves"
            , attribute "role" "group"
            , attribute "aria-label" "Death saving throws"
            ]
            [ viewDeathSave creature.name 0 a
            , viewDeathSave creature.name 1 b
            , viewDeathSave creature.name 2 c
            ]

    else
        text ""


viewCardRowBot : Creature -> Html Msg
viewCardRowBot creature =
    div [ class "creature-card__row creature-card__row--bot" ]
        [ button
            [ class "action-btn action-btn--damage"
            , title "Apply damage"
            ]
            [ text "Damage" ]
        , button
            [ class "action-btn action-btn--heal"
            , title "Heal hit points"
            ]
            [ text "Heal" ]
        , button
            [ class "action-btn action-btn--temp"
            , title "Add temporary hit points"
            ]
            [ text "Temp HP" ]
        , button
            [ class "action-btn action-btn--condition"
            , title "Apply condition or effect"
            ]
            [ text "Condition/Effect" ]
        , viewHoldToggle creature
        , button
            [ class "action-btn action-btn--icon"
            , title "Memo"
            , attribute "aria-label" "Memo"
            ]
            [ text "📝" ]
        , button
            [ class "action-btn action-btn--icon"
            , title "Stopwatch / timer"
            , attribute "aria-label" "Timer"
            ]
            [ text "⏱️" ]
        , button
            [ class "action-btn action-btn--icon"
            , title "Roll dice"
            , attribute "aria-label" "Roll dice"
            ]
            [ text "🎲" ]
        ]


viewHoldToggle : Creature -> Html Msg
viewHoldToggle creature =
    let
        ( bodyText, cls, label ) =
            if creature.holding then
                ( "✊ Holding"
                , "action-btn action-btn--holding"
                , "Holding action — click to release"
                )

            else
                ( "✋ Hold"
                , "action-btn action-btn--hold"
                , "Hold action — click to set"
                )
    in
    button
        [ class cls
        , onClick (ToggleHolding creature.name)
        , title label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if creature.holding then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]


viewDeathSave : String -> Int -> Bool -> Html Msg
viewDeathSave name idx isFailed =
    let
        ( glyph, state ) =
            if isFailed then
                ( "💀", "failed" )

            else
                ( "○", "open" )

        label =
            "Death save " ++ String.fromInt (idx + 1) ++ ": " ++ state
    in
    button
        [ class "death-save"
        , onClick (ToggleDeathSave name idx)
        , title label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if isFailed then
                "true"

             else
                "false"
            )
        ]
        [ text glyph ]


viewBoolToggle : String -> String -> Bool -> Msg -> Html Msg
viewBoolToggle icon label isOn msg =
    let
        ( bodyText, cls, tip ) =
            if isOn then
                ( icon ++ " " ++ label
                , "status-toggle status-toggle--on"
                , label ++ " — click to clear"
                )

            else
                ( "not " ++ label
                , "status-toggle"
                , "not " ++ label ++ " — click to set"
                )
    in
    button
        [ class cls
        , onClick msg
        , title tip
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ text bodyText ]


viewCoverToggle : Creature -> Html Msg
viewCoverToggle creature =
    let
        ( bodyText, label, modifier ) =
            case creature.cover of
                NoCover ->
                    ( "○ no cover", "No cover", "status-toggle--off" )

                HalfCover ->
                    ( "◐ ½ cover", "Half cover", "status-toggle--on" )

                ThreeQuartersCover ->
                    ( "◕ ¾ cover", "Three-quarters cover", "status-toggle--on" )

                FullCover ->
                    ( "● full cover", "Full cover", "status-toggle--on" )
    in
    button
        [ class ("status-toggle " ++ modifier)
        , onClick (CycleCover creature.name)
        , title (label ++ " — click to cycle")
        , attribute "aria-label" ("Cover: " ++ label)
        ]
        [ text bodyText ]


viewFlyHeight : Creature -> Html Msg
viewFlyHeight creature =
    if creature.flying then
        span [ class "fly-height" ]
            [ button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name 5)
                , title "Increase by 5 ft"
                , attribute "aria-label" "Increase flight height by 5 feet"
                ]
                [ text "▲" ]
            , span [ class "fly-height__value" ]
                [ text (String.fromInt creature.flyHeight) ]
            , button
                [ class "fly-height__btn"
                , onClick (AdjustFlyHeight creature.name -5)
                , title "Decrease by 5 ft"
                , attribute "aria-label" "Decrease flight height by 5 feet"
                ]
                [ text "▼" ]
            , span [ class "fly-height__unit" ] [ text "ft" ]
            , button
                [ class "icon-btn icon-btn--sm fly-height__fall"
                , title "Calculate falling damage (placeholder)"
                , attribute "aria-label" "Calculate falling damage"
                ]
                [ text "↯" ]
            ]

    else
        text ""


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
