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
import HpChange
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput, preventDefaultOn, stopPropagationOn)
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
    , hpChange : Maybe HpChangeUi
    , hpChangeLog : List HpChangeEntry
    , hpEdit : Maybe HpEdit
    , initiative : Maybe InitiativeUi
    }


{-| Initiative-manager modal state. `target` is the creature whose
init circle was clicked (the modal's per-creature buttons read
"Roll Initiative & Sort: <target>" / "Apply & Sort: <target>").

`customValueText` is the raw text in the "Initiative Value:" input.
Same trick as the dice modifier and HP edit fields: tracking the
characters lets the user type a transient `-` while typing a
negative initiative without the controlled input clobbering it.

-}
type alias InitiativeUi =
    { target : String
    , customValueText : String
    }


freshInitiativeUi : String -> InitiativeUi
freshInitiativeUi target =
    { target = target
    , customValueText = ""
    }


{-| One row in the recent-HP-changes log shown at the bottom of the
Damage / Heal / Temp HP modals. Captures who, what kind, the input
amount, and the before/after HP+temp snapshots so the row can render
"27/59 (+0) → 14/59 (+0)" without re-querying the encounter state.
-}
type alias HpChangeEntry =
    { kind : HpKind
    , target : String
    , amount : Int
    , beforeHp : Int
    , beforeTemp : Int
    , afterHp : Int
    , afterTemp : Int
    }


{-| Active inline-HP edit. When set, the corresponding `<span>` on
the matching creature card renders as an `<input>` instead. Only one
edit at a time so we don't have to disambiguate keyboard focus.

`text` mirrors the `<input>` value (same trick as the dice modifier
field — keeps transient typing states like the empty string from
being clobbered on every re-render).

-}
type alias HpEdit =
    { target : String
    , field : HpField
    , text : String
    }


type HpField
    = CurrentHpField
    | MaxHpField


{-| Cap on the HP-change log size. Matches the user's request for
"last 10 applications".
-}
maxHpLogEntries : Int
maxHpLogEntries =
    10


{-| Per-instance state for the HP-change modal.

Open ↔ closed lives at the `Model.hpChange` field (Just / Nothing)
rather than as a flag here, so an `Encounter.mapCreature` that
deletes the targeted creature can't leave a stale modal pointing at
something that no longer exists.

`amountText` mirrors the `<input>` characters for the same reason
`DiceUi.modifierText` does — to allow transient states like a bare
"-" while the user is mid-typing without the controlled input
overwriting their text.

-}
type alias HpChangeUi =
    { target : String
    , kind : HpKind
    , mode : HpInputMode
    , amount : Int
    , amountText : String
    , expression : String
    , parseError : Maybe Dice.Error
    , ignoreTemp : Bool
    }


type HpKind
    = DamageKind
    | HealKind
    | TempHpKind


type HpInputMode
    = ManualMode
    | DiceMode


{-| Initial state for opening the HP-change modal targeted at a
creature. The kind picks Damage / Heal / Temp HP; the rest defaults
to a 0-amount manual entry.
-}
freshHpChangeUi : String -> HpKind -> HpChangeUi
freshHpChangeUi target kind =
    { target = target
    , kind = kind
    , mode = ManualMode
    , amount = 0
    , amountText = "0"
    , expression = ""
    , parseError = Nothing
    , ignoreTemp = False
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
    , modifierText : String
    , history : Dice.History
    }


{-| The parsed `modifier` is what generators consume; `modifierText`
mirrors the literal characters in the `<input>`. The two diverge
during transient typing — e.g. while the user is typing "-5", the
field briefly contains just "-", which doesn't parse as an Int. We
keep the raw text in the model so re-renders don't overwrite the
"-" with a stringified previous value, which used to make negative
input feel impossible.
-}
emptyDice : DiceUi
emptyDice =
    { open = False
    , input = ""
    , inputError = Nothing
    , count = 1
    , modifier = 0
    , modifierText = "0"
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
    | DiceResetSliders
    | DiceRollFromInput
    | DiceRollFaces Int
    | DiceRollAdvantage
    | DiceRollDisadvantage
    | DiceFlipCoin
    | DiceRerun Dice.Roll
    | DiceClearHistory
    | DiceRollLanded Dice.Roll
    | DiceHistoryLoaded (Result Http.Error (List Dice.Roll))
    | DicePersistResponse (Result Http.Error (List Dice.Roll))
    | DiceClearResponse (Result Http.Error ())
    | RollFromStatBlock String Dice.Expression
      -- HP change modal
    | HpChangeOpen String HpKind
    | HpChangeClose
    | HpChangeModeSet HpInputMode
    | HpChangeAmountChanged String
    | HpChangeExpressionChanged String
    | HpChangeIgnoreTempToggle
    | HpChangeApply
    | HpChangeRollLanded Dice.Roll
      -- Inline HP edit on the creature card
    | HpEditStart String HpField Int
    | HpEditChange String
    | HpEditCommit
    | HpEditCancel
      -- Selection
    | ToggleSelected String
    | ShiftToggleSelected
      -- Manual queue reordering
    | MoveCreatureUp String
    | MoveCreatureDown String
      -- Initiative manager modal
    | InitiativeOpen String
    | InitiativeClose
    | InitiativeCustomChanged String
    | InitiativeQuickSort
    | InitiativeAutoRollTarget
    | InitiativeAutoRollAll
    | InitiativeAutoRollSelected
    | InitiativeApplyTarget
    | InitiativeApplySelected
    | InitiativeRollsLanded (List ( String, Dice.Roll ))
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
      , hpChange = Nothing
      , hpChangeLog = []
      , hpEdit = Nothing
      , initiative = Nothing
      }
      -- Always fetch the persisted dice history alongside whatever
      -- the current route needs. Failures are silently swallowed so
      -- a fresh server (no dice-history.json yet) still loads.
    , Cmd.batch [ cmdForRoute route, fetchDiceHistoryCmd ]
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
            -- Track the raw characters in `modifierText`; only update
            -- the parsed `modifier` when the input is actually a
            -- number. Lets the user type "-" before "-5" without
            -- losing the minus on re-render.
            ( withDice
                (\d ->
                    { d
                        | modifierText = text
                        , modifier =
                            String.toInt (String.trim text)
                                |> Maybe.map (Basics.max -999 >> Basics.min 999)
                                |> Maybe.withDefault d.modifier
                    }
                )
                model
            , Cmd.none
            )

        DiceResetSliders ->
            ( withDice (\d -> { d | count = 1, modifier = 0, modifierText = "0" }) model
            , Cmd.none
            )

        DiceRollFromInput ->
            -- Parse the free-text expression. On failure, stash the
            -- error in the modal so the input can show "couldn't read
            -- 'xyz'"; on success, fire the roll Cmd.
            case Dice.parse model.dice.input of
                Ok expr ->
                    ( withDice (\d -> { d | inputError = Nothing }) model
                    , Dice.rollCmd DiceRollLanded Dice.manualSource expr
                    )

                Err err ->
                    ( withDice (\d -> { d | inputError = Just err }) model
                    , Cmd.none
                    )

        DiceRollFaces faces ->
            -- Each rainbow face button rolls (count)d(faces) + modifier
            -- using the current sliders. No parse needed.
            ( model
            , Dice.rollCmd DiceRollLanded Dice.manualSource (faceExpression model.dice faces)
            )

        DiceRollAdvantage ->
            ( model, Dice.advantageCmd DiceRollLanded Dice.manualSource model.dice.modifier )

        DiceRollDisadvantage ->
            ( model, Dice.disadvantageCmd DiceRollLanded Dice.manualSource model.dice.modifier )

        DiceFlipCoin ->
            ( model, Dice.coinCmd DiceRollLanded Dice.manualSource )

        DiceRerun roll ->
            -- Re-execute a historical roll using the same kind AND the
            -- original source label, so a re-rolled "Damage → Brakka"
            -- still reads as such in the history (rather than silently
            -- demoting to "Manual").
            case roll.kind of
                Dice.Standard ->
                    ( model, Dice.rollCmd DiceRollLanded roll.source roll.expression )

                Dice.Advantage ->
                    ( model, Dice.advantageCmd DiceRollLanded roll.source roll.expression.constant )

                Dice.Disadvantage ->
                    ( model, Dice.disadvantageCmd DiceRollLanded roll.source roll.expression.constant )

                Dice.Coin ->
                    ( model, Dice.coinCmd DiceRollLanded roll.source )

        DiceClearHistory ->
            ( withDice (\d -> { d | history = Dice.emptyHistory }) model
            , clearDiceHistoryCmd
            )

        DiceRollLanded roll ->
            -- Update the local history immediately for snappy UI; fire
            -- the persistence POST in parallel. The server response
            -- replaces the local view in DicePersistResponse so the two
            -- stay in sync (and any older entries surfacing from disk
            -- after init come through that same path).
            ( withDice (\d -> { d | history = Dice.push roll d.history }) model
            , persistRollCmd roll
            )

        DiceHistoryLoaded result ->
            case result of
                Ok rolls ->
                    ( withDice
                        (\d ->
                            { d
                                | history =
                                    { entries = rolls
                                    , max = Dice.maxHistoryEntries
                                    }
                            }
                        )
                        model
                    , Cmd.none
                    )

                Err _ ->
                    -- No persisted history yet, or the server is
                    -- unreachable. Either way, fall back to the
                    -- already-empty in-memory history.
                    ( model, Cmd.none )

        DicePersistResponse result ->
            case result of
                Ok rolls ->
                    -- Server is now the source of truth for what's
                    -- persisted; reflect its truncation/ordering back
                    -- into the local UI so reroll buttons match disk.
                    ( withDice
                        (\d ->
                            { d
                                | history =
                                    { entries = rolls
                                    , max = Dice.maxHistoryEntries
                                    }
                            }
                        )
                        model
                    , Cmd.none
                    )

                Err _ ->
                    -- Persistence failure is non-fatal; the local copy
                    -- of the history already has the new roll.
                    ( model, Cmd.none )

        DiceClearResponse _ ->
            -- Server-side clear succeeded or didn't; either way the
            -- local history has already been emptied in DiceClearHistory.
            ( model, Cmd.none )

        RollFromStatBlock creatureName expr ->
            -- Click on inline dice notation in a stat-block trait.
            -- Open the modal so the user sees the result land, and
            -- fire the roll through the same code path as the modal's
            -- own buttons. The source is tagged "Stat block" with the
            -- creature name so it shows up in the history as
            -- "Stat block → Brakka, Ogre Brute".
            ( withDice (\d -> { d | open = True, inputError = Nothing }) model
            , Dice.rollCmd DiceRollLanded
                { feature = "Stat block", target = Just creatureName }
                expr
            )

        -- HP change modal lifecycle
        HpChangeOpen target kind ->
            ( { model | hpChange = Just (freshHpChangeUi target kind) }
            , Cmd.none
            )

        HpChangeClose ->
            ( { model | hpChange = Nothing }, Cmd.none )

        HpChangeModeSet mode ->
            ( withHpChange (\u -> { u | mode = mode, parseError = Nothing }) model
            , Cmd.none
            )

        HpChangeAmountChanged text ->
            -- Mirror the dice-modifier pattern: track raw text for
            -- the controlled input, only update the parsed integer
            -- when the input actually parses. Unsigned here — heal
            -- and temp-HP can't be negative, and damage flips the
            -- sign internally via the engine.
            ( withHpChange
                (\u ->
                    { u
                        | amountText = text
                        , amount =
                            String.toInt (String.trim text)
                                |> Maybe.map (Basics.max 0)
                                |> Maybe.withDefault u.amount
                    }
                )
                model
            , Cmd.none
            )

        HpChangeExpressionChanged text ->
            ( withHpChange (\u -> { u | expression = text, parseError = Nothing }) model
            , Cmd.none
            )

        HpChangeIgnoreTempToggle ->
            ( withHpChange (\u -> { u | ignoreTemp = not u.ignoreTemp }) model
            , Cmd.none
            )

        HpChangeApply ->
            -- Manual mode commits ui.amount via the engine straight
            -- away. Dice mode parses the expression and fires
            -- Dice.rollCmd; the resulting roll comes back via
            -- HpChangeRollLanded which then commits with the rolled
            -- total AND logs the roll to the dice history. So both
            -- paths converge on a single applyHpChange step.
            case model.hpChange of
                Nothing ->
                    ( model, Cmd.none )

                Just ui ->
                    case ui.mode of
                        ManualMode ->
                            ( applyHpChangeAndClose ui ui.amount model
                            , Cmd.none
                            )

                        DiceMode ->
                            case Dice.parse ui.expression of
                                Ok expr ->
                                    ( model
                                    , Dice.rollCmd HpChangeRollLanded
                                        (hpChangeSource ui)
                                        expr
                                    )

                                Err err ->
                                    ( withHpChange (\u -> { u | parseError = Just err }) model
                                    , Cmd.none
                                    )

        HpChangeRollLanded roll ->
            -- The dice-mode path lands here. We commit the change
            -- with roll.total, log the roll to the dice history (so
            -- the user has a record), and persist it server-side
            -- through the same /api/dice/history pipe the dice modal
            -- uses. If the modal got closed mid-flight (defensive),
            -- still log/persist so we don't drop rolls on the floor.
            let
                logged =
                    withDice (\d -> { d | history = Dice.push roll d.history }) model

                committed =
                    case logged.hpChange of
                        Just ui ->
                            applyHpChangeAndClose ui roll.total logged

                        Nothing ->
                            logged
            in
            ( committed, persistRollCmd roll )

        -- Inline HP edit on a creature card
        HpEditStart name field current ->
            ( { model
                | hpEdit =
                    Just
                        { target = name
                        , field = field
                        , text = String.fromInt current
                        }
              }
            , Cmd.none
            )

        HpEditChange text ->
            ( case model.hpEdit of
                Just edit ->
                    { model | hpEdit = Just { edit | text = text } }

                Nothing ->
                    model
            , Cmd.none
            )

        HpEditCommit ->
            -- Parse the text. On success, write through HpChange's
            -- manual-edit helpers (which clamp + recompute bloodied).
            -- On parse failure, just close the editor without
            -- changing anything — easier than surfacing a transient
            -- error inline.
            case model.hpEdit of
                Nothing ->
                    ( model, Cmd.none )

                Just edit ->
                    case String.toInt (String.trim edit.text) of
                        Just n ->
                            let
                                transform =
                                    case edit.field of
                                        CurrentHpField ->
                                            HpChange.setCurrentHp n

                                        MaxHpField ->
                                            HpChange.setMaxHp n
                            in
                            ( { model
                                | encounter =
                                    Encounter.mapCreature edit.target transform model.encounter
                                , hpEdit = Nothing
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( { model | hpEdit = Nothing }, Cmd.none )

        HpEditCancel ->
            ( { model | hpEdit = Nothing }, Cmd.none )

        -- Selection
        ToggleSelected name ->
            ( withEncounter
                (Encounter.mapCreature name (\c -> { c | selected = not c.selected }))
                model
            , Cmd.none
            )

        ShiftToggleSelected ->
            -- Bulk: if every creature is already selected, deselect
            -- all; otherwise select all. The clicked creature ends up
            -- in the resulting bulk state regardless of where it
            -- started.
            let
                allSelected =
                    List.all .selected model.encounter.creatures

                newValue =
                    not allSelected
            in
            ( withEncounter
                (\enc ->
                    { enc
                        | creatures =
                            List.map (\c -> { c | selected = newValue })
                                enc.creatures
                    }
                )
                model
            , Cmd.none
            )

        -- Manual queue reordering (the up/down arrows on each card).
        -- Pure position swaps; initiative isn't touched. A later
        -- sortByInitiative wipes the manual order, which matches
        -- the documented contract.
        MoveCreatureUp name ->
            ( withEncounter (Encounter.moveUp name) model, Cmd.none )

        MoveCreatureDown name ->
            ( withEncounter (Encounter.moveDown name) model, Cmd.none )

        -- Initiative manager
        InitiativeOpen target ->
            ( { model | initiative = Just (freshInitiativeUi target) }
            , Cmd.none
            )

        InitiativeClose ->
            ( { model | initiative = Nothing }, Cmd.none )

        InitiativeCustomChanged text ->
            ( withInitiative (\u -> { u | customValueText = text }) model
            , Cmd.none
            )

        InitiativeQuickSort ->
            ( { model
                | encounter = Encounter.sortByInitiative model.encounter
                , initiative = Nothing
              }
            , Cmd.none
            )

        InitiativeAutoRollTarget ->
            -- Roll just the target's initiative. The handler is
            -- batchRollCmd-shaped (list of specs) so the resulting
            -- Msg arrives in the same shape as multi-creature rolls;
            -- the receiver handles 1-element and N-element batches
            -- through the same pipeline.
            case model.initiative of
                Just ui ->
                    ( model
                    , initiativeRollCmd
                        (List.filter (\c -> c.name == ui.target) model.encounter.creatures)
                    )

                Nothing ->
                    ( model, Cmd.none )

        InitiativeAutoRollAll ->
            ( model, initiativeRollCmd model.encounter.creatures )

        InitiativeAutoRollSelected ->
            ( model
            , initiativeRollCmd
                (List.filter .selected model.encounter.creatures)
            )

        InitiativeApplyTarget ->
            -- Manual override for one creature. Closes the modal
            -- whether or not the value parsed; an unparsable input
            -- gets silently discarded (same UX as the HP edit).
            case model.initiative of
                Just ui ->
                    ( applyCustomInitiative [ ui.target ] ui model
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        InitiativeApplySelected ->
            case model.initiative of
                Just ui ->
                    let
                        targets =
                            List.filter .selected model.encounter.creatures
                                |> List.map .name
                    in
                    ( applyCustomInitiative targets ui model
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        InitiativeRollsLanded results ->
            -- Fold each (creature name, roll) pair into a fresh
            -- Model: stamp the rolled total onto the creature's
            -- initiative, push the roll into the dice history.
            -- Then sort the queue, close the modal, and persist all
            -- the rolls server-side. mapCreature silently no-ops on
            -- unknown names so a stale roll (defensive) won't blow
            -- up.
            let
                applyOne ( name, roll ) m =
                    { m
                        | encounter =
                            Encounter.mapCreature name
                                (\c -> { c | initiative = roll.total })
                                m.encounter
                    }
                        |> withDice (\d -> { d | history = Dice.push roll d.history })

                m1 =
                    List.foldl applyOne model results

                rolls =
                    List.map Tuple.second results
            in
            ( { m1
                | encounter = Encounter.sortByInitiative m1.encounter
                , initiative = Nothing
              }
            , Cmd.batch (List.map persistRollCmd rolls)
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


{-| Apply `fn` to the open HP-change modal. No-op when the modal is
closed (the field is `Nothing`).
-}
withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model
withHpChange fn model =
    case model.hpChange of
        Just ui ->
            { model | hpChange = Just (fn ui) }

        Nothing ->
            model


{-| Click handler for the row 1 selection checkbox.

We intercept the raw `click` event so we can read the Shift modifier:
holding Shift while clicking dispatches `ShiftToggleSelected` (bulk
select-all / deselect-all), and a plain click toggles just the
clicked creature. We always `preventDefault` so the browser doesn't
auto-toggle the checkbox visual — its `checked` attribute is driven
straight from the model on the next render, keeping a single source
of truth and avoiding the double-toggle that an `onCheck` listener
plus the browser's default would cause.

-}
selectionClickHandler : String -> Html.Attribute Msg
selectionClickHandler creatureName =
    preventDefaultOn "click"
        (Decode.field "shiftKey" Decode.bool
            |> Decode.map
                (\shift ->
                    if shift then
                        ( ShiftToggleSelected, True )

                    else
                        ( ToggleSelected creatureName, True )
                )
        )


{-| Apply `fn` to the open initiative-manager modal. No-op when the
modal is closed.
-}
withInitiative : (InitiativeUi -> InitiativeUi) -> Model -> Model
withInitiative fn model =
    case model.initiative of
        Just ui ->
            { model | initiative = Just (fn ui) }

        Nothing ->
            model


{-| Build the `Cmd` for an initiative roll batch. The per-creature
expression is `1d20 + initiativeBonus` (matching the modal's caption
"Rolls 1d20 + creature's initiative bonus from stat block"), and
each roll is tagged so the dice history reads
"Initiative → Brakka, Ogre Brute".

Empty input → `Cmd.none` (handles the "Selected" buttons being
clicked when no creatures are selected).

-}
initiativeRollCmd : List Creature -> Cmd Msg
initiativeRollCmd creatures =
    if List.isEmpty creatures then
        Cmd.none

    else
        Dice.batchRollCmd InitiativeRollsLanded
            (List.map
                (\c ->
                    ( c.name
                    , initiativeSource c.name
                    , initiativeExpression c
                    )
                )
                creatures
            )


{-| `1d20 + creature.initiativeBonus`, the standard 5e initiative roll.
-}
initiativeExpression : Creature -> Dice.Expression
initiativeExpression c =
    { dice =
        [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = c.initiativeBonus
    , damageType = Nothing
    }


{-| Source label for initiative rolls so the dice history shows
"Initiative → <creature>".
-}
initiativeSource : String -> Dice.Source
initiativeSource name =
    { feature = "Initiative", target = Just name }


{-| Custom-initiative apply path: parse the modal's text input, set
each named creature's initiative to that value, sort the queue,
close the modal. An unparseable text just closes the modal without
mutating anything.
-}
applyCustomInitiative : List String -> InitiativeUi -> Model -> Model
applyCustomInitiative names ui model =
    case String.toInt (String.trim ui.customValueText) of
        Just n ->
            let
                applyOne name m =
                    { m
                        | encounter =
                            Encounter.mapCreature name
                                (\c -> { c | initiative = n })
                                m.encounter
                    }

                m1 =
                    List.foldl applyOne model names
            in
            { m1
                | encounter = Encounter.sortByInitiative m1.encounter
                , initiative = Nothing
            }

        Nothing ->
            { model | initiative = Nothing }


{-| Build the dice-roller `Source` label for an HP-change roll, so
the dice history reads e.g. "Damage → Brakka, Ogre Brute" rather
than just the formula.
-}
hpChangeSource : HpChangeUi -> Dice.Source
hpChangeSource ui =
    let
        feature =
            case ui.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"
    in
    { feature = feature, target = Just ui.target }


{-| Resolve the modal's kind + flags into an `HpChange.Change`,
hand it to the engine, write the updated creature back through
`Encounter.mapCreature`, push a log entry capturing the before/after
snapshot, and close the modal. The caller decides the amount — it
comes from the manual input on the manual path or from the rolled
total on the dice path.
-}
applyHpChangeAndClose : HpChangeUi -> Int -> Model -> Model
applyHpChangeAndClose ui amount model =
    let
        change =
            case ui.kind of
                DamageKind ->
                    HpChange.Damage
                        { amount = amount
                        , ignoreTemp = ui.ignoreTemp
                        }

                HealKind ->
                    HpChange.Heal amount

                TempHpKind ->
                    HpChange.TempHp amount

        before =
            findCreature ui.target model.encounter

        newEncounter =
            Encounter.mapCreature ui.target (HpChange.apply change) model.encounter

        after =
            findCreature ui.target newEncounter

        logEntry =
            Maybe.map2
                (\b a ->
                    { kind = ui.kind
                    , target = ui.target
                    , amount = amount
                    , beforeHp = b.currentHp
                    , beforeTemp = b.tempHp
                    , afterHp = a.currentHp
                    , afterTemp = a.tempHp
                    }
                )
                before
                after
    in
    { model
        | encounter = newEncounter
        , hpChange = Nothing
        , hpChangeLog =
            case logEntry of
                Just e ->
                    e :: List.take (maxHpLogEntries - 1) model.hpChangeLog

                Nothing ->
                    model.hpChangeLog
    }


{-| Look up a creature by name in an encounter. Used by the HP-change
log to grab before/after snapshots.
-}
findCreature : String -> Encounter -> Maybe Creature
findCreature name enc =
    List.filter (\c -> c.name == name) enc.creatures
        |> List.head


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


{-| GET the persisted dice history from the server. Failures (no
server, no file yet, malformed JSON) are not surfaced — the modal
just shows whatever is in the local in-memory copy.
-}
fetchDiceHistoryCmd : Cmd Msg
fetchDiceHistoryCmd =
    Http.get
        { url = "/api/dice/history"
        , expect = Http.expectJson DiceHistoryLoaded (Decode.list Dice.decodeRoll)
        }


{-| POST a fresh roll to the server's history endpoint. The response
body is the new (truncated) list, which we use to overwrite the local
view in `DicePersistResponse`.
-}
persistRollCmd : Dice.Roll -> Cmd Msg
persistRollCmd roll =
    Http.post
        { url = "/api/dice/history"
        , body = Http.jsonBody (Dice.encodeRoll roll)
        , expect = Http.expectJson DicePersistResponse (Decode.list Dice.decodeRoll)
        }


{-| DELETE the persisted history. Wraps `Http.request` because
elm/http doesn't ship an `Http.delete` shorthand.
-}
clearDiceHistoryCmd : Cmd Msg
clearDiceHistoryCmd =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/dice/history"
        , body = Http.emptyBody
        , expect = Http.expectWhatever DiceClearResponse
        , timeout = Nothing
        , tracker = Nothing
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
            , viewHpChangeModal model
            , viewInitiativeModal model
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
        [ viewPanelMain model.encounter model.hpEdit
        , viewPanelControls
        , viewPanelDetail
        ]


{-| The encounter pane. `hpEdit` is threaded through so any open
inline-edit input (current/max HP) renders on the right card.
-}
viewPanelMain : Encounter -> Maybe HpEdit -> Html Msg
viewPanelMain enc hpEdit =
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ viewEncounterBar enc ]
        , div [ class "panel__body" ]
            [ div [ class "creature-grid" ]
                (List.map (viewCreatureCard enc.activeName hpEdit) enc.creatures)
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


viewCreatureCard : String -> Maybe HpEdit -> Creature -> Html Msg
viewCreatureCard activeName hpEdit creature =
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
                    , selectionClickHandler creature.name
                    , attribute "aria-label" ("Select " ++ creature.name)
                    , title "Shift-click to select / deselect all"
                    ]
                    []
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureUp creature.name)
                    , title "Move up in queue (manual; ignores initiative)"
                    , attribute "aria-label" "Move up in queue"
                    ]
                    [ text "↑" ]
                , button
                    [ class "icon-btn"
                    , onClick (MoveCreatureDown creature.name)
                    , title "Move down in queue (manual; ignores initiative)"
                    , attribute "aria-label" "Move down in queue"
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
            , viewCardRowMid creature hpEdit
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
        [ button
            [ class "init-circle init-circle--clickable"
            , onClick (InitiativeOpen creature.name)
            , title "Click to open the initiative manager"
            , attribute "aria-label"
                ("Initiative " ++ String.fromInt creature.initiative ++ " — open initiative manager")
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


viewCardRowMid : Creature -> Maybe HpEdit -> Html Msg
viewCardRowMid creature hpEdit =
    div [ class "creature-card__row creature-card__row--mid" ]
        [ viewHpDisplay creature hpEdit
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


{-| Card row 2 HP readout: green current / muted max, plus an inline
"+N" temp-HP marker when the creature is buffed. Renders the actual
creature state. Both the current and max values are click-to-edit:
clicking swaps the span for a small `<input>` (autofocus + onBlur
commits, Enter commits, Esc cancels). The temp HP doesn't get an
inline editor — it's not a value the GM normally types directly,
and the Temp HP modal is the canonical write path.
-}
viewHpDisplay : Creature -> Maybe HpEdit -> Html Msg
viewHpDisplay creature hpEdit =
    span [ class "hp-display" ]
        [ viewHpEditable creature hpEdit CurrentHpField creature.currentHp "hp-display__current"
        , span [ class "hp-display__sep" ] [ text "/" ]
        , viewHpEditable creature hpEdit MaxHpField creature.maxHp "hp-display__max"
        , if creature.tempHp > 0 then
            span
                [ class "hp-display__temp"
                , title "Temporary hit points"
                ]
                [ text ("+" ++ String.fromInt creature.tempHp) ]

          else
            text ""
        ]


{-| Render either a clickable value or the active inline-edit
input, depending on whether `hpEdit` is targeting this creature +
field. Same shape as the dice modifier field — the input value
mirrors `edit.text` (raw characters) so transient empty / "-"
states aren't clobbered.
-}
viewHpEditable : Creature -> Maybe HpEdit -> HpField -> Int -> String -> Html Msg
viewHpEditable creature hpEdit field current cls =
    let
        isEditing =
            case hpEdit of
                Just e ->
                    e.target == creature.name && e.field == field

                Nothing ->
                    False
    in
    if isEditing then
        input
            [ class "hp-display__edit"
            , type_ "number"
            , Html.Attributes.min "0"
            , Html.Attributes.max "9999"
            , value (Maybe.withDefault "" (Maybe.map .text hpEdit))
            , onInput HpEditChange
            , Html.Events.onBlur HpEditCommit
            , Html.Events.on "keydown" hpEditKeyDecoder
            , autofocus True
            ]
            []

    else
        span
            [ class (cls ++ " hp-display__editable")
            , onClick (HpEditStart creature.name field current)
            , title "Click to edit"
            ]
            [ text (String.fromInt current) ]


{-| Enter commits the inline HP edit, Esc cancels. Other keys fall
through to the input's normal handling.
-}
hpEditKeyDecoder : Decode.Decoder Msg
hpEditKeyDecoder =
    Decode.field "key" Decode.string
        |> Decode.andThen
            (\key ->
                case key of
                    "Enter" ->
                        Decode.succeed HpEditCommit

                    "Escape" ->
                        Decode.succeed HpEditCancel

                    _ ->
                        Decode.fail "ignore"
            )


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
            , onClick (HpChangeOpen creature.name DamageKind)
            , title "Apply damage"
            ]
            [ text "Damage" ]
        , button
            [ class "action-btn action-btn--heal"
            , onClick (HpChangeOpen creature.name HealKind)
            , title "Heal hit points"
            ]
            [ text "Heal" ]
        , button
            [ class "action-btn action-btn--temp"
            , onClick (HpChangeOpen creature.name TempHpKind)
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
            (List.map (viewTrait sb.name) sb.traits)
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


viewTrait : String -> ( String, String ) -> Html Msg
viewTrait creatureName ( name, body ) =
    p []
        (strong [] [ text (name ++ ". ") ]
            :: List.map (viewSegment creatureName) (Dice.scan body)
        )


{-| Render one segment of scanned trait body. `Literal` runs render
as plain text; `DiceLink` segments render as clickable inline buttons
that fire a roll via the dice modal. `creatureName` is threaded
through so the resulting roll's `source` records which stat block
the formula came from.
-}
viewSegment : String -> Dice.Segment -> Html Msg
viewSegment creatureName segment =
    case segment of
        Dice.Literal s ->
            text s

        Dice.DiceLink shown expr ->
            button
                [ class "dice-link"
                , onClick (RollFromStatBlock creatureName expr)
                , title ("Roll " ++ shown)
                ]
                [ text shown ]



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
                , value ui.modifierText
                , onInput DiceModifierChanged
                ]
                []
            , button
                [ class "dice-form__reset"
                , onClick DiceResetSliders
                , title "Reset count to 1 and modifier to 0"
                , attribute "aria-label" "Reset count and modifier"
                ]
                [ text "❌" ]
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
            [ viewRollSource roll.source
            , text roll.formula
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


{-| Render the source chip on a history entry: "Damage → Brakka,
Ogre Brute" / "Stat block → Goblin Boss" / etc. Hides the chip for
the default `Manual` source since the dice modal's own buttons
already make the context obvious.
-}
viewRollSource : Dice.Source -> Html Msg
viewRollSource source =
    if source.feature == "Manual" then
        text ""

    else
        let
            label =
                case source.target of
                    Just t ->
                        source.feature ++ " → " ++ t

                    Nothing ->
                        source.feature
        in
        span [ class "dice-history__source", title label ]
            [ text label ]


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



-- HP CHANGE MODAL


{-| Renders the HP-change modal when one is open. Reuses the dice
modal's backdrop / panel shell — the chrome is the same, only the
body differs. Closes on backdrop click, ✕, or Cancel.
-}
viewHpChangeModal : Model -> Html Msg
viewHpChangeModal model =
    case model.hpChange of
        Nothing ->
            text ""

        Just ui ->
            let
                target =
                    List.filter (\c -> c.name == ui.target) model.encounter.creatures
                        |> List.head
            in
            div
                [ class "modal-backdrop"
                , onClick HpChangeClose
                ]
                [ div
                    [ class "modal modal--hp-change"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    ]
                    [ viewHpChangeHeader ui
                    , div [ class "modal__body" ]
                        [ viewHpChangeModeToggle ui
                        , viewHpChangeAmount ui
                        , viewHpChangeOptions ui
                        , case target of
                            Just c ->
                                viewHpChangePreview ui c

                            Nothing ->
                                text ""
                        , viewHpChangeFooter
                        , viewHpChangeLog model.hpChangeLog
                        ]
                    ]
                ]


viewHpChangeHeader : HpChangeUi -> Html Msg
viewHpChangeHeader ui =
    let
        verb =
            case ui.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"
    in
    div [ class "modal__header" ]
        [ div [ class "modal__title" ]
            [ text (verb ++ " — " ++ ui.target) ]
        , button
            [ class "modal__close"
            , onClick HpChangeClose
            , title "Cancel"
            , attribute "aria-label" "Cancel"
            ]
            [ text "×" ]
        ]


viewHpChangeModeToggle : HpChangeUi -> Html Msg
viewHpChangeModeToggle ui =
    div [ class "hp-change__mode" ]
        [ modeRadio "Manual" (ui.mode == ManualMode) (HpChangeModeSet ManualMode)
        , modeRadio "Roll dice" (ui.mode == DiceMode) (HpChangeModeSet DiceMode)
        ]


modeRadio : String -> Bool -> Msg -> Html Msg
modeRadio label isOn msg =
    button
        [ class
            (if isOn then
                "hp-change__mode-btn hp-change__mode-btn--active"

             else
                "hp-change__mode-btn"
            )
        , onClick msg
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ text label ]


viewHpChangeAmount : HpChangeUi -> Html Msg
viewHpChangeAmount ui =
    case ui.mode of
        ManualMode ->
            div [ class "hp-change__row" ]
                [ Html.label [ for "hp-amount" ] [ text "Amount" ]
                , input
                    [ id "hp-amount"
                    , class "hp-change__input"
                    , type_ "number"
                    , Html.Attributes.min "0"
                    , Html.Attributes.max "999"
                    , value ui.amountText
                    , onInput HpChangeAmountChanged
                    , Html.Events.on "keydown" (enterKey HpChangeApply)
                    ]
                    []
                ]

        DiceMode ->
            div []
                [ div [ class "hp-change__row" ]
                    [ Html.label [ for "hp-expression" ] [ text "Expression" ]
                    , input
                        [ id "hp-expression"
                        , class "hp-change__input"
                        , type_ "text"
                        , placeholder "e.g. 2d6+3"
                        , value ui.expression
                        , onInput HpChangeExpressionChanged
                        , Html.Events.on "keydown" (enterKey HpChangeApply)
                        ]
                        []
                    ]
                , case ui.parseError of
                    Just (Dice.ParseError raw) ->
                        div [ class "hp-change__error" ]
                            [ text ("Couldn't parse: " ++ raw) ]

                    Nothing ->
                        text ""
                ]


viewHpChangeOptions : HpChangeUi -> Html Msg
viewHpChangeOptions ui =
    case ui.kind of
        DamageKind ->
            div [ class "hp-change__row" ]
                [ Html.label [ class "hp-change__checkbox" ]
                    [ input
                        [ type_ "checkbox"
                        , checked ui.ignoreTemp
                        , onClick HpChangeIgnoreTempToggle
                        ]
                        []
                    , text " Ignore temporary HP"
                    ]
                ]

        _ ->
            text ""


{-| Preview of the manual-mode arithmetic: shows what the change
would do to the target's HP if Apply were clicked right now. In
dice mode the result depends on the roll, so we show the expression
that will be rolled instead of a numeric prediction.
-}
viewHpChangePreview : HpChangeUi -> Creature -> Html Msg
viewHpChangePreview ui c =
    let
        before =
            hpBeforeText c
    in
    div [ class "hp-change__preview" ]
        [ div [ class "hp-change__preview-label" ] [ text "Preview" ]
        , div [ class "hp-change__preview-body" ]
            (case ui.mode of
                ManualMode ->
                    let
                        change =
                            buildPreviewChange ui ui.amount

                        after =
                            HpChange.apply change c
                    in
                    [ text before
                    , span [ class "hp-change__preview-arrow" ] [ text " → " ]
                    , text (hpAfterText after)
                    ]

                DiceMode ->
                    [ text before
                    , span [ class "hp-change__preview-arrow" ] [ text " → " ]
                    , span [ class "hp-change__preview-roll" ]
                        [ text
                            (if String.isEmpty (String.trim ui.expression) then
                                "(enter an expression)"

                             else
                                "roll " ++ String.trim ui.expression
                            )
                        ]
                    ]
            )
        ]


buildPreviewChange : HpChangeUi -> Int -> HpChange.Change
buildPreviewChange ui amount =
    case ui.kind of
        DamageKind ->
            HpChange.Damage { amount = amount, ignoreTemp = ui.ignoreTemp }

        HealKind ->
            HpChange.Heal amount

        TempHpKind ->
            HpChange.TempHp amount


hpBeforeText : Creature -> String
hpBeforeText c =
    String.fromInt c.currentHp
        ++ "/"
        ++ String.fromInt c.maxHp
        ++ (if c.tempHp > 0 then
                " (+" ++ String.fromInt c.tempHp ++ " temp)"

            else
                ""
           )


hpAfterText : Creature -> String
hpAfterText c =
    String.fromInt c.currentHp
        ++ "/"
        ++ String.fromInt c.maxHp
        ++ (if c.tempHp > 0 then
                " (+" ++ String.fromInt c.tempHp ++ " temp)"

            else
                ""
           )


viewHpChangeFooter : Html Msg
viewHpChangeFooter =
    div [ class "hp-change__footer" ]
        [ button
            [ class "action-btn"
            , onClick HpChangeClose
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick HpChangeApply
            ]
            [ text "Apply" ]
        ]


{-| Last-N HP-change log shown at the bottom of the modal. Includes
every kind (damage / heal / temp) so the GM can see recent table
context without flipping between the three modal verbs. Empty state
shows a small "No HP changes yet" line so the section doesn't
collapse to nothing on first open.
-}
viewHpChangeLog : List HpChangeEntry -> Html Msg
viewHpChangeLog entries =
    div [ class "hp-change__log" ]
        [ div [ class "hp-change__log-title" ]
            [ text ("Recent HP changes (" ++ String.fromInt (List.length entries) ++ ")") ]
        , if List.isEmpty entries then
            div [ class "hp-change__log-empty" ]
                [ text "No HP changes yet." ]

          else
            ul [ class "hp-change__log-list" ]
                (List.map viewHpChangeLogEntry entries)
        ]


viewHpChangeLogEntry : HpChangeEntry -> Html Msg
viewHpChangeLogEntry entry =
    let
        kindLabel =
            case entry.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"

        kindClass =
            case entry.kind of
                DamageKind ->
                    "hp-change__log-kind hp-change__log-kind--damage"

                HealKind ->
                    "hp-change__log-kind hp-change__log-kind--heal"

                TempHpKind ->
                    "hp-change__log-kind hp-change__log-kind--temp"

        beforeStr =
            hpSnapshot entry.beforeHp entry.beforeTemp

        afterStr =
            hpSnapshot entry.afterHp entry.afterTemp
    in
    li [ class "hp-change__log-entry" ]
        [ span [ class kindClass ] [ text kindLabel ]
        , span [ class "hp-change__log-target" ] [ text entry.target ]
        , span [ class "hp-change__log-amount" ]
            [ text (String.fromInt entry.amount) ]
        , span [ class "hp-change__log-trans" ]
            [ text (beforeStr ++ " → " ++ afterStr) ]
        ]


{-| Render an HP+temp pair for the log: "27/59" or "27/59 +5" when
temp HP is positive. Reused for both before and after columns.
-}
hpSnapshot : Int -> Int -> String
hpSnapshot hp temp =
    if temp > 0 then
        String.fromInt hp ++ " +" ++ String.fromInt temp

    else
        String.fromInt hp



-- INITIATIVE MANAGER MODAL


{-| Renders the initiative manager when one is open. Three stacked
sections: a single-button quick sort, an auto-roll batch (one button
each for target / all / selected), and a custom value entry with
target / selected apply. Closes on backdrop click or Cancel.
-}
viewInitiativeModal : Model -> Html Msg
viewInitiativeModal model =
    case model.initiative of
        Nothing ->
            text ""

        Just ui ->
            let
                selectedCount =
                    List.length (List.filter .selected model.encounter.creatures)
            in
            div
                [ class "modal-backdrop"
                , onClick InitiativeClose
                ]
                [ div
                    [ class "modal modal--initiative"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    , attribute "aria-label" "Initiative manager"
                    ]
                    [ viewInitiativeHeader ui
                    , div [ class "modal__body" ]
                        [ viewInitiativeQuickSort
                        , viewInitiativeAutoRoll ui selectedCount
                        , viewInitiativeCustom ui selectedCount
                        , viewInitiativeFooter
                        ]
                    ]
                ]


viewInitiativeHeader : InitiativeUi -> Html Msg
viewInitiativeHeader ui =
    div [ class "modal__header" ]
        [ div [ class "modal__title" ]
            [ text ("Initiative — " ++ ui.target) ]
        , button
            [ class "modal__close"
            , onClick InitiativeClose
            , title "Cancel"
            , attribute "aria-label" "Cancel"
            ]
            [ text "×" ]
        ]


viewInitiativeQuickSort : Html Msg
viewInitiativeQuickSort =
    div [ class "init-section" ]
        [ button
            [ class "action-btn action-btn--blue init-btn-block"
            , onClick InitiativeQuickSort
            ]
            [ text "🔄 Quick Sort Encounter" ]
        , div [ class "init-section__caption" ]
            [ text "Sort all creatures by their current initiative values" ]
        ]


viewInitiativeAutoRoll : InitiativeUi -> Int -> Html Msg
viewInitiativeAutoRoll ui selectedCount =
    div [ class "init-section" ]
        [ h3 [ class "init-section__heading" ]
            [ text "Auto-roll Initiative" ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeAutoRollTarget
            ]
            [ text ("🎲 Roll Initiative & Sort: " ++ ui.target) ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeAutoRollAll
            ]
            [ text "🎲 Roll Initiative & Sort: All" ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeAutoRollSelected
            , disabled (selectedCount == 0)
            , attribute "aria-disabled"
                (if selectedCount == 0 then
                    "true"

                 else
                    "false"
                )
            , title (selectedTitle selectedCount)
            ]
            [ text ("🎲 Roll Initiative & Sort: Selected" ++ selectedCountSuffix selectedCount) ]
        , div [ class "init-section__caption" ]
            [ text "Rolls 1d20 + creature's initiative bonus from stat block" ]
        ]


viewInitiativeCustom : InitiativeUi -> Int -> Html Msg
viewInitiativeCustom ui selectedCount =
    div [ class "init-section" ]
        [ h3 [ class "init-section__heading" ]
            [ text "Custom Initiative" ]
        , div [ class "init-section__row" ]
            [ Html.label [ for "init-custom-value" ]
                [ text "Initiative Value:" ]
            , input
                [ id "init-custom-value"
                , class "init-section__input"
                , type_ "number"
                , Html.Attributes.min "-99"
                , Html.Attributes.max "99"
                , value ui.customValueText
                , onInput InitiativeCustomChanged
                , Html.Events.on "keydown" (enterKey InitiativeApplyTarget)
                ]
                []
            ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeApplyTarget
            ]
            [ text ("Apply & Sort: " ++ ui.target) ]
        , button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick InitiativeApplySelected
            , disabled (selectedCount == 0)
            , attribute "aria-disabled"
                (if selectedCount == 0 then
                    "true"

                 else
                    "false"
                )
            , title (selectedTitle selectedCount)
            ]
            [ text ("Apply & Sort: Selected" ++ selectedCountSuffix selectedCount) ]
        ]


{-| Tooltip for "Selected" buttons: explains why they're disabled
when no creatures are checked, and confirms the count when at least
one is. Saves the GM a click to figure out why nothing happens.
-}
selectedTitle : Int -> String
selectedTitle n =
    case n of
        0 ->
            "No creatures are selected — tick the row 1 checkbox on the cards you want first"

        1 ->
            "1 creature selected"

        _ ->
            String.fromInt n ++ " creatures selected"


selectedCountSuffix : Int -> String
selectedCountSuffix n =
    if n > 0 then
        " (" ++ String.fromInt n ++ ")"

    else
        ""


viewInitiativeFooter : Html Msg
viewInitiativeFooter =
    div [ class "init-footer" ]
        [ button
            [ class "action-btn"
            , onClick InitiativeClose
            ]
            [ text "Close" ]
        ]
