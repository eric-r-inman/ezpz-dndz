module Main exposing (main)

import Browser
import Browser.Events
import Browser.Navigation as Nav
import Dice
import Encounter
    exposing
        ( Cover(..)
        , Creature
        , Encounter
        )
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
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


{-| The single source of truth for the running app.

`encounter` holds all D&D-specific state (queue, active creature,
round). `route` / `url` / `key` / `me` are presentation/auth concerns
that have nothing to do with the rules. The split mirrors the larger
discipline: domain state goes through `Encounter`, everything else
stays here.

-}
type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    , encounter : Encounter
    , dice : DiceUi
    }


{-| UI state for the dice-roller modal. Holds presentation-only
fields (open/closed, current text input, count/modifier sliders)
plus the persisted-this-session roll history. The actual rules and
random-roll logic live in `Dice`; this record exists in `Main` so
it stays adjacent to the view code that consumes it.
-}
type alias DiceUi =
    { open : Bool
    , input : String
    , inputError : Maybe Dice.Error
    , count : Int
    , modifier : Int
    , history : Dice.History
    }


emptyDice : DiceUi
emptyDice =
    { open = False
    , input = ""
    , inputError = Nothing
    , count = 1
    , modifier = 0
    , history = Dice.emptyHistory
    }


{-| Every message the runtime can send the update loop. Per-creature
messages carry the target creature's `name` as their identity; that's
how we look up which row of `encounter.creatures` to operate on.

`NextTurn` advances the queue one slot — it's the first piece of real
turn logic in the app and the place where future per-phase hooks
(begin / end / off / on) will land as separate pure functions.

-}
type Msg
    = UrlRequested Browser.UrlRequest
    | UrlChanged Url
    | GotMe (Result Http.Error MeInfo)
    | NextTurn
    | SetActive String
    | ToggleSurprised String
    | CycleCover String
    | ToggleConcentration String
    | ToggleHiding String
    | ToggleFlying String
    | AdjustFlyHeight String Int
    | ToggleDeathSave String Int
    | ToggleHolding String
      -- Dice modal
    | OpenDice
    | CloseDice
    | DiceInputChanged String
    | DiceCountChanged String
    | DiceModifierChanged String
    | DiceRollFromInput
    | DiceRollFaces Int
    | DiceRollAdvantage
    | DiceRollDisadvantage
    | DiceFlipCoin
    | DiceRerun Dice.Roll
    | DiceClearHistory
    | DiceRollLanded Dice.Roll
    | NoOp


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = UrlRequested
        , onUrlChange = UrlChanged
        }


{-| Subscribe to keyboard events while the dice modal is open so Esc
can close it. Other routes don't need any subscriptions yet.
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    if model.dice.open then
        Browser.Events.onKeyDown
            (Decode.field "key" Decode.string
                |> Decode.andThen
                    (\key ->
                        if key == "Escape" then
                            Decode.succeed CloseDice

                        else
                            Decode.fail "ignore"
                    )
            )

    else
        Sub.none


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
      , encounter = Encounter.initialEncounter
      , dice = emptyDice
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

        NextTurn ->
            -- Domain layer owns the queue walk and round bookkeeping; this
            -- branch is intentionally a one-liner so all the rules-y
            -- behavior is inspectable in one place (Encounter.nextTurn).
            ( { model | encounter = Encounter.nextTurn model.encounter }
            , Cmd.none
            )

        SetActive name ->
            -- Manual jump (the right-arrow button on a card). Distinct
            -- from NextTurn: no round bump, no turn-progression hooks
            -- when those land. See Encounter.setActive for rationale.
            ( withEncounter (Encounter.setActive name) model
            , Cmd.none
            )

        ToggleSurprised name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | surprised = not c.surprised })) model
            , Cmd.none
            )

        CycleCover name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | cover = Encounter.nextCover c.cover })) model
            , Cmd.none
            )

        ToggleConcentration name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | concentrating = not c.concentrating })) model
            , Cmd.none
            )

        ToggleHiding name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | hiding = not c.hiding })) model
            , Cmd.none
            )

        ToggleFlying name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | flying = not c.flying })) model
            , Cmd.none
            )

        AdjustFlyHeight name delta ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | flyHeight = Basics.max 0 (c.flyHeight + delta) })) model
            , Cmd.none
            )

        ToggleDeathSave name idx ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | deathSaves = Encounter.toggleDeathSave idx c.deathSaves })) model
            , Cmd.none
            )

        ToggleHolding name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | holding = not c.holding })) model
            , Cmd.none
            )

        -- Dice modal lifecycle
        OpenDice ->
            ( withDice (\d -> { d | open = True, inputError = Nothing }) model
            , Cmd.none
            )

        CloseDice ->
            ( withDice (\d -> { d | open = False, inputError = Nothing }) model
            , Cmd.none
            )

        DiceInputChanged text ->
            ( withDice (\d -> { d | input = text, inputError = Nothing }) model
            , Cmd.none
            )

        DiceCountChanged text ->
            ( withDice (\d -> { d | count = parseClamp 1 99 1 text }) model
            , Cmd.none
            )

        DiceModifierChanged text ->
            ( withDice (\d -> { d | modifier = parseClamp -999 999 0 text }) model
            , Cmd.none
            )

        DiceRollFromInput ->
            -- Parse the free-text expression. On failure, stash the
            -- error in the modal so the input can show "couldn't read
            -- 'xyz'"; on success, fire the roll Cmd.
            case Dice.parse model.dice.input of
                Ok expr ->
                    ( withDice (\d -> { d | inputError = Nothing }) model
                    , Dice.rollCmd DiceRollLanded expr
                    )

                Err err ->
                    ( withDice (\d -> { d | inputError = Just err }) model
                    , Cmd.none
                    )

        DiceRollFaces faces ->
            -- Each rainbow face button rolls (count)d(faces) + modifier
            -- using the current sliders. No parse needed.
            ( model
            , Dice.rollCmd DiceRollLanded (faceExpression model.dice faces)
            )

        DiceRollAdvantage ->
            ( model, Dice.advantageCmd DiceRollLanded model.dice.modifier )

        DiceRollDisadvantage ->
            ( model, Dice.disadvantageCmd DiceRollLanded model.dice.modifier )

        DiceFlipCoin ->
            ( model, Dice.coinCmd DiceRollLanded )

        DiceRerun roll ->
            -- Re-execute a historical roll using the same kind. Coin
            -- and adv/dis bypass the parsed expression because their
            -- semantics aren't fully captured by Expression alone.
            case roll.kind of
                Dice.Standard ->
                    ( model, Dice.rollCmd DiceRollLanded roll.expression )

                Dice.Advantage ->
                    ( model, Dice.advantageCmd DiceRollLanded roll.expression.constant )

                Dice.Disadvantage ->
                    ( model, Dice.disadvantageCmd DiceRollLanded roll.expression.constant )

                Dice.Coin ->
                    ( model, Dice.coinCmd DiceRollLanded )

        DiceClearHistory ->
            ( withDice (\d -> { d | history = Dice.emptyHistory }) model
            , Cmd.none
            )

        DiceRollLanded roll ->
            ( withDice (\d -> { d | history = Dice.push roll d.history }) model
            , Cmd.none
            )

        NoOp ->
            ( model, Cmd.none )


{-| Lift an `Encounter -> Encounter` transformation into a
`Model -> Model` transformation by threading it through the encounter
field. Keeps every per-creature update branch a one-liner and makes
the rest of `Model` (route, auth, nav key) literally invisible to
domain code, which is what the layering discipline demands.
-}
withEncounter : (Encounter -> Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


{-| Same trick as `withEncounter`, but for the dice-roller UI state.
Threading the field-level update through a helper keeps the dice
update branches as one-liners and avoids destructuring `model.dice`
inline at every call site.
-}
withDice : (DiceUi -> DiceUi) -> Model -> Model
withDice fn model =
    { model | dice = fn model.dice }


{-| Parse a numeric `<input>`'s string value into an Int, clamping
to `lo..hi`. Falls back to `def` when the input is empty or
unparseable so the form never crashes on transient bad states like
the user mid-typing "-".
-}
parseClamp : Int -> Int -> Int -> String -> Int
parseClamp lo hi def text =
    case String.toInt (String.trim text) of
        Just n ->
            Basics.max lo (Basics.min hi n)

        Nothing ->
            def


{-| Build the `Dice.Expression` that one rainbow face-button rolls.
Uses the modal's current count/modifier sliders.
-}
faceExpression : DiceUi -> Int -> Dice.Expression
faceExpression ui faces =
    { dice =
        [ { count = ui.count
          , faces = faces
          , sign = Dice.Positive
          }
        ]
    , constant = ui.modifier
    , damageType = Nothing
    }



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "eZpZ-dndZ"
    , body =
        [ div [ class "app-shell" ]
            [ viewAppBar
            , viewPage model
            , viewDiceModal model.dice
            ]
        ]
    }


viewAppBar : Html Msg
viewAppBar =
    header [ class "app-bar" ]
        [ div [ class "app-bar__brand" ]
            [ div [ class "app-bar__title" ] [ text "eZpZ-dndZ" ]
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
        [ viewPanelMain model.encounter
        , viewPanelControls
        , viewPanelDetail
        ]


viewPanelMain : Encounter -> Html Msg
viewPanelMain enc =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ viewEncounterBar enc ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (viewCreatureCard enc.activeName) enc.creatures)
            ]
        ]


viewEncounterBar : Encounter -> Html Msg
viewEncounterBar enc =
    let
        active =
            Encounter.activeCreature enc

        activeName =
            Maybe.map .name active
                |> Maybe.withDefault "—"

        hpText =
            case active of
                Just c ->
                    String.fromInt c.currentHp ++ "/" ++ String.fromInt c.maxHp

                Nothing ->
                    "—"
    in
    div [ class "encounter-bar" ]
        [ div [ class "encounter-bar__group" ]
            [ span
                [ class "encounter-bar__info"
                , title "from file: "
                , attribute "aria-label" "Encounter file"
                , tabindex 0
                ]
                [ text "ⓘ" ]
            , span [ class "encounter-bar__round" ]
                [ text ("Round " ++ String.fromInt enc.round) ]
            , span [ class "encounter-bar__sep" ] [ text "|" ]
            , span [ class "encounter-bar__active" ] [ text activeName ]
            , span [ class "encounter-bar__hp" ] [ text hpText ]
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , div [ class "encounter-bar__states" ]
                [ span [ class "encounter-bar__state", title "State 1 (placeholder)" ] [ text "✊" ]
                , span [ class "encounter-bar__state", title "State 2 (placeholder)" ] [ text "◕" ]
                , span [ class "encounter-bar__state", title "State 3 (placeholder)" ] [ text "🧠" ]
                , span [ class "encounter-bar__state", title "State 4 (placeholder)" ] [ text "🪽" ]
                ]
            , span [ class "condition-list" ]
                [ span [ class "condition-list__item" ] [ text "Paralyzed" ]
                , span [ class "condition-list__sep" ] [ text "|" ]
                , span [ class "condition-list__item" ] [ text "Poisoned" ]
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
                , onClick OpenDice
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
                , button
                    [ class "action-btn action-btn--green"
                    , onClick NextTurn
                    , title "Advance to the next creature in initiative order"
                    ]
                    [ text "⏭ Next Turn" ]
                , button [ class "action-btn action-btn--orange" ]
                    [ span [ class "btn-glyph" ] [ text "⟲" ]
                    , text " Reset"
                    ]
                , button [ class "action-btn action-btn--red" ] [ text "🗑 Clear" ]
                ]
            ]
        ]


viewPanelDetail : Html Msg
viewPanelDetail =
    section [ class "panel panel--detail" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Compendium" ] ]
        , div [ class "panel__body" ]
            [ div [ class "btn-grid compendium-toolbar" ]
                [ button [ class "action-btn action-btn--blue" ] [ text "🔍 Quick View" ]
                , button [ class "action-btn action-btn--blue" ] [ text "📖 Open" ]
                , button
                    [ class "action-btn action-btn--blue"
                    , disabled True
                    , attribute "aria-disabled" "true"
                    , title "CR Calculator (not yet available)"
                    ]
                    [ text "⚔️ CR Calculator" ]
                ]
            , viewStatBlock mockStatBlock
            ]
        ]



-- COMPENDIUM MOCK DATA
--
-- The stat-block panel still renders against this hard-coded record;
-- it'll move into the domain layer alongside a real monster catalog
-- once the compendium feature actually does anything beyond display.


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
                    , onClick (SetActive creature.name)
                    , title "Make active creature (does not advance the turn)"
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



-- DICE MODAL


{-| Renders nothing while closed, the full overlay while open. The
backdrop click closes the modal; clicks inside stop propagation so
they don't bubble out.
-}
viewDiceModal : DiceUi -> Html Msg
viewDiceModal ui =
    if ui.open then
        div
            [ class "modal-backdrop"
            , onClick CloseDice
            ]
            [ div
                [ class "modal modal--dice"
                , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                , attribute "role" "dialog"
                , attribute "aria-modal" "true"
                , attribute "aria-label" "Dice roller"
                ]
                [ viewDiceModalHeader
                , div [ class "modal__body" ]
                    [ viewDiceForm ui
                    , viewDiceFaceButtons
                    , viewDiceSpecialButtons
                    , viewDiceHistory ui.history
                    ]
                ]
            ]

    else
        text ""


viewDiceModalHeader : Html Msg
viewDiceModalHeader =
    div [ class "modal__header" ]
        [ div [ class "modal__title" ] [ text "🎲 Dice Roller" ]
        , button
            [ class "modal__close"
            , onClick CloseDice
            , title "Close (Esc)"
            , attribute "aria-label" "Close dice roller"
            ]
            [ text "×" ]
        ]


viewDiceForm : DiceUi -> Html Msg
viewDiceForm ui =
    div [ class "dice-form" ]
        [ div [ class "dice-form__row" ]
            [ label [ for "dice-input" ] [ text "Expression" ]
            , input
                [ id "dice-input"
                , class "dice-form__input"
                , type_ "text"
                , placeholder "e.g. 2d6+3 fire damage"
                , value ui.input
                , onInput DiceInputChanged
                , Html.Events.on "keydown" (enterKey DiceRollFromInput)
                ]
                []
            , button
                [ class "action-btn action-btn--green"
                , onClick DiceRollFromInput
                ]
                [ text "Roll" ]
            ]
        , case ui.inputError of
            Just (Dice.ParseError raw) ->
                div [ class "dice-form__error" ]
                    [ text ("Couldn't parse: " ++ raw) ]

            Nothing ->
                text ""
        , div [ class "dice-form__row" ]
            [ label [ for "dice-count" ] [ text "Count" ]
            , input
                [ id "dice-count"
                , class "dice-form__input dice-form__numeric"
                , type_ "number"
                , Html.Attributes.min "1"
                , Html.Attributes.max "99"
                , value (String.fromInt ui.count)
                , onInput DiceCountChanged
                ]
                []
            , label [ for "dice-modifier", class "dice-form__row-spacer" ] [ text "Modifier" ]
            , input
                [ id "dice-modifier"
                , class "dice-form__input dice-form__numeric"
                , type_ "number"
                , Html.Attributes.min "-999"
                , Html.Attributes.max "999"
                , value (String.fromInt ui.modifier)
                , onInput DiceModifierChanged
                ]
                []
            ]
        ]


{-| Decode an Enter keypress into the given Msg; otherwise fail (which
silences the event handler).
-}
enterKey : Msg -> Decode.Decoder Msg
enterKey msg =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                if key == "Enter" then
                    Decode.succeed msg

                else
                    Decode.fail "ignore"
            )


viewDiceFaceButtons : Html Msg
viewDiceFaceButtons =
    div [ class "die-btn-grid" ]
        [ faceButton 4 "die-btn--d4"
        , faceButton 6 "die-btn--d6"
        , faceButton 8 "die-btn--d8"
        , faceButton 10 "die-btn--d10"
        , faceButton 12 "die-btn--d12"
        , faceButton 20 "die-btn--d20"
        , faceButton 100 "die-btn--d100"
        ]


faceButton : Int -> String -> Html Msg
faceButton faces colorClass =
    button
        [ class ("die-btn " ++ colorClass)
        , onClick (DiceRollFaces faces)
        , title ("Roll d" ++ String.fromInt faces)
        ]
        [ text ("d" ++ String.fromInt faces) ]


viewDiceSpecialButtons : Html Msg
viewDiceSpecialButtons =
    div [ class "dice-special-row" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick DiceRollAdvantage
            , title "Roll 2d20, keep highest"
            ]
            [ text "Advantage" ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick DiceRollDisadvantage
            , title "Roll 2d20, keep lowest"
            ]
            [ text "Disadvantage" ]
        , button
            [ class "action-btn"
            , onClick DiceFlipCoin
            , title "50/50 coin flip"
            ]
            [ text "🪙 Coin Flip" ]
        ]


viewDiceHistory : Dice.History -> Html Msg
viewDiceHistory history =
    let
        entries =
            Dice.historyEntries history
    in
    div [ class "dice-history" ]
        [ div [ class "dice-history__head" ]
            [ div [ class "dice-history__title" ]
                [ text ("Recent rolls (" ++ String.fromInt (List.length entries) ++ ")") ]
            , if List.isEmpty entries then
                text ""

              else
                button
                    [ class "dice-history__rerun"
                    , onClick DiceClearHistory
                    , title "Clear roll history"
                    ]
                    [ text "Clear" ]
            ]
        , if List.isEmpty entries then
            div [ class "dice-history__empty" ]
                [ text "No rolls yet. Click a die above or type an expression." ]

          else
            ul [ class "dice-history__list" ]
                (List.map viewHistoryEntry entries)
        ]


viewHistoryEntry : Dice.Roll -> Html Msg
viewHistoryEntry roll =
    li [ class "dice-history__entry" ]
        [ div [ class "dice-history__formula" ]
            [ text roll.formula
            , span [ class "dice-history__rolled" ]
                [ text (" — " ++ rolledString roll) ]
            , case roll.expression.damageType of
                Just damage ->
                    span [ class "dice-history__damage" ] [ text damage ]

                Nothing ->
                    text ""
            ]
        , div [ class "dice-history__total" ] [ text (String.fromInt roll.total) ]
        , button
            [ class "dice-history__rerun"
            , onClick (DiceRerun roll)
            , title "Roll this again"
            ]
            [ text "↻" ]
        ]


{-| Format the individual face values for a Roll, with kept faces
inline and dropped (advantage/disadvantage loser) ones bracketed.
"rolled 14, +3" or "rolled 17 (8 dropped)" etc.
-}
rolledString : Dice.Roll -> String
rolledString roll =
    let
        faces =
            roll.groups
                |> List.concatMap .rolled
                |> List.map
                    (\d ->
                        if d.kept then
                            String.fromInt d.face

                        else
                            "[" ++ String.fromInt d.face ++ "]"
                    )
                |> String.join ", "

        modifierText =
            if roll.expression.constant > 0 then
                " + " ++ String.fromInt roll.expression.constant

            else if roll.expression.constant < 0 then
                " − " ++ String.fromInt (abs roll.expression.constant)

            else
                ""
    in
    "rolled " ++ faces ++ modifierText
