module Main exposing (main)

import Browser
import Browser.Dom
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
import Random
import Task
import Url exposing (Url)
import Url.Parser exposing (Parser, oneOf, top)
import Util.Keyboard



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
    , noteEdit : Maybe NoteEditUi
    , conditionUi : Maybe ConditionUi
    , memoEdit : Maybe MemoEditUi
    , timerSetup : Maybe TimerSetupUi
    }


{-| Note-edit modal state. Open when the user clicks the row 1
pencil button on a creature card. `target` identifies the creature;
`text` mirrors the `<input>` value so re-renders don't clobber
transient typing. The text is hard-capped at `maxNoteLength`
characters at input time so we never have to truncate on commit.
-}
type alias NoteEditUi =
    { target : String
    , text : String
    }


{-| Hard cap on creature notes. Twenty characters keeps the inline
display next to the name from blowing out the card width — anything
longer belongs in a real journal entry, not a card sticky.
-}
maxNoteLength : Int
maxNoteLength =
    20


freshNoteEditUi : String -> String -> NoteEditUi
freshNoteEditUi target current =
    { target = target
    , text = current
    }


{-| Card row 3 memo edit modal state. Same general shape as
`NoteEditUi` (the row 1 short label) but writes to a different
field on `Creature` — `memo` instead of `note` — so the two can
coexist on a card.
-}
type alias MemoEditUi =
    { target : String
    , text : String
    }


maxMemoLength : Int
maxMemoLength =
    20


freshMemoEditUi : String -> String -> MemoEditUi
freshMemoEditUi target current =
    { target = target
    , text = current
    }


{-| Card row 3 timer setup modal state. The GM picks a count
(1..99) and a phase (begin/end of the bearer's turn). Apply
writes the timer onto the creature; cancel discards.
-}
type alias TimerSetupUi =
    { target : String
    , turnsText : String
    , turns : Int
    , phase : Encounter.TurnPhase
    }


freshTimerSetupUi : String -> TimerSetupUi
freshTimerSetupUi target =
    { target = target
    , turnsText = "3"
    , turns = 3
    , phase = Encounter.AtEnd
    }


{-| Condition / effect modal state.

`target` is the creature whose Condition/Effect button (or chip)
was clicked. `editingId` is `Nothing` when creating a new condition
and `Just id` when editing an existing one — the latter unlocks a
"Delete" button in the modal footer.

The remaining fields mirror the rendered form. We track raw text
inputs alongside parsed integers (the same trick as the dice
modifier and HP edit fields) so transient typing states don't get
clobbered between keystrokes.

`customName` is the free-text input under the radio group; the
radio group itself sets `name` directly. When the user clicks a
radio, `customName` is cleared and `name` becomes the chosen label.
When the user types into the custom input, `name` and `customName`
are both updated to that value (so the radios visually deselect).

`saveToEnd : Maybe SaveToEndUi` controls visibility of the save
section: `Nothing` hides it, `Just _` reveals.

-}
type alias ConditionUi =
    { target : String
    , editingId : Maybe Int
    , name : String
    , customName : String
    , note : String
    , durationKind : DurationKind
    , untilCreature : String
    , untilPhase : Encounter.TurnPhase
    , untilTarget : Encounter.TurnTarget
    , countdownTurnsText : String
    , countdownTurns : Int
    , countdownPhase : Encounter.TurnPhase
    , saveToEnd : Maybe SaveToEndUi
    , applyToSelected : Bool
    }


type DurationKind
    = DurKindManual
    | DurKindUntilTurn
    | DurKindCountdown


type alias SaveToEndUi =
    { ability : String
    , dcText : String
    , dc : Int
    , bonusText : String
    , bonus : Int
    , autoRoll : Encounter.AutoRollMode
    }


{-| Default save spec when the user enables "save to end" — DC 10
neutral save, no bonus, manual roll. The GM tweaks from there.
Manual is the safest default since auto-rolling at begin- or
end-of-turn could surprise the GM with an end-of-condition the
moment they enable save-to-end at all.
-}
freshSaveToEndUi : SaveToEndUi
freshSaveToEndUi =
    { ability = "WIS"
    , dcText = "10"
    , dc = 10
    , bonusText = "0"
    , bonus = 0
    , autoRoll = Encounter.AutoRollManual
    }


{-| Fresh condition-modal state for creating a new condition on
`target`. The "until X's turn" reference defaults to the target
itself — common for self-effects like "Concentrating until end of
my next turn".
-}
freshConditionUi : String -> ConditionUi
freshConditionUi target =
    { target = target
    , editingId = Nothing
    , name = ""
    , customName = ""
    , note = ""
    , durationKind = DurKindManual
    , untilCreature = target
    , untilPhase = Encounter.AtEnd
    , untilTarget = Encounter.OnNextTurn
    , countdownTurnsText = "1"
    , countdownTurns = 1
    , countdownPhase = Encounter.AtEnd
    , saveToEnd = Nothing
    , applyToSelected = False
    }


{-| Pre-fill the modal's form fields from an existing condition so
the GM can edit it. Reverse of [`uiToConditionDraft`](#uiToConditionDraft):
break a stored Condition apart into the raw text states the form
needs.
-}
conditionToUi : String -> Encounter.Condition -> ConditionUi
conditionToUi target cond =
    let
        durFields =
            case cond.duration of
                Encounter.DurationManual ->
                    { kind = DurKindManual
                    , untilCreature = target
                    , untilPhase = Encounter.AtEnd
                    , untilTarget = Encounter.OnNextTurn
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationUntilTurn phase tgt ref ->
                    { kind = DurKindUntilTurn
                    , untilCreature = ref
                    , untilPhase = phase
                    , untilTarget = tgt
                    , countdownTurns = 1
                    , countdownPhase = Encounter.AtEnd
                    }

                Encounter.DurationCountdown phase n _ ->
                    { kind = DurKindCountdown
                    , untilCreature = target
                    , untilPhase = Encounter.AtEnd
                    , untilTarget = Encounter.OnNextTurn
                    , countdownTurns = n
                    , countdownPhase = phase
                    }

        saveUi =
            cond.saveToEnd
                |> Maybe.map
                    (\s ->
                        { ability = s.ability
                        , dcText = String.fromInt s.dc
                        , dc = s.dc
                        , bonusText = String.fromInt s.bonus
                        , bonus = s.bonus
                        , autoRoll = s.autoRoll
                        }
                    )
    in
    { target = target
    , editingId = Just cond.id
    , name = cond.name
    , customName =
        if List.member cond.name Encounter.standardConditions then
            ""

        else
            cond.name
    , note = cond.note
    , durationKind = durFields.kind
    , untilCreature = durFields.untilCreature
    , untilPhase = durFields.untilPhase
    , untilTarget = durFields.untilTarget
    , countdownTurnsText = String.fromInt durFields.countdownTurns
    , countdownTurns = durFields.countdownTurns
    , countdownPhase = durFields.countdownPhase
    , saveToEnd = saveUi
    , applyToSelected = False
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


{-| Which set of creatures an auto-roll applies to.

  - `ScopeTarget` — the creature whose init-circle was clicked
    (the modal's `target`).
  - `ScopeAll` — every creature in the queue.
  - `ScopeSelected` — only creatures with `selected = True`. The
    button is disabled (and emits no Cmd) when nothing is selected.

-}
type RollScope
    = ScopeTarget
    | ScopeAll
    | ScopeSelected


{-| Standard 1d20 vs. 5e advantage (roll twice, keep highest). The
spec only asked for advantage, but the type is left open so a
future "Disadvantage" sister button drops in as a third constructor
without churning the Msg shape again.
-}
type RollMode
    = ModeStandard
    | ModeAdvantage


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
    , applyToSelected : Bool
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
    , applyToSelected = False
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
    , unread : Bool
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
    , unread = False
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
    | DeathSaveToggleSuccess String Int
    | DeathSaveToggleFailure String Int
    | DeathSaveRoll String
    | DeathSaveRollLanded String Dice.Roll
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
    | HpChangeApplyToSelectedToggle
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
      -- Roster mutation (right rail × / ⧉ buttons)
    | RemoveCreature String
    | DuplicateCreature String
      -- Initiative manager modal
    | InitiativeOpen String
    | InitiativeClose
    | InitiativeCustomChanged String
    | InitiativeQuickSort
    | InitiativeAutoRoll RollScope RollMode
    | InitiativeApplyTarget
    | InitiativeApplySelected
    | InitiativeRollsLanded (List ( String, Dice.Roll ))
    | ActiveCardScrollChecked (Result Browser.Dom.Error ())
      -- Note-edit modal (the row 1 pencil button)
    | NoteEditOpen String String
    | NoteEditChange String
    | NoteEditCommit
    | NoteEditCancel
      -- Condition / effect modal
    | ConditionOpenNew String
    | ConditionOpenEdit String Int
    | ConditionClose
    | ConditionPickStandard String
    | ConditionCustomNameChanged String
    | ConditionNoteChanged String
    | ConditionDurationKindSet DurationKind
    | ConditionUntilCreatureChanged String
    | ConditionUntilPhaseSet Encounter.TurnPhase
    | ConditionUntilTargetSet Encounter.TurnTarget
    | ConditionCountdownTurnsChanged String
    | ConditionCountdownPhaseSet Encounter.TurnPhase
    | ConditionSaveToggle
    | ConditionSaveAbilityChanged String
    | ConditionSaveDcChanged String
    | ConditionSaveBonusChanged String
    | ConditionSaveAutoRollSet Encounter.AutoRollMode
    | ConditionApplyToSelectedToggle
    | ConditionSubmit
    | ConditionDelete
    | ConditionRemoveChip String Int
    | ConditionRollSave String Int
    | ConditionSaveLanded String Int Int Bool Dice.Roll
      -- (creature, condition id, dc, wasAutoRoll, roll)
    | SaveNoticeDismiss String Int
      -- Card row 3 memo
    | MemoOpen String
    | MemoChange String
    | MemoCommit
    | MemoCancel
    | MemoClear String
      -- Card row 3 timer
    | TimerOpen String
    | TimerSetupTurnsChanged String
    | TimerSetupPhaseSet Encounter.TurnPhase
    | TimerSetupApply
    | TimerSetupCancel
    | TimerDismiss String
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
        Browser.Events.onKeyDown (escKey CloseDice)

    else if model.noteEdit /= Nothing then
        Browser.Events.onKeyDown (escKey NoteEditCancel)

    else
        Sub.none


escKey : Msg -> Decode.Decoder Msg
escKey =
    Util.Keyboard.escKey


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
      , noteEdit = Nothing
      , conditionUi = Nothing
      , memoEdit = Nothing
      , timerSetup = Nothing
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
            -- Domain layer owns the queue walk, round bookkeeping,
            -- and condition lifecycle hooks (begin / end of turn).
            -- The update layer fires the side effects:
            --   - auto-roll saves at the OUTGOING creature's
            --     end-of-turn (AutoRollAtEnd),
            --   - auto-roll saves at the INCOMING creature's
            --     begin-of-turn (AutoRollAtBegin),
            --   - and a viewport check so the active card scrolls
            --     into view.
            -- Both auto-roll batches read the post-`nextTurn`
            -- encounter so they see the outgoing creature's
            -- conditions AFTER end-of-turn ticks (any UntilTurn
            -- AtEnd <self> already expired, so we don't roll for
            -- a condition the engine just removed).
            let
                outgoingName =
                    model.encounter.activeName

                newEnc =
                    Encounter.nextTurn model.encounter

                endRolls =
                    autoRollCmdsFor Encounter.AutoRollAtEnd outgoingName newEnc

                beginRolls =
                    autoRollCmdsFor Encounter.AutoRollAtBegin newEnc.activeName newEnc
            in
            ( { model | encounter = newEnc }
            , Cmd.batch
                (scrollActiveIntoViewCmd newEnc.activeName
                    :: endRolls
                    ++ beginRolls
                )
            )

        SetActive name ->
            -- Manual jump (the right-arrow button on a card). Distinct
            -- from NextTurn: no round bump, no turn-progression hooks
            -- when those land. See Encounter.setActive for rationale.
            -- Scroll-into-view still runs so the GM sees the card
            -- they just promoted.
            ( withEncounter (Encounter.setActive name) model
            , scrollActiveIntoViewCmd name
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

        DeathSaveToggleSuccess name idx ->
            -- Click on success pip `idx` (0..2). Star-rating
            -- semantics: clicking a filled pip clears it and every
            -- later one (so unchecking pip 0 wipes pips 1 and 2);
            -- clicking an empty pip fills up to and including it.
            -- Pure visual toggle — no roll fired here.
            ( withEncounter
                (Encounter.mapCreature name
                    (\c ->
                        { c
                            | deathSaves =
                                let
                                    ds =
                                        c.deathSaves
                                in
                                { ds | successes = pipStripTarget idx ds.successes }
                        }
                    )
                )
                model
            , Cmd.none
            )

        DeathSaveToggleFailure name idx ->
            ( withEncounter
                (Encounter.mapCreature name
                    (\c ->
                        { c
                            | deathSaves =
                                let
                                    ds =
                                        c.deathSaves
                                in
                                { ds | failures = pipStripTarget idx ds.failures }
                        }
                    )
                )
                model
            , Cmd.none
            )

        DeathSaveRoll name ->
            -- Fire a 1d20 roll tagged so the dice history reads
            -- "Death save → <name>". The result lands in
            -- DeathSaveRollLanded which interprets it per 5e.
            ( model
            , Dice.rollCmd (DeathSaveRollLanded name)
                (deathSaveSource name)
                deathSaveExpression
            )

        DeathSaveRollLanded name roll ->
            -- 5e death-save rules:
            --   nat 1  → +2 failures
            --   2..9   → +1 failure
            --   10..19 → +1 success
            --   nat 20 → revive at 1 HP, clear tracker, conscious
            -- The roll itself is a plain 1d20 with no modifier so
            -- `roll.total` is the d20 face. Apply the rule, push
            -- the roll into the dice history, and persist.
            let
                applyRule c =
                    applyDeathSaveResult roll.total c
            in
            ( { model
                | encounter = Encounter.mapCreature name applyRule model.encounter
              }
                |> pushDiceRoll roll
            , persistRollCmd roll
            )

        ToggleHolding name ->
            ( withEncounter (Encounter.mapCreature name (\c -> { c | holding = not c.holding })) model
            , Cmd.none
            )

        -- Dice modal lifecycle
        OpenDice ->
            -- Clear the "unread rolls landed" flag whenever the
            -- modal opens; whatever the user is about to see, they
            -- are now caught up.
            ( withDice (\d -> { d | open = True, inputError = Nothing, unread = False }) model
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
            ( pushDiceRoll roll model
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

        HpChangeApplyToSelectedToggle ->
            ( withHpChange (\u -> { u | applyToSelected = not u.applyToSelected }) model
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
                                        (hpChangeSource ui model.encounter)
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
                    pushDiceRoll roll model

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

        -- Roster mutation
        RemoveCreature name ->
            ( withEncounter (Encounter.removeCreature name) model, Cmd.none )

        DuplicateCreature name ->
            ( withEncounter (Encounter.duplicateCreature name) model, Cmd.none )

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

        InitiativeAutoRoll scope mode ->
            -- Resolve which creatures the scope picks out and fire
            -- one batched roll Cmd. Mode picks the per-creature
            -- generator (standard 1d20+bonus vs. 2d20-keep-high+
            -- bonus). The handler (InitiativeRollsLanded) is
            -- shape-agnostic — it works for 1-element or N-element
            -- batches and for either roll mode.
            let
                creatures =
                    case scope of
                        ScopeTarget ->
                            case model.initiative of
                                Just ui ->
                                    List.filter
                                        (\c -> c.name == ui.target)
                                        model.encounter.creatures

                                Nothing ->
                                    []

                        ScopeAll ->
                            model.encounter.creatures

                        ScopeSelected ->
                            List.filter .selected model.encounter.creatures
            in
            ( model, initiativeRollCmd mode creatures )

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
                        |> pushDiceRoll roll

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

        -- Note-edit modal
        NoteEditOpen name current ->
            ( { model | noteEdit = Just (freshNoteEditUi name current) }
            , Cmd.none
            )

        NoteEditChange text ->
            -- Cap the text at maxNoteLength here so the model never
            -- holds an over-long note even if a paste sneaks past
            -- the input's `maxlength` attribute.
            ( withNoteEdit (\u -> { u | text = String.left maxNoteLength text }) model
            , Cmd.none
            )

        NoteEditCommit ->
            -- Trim trailing whitespace before stamping. Empty strings
            -- are valid (clears the note) — that's how the user
            -- removes a note without a separate "delete" action.
            case model.noteEdit of
                Just ui ->
                    let
                        trimmed =
                            String.trim ui.text
                    in
                    ( { model
                        | encounter =
                            Encounter.mapCreature ui.target
                                (\c -> { c | note = trimmed })
                                model.encounter
                        , noteEdit = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        NoteEditCancel ->
            ( { model | noteEdit = Nothing }, Cmd.none )

        -- Condition / effect modal lifecycle
        ConditionOpenNew name ->
            ( { model | conditionUi = Just (freshConditionUi name) }, Cmd.none )

        ConditionOpenEdit name id ->
            ( case Encounter.findCondition name id model.encounter of
                Just ( _, cond ) ->
                    { model | conditionUi = Just (conditionToUi name cond) }

                Nothing ->
                    model
            , Cmd.none
            )

        ConditionClose ->
            ( { model | conditionUi = Nothing }, Cmd.none )

        ConditionPickStandard label ->
            ( withConditionUi
                (\u -> { u | name = label, customName = "" })
                model
            , Cmd.none
            )

        ConditionCustomNameChanged text ->
            -- Typing in the custom field both populates the name
            -- and clears the standard radio selection (logically:
            -- "name" is whatever the user last touched).
            ( withConditionUi
                (\u -> { u | name = text, customName = text })
                model
            , Cmd.none
            )

        ConditionNoteChanged text ->
            ( withConditionUi
                (\u -> { u | note = String.left maxConditionNoteLength text })
                model
            , Cmd.none
            )

        ConditionDurationKindSet kind ->
            ( withConditionUi (\u -> { u | durationKind = kind }) model, Cmd.none )

        ConditionUntilCreatureChanged name ->
            -- Switching the reference creature can make
            -- "begin + current" newly invalid (or no longer
            -- invalid). Repair the target field if so — the GM
            -- doesn't want to babysit the radio after a dropdown
            -- change.
            ( withConditionUi
                (\u -> repairUntilTarget model { u | untilCreature = name })
                model
            , Cmd.none
            )

        ConditionUntilPhaseSet phase ->
            ( withConditionUi
                (\u -> repairUntilTarget model { u | untilPhase = phase })
                model
            , Cmd.none
            )

        ConditionUntilTargetSet target ->
            ( withConditionUi (\u -> { u | untilTarget = target }) model, Cmd.none )

        ConditionCountdownTurnsChanged text ->
            ( withConditionUi
                (\u ->
                    { u
                        | countdownTurnsText = text
                        , countdownTurns =
                            String.toInt (String.trim text)
                                |> Maybe.map (Basics.max 1 >> Basics.min 99)
                                |> Maybe.withDefault u.countdownTurns
                    }
                )
                model
            , Cmd.none
            )

        ConditionCountdownPhaseSet phase ->
            ( withConditionUi (\u -> { u | countdownPhase = phase }) model, Cmd.none )

        ConditionSaveToggle ->
            ( withConditionUi
                (\u ->
                    { u
                        | saveToEnd =
                            case u.saveToEnd of
                                Just _ ->
                                    Nothing

                                Nothing ->
                                    Just freshSaveToEndUi
                    }
                )
                model
            , Cmd.none
            )

        ConditionSaveAbilityChanged ability ->
            ( withConditionUi
                (\u -> { u | saveToEnd = Maybe.map (\s -> { s | ability = ability }) u.saveToEnd })
                model
            , Cmd.none
            )

        ConditionSaveDcChanged text ->
            ( withConditionUi
                (\u ->
                    { u
                        | saveToEnd =
                            Maybe.map
                                (\s ->
                                    { s
                                        | dcText = text
                                        , dc =
                                            String.toInt (String.trim text)
                                                |> Maybe.withDefault s.dc
                                    }
                                )
                                u.saveToEnd
                    }
                )
                model
            , Cmd.none
            )

        ConditionSaveBonusChanged text ->
            ( withConditionUi
                (\u ->
                    { u
                        | saveToEnd =
                            Maybe.map
                                (\s ->
                                    { s
                                        | bonusText = text
                                        , bonus =
                                            String.toInt (String.trim text)
                                                |> Maybe.withDefault s.bonus
                                    }
                                )
                                u.saveToEnd
                    }
                )
                model
            , Cmd.none
            )

        ConditionSaveAutoRollSet mode ->
            ( withConditionUi
                (\u ->
                    { u
                        | saveToEnd =
                            Maybe.map (\s -> { s | autoRoll = mode })
                                u.saveToEnd
                    }
                )
                model
            , Cmd.none
            )

        ConditionApplyToSelectedToggle ->
            ( withConditionUi (\u -> { u | applyToSelected = not u.applyToSelected }) model
            , Cmd.none
            )

        ConditionSubmit ->
            -- Validate that there's a name; empty-name conditions
            -- are silently dropped (close the modal). Build a draft,
            -- then either insert (creating) or update (editing).
            case model.conditionUi of
                Just ui ->
                    let
                        name =
                            String.trim ui.name
                    in
                    if String.isEmpty name then
                        ( { model | conditionUi = Nothing }, Cmd.none )

                    else
                        ( commitCondition ui name model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ConditionDelete ->
            -- Delete from the modal's footer (only visible when editing).
            case model.conditionUi of
                Just ui ->
                    case ui.editingId of
                        Just id ->
                            ( { model
                                | encounter = Encounter.removeCondition ui.target id model.encounter
                                , conditionUi = Nothing
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( { model | conditionUi = Nothing }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ConditionRemoveChip name id ->
            ( { model | encounter = Encounter.removeCondition name id model.encounter }
            , Cmd.none
            )

        ConditionRollSave name id ->
            -- Manual click on the save chip's d20 button. Same Cmd
            -- shape as the auto-roll path, but flagged
            -- `wasAutoRoll = False` so a successful save removes
            -- the condition silently rather than posting a
            -- "Saved: <name>" notice on the card.
            case Encounter.findCondition name id model.encounter of
                Just ( _, cond ) ->
                    case cond.saveToEnd of
                        Just spec ->
                            ( model
                            , Dice.rollCmd (ConditionSaveLanded name id spec.dc False)
                                (saveSource cond name spec)
                                (saveExpression spec.bonus)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ConditionSaveLanded name id dc wasAutoRoll roll ->
            -- Save resolves: roll.total >= dc means the condition
            -- ends. Look up the condition name BEFORE we remove it
            -- so the auto-roll success path can post a notice with
            -- the right label. Manual rolls remove silently.
            let
                conditionName =
                    Encounter.findCondition name id model.encounter
                        |> Maybe.map (\( _, cond ) -> cond.name)

                succeeded =
                    roll.total >= dc

                m1 =
                    if succeeded then
                        let
                            removed =
                                { model
                                    | encounter = Encounter.removeCondition name id model.encounter
                                }
                        in
                        case ( wasAutoRoll, conditionName ) of
                            ( True, Just label ) ->
                                { removed
                                    | encounter =
                                        Encounter.addSaveNotice name label removed.encounter
                                }

                            _ ->
                                removed

                    else
                        model
            in
            ( m1 |> pushDiceRoll roll
            , persistRollCmd roll
            )

        SaveNoticeDismiss name id ->
            ( { model | encounter = Encounter.removeSaveNotice name id model.encounter }
            , Cmd.none
            )

        ActiveCardScrollChecked _ ->
            -- Result of the scroll-into-view Task. Either the scroll
            -- worked or the element wasn't found (defensive); either
            -- way, nothing further to do.
            ( model, Cmd.none )

        -- Memo modal (card row 3 📝)
        MemoOpen name ->
            let
                current =
                    model.encounter.creatures
                        |> List.filter (\c -> c.name == name)
                        |> List.head
                        |> Maybe.map .memo
                        |> Maybe.withDefault ""
            in
            ( { model | memoEdit = Just (freshMemoEditUi name current) }
            , Cmd.none
            )

        MemoChange text ->
            ( withMemoEdit (\u -> { u | text = String.left maxMemoLength text }) model
            , Cmd.none
            )

        MemoCommit ->
            case model.memoEdit of
                Just ui ->
                    let
                        trimmed =
                            String.trim ui.text
                    in
                    ( { model
                        | encounter =
                            Encounter.mapCreature ui.target
                                (\c -> { c | memo = trimmed })
                                model.encounter
                        , memoEdit = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        MemoCancel ->
            ( { model | memoEdit = Nothing }, Cmd.none )

        MemoClear name ->
            ( { model
                | encounter =
                    Encounter.mapCreature name (\c -> { c | memo = "" }) model.encounter
              }
            , Cmd.none
            )

        -- Timer modal (card row 3 ⏱)
        TimerOpen name ->
            ( { model | timerSetup = Just (freshTimerSetupUi name) }
            , Cmd.none
            )

        TimerSetupTurnsChanged text ->
            ( withTimerSetup
                (\u ->
                    { u
                        | turnsText = text
                        , turns =
                            String.toInt (String.trim text)
                                |> Maybe.map (Basics.max 1 >> Basics.min 99)
                                |> Maybe.withDefault u.turns
                    }
                )
                model
            , Cmd.none
            )

        TimerSetupPhaseSet phase ->
            ( withTimerSetup (\u -> { u | phase = phase }) model, Cmd.none )

        TimerSetupApply ->
            case model.timerSetup of
                Just ui ->
                    let
                        newTimer =
                            { remaining = ui.turns
                            , phase = ui.phase
                            , ringing = False
                            }
                    in
                    ( { model
                        | encounter =
                            Encounter.mapCreature ui.target
                                (\c -> { c | timer = Just newTimer })
                                model.encounter
                        , timerSetup = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        TimerSetupCancel ->
            ( { model | timerSetup = Nothing }, Cmd.none )

        TimerDismiss name ->
            -- Dismiss whether ringing or still counting; the GM
            -- gets to cancel a timer mid-flight if combat ends
            -- early or they set the wrong creature.
            ( { model
                | encounter =
                    Encounter.mapCreature name (\c -> { c | timer = Nothing }) model.encounter
              }
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


{-| Land one roll into the dice history. Single chokepoint so the
"unread" indicator on the encounter-controls Roll button stays in
sync — every Cmd that returns a Roll funnels through here.

`unread = True` only when the modal is closed at land time. When
the modal is already open, the user can already see the roll, so
no indicator is needed.

-}
pushDiceRoll : Dice.Roll -> Model -> Model
pushDiceRoll roll model =
    let
        d =
            model.dice
    in
    { model
        | dice =
            { d
                | history = Dice.push roll d.history
                , unread =
                    if d.open then
                        d.unread

                    else
                        True
            }
    }


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


{-| Apply `fn` to the open note-edit modal. No-op when closed.
-}
withNoteEdit : (NoteEditUi -> NoteEditUi) -> Model -> Model
withNoteEdit fn model =
    case model.noteEdit of
        Just ui ->
            { model | noteEdit = Just (fn ui) }

        Nothing ->
            model


{-| Apply `fn` to the open condition modal. No-op when closed.
-}
withConditionUi : (ConditionUi -> ConditionUi) -> Model -> Model
withConditionUi fn model =
    case model.conditionUi of
        Just ui ->
            { model | conditionUi = Just (fn ui) }

        Nothing ->
            model


{-| Apply `fn` to the open memo-edit modal. No-op when closed.
-}
withMemoEdit : (MemoEditUi -> MemoEditUi) -> Model -> Model
withMemoEdit fn model =
    case model.memoEdit of
        Just ui ->
            { model | memoEdit = Just (fn ui) }

        Nothing ->
            model


{-| Apply `fn` to the open timer-setup modal. No-op when closed.
-}
withTimerSetup : (TimerSetupUi -> TimerSetupUi) -> Model -> Model
withTimerSetup fn model =
    case model.timerSetup of
        Just ui ->
            { model | timerSetup = Just (fn ui) }

        Nothing ->
            model


{-| Auto-correct the `untilTarget` field if the current
phase / creature combo has made `OnCurrentTurn` nonsensical.

A "Begin + Current turn" pairing is logically invalid when the
reference creature is currently active: the begin of their
current turn already fired when they became active, so there's
no future hook to expire on. Flip to `OnNextTurn` so the
condition has a real expiration point.

-}
repairUntilTarget : Model -> ConditionUi -> ConditionUi
repairUntilTarget model ui =
    if currentTurnInvalid model ui && ui.untilTarget == Encounter.OnCurrentTurn then
        { ui | untilTarget = Encounter.OnNextTurn }

    else
        ui


{-| True when `OnCurrentTurn` would be a no-op — only the
"Begin + active reference creature" case for now.
-}
currentTurnInvalid : Model -> ConditionUi -> Bool
currentTurnInvalid model ui =
    ui.untilPhase == Encounter.AtBegin && ui.untilCreature == model.encounter.activeName


{-| Hard cap on the chip-note text. Ten characters keeps the chip
small and prevents wrap-overflow on the card row 1.
-}
maxConditionNoteLength : Int
maxConditionNoteLength =
    10


{-| Translate the modal's UI state into a domain-level
`ConditionDraft`, then either insert it (when creating) or replace
the existing condition's fields (when editing). The "skip first
end-of-turn tick" rule is applied here for AtEnd countdowns
created on the currently-active creature.
-}
commitCondition : ConditionUi -> String -> Model -> Model
commitCondition ui name model =
    let
        duration =
            buildDuration ui model

        saveToEnd =
            Maybe.map
                (\s ->
                    { ability = s.ability
                    , dc = s.dc
                    , bonus = s.bonus
                    , autoRoll = s.autoRoll
                    }
                )
                ui.saveToEnd

        draft =
            { name = name
            , note = String.trim ui.note
            , duration = duration
            , saveToEnd = saveToEnd
            }
    in
    case ui.editingId of
        Just id ->
            -- Editing an existing condition is always single-target —
            -- you're modifying one specific row, not splatting it.
            { model
                | encounter =
                    Encounter.updateCondition ui.target
                        id
                        (\c ->
                            { c
                                | name = draft.name
                                , note = draft.note
                                , duration = draft.duration
                                , saveToEnd = draft.saveToEnd
                            }
                        )
                        model.encounter
                , conditionUi = Nothing
            }

        Nothing ->
            let
                targets =
                    conditionTargets ui model.encounter

                addOne tgt enc =
                    Encounter.addCondition tgt draft enc
            in
            { model
                | encounter = List.foldl addOne model.encounter targets
                , conditionUi = Nothing
            }


{-| Resolve which creatures a new condition applies to. When
`applyToSelected` is True, every creature with `selected = True`
gets a fresh copy (each gets its own id via `addCondition`).
Otherwise just the modal's `target`.
-}
conditionTargets : ConditionUi -> Encounter -> List String
conditionTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]


{-| Build the domain `Duration` from the UI's three sub-states.

For `DurKindCountdown` with `AtEnd` placed on the currently-active
creature, set `skipNextTick = True` so the bearer's imminent
end-of-turn (which is right around the corner) doesn't get counted
as a full turn.

-}
buildDuration : ConditionUi -> Model -> Encounter.Duration
buildDuration ui model =
    case ui.durationKind of
        DurKindManual ->
            Encounter.DurationManual

        DurKindUntilTurn ->
            Encounter.DurationUntilTurn ui.untilPhase ui.untilTarget ui.untilCreature

        DurKindCountdown ->
            let
                isCurrentlyActive =
                    ui.target == model.encounter.activeName

                skipNextTick =
                    ui.countdownPhase == Encounter.AtEnd && isCurrentlyActive
            in
            Encounter.DurationCountdown ui.countdownPhase ui.countdownTurns skipNextTick


{-| DOM id stamped on each creature card's outer `<article>`.
Used by [`scrollActiveIntoViewCmd`](#scrollActiveIntoViewCmd) to
locate the active card via `Browser.Dom.getElement`. Spaces and
punctuation in creature names are mapped to underscores so the
resulting id meets HTML5's "no ASCII whitespace" rule.
-}
cardId : String -> String
cardId name =
    "creature-card-" ++ slugifyName name


slugifyName : String -> String
slugifyName name =
    name
        |> String.toList
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    '_'
            )
        |> String.fromList


{-| If the active creature's card is partially below the browser
viewport's bottom edge, scroll the document so it's fully
visible (with a small bottom margin). Otherwise no-op.

Composed from `Browser.Dom.getViewport` and
`Browser.Dom.getElement` — both are read-only Tasks, so we only
issue a `setViewport` when the math says we have to. The result
lands in [`ActiveCardScrollChecked`](#ActiveCardScrollChecked)
which is a no-op handler.

-}
scrollActiveIntoViewCmd : String -> Cmd Msg
scrollActiveIntoViewCmd name =
    Task.map2
        (\viewport element ->
            let
                cardBottom =
                    element.element.y + element.element.height

                viewportBottom =
                    viewport.viewport.y + viewport.viewport.height

                bottomMargin =
                    16

                overflow =
                    cardBottom - (viewportBottom - bottomMargin)
            in
            if overflow > 0 then
                Browser.Dom.setViewport
                    viewport.viewport.x
                    (viewport.viewport.y + overflow)

            else
                Task.succeed ()
        )
        Browser.Dom.getViewport
        (Browser.Dom.getElement (cardId name))
        |> Task.andThen identity
        |> Task.attempt ActiveCardScrollChecked


{-| Build a list of Cmds that fire auto-roll saves for one
creature in one turn-phase. Each result lands in
`ConditionSaveLanded`, which applies the success / failure logic
and updates the dice history.

`mode` filters: only conditions whose `saveToEnd.autoRoll`
matches `mode` produce a Cmd. The two phases (`AutoRollAtBegin`
and `AutoRollAtEnd`) are fired separately — see the `NextTurn`
update branch.

Returns `[]` when the named creature isn't in the queue or has
no matching auto-roll saves, which is the common case.

-}
autoRollCmdsFor : Encounter.AutoRollMode -> String -> Encounter.Encounter -> List (Cmd Msg)
autoRollCmdsFor mode name enc =
    enc.creatures
        |> List.filter (\c -> c.name == name)
        |> List.concatMap
            (\c ->
                List.filterMap (autoRollCmdForCondition mode c.name) c.conditions
            )


autoRollCmdForCondition : Encounter.AutoRollMode -> String -> Encounter.Condition -> Maybe (Cmd Msg)
autoRollCmdForCondition mode bearer cond =
    case cond.saveToEnd of
        Just spec ->
            if spec.autoRoll == mode then
                Just
                    (Dice.rollCmd
                        (ConditionSaveLanded bearer cond.id spec.dc True)
                        (saveSource cond bearer spec)
                        (saveExpression spec.bonus)
                    )

            else
                Nothing

        Nothing ->
            Nothing


{-| Source label for save-to-end rolls: "Save: WIS DC 13 → Brakka".
The history reads informatively without the GM having to remember
which condition the save was for.
-}
saveSource : Encounter.Condition -> String -> Encounter.SaveToEnd -> Dice.Source
saveSource cond target spec =
    { feature =
        "Save: " ++ spec.ability ++ " DC " ++ String.fromInt spec.dc ++ " (" ++ cond.name ++ ")"
    , target = Just target
    }


{-| Build a `1d20 + bonus` expression for a save roll. Bonus may
be 0; in that case `expressionToString` will render just "1d20".
-}
saveExpression : Int -> Dice.Expression
saveExpression bonus =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = bonus
    , damageType = Nothing
    }


{-| Build the `Cmd` for an initiative roll batch.

`mode` chooses the per-creature generator: `ModeStandard` rolls
plain `1d20 + initiativeBonus`; `ModeAdvantage` rolls `2d20`,
keeps the higher, and adds the bonus (5e advantage). Each roll is
tagged with a `Source` so the dice history reads "Initiative →
Brakka, Ogre Brute" — the formula in the entry already encodes
the mode (advantage rolls render as "Adv: 1d20+5" via
`Dice.advantageGenerator`'s formula prefix).

Empty input → `Cmd.none` (handles the "Selected" buttons being
clicked when no creatures are selected).

-}
initiativeRollCmd : RollMode -> List Creature -> Cmd Msg
initiativeRollCmd mode creatures =
    if List.isEmpty creatures then
        Cmd.none

    else
        Dice.batchRollCmd InitiativeRollsLanded
            (List.map
                (\c ->
                    ( c.name
                    , initiativeSource c.name
                    , initiativeGenerator mode c
                    )
                )
                creatures
            )


{-| Pick the per-creature roll generator for the given mode.
Standard uses [`Dice.generator`](Dice#generator) over a 1d20+bonus
expression; advantage uses [`Dice.advantageGenerator`](Dice#advantageGenerator)
which natively handles the 2d20-keep-highest mechanic and tags the
kept die in the resulting `Roll.groups`.
-}
initiativeGenerator : RollMode -> Creature -> Random.Generator Dice.Roll
initiativeGenerator mode c =
    case mode of
        ModeStandard ->
            Dice.generator (initiativeExpression c)

        ModeAdvantage ->
            Dice.advantageGenerator c.initiativeBonus


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


{-| Source label for death-save rolls — "Death save → <creature>"
in the dice history.
-}
deathSaveSource : String -> Dice.Source
deathSaveSource name =
    { feature = "Death save", target = Just name }


{-| Plain 1d20, no modifier. Built once and re-used so every
death-save roll has the same expression shape (and the dice
history's "1d20" label stays stable for searching/filtering).
-}
deathSaveExpression : Dice.Expression
deathSaveExpression =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = 0
    , damageType = Nothing
    }


{-| Compute the new pip-strip count when pip `idx` (0..2) is
clicked given the current count. Star-rating semantics — clicking
a filled pip clears it and every later pip; clicking an empty pip
fills up to and including it.
-}
pipStripTarget : Int -> Int -> Int
pipStripTarget idx current =
    if idx < current then
        idx

    else
        idx + 1


{-| Resolve a 5e death-save d20 face against the creature.

  - 20 → revive at 1 HP, conscious, tracker cleared.
  - 1 → +2 failures.
  - 10..19 → +1 success.
  - 2..9 → +1 failure.

The helper checks for the pre-existing dead/stable state and is a
no-op there so a stray click on the Roll button after death
doesn't change anything.

-}
applyDeathSaveResult : Int -> Creature -> Creature
applyDeathSaveResult d20 c =
    if Encounter.isDeathSaveDead c.deathSaves || Encounter.isDeathSaveStable c.deathSaves then
        c

    else if d20 == 20 then
        -- Nat 20 revives at 1 HP. Bumping currentHp above 0 also
        -- hides the tracker (view gates on currentHp == 0) and
        -- the cleared counts mean the next time they go down
        -- they start fresh.
        { c
            | currentHp = Basics.max 1 c.currentHp
            , deathSaves = Encounter.emptyDeathSaves
        }

    else if d20 == 1 then
        { c | deathSaves = Encounter.addDeathSaveFailures 2 c.deathSaves }

    else if d20 >= 10 then
        { c | deathSaves = Encounter.addDeathSaveSuccesses 1 c.deathSaves }

    else
        { c | deathSaves = Encounter.addDeathSaveFailures 1 c.deathSaves }


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
hpChangeSource : HpChangeUi -> Encounter -> Dice.Source
hpChangeSource ui enc =
    let
        feature =
            case ui.kind of
                DamageKind ->
                    "Damage"

                HealKind ->
                    "Heal"

                TempHpKind ->
                    "Temp HP"

        targetLabel =
            if ui.applyToSelected then
                let
                    names =
                        hpChangeTargets ui enc
                in
                if List.isEmpty names then
                    ui.target

                else
                    String.join ", " names

            else
                ui.target
    in
    { feature = feature, target = Just targetLabel }


{-| Resolve the modal's kind + flags into an `HpChange.Change`,
hand it to the engine, write the updated creature back through
`Encounter.mapCreature`, push a log entry capturing the before/after
snapshot, and close the modal. The caller decides the amount — it
comes from the manual input on the manual path or from the rolled
total on the dice path.

When `ui.applyToSelected` is True, the change is applied to every
selected creature (`Creature.selected = True`). Same amount
across all targets — for dice mode this means the GM rolled once
and N creatures soak the same total, which matches 5e's
single-roll-per-AOE convention (a Fireball rolls 8d6 once and
each target takes that much, not 8d6 per target).

When `applyToSelected` is False, only `ui.target` is affected
(the original single-card flow).

If no creatures match (no selection), the modal still closes
without applying to anyone — better than silently falling back
to `ui.target`, which would surprise the GM who explicitly
checked the multi-target toggle.

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

        targets =
            hpChangeTargets ui model.encounter

        applyOne name acc =
            let
                before =
                    findCreature name acc.encounter

                newEnc =
                    Encounter.mapCreature name (HpChange.apply change) acc.encounter

                after =
                    findCreature name newEnc

                entry =
                    Maybe.map2
                        (\b a ->
                            { kind = ui.kind
                            , target = name
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
            { encounter = newEnc
            , log =
                case entry of
                    Just e ->
                        e :: acc.log

                    Nothing ->
                        acc.log
            }

        result =
            List.foldl applyOne { encounter = model.encounter, log = [] } targets
    in
    { model
        | encounter = result.encounter
        , hpChange = Nothing
        , hpChangeLog =
            -- Newly-applied entries are accumulated newest-last in
            -- the foldl above; reverse so the first target appears
            -- first when prepended to the existing log.
            List.reverse result.log
                ++ List.take (Basics.max 0 (maxHpLogEntries - List.length result.log)) model.hpChangeLog
    }


{-| Resolve which creatures the HP-change applies to, based on
`ui.applyToSelected`. Returns the modal's single target
otherwise.
-}
hpChangeTargets : HpChangeUi -> Encounter -> List String
hpChangeTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]


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
            , viewNoteEditModal model
            , viewConditionModal model
            , viewMemoEditModal model
            , viewTimerSetupModal model
            , viewRingerAudio model
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
        , viewPanelControls model.dice
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
            , viewEncounterBarHp active
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , viewActiveStateIcons active
            , viewActiveConditionsText active
            ]
        , div [ class "encounter-bar__group encounter-bar__right" ]
            [ span [ class "encounter-bar__xp" ] [ text "93,000 XP" ]
            , span [ class "encounter-bar__xp-lair" ] [ text "(115,200 w/Lair)" ]
            , viewXpFilter
            ]
        ]


{-| HP readout for the encounter title bar. Reuses the same
.hp-display\* classes the card row 2 uses so the green/muted/blue
colors line up exactly. Renders an em-dash when no creature is
active (empty queue or activeName drift).
-}
viewEncounterBarHp : Maybe Creature -> Html Msg
viewEncounterBarHp active =
    case active of
        Just c ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__current" ]
                    [ text (String.fromInt c.currentHp) ]
                , span [ class "hp-display__sep" ] [ text "/" ]
                , span [ class "hp-display__max" ]
                    [ text (String.fromInt c.maxHp) ]
                , if c.tempHp > 0 then
                    span
                        [ class "hp-display__temp"
                        , title "Temporary hit points"
                        ]
                        [ text ("+" ++ String.fromInt c.tempHp) ]

                  else
                    text ""
                ]

        Nothing ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__max" ] [ text "—" ] ]


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


{-| Latest dice-roll total displayed left of the Roll button. Bold
white integer (no formula, no source label) so the most recent
result is glanceable from across the table even with the modal
closed. Hidden when no rolls have landed yet.
-}
viewDiceLastTotal : DiceUi -> Html Msg
viewDiceLastTotal dice =
    case List.head dice.history.entries of
        Just roll ->
            span
                [ class "dice-last-total"
                , title "Last roll total"
                ]
                [ text (String.fromInt roll.total) ]

        Nothing ->
            text ""


{-| Left-facing arrow between the latest-total readout and the
Roll button, signalling that the number was emitted by the
roller. Hidden until at least one roll has landed so the cluster
isn't visually cluttered on first load.
-}
viewDiceArrow : DiceUi -> Html Msg
viewDiceArrow dice =
    if List.isEmpty dice.history.entries then
        text ""

    else
        span
            [ class "dice-arrow"
            , attribute "aria-hidden" "true"
            ]
            [ text "←" ]


viewPanelControls : DiceUi -> Html Msg
viewPanelControls dice =
    section [ class "panel panel--controls" ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ] [ text "Encounter Controls" ]
            , div [ class "dice-roll-cluster" ]
                [ viewDiceLastTotal dice
                , viewDiceArrow dice
                , button
                    [ class
                        (if dice.unread then
                            "action-btn action-btn--green dice-roll-btn dice-roll-btn--unread"

                         else
                            "action-btn action-btn--green dice-roll-btn"
                        )
                    , onClick OpenDice
                    , title
                        (if dice.unread then
                            "Roll dice (new entries since last open)"

                         else
                            "Roll dice"
                        )
                    , attribute "aria-label" "Roll dice"
                    ]
                    [ text "🎲 Roll" ]
                ]
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

        isDead =
            Encounter.isDeathSaveDead creature.deathSaves

        cardClass =
            String.join " "
                (List.filterMap identity
                    [ Just "creature-card"
                    , if isActive then
                        Just "creature-card--active"

                      else
                        Nothing
                    , if isDead then
                        Just "creature-card--dead"

                      else
                        Nothing
                    ]
                )
    in
    article [ id (cardId creature.name), class cardClass ]
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
                    , onClick (RemoveCreature creature.name)
                    , title "Remove from queue"
                    , attribute "aria-label" "Remove"
                    ]
                    [ text "×" ]
                ]
            , div [ class "creature-card__rail-group" ]
                [ button
                    [ class "icon-btn"
                    , onClick (DuplicateCreature creature.name)
                    , title "Duplicate creature (insert below)"
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
        , viewNoteOrPencil creature
        , span [ class "ac-readout" ]
            [ text ("AC: " ++ String.fromInt creature.armorClass) ]
        , viewConditionChips creature
        ]


{-| Note-or-pencil sliver of row 1.

Empty note: just the pencil ✏️ button as an "add a note" affordance.

Non-empty note: the note itself (clickable, opens the same edit
modal so the user can rename or clear it) followed by a pipe
separator before the AC readout. The pencil is intentionally
hidden in this state — the note is now the click target, and
showing both would make the user wonder which one to use.

Returns a `List (Html Msg)` so the caller can splice it into the
row alongside the rest of the elements without a wrapper div
(which would break the row's flex gap).

-}
viewNoteOrPencil : Creature -> Html Msg
viewNoteOrPencil creature =
    if String.isEmpty creature.note then
        button
            [ class "icon-btn icon-btn--sm"
            , onClick (NoteEditOpen creature.name creature.note)
            , title "Add note"
            , attribute "aria-label" "Add note"
            ]
            [ text "✏️" ]

    else
        span [ class "creature-note-wrap" ]
            [ button
                [ class "creature-note creature-note--clickable"
                , onClick (NoteEditOpen creature.name creature.note)
                , title "Edit or clear note"
                , attribute "aria-label" ("Edit note: " ++ creature.note)
                ]
                [ text creature.note ]
            , span [ class "creature-note__sep" ] [ text "|" ]
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


{-| Live render of a creature's conditions and any post-save
"Saved: <name>" notices on row 1 of the card. Empty for both →
empty text node so the row's flex gap collapses naturally.
Otherwise we render a leading separator pipe followed by chips
(active conditions first, then notices) so the eye lands on the
condition the GM is most likely to act on.
-}
viewConditionChips : Creature -> Html Msg
viewConditionChips creature =
    if List.isEmpty creature.conditions && List.isEmpty creature.saveNotices then
        text ""

    else
        span [ class "condition-chips-wrap" ]
            (span [ class "row-top__sep" ] [ text "|" ]
                :: List.map (viewConditionChip creature.name) creature.conditions
                ++ List.map (viewSaveNoticeChip creature.name) creature.saveNotices
            )


{-| "Saved: <Condition>" notice rendered as a small green chip.
Posted after a successful AUTO-roll save (manual chip-roll
successes remove the condition silently). Auto-removes on the
bearer's next end-of-turn; the × button dismisses earlier.
-}
viewSaveNoticeChip : String -> Encounter.SaveNotice -> Html Msg
viewSaveNoticeChip target notice =
    span
        [ class "save-notice"
        , title ("Saved against " ++ notice.conditionName ++ " — auto-clears on next end-of-turn")
        ]
        [ text ("Saved: " ++ notice.conditionName)
        , button
            [ class "save-notice__dismiss"
            , onClick (SaveNoticeDismiss target notice.id)
            , title "Dismiss"
            , attribute "aria-label" "Dismiss save notice"
            ]
            [ text "×" ]
        ]


{-| One condition chip. Layout (left → right):
[ name + note ][ optional save-roll button ] [ duration glyph ][ × ]

Clicking the name opens the edit modal; the × runs the remove
Msg directly (and stops propagation so it doesn't also open the
modal). The save-roll button (when the condition has a `saveToEnd`)
fires a 1d20 vs. the DC and removes the condition on success.

-}
viewConditionChip : String -> Encounter.Condition -> Html Msg
viewConditionChip target cond =
    span
        [ class "condition-chip"
        , title (chipTitle cond)
        ]
        [ button
            [ class "condition-chip__name"
            , onClick (ConditionOpenEdit target cond.id)
            , title "Click to edit"
            ]
            [ text cond.name
            , if String.isEmpty cond.note then
                text ""

              else
                span [ class "condition-chip__note" ]
                    [ text (" (" ++ cond.note ++ ")") ]
            ]
        , viewChipSaveButton target cond
        , viewChipDurationGlyph cond
        , button
            [ class "condition-chip__remove"
            , stopPropagationOn "click"
                (Decode.succeed ( ConditionRemoveChip target cond.id, True ))
            , title "Remove condition"
            , attribute "aria-label" "Remove condition"
            ]
            [ text "×" ]
        ]


{-| Tooltip text for the whole chip. Combines name, duration, and
(if present) the save-to-end terms so the GM can hover for full
context without opening the modal.
-}
chipTitle : Encounter.Condition -> String
chipTitle cond =
    let
        durPart =
            Encounter.describeDuration cond.duration

        savePart =
            case cond.saveToEnd of
                Just s ->
                    " · " ++ s.ability ++ " save DC " ++ String.fromInt s.dc

                Nothing ->
                    ""
    in
    cond.name ++ " — " ++ durPart ++ savePart


{-| Inline d20 button next to a chip when the condition has a
saving throw conditional. Click rolls 1d20 + bonus and removes
the chip on success. Hidden when no save is configured.
-}
viewChipSaveButton : String -> Encounter.Condition -> Html Msg
viewChipSaveButton target cond =
    case cond.saveToEnd of
        Just spec ->
            button
                [ class "condition-chip__save"
                , stopPropagationOn "click"
                    (Decode.succeed ( ConditionRollSave target cond.id, True ))
                , title
                    ("Roll "
                        ++ spec.ability
                        ++ " save (DC "
                        ++ String.fromInt spec.dc
                        ++ ", bonus "
                        ++ formatBonus spec.bonus
                        ++ ")"
                    )
                , attribute "aria-label" ("Roll save for " ++ cond.name)
                ]
                [ text "🎲" ]

        Nothing ->
            text ""


{-| Compact duration glyph appended to a chip. Manual durations
get nothing (the GM removes by hand); UntilTurn shows ⏱
N (where N is "Bk" or first 3 chars of the ref creature's name);
Countdown shows ⏳N.
-}
viewChipDurationGlyph : Encounter.Condition -> Html Msg
viewChipDurationGlyph cond =
    case cond.duration of
        Encounter.DurationManual ->
            text ""

        Encounter.DurationUntilTurn _ _ ref ->
            span [ class "condition-chip__duration" ]
                [ text ("⏱ " ++ String.left 4 ref) ]

        Encounter.DurationCountdown _ remaining _ ->
            span [ class "condition-chip__duration" ]
                [ text ("⏳ " ++ String.fromInt remaining) ]


formatBonus : Int -> String
formatBonus n =
    if n >= 0 then
        "+" ++ String.fromInt n

    else
        String.fromInt n


{-| Active-creature state icons in the encounter title bar.
Renders one icon per actual non-default state (cover, concentrating,
hiding, flying) — purely indicative, no click handlers. Hidden
when nothing is active.

Cover uses the same ◐ / ◕ / ● glyph vocabulary as the card row 2
toggle so the title bar reads consistently with the card.

-}
viewActiveStateIcons : Maybe Creature -> Html Msg
viewActiveStateIcons active =
    case active of
        Just c ->
            div [ class "encounter-bar__states" ]
                (List.filterMap identity
                    [ coverIcon c
                    , stateIconIf c.concentrating "🧠" "Concentrating"
                    , stateIconIf c.hiding "👤" "Hiding"
                    , flyingIcon c
                    ]
                )

        Nothing ->
            text ""


{-| Single state icon, shown only when `on` is True. Tooltip
labels it for accessibility. Returned as `Maybe (Html msg)` so
the caller can `filterMap identity` and skip the false ones.
-}
stateIconIf : Bool -> String -> String -> Maybe (Html Msg)
stateIconIf on glyph label =
    if on then
        Just
            (span
                [ class "encounter-bar__state"
                , title label
                , attribute "aria-label" label
                ]
                [ text glyph ]
            )

    else
        Nothing


coverIcon : Creature -> Maybe (Html Msg)
coverIcon c =
    case c.cover of
        Encounter.NoCover ->
            Nothing

        Encounter.HalfCover ->
            Just (stateIcon "◐" "Half cover")

        Encounter.ThreeQuartersCover ->
            Just (stateIcon "◕" "Three-quarters cover")

        Encounter.FullCover ->
            Just (stateIcon "●" "Full cover")


{-| Flying icon includes the height inline so the GM can read
"how high" at a glance without opening the card.
-}
flyingIcon : Creature -> Maybe (Html Msg)
flyingIcon c =
    if c.flying then
        Just
            (span
                [ class "encounter-bar__state"
                , title ("Flying — " ++ String.fromInt c.flyHeight ++ " ft")
                , attribute "aria-label" "Flying"
                ]
                [ text ("🪽 " ++ String.fromInt c.flyHeight) ]
            )

    else
        Nothing


stateIcon : String -> String -> Html Msg
stateIcon glyph label =
    span
        [ class "encounter-bar__state"
        , title label
        , attribute "aria-label" label
        ]
        [ text glyph ]


{-| Active-creature conditions slot in the title bar. Plain
purple text separated by " | ", not chips — the GM uses this as
a glanceable summary; the editable chips are on the card itself.
Hidden when there are no conditions.
-}
viewActiveConditionsText : Maybe Creature -> Html Msg
viewActiveConditionsText active =
    case active of
        Just c ->
            if List.isEmpty c.conditions then
                text ""

            else
                span [ class "encounter-bar__conditions" ]
                    (List.intersperse
                        (span [ class "encounter-bar__cond-sep" ] [ text "|" ])
                        (List.map
                            (\cond ->
                                span [ class "encounter-bar__cond" ]
                                    [ text cond.name ]
                            )
                            c.conditions
                        )
                    )

        Nothing ->
            text ""


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


{-| The 5e death-save tracker as it appears in row 2 (right after
the bloodied indicator). Visibility is keyed off `currentHp == 0`
exclusively — the moment the creature is back above 0 HP they're
conscious, and the tracker shouldn't be on screen at all. The
HP-change engine already resets the counts on heal-to-positive,
so when the tracker re-appears (next time they hit 0) it starts
fresh.

Layout: three success pips (🌟), three failure pips (💀), and a
small 🎲 button that fires a 1d20 death save and resolves it per
5e. Once stable (3 successes) or dead (3 failures), the Roll
button disappears — the GM can still un-set pips manually if they
need to reset, but the automated flow stops.

-}
viewDeathSaves : Creature -> Html Msg
viewDeathSaves creature =
    if creature.currentHp == 0 then
        let
            ds =
                creature.deathSaves

            stable =
                Encounter.isDeathSaveStable ds

            dead =
                Encounter.isDeathSaveDead ds

            statusBadge =
                if dead then
                    span [ class "death-saves__badge death-saves__badge--dead" ]
                        [ text "💀 Dead" ]

                else if stable then
                    span [ class "death-saves__badge death-saves__badge--stable" ]
                        [ text "🛡 Stable" ]

                else
                    text ""

            rollButton =
                if dead || stable then
                    text ""

                else
                    button
                        [ class "death-saves__roll"
                        , onClick (DeathSaveRoll creature.name)
                        , title "Roll a 1d20 death save (5e: 10+ success, ≤9 failure, nat 20 revives, nat 1 = 2 failures)"
                        , attribute "aria-label" "Roll death save"
                        ]
                        [ text "🎲" ]
        in
        span
            [ class "death-saves"
            , attribute "role" "group"
            , attribute "aria-label" "Death saving throws"
            ]
            [ span [ class "death-saves__strip death-saves__strip--success" ]
                (span
                    [ class "death-saves__label"
                    , title "Successful death saves"
                    , attribute "aria-hidden" "true"
                    ]
                    [ text "🌟" ]
                    :: List.map (viewDeathSavePip creature.name DeathSaveToggleSuccess "🌟" "Success" ds.successes) [ 0, 1, 2 ]
                )
            , span [ class "death-saves__strip death-saves__strip--failure" ]
                (span
                    [ class "death-saves__label"
                    , title "Failed death saves"
                    , attribute "aria-hidden" "true"
                    ]
                    [ text "💀" ]
                    :: List.map (viewDeathSavePip creature.name DeathSaveToggleFailure "💀" "Failure" ds.failures) [ 0, 1, 2 ]
                )
            , rollButton
            , statusBadge
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
            , onClick (ConditionOpenNew creature.name)
            , title "Apply condition or effect"
            ]
            [ text "Condition/Effect" ]
        , viewHoldToggle creature
        , viewMemoSlot creature
        , viewTimerSlot creature
        ]


{-| Row 3 memo slot. Empty memo → 📝 button that opens the
memo-edit modal. Non-empty memo → white-text inline display with
an × dismiss button (clearing the memo restores the icon).
-}
viewMemoSlot : Creature -> Html Msg
viewMemoSlot creature =
    if String.isEmpty creature.memo then
        button
            [ class "action-btn action-btn--icon"
            , onClick (MemoOpen creature.name)
            , title "Add memo"
            , attribute "aria-label" "Add memo"
            ]
            [ text "📝" ]

    else
        span
            [ class "memo-pill"
            , title creature.memo
            ]
            [ button
                [ class "memo-pill__text"
                , onClick (MemoOpen creature.name)
                , title "Edit memo"
                ]
                [ text creature.memo ]
            , button
                [ class "memo-pill__dismiss"
                , onClick (MemoClear creature.name)
                , title "Clear memo"
                , attribute "aria-label" "Clear memo"
                ]
                [ text "×" ]
            ]


{-| Row 3 timer slot. Three states:

  - No timer set → ⏱ button that opens the timer-setup modal.
  - Timer counting → display the remaining count + × dismiss.
  - Timer ringing (`remaining = 0`) → flashing 0 + × dismiss.
    The browser also plays a ping sound courtesy of the
    page-level `<audio>` element mounted by `viewRingerAudio`.

-}
viewTimerSlot : Creature -> Html Msg
viewTimerSlot creature =
    case creature.timer of
        Nothing ->
            button
                [ class "action-btn action-btn--icon"
                , onClick (TimerOpen creature.name)
                , title "Set timer"
                , attribute "aria-label" "Set timer"
                ]
                [ text "⏱️" ]

        Just t ->
            span
                [ class
                    (if t.ringing then
                        "timer-pill timer-pill--ringing"

                     else
                        "timer-pill"
                    )
                , title (timerTooltip t)
                ]
                [ span [ class "timer-pill__count" ]
                    [ text (String.fromInt t.remaining) ]
                , button
                    [ class "timer-pill__dismiss"
                    , onClick (TimerDismiss creature.name)
                    , title "Cancel timer"
                    , attribute "aria-label" "Cancel timer"
                    ]
                    [ text "×" ]
                ]


timerTooltip : Encounter.Timer -> String
timerTooltip t =
    let
        phaseWord =
            case t.phase of
                Encounter.AtBegin ->
                    "begin"

                Encounter.AtEnd ->
                    "end"
    in
    if t.ringing then
        "Timer rang at " ++ phaseWord ++ "-of-turn — click × to dismiss"

    else
        "Timer: "
            ++ String.fromInt t.remaining
            ++ " left, ticks at "
            ++ phaseWord
            ++ "-of-turn"


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


{-| Render one pip of a death-save strip.

`msgFor name idx` is the toggle Msg constructor (success or
failure variant); `filledGlyph` and `kindLabel` differ between
strips. `currentCount` is the strip's current filled-pip count,
used to decide whether THIS pip (`idx`) is filled.

-}
viewDeathSavePip : String -> (String -> Int -> Msg) -> String -> String -> Int -> Int -> Html Msg
viewDeathSavePip name msgFor filledGlyph kindLabel currentCount idx =
    let
        filled =
            idx < currentCount

        glyph =
            if filled then
                filledGlyph

            else
                "○"

        stateLabel =
            if filled then
                "filled"

            else
                "empty"
    in
    button
        [ class
            (String.join " "
                [ "death-save-pip"
                , if filled then
                    "death-save-pip--filled"

                  else
                    "death-save-pip--empty"
                ]
            )
        , onClick (msgFor name idx)
        , title (kindLabel ++ " " ++ String.fromInt (idx + 1) ++ ": " ++ stateLabel)
        , attribute "aria-label" (kindLabel ++ " pip " ++ String.fromInt (idx + 1))
        , attribute "aria-pressed"
            (if filled then
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


enterKey : Msg -> Decode.Decoder Msg
enterKey =
    Util.Keyboard.enterKey


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
                        , viewHpChangeApplyScope ui model.encounter
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


{-| Multi-target scope checkbox. Hidden entirely when zero
creatures are selected — there's no useful "apply to all
selected" when there's no selection. When at least one is
selected, renders the toggle plus a count hint so the GM knows
the blast radius.

Dice mode comes with an inline note explaining that all selected
creatures share the same rolled total (the 5e Fireball
single-roll-per-AOE convention).

-}
viewHpChangeApplyScope : HpChangeUi -> Encounter -> Html Msg
viewHpChangeApplyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
    if selectedCount == 0 then
        text ""

    else
        div [ class "hp-change__row" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick HpChangeApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            , if ui.applyToSelected && ui.mode == DiceMode then
                div [ class "hp-change__caption" ]
                    [ text "All selected creatures take the same rolled total (one roll, shared across the AOE)." ]

              else
                text ""
            ]


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
        , viewAutoRollPair ScopeTarget
            ("🎲 Roll Initiative & Sort: " ++ ui.target)
            True
            ""
        , viewAutoRollPair ScopeAll
            "🎲 Roll Initiative & Sort: All"
            True
            ""
        , viewAutoRollPair ScopeSelected
            ("🎲 Roll Initiative & Sort: Selected" ++ selectedCountSuffix selectedCount)
            (selectedCount > 0)
            (selectedTitle selectedCount)
        , div [ class "init-section__caption" ]
            [ text "Rolls 1d20 + creature's initiative bonus from stat block" ]
        ]


{-| One row in the Auto-roll section: the main "& Sort" button on
the left, the Advantage sister button on the right. Both fire
`InitiativeAutoRoll` with the same scope; only the mode differs.
-}
viewAutoRollPair : RollScope -> String -> Bool -> String -> Html Msg
viewAutoRollPair scope label enabled tipOverride =
    let
        mainTitle =
            if String.isEmpty tipOverride then
                "Roll 1d20 + initiative bonus"

            else
                tipOverride

        advTitle =
            if enabled then
                "Roll 2d20, keep highest, + initiative bonus (5e advantage)"

            else
                tipOverride
    in
    div [ class "init-btn-row" ]
        [ button
            [ class "action-btn action-btn--green init-btn-block"
            , onClick (InitiativeAutoRoll scope ModeStandard)
            , disabled (not enabled)
            , attribute "aria-disabled"
                (if enabled then
                    "false"

                 else
                    "true"
                )
            , title mainTitle
            ]
            [ text label ]
        , button
            [ class "action-btn action-btn--green init-btn-adv"
            , onClick (InitiativeAutoRoll scope ModeAdvantage)
            , disabled (not enabled)
            , attribute "aria-disabled"
                (if enabled then
                    "false"

                 else
                    "true"
                )
            , title advTitle
            ]
            [ text "Advantage" ]
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



-- NOTE-EDIT MODAL


{-| Renders the per-creature note editor when the row 1 pencil
button has been clicked. Single text input capped at
`maxNoteLength`, with Save / Cancel buttons. Enter commits, Esc /
backdrop / ✕ / Cancel all close without changes. Saving an empty
string is the canonical way to clear a note.
-}
viewNoteEditModal : Model -> Html Msg
viewNoteEditModal model =
    case model.noteEdit of
        Nothing ->
            text ""

        Just ui ->
            div
                [ class "modal-backdrop"
                , onClick NoteEditCancel
                ]
                [ div
                    [ class "modal modal--note-edit"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    , attribute "aria-label" ("Note for " ++ ui.target)
                    ]
                    [ div [ class "modal__header" ]
                        [ div [ class "modal__title" ]
                            [ text ("Note — " ++ ui.target) ]
                        , button
                            [ class "modal__close"
                            , onClick NoteEditCancel
                            , title "Cancel"
                            , attribute "aria-label" "Cancel"
                            ]
                            [ text "×" ]
                        ]
                    , div [ class "modal__body" ]
                        [ Html.label [ for "note-edit-input" ]
                            [ text ("Short label (max " ++ String.fromInt maxNoteLength ++ " chars)") ]
                        , input
                            [ id "note-edit-input"
                            , class "note-edit__input"
                            , type_ "text"
                            , value ui.text
                            , maxlength maxNoteLength
                            , placeholder "e.g. boss, summoned, ally"
                            , autofocus True
                            , onInput NoteEditChange
                            , Html.Events.on "keydown" (enterKey NoteEditCommit)
                            ]
                            []
                        , div [ class "note-edit__buttons" ]
                            [ button
                                [ class "action-btn action-btn--green"
                                , onClick NoteEditCommit
                                ]
                                [ text "Save" ]
                            , button
                                [ class "action-btn"
                                , onClick NoteEditCancel
                                ]
                                [ text "Cancel" ]
                            ]
                        ]
                    ]
                ]



-- CONDITION / EFFECT MODAL


{-| Render the condition modal when one is open. Sections, top to
bottom: standard-condition radios, custom name input, note input,
duration choice (Manual / Until turn / Countdown) with the
relevant sub-controls, optional save-to-end block, and the action
footer (Apply / Cancel / Delete-when-editing).
-}
viewConditionModal : Model -> Html Msg
viewConditionModal model =
    case model.conditionUi of
        Nothing ->
            text ""

        Just ui ->
            div
                [ class "modal-backdrop"
                , onClick ConditionClose
                ]
                [ div
                    [ class "modal modal--condition"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    , attribute "aria-label" ("Condition for " ++ ui.target)
                    ]
                    [ div [ class "modal__header" ]
                        [ div [ class "modal__title" ]
                            [ text
                                ((if ui.editingId == Nothing then
                                    "Add Condition — "

                                  else
                                    "Edit Condition — "
                                 )
                                    ++ ui.target
                                )
                            ]
                        , button
                            [ class "modal__close"
                            , onClick ConditionClose
                            , title "Cancel"
                            , attribute "aria-label" "Cancel"
                            ]
                            [ text "×" ]
                        ]
                    , div [ class "modal__body" ]
                        [ viewConditionStandardSection ui
                        , viewConditionCustomSection ui
                        , viewConditionNoteSection ui
                        , viewConditionDurationSection ui model
                        , viewConditionSaveSection ui
                        , viewConditionApplyScope ui model.encounter
                        , viewConditionFooter ui
                        ]
                    ]
                ]


{-| Multi-target scope checkbox for the condition modal. Same
shape as `viewHpChangeApplyScope`: hidden when no creatures are
selected, otherwise a toggle that splatters a fresh copy of the
new condition onto every selected creature (each gets its own
id).

Hidden entirely when editing an existing condition — you're
modifying one specific row, not creating new ones in bulk.

-}
viewConditionApplyScope : ConditionUi -> Encounter -> Html Msg
viewConditionApplyScope ui enc =
    let
        selectedCount =
            List.length (List.filter .selected enc.creatures)
    in
    if ui.editingId /= Nothing || selectedCount == 0 then
        text ""

    else
        div [ class "cond-section" ]
            [ Html.label [ class "hp-change__checkbox" ]
                [ input
                    [ type_ "checkbox"
                    , checked ui.applyToSelected
                    , onClick ConditionApplyToSelectedToggle
                    ]
                    []
                , text
                    (" Apply to all selected creatures ("
                        ++ String.fromInt selectedCount
                        ++ ")"
                    )
                ]
            , div [ class "cond-section__caption" ]
                [ text "Each selected creature gets its own copy of the condition (separate ids, independent durations)." ]
            ]


viewConditionStandardSection : ConditionUi -> Html Msg
viewConditionStandardSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Standard 5e Conditions" ]
        , div [ class "cond-radio-grid" ]
            (List.map (viewConditionRadio ui) Encounter.standardConditions)
        ]


viewConditionRadio : ConditionUi -> String -> Html Msg
viewConditionRadio ui label =
    let
        isSelected =
            ui.name == label
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Html.Attributes.name "condition-radio"
            , checked isSelected
            , onClick (ConditionPickStandard label)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


viewConditionCustomSection : ConditionUi -> Html Msg
viewConditionCustomSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Custom Name" ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.customName
            , placeholder "e.g. Bardic Inspiration, On fire"
            , onInput ConditionCustomNameChanged
            ]
            []
        , div [ class "cond-section__caption" ]
            [ text "Typing here overrides the radio selection above." ]
        ]


viewConditionNoteSection : ConditionUi -> Html Msg
viewConditionNoteSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text ("Note (max " ++ String.fromInt maxConditionNoteLength ++ " chars)") ]
        , input
            [ class "cond-input"
            , type_ "text"
            , value ui.note
            , maxlength maxConditionNoteLength
            , placeholder "e.g. from Lyra"
            , onInput ConditionNoteChanged
            ]
            []
        ]


viewConditionDurationSection : ConditionUi -> Model -> Html Msg
viewConditionDurationSection ui model =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ text "Duration" ]
        , div [ class "cond-radio-row" ]
            [ viewDurationKindRadio ui DurKindManual "Manual"
            , viewDurationKindRadio ui DurKindUntilTurn "Until turn"
            , viewDurationKindRadio ui DurKindCountdown "Countdown"
            ]
        , case ui.durationKind of
            DurKindManual ->
                div [ class "cond-section__caption" ]
                    [ text "Stays until the GM clicks the chip's × to remove." ]

            DurKindUntilTurn ->
                viewDurationUntilSubsection ui model

            DurKindCountdown ->
                viewDurationCountdownSubsection ui
        ]


viewDurationKindRadio : ConditionUi -> DurationKind -> String -> Html Msg
viewDurationKindRadio ui kind label =
    Html.label
        [ class
            (if ui.durationKind == kind then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Html.Attributes.name "duration-kind"
            , checked (ui.durationKind == kind)
            , onClick (ConditionDurationKindSet kind)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


viewDurationUntilSubsection : ConditionUi -> Model -> Html Msg
viewDurationUntilSubsection ui model =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [] [ text "At" ]
            , viewPhaseToggle "until-phase" ui.untilPhase ConditionUntilPhaseSet
            , Html.label [] [ text "of" ]
            , Html.select
                [ class "cond-select"
                , onInput ConditionUntilCreatureChanged
                ]
                (List.map
                    (\c ->
                        Html.option
                            [ value c.name
                            , Html.Attributes.selected (c.name == ui.untilCreature)
                            ]
                            [ text c.name ]
                    )
                    model.encounter.creatures
                )
            , Html.label [] [ text "'s" ]
            , viewTurnTargetToggle ui model
            , Html.label [] [ text "turn" ]
            ]
        ]


{-| Two-button current / next radio toggle inserted between the
reference creature and the word "turn" in the duration row.

The "current" button is disabled when [`currentTurnInvalid`] is
true — i.e. begin-of-turn paired with the currently-active
creature, since their current begin-of-turn already fired.

-}
viewTurnTargetToggle : ConditionUi -> Model -> Html Msg
viewTurnTargetToggle ui model =
    let
        currentDisabled =
            currentTurnInvalid model ui
    in
    span [ class "cond-phase-toggle" ]
        [ Html.label
            [ class
                (String.join " "
                    (List.filterMap identity
                        [ Just "cond-phase"
                        , if ui.untilTarget == Encounter.OnCurrentTurn then
                            Just "cond-phase--on"

                          else
                            Nothing
                        , if currentDisabled then
                            Just "cond-phase--disabled"

                          else
                            Nothing
                        ]
                    )
                )
            , title
                (if currentDisabled then
                    "The current begin-of-turn already fired for the active creature — pick 'next' instead"

                 else
                    "Expire on the first matching hook fire"
                )
            ]
            [ input
                [ type_ "radio"
                , Html.Attributes.name "until-target"
                , checked (ui.untilTarget == Encounter.OnCurrentTurn)
                , disabled currentDisabled
                , onClick (ConditionUntilTargetSet Encounter.OnCurrentTurn)
                ]
                []
            , text "current"
            ]
        , Html.label
            [ class
                (if ui.untilTarget == Encounter.OnNextTurn then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            , title "Skip the first matching hook fire and expire on the second"
            ]
            [ input
                [ type_ "radio"
                , Html.Attributes.name "until-target"
                , checked (ui.untilTarget == Encounter.OnNextTurn)
                , onClick (ConditionUntilTargetSet Encounter.OnNextTurn)
                ]
                []
            , text "next"
            ]
        ]


viewDurationCountdownSubsection : ConditionUi -> Html Msg
viewDurationCountdownSubsection ui =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-countdown-turns" ]
                [ text "Lasts" ]
            , input
                [ id "cond-countdown-turns"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Html.Attributes.min "1"
                , Html.Attributes.max "99"
                , value ui.countdownTurnsText
                , onInput ConditionCountdownTurnsChanged
                ]
                []
            , Html.label [] [ text "turns, ticking at" ]
            , viewPhaseToggle "countdown-phase" ui.countdownPhase ConditionCountdownPhaseSet
            , Html.label [] [ text "of the bearer's turn" ]
            ]
        , div [ class "cond-section__caption" ]
            [ text
                ("If you set 'end' while it's already this creature's turn, "
                    ++ "the countdown skips this end-of-turn so they get a "
                    ++ "full first turn under the effect."
                )
            ]
        ]


viewPhaseToggle : String -> Encounter.TurnPhase -> (Encounter.TurnPhase -> Msg) -> Html Msg
viewPhaseToggle groupName current toMsg =
    span [ class "cond-phase-toggle" ]
        [ Html.label
            [ class
                (if current == Encounter.AtBegin then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            ]
            [ input
                [ type_ "radio"
                , Html.Attributes.name groupName
                , checked (current == Encounter.AtBegin)
                , onClick (toMsg Encounter.AtBegin)
                ]
                []
            , text "beginning"
            ]
        , Html.label
            [ class
                (if current == Encounter.AtEnd then
                    "cond-phase cond-phase--on"

                 else
                    "cond-phase"
                )
            ]
            [ input
                [ type_ "radio"
                , Html.Attributes.name groupName
                , checked (current == Encounter.AtEnd)
                , onClick (toMsg Encounter.AtEnd)
                ]
                []
            , text "end"
            ]
        ]


viewConditionSaveSection : ConditionUi -> Html Msg
viewConditionSaveSection ui =
    div [ class "cond-section" ]
        [ h3 [ class "cond-section__heading" ]
            [ Html.label []
                [ input
                    [ type_ "checkbox"
                    , checked (ui.saveToEnd /= Nothing)
                    , onClick ConditionSaveToggle
                    ]
                    []
                , text " Save-to-end"
                ]
            ]
        , case ui.saveToEnd of
            Nothing ->
                div [ class "cond-section__caption" ]
                    [ text "Optional: condition can end on a successful saving throw." ]

            Just s ->
                viewConditionSaveSubsection s
        ]


viewConditionSaveSubsection : SaveToEndUi -> Html Msg
viewConditionSaveSubsection s =
    div [ class "cond-subsection" ]
        [ div [ class "cond-row" ]
            [ Html.label [ for "cond-save-ability" ] [ text "Ability" ]
            , Html.select
                [ id "cond-save-ability"
                , class "cond-select"
                , onInput ConditionSaveAbilityChanged
                ]
                (List.map
                    (\a ->
                        Html.option
                            [ value a
                            , Html.Attributes.selected (a == s.ability)
                            ]
                            [ text a ]
                    )
                    [ "STR", "DEX", "CON", "INT", "WIS", "CHA" ]
                )
            , Html.label [ for "cond-save-dc" ] [ text "DC" ]
            , input
                [ id "cond-save-dc"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Html.Attributes.min "1"
                , Html.Attributes.max "40"
                , value s.dcText
                , onInput ConditionSaveDcChanged
                ]
                []
            , Html.label [ for "cond-save-bonus" ] [ text "Bonus" ]
            , input
                [ id "cond-save-bonus"
                , class "cond-input cond-input--narrow"
                , type_ "number"
                , Html.Attributes.min "-10"
                , Html.Attributes.max "20"
                , value s.bonusText
                , onInput ConditionSaveBonusChanged
                ]
                []
            ]
        , div [ class "cond-radio-stack" ]
            [ viewAutoRollRadio s
                Encounter.AutoRollManual
                "Manual (no auto-roll — GM clicks 🎲 on the chip)"
            , viewAutoRollRadio s
                Encounter.AutoRollAtBegin
                "Auto-roll at the bearer's beginning-of-turn"
            , viewAutoRollRadio s
                Encounter.AutoRollAtEnd
                "Auto-roll at the bearer's end-of-turn"
            ]
        , div [ class "cond-section__caption" ]
            [ text (autoRollCaption s.autoRoll) ]
        ]


{-| One radio button in the auto-roll mode group. Shares the
.cond-radio chrome with the other radio groups in the modal.
-}
viewAutoRollRadio : SaveToEndUi -> Encounter.AutoRollMode -> String -> Html Msg
viewAutoRollRadio s mode label =
    let
        isSelected =
            s.autoRoll == mode
    in
    Html.label
        [ class
            (if isSelected then
                "cond-radio cond-radio--selected"

             else
                "cond-radio"
            )
        ]
        [ input
            [ type_ "radio"
            , Html.Attributes.name "cond-save-autoroll"
            , checked isSelected
            , onClick (ConditionSaveAutoRollSet mode)
            ]
            []
        , span [ class "cond-radio__label" ] [ text label ]
        ]


{-| Caption text under the auto-roll radio group describing what
will actually happen in play. Updates live with the selection so
the GM can see the consequence without clicking submit.
-}
autoRollCaption : Encounter.AutoRollMode -> String
autoRollCaption mode =
    case mode of
        Encounter.AutoRollManual ->
            "The 🎲 button on the chip rolls manually — a reminder, not auto-applied."

        Encounter.AutoRollAtBegin ->
            "Save fires at the start of the bearer's turn; success removes the condition."

        Encounter.AutoRollAtEnd ->
            "Save fires at the end of the bearer's turn; success removes the condition."


viewConditionFooter : ConditionUi -> Html Msg
viewConditionFooter ui =
    let
        canSubmit =
            not (String.isEmpty (String.trim ui.name))

        applyLabel =
            if ui.editingId == Nothing then
                "Apply"

            else
                "Save Changes"
    in
    div [ class "cond-footer" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick ConditionSubmit
            , disabled (not canSubmit)
            , attribute "aria-disabled"
                (if canSubmit then
                    "false"

                 else
                    "true"
                )
            , title
                (if canSubmit then
                    applyLabel

                 else
                    "Pick a condition or type a custom name first"
                )
            ]
            [ text applyLabel ]
        , case ui.editingId of
            Just _ ->
                button
                    [ class "action-btn action-btn--damage"
                    , onClick ConditionDelete
                    , title "Remove this condition"
                    ]
                    [ text "Delete" ]

            Nothing ->
                text ""
        , button
            [ class "action-btn"
            , onClick ConditionClose
            ]
            [ text "Cancel" ]
        ]



-- MEMO + TIMER MODALS


{-| Card row 3 memo edit modal. Single text input capped at 20
chars with Save / Cancel buttons. Same chrome as the row 1
note-edit modal but writes to a different field on Creature
(`memo` vs `note`) so they can coexist on the same card.
-}
viewMemoEditModal : Model -> Html Msg
viewMemoEditModal model =
    case model.memoEdit of
        Nothing ->
            text ""

        Just ui ->
            div
                [ class "modal-backdrop"
                , onClick MemoCancel
                ]
                [ div
                    [ class "modal modal--note-edit"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    , attribute "aria-label" ("Memo for " ++ ui.target)
                    ]
                    [ div [ class "modal__header" ]
                        [ div [ class "modal__title" ]
                            [ text ("Memo — " ++ ui.target) ]
                        , button
                            [ class "modal__close"
                            , onClick MemoCancel
                            , title "Cancel"
                            , attribute "aria-label" "Cancel"
                            ]
                            [ text "×" ]
                        ]
                    , div [ class "modal__body" ]
                        [ Html.label [ for "memo-edit-input" ]
                            [ text ("Short memo (max " ++ String.fromInt maxMemoLength ++ " chars)") ]
                        , input
                            [ id "memo-edit-input"
                            , class "note-edit__input"
                            , type_ "text"
                            , value ui.text
                            , maxlength maxMemoLength
                            , placeholder "e.g. legendary res used"
                            , autofocus True
                            , onInput MemoChange
                            , Html.Events.on "keydown" (enterKey MemoCommit)
                            ]
                            []
                        , div [ class "note-edit__buttons" ]
                            [ button
                                [ class "action-btn action-btn--green"
                                , onClick MemoCommit
                                ]
                                [ text "Save" ]
                            , button
                                [ class "action-btn"
                                , onClick MemoCancel
                                ]
                                [ text "Cancel" ]
                            ]
                        ]
                    ]
                ]


{-| Card row 3 timer-setup modal. The GM picks a turn count
(1..99) and a phase (begin/end of bearer's turn). Apply writes
the timer; Cancel discards.
-}
viewTimerSetupModal : Model -> Html Msg
viewTimerSetupModal model =
    case model.timerSetup of
        Nothing ->
            text ""

        Just ui ->
            div
                [ class "modal-backdrop"
                , onClick TimerSetupCancel
                ]
                [ div
                    [ class "modal modal--timer"
                    , stopPropagationOn "click" (Decode.succeed ( NoOp, True ))
                    , attribute "role" "dialog"
                    , attribute "aria-modal" "true"
                    , attribute "aria-label" ("Timer for " ++ ui.target)
                    ]
                    [ div [ class "modal__header" ]
                        [ div [ class "modal__title" ]
                            [ text ("Timer — " ++ ui.target) ]
                        , button
                            [ class "modal__close"
                            , onClick TimerSetupCancel
                            , title "Cancel"
                            , attribute "aria-label" "Cancel"
                            ]
                            [ text "×" ]
                        ]
                    , div [ class "modal__body" ]
                        [ div [ class "cond-row" ]
                            [ Html.label [ for "timer-turns-input" ]
                                [ text "Lasts" ]
                            , input
                                [ id "timer-turns-input"
                                , class "cond-input cond-input--narrow"
                                , type_ "number"
                                , Html.Attributes.min "1"
                                , Html.Attributes.max "99"
                                , value ui.turnsText
                                , autofocus True
                                , onInput TimerSetupTurnsChanged
                                , Html.Events.on "keydown" (enterKey TimerSetupApply)
                                ]
                                []
                            , Html.label [] [ text "turns, ticking at" ]
                            , viewPhaseToggle "timer-phase" ui.phase TimerSetupPhaseSet
                            , Html.label [] [ text "of the bearer's turn" ]
                            ]
                        , div [ class "cond-section__caption" ]
                            [ text "When it reaches 0 the card flashes a 0 and the page plays a ping. Click × on the timer to dismiss." ]
                        , div [ class "note-edit__buttons" ]
                            [ button
                                [ class "action-btn action-btn--green"
                                , onClick TimerSetupApply
                                ]
                                [ text "Start Timer" ]
                            , button
                                [ class "action-btn"
                                , onClick TimerSetupCancel
                                ]
                                [ text "Cancel" ]
                            ]
                        ]
                    ]
                ]


{-| Page-level audio element that plays the ping sound when any
creature has a ringing timer. Mounted only when at least one
timer is ringing — the mount triggers HTML5's `autoplay` so the
sound fires once. When all rings are dismissed the element
unmounts; a future ring remounts it and replays the sound.

Browsers without autoplay permission may block the first play
until the user has interacted with the page; in this app the GM
has already clicked Next Turn (which is what triggered the ring)
so the user-gesture requirement is satisfied.

-}
viewRingerAudio : Model -> Html Msg
viewRingerAudio model =
    let
        anyRinging =
            List.any
                (\c ->
                    case c.timer of
                        Just t ->
                            t.ringing

                        Nothing ->
                            False
                )
                model.encounter.creatures
    in
    if anyRinging then
        Html.audio
            [ src "/ping.wav"
            , autoplay True
            , attribute "aria-hidden" "true"
            ]
            []

    else
        text ""
