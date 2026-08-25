module Update.HpChange exposing
    ( amountChanged
    , applyAs
    , applyToSelectedToggle
    , close
    , editCancel
    , editChange
    , editCommit
    , editStart
    , ignoreTempToggle
    , open
    , rollLanded
    , undoLatest
    )

{-| Update branches for the HP-change modal (Manage HP) and
the inline HP edit pencil on each creature card.

Now uses a single smart amount input: on apply, the raw text
is either parsed as an integer (applied immediately) or as a
dice expression (rolled, then the total is applied). Parse
errors are surfaced next to the input. The previous
Manual/Roll-dice mode toggle is gone — the parse itself
decides which path to take.

-}

import Dice
import Effects
import Encounter exposing (Creature, Encounter)
import HpChange
import Model exposing (Model, Surface(..))
import Msg
    exposing
        ( HpField(..)
        , HpKind(..)
        , Msg(..)
        )
import Ui.HpChange as HpChangeUi exposing (HpChangeUi)


{-| Apply `fn` to the open HP-change modal. No-op when the modal
is closed (or a different modal is open).
-}
withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model
withHpChange =
    Model.mapSurface Model.hpChangeLens


{-| Opening is a toggle: clicking the card's Manage HP button
while its own editor is already expanded closes it (a cancel),
matching how the button reads once the editor sits inline on
the card rather than in an overlay.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case model.surface of
        Just (SurfaceHpChange ui) ->
            if ui.target == target then
                { model | surface = Nothing }

            else
                { model | surface = Just (SurfaceHpChange (HpChangeUi.fresh target)) }

        _ ->
            { model | surface = Just (SurfaceHpChange (HpChangeUi.fresh target)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | surface = Nothing }, Cmd.none )


{-| Mirror the raw text for the controlled input. Clears any
prior parse error on every keystroke so the "invalid formula"
hint disappears the moment the GM starts fixing it.
-}
amountChanged : String -> Model -> ( Model, Cmd Msg )
amountChanged text model =
    ( withHpChange (\u -> { u | amountText = text, parseError = Nothing }) model
    , Cmd.none
    )


ignoreTempToggle : Model -> ( Model, Cmd Msg )
ignoreTempToggle model =
    ( withHpChange (\u -> { u | ignoreTemp = not u.ignoreTemp }) model
    , Cmd.none
    )


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withHpChange (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )


{-| Footer action-button click: commit the modal's amount text
as `kind`. Sets `ui.kind = kind` first (so the dice-source
label + log entry reflect the chosen kind), then routes based
on what the input looks like:

  - integer → apply immediately with that value
  - dice formula → roll, land in `rollLanded`, apply the total
  - parse failure → set `parseError`, leave modal open

-}
applyAs : HpKind -> Model -> ( Model, Cmd Msg )
applyAs kind model =
    case model.surface of
        Just (SurfaceHpChange ui) ->
            let
                withKind =
                    { ui | kind = kind }

                modelWithKind =
                    { model | surface = Just (SurfaceHpChange withKind) }

                trimmed =
                    String.trim withKind.amountText
            in
            case String.toInt trimmed of
                Just n ->
                    ( applyHpChangeAndClose withKind n modelWithKind
                    , Cmd.none
                    )

                Nothing ->
                    if String.isEmpty trimmed then
                        -- Empty field: treat as 0 so the GM
                        -- can click Damage on a fresh open
                        -- without typing to test the target
                        -- creature reference — the previous
                        -- behaviour when `amountText = "0"`
                        -- was the default.
                        ( applyHpChangeAndClose withKind 0 modelWithKind
                        , Cmd.none
                        )

                    else
                        case Dice.parse trimmed of
                            Ok expr ->
                                ( modelWithKind
                                , Dice.rollCmd HpChangeRollLanded
                                    (hpChangeSource withKind modelWithKind.encounter)
                                    expr
                                )

                            Err err ->
                                ( withHpChange (\u -> { u | parseError = Just err }) modelWithKind
                                , Cmd.none
                                )

        _ ->
            ( model, Cmd.none )


{-| The dice-mode path lands here. We commit the change with
`roll.total`, log the roll to the dice history (so the user has a
record), and persist it server-side through the same
`/api/dice/history` pipe the dice modal uses. If the modal got
closed mid-flight (defensive), still log/persist so we don't drop
rolls on the floor.
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    let
        ( logged, flashCmd ) =
            Effects.pushDiceRoll roll model

        committed =
            case logged.surface of
                Just (SurfaceHpChange ui) ->
                    applyHpChangeAndClose ui roll.total logged

                _ ->
                    logged
    in
    ( committed
    , Cmd.batch [ Effects.persistDiceRoll roll, flashCmd ]
    )


editStart : String -> HpField -> Int -> Model -> ( Model, Cmd Msg )
editStart name field current model =
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


editChange : String -> Model -> ( Model, Cmd Msg )
editChange text model =
    ( case model.hpEdit of
        Just edit ->
            { model | hpEdit = Just { edit | text = text } }

        Nothing ->
            model
    , Cmd.none
    )


{-| Parse the text. On success, write through HpChange's manual-edit
helpers (which clamp + recompute bloodied). On parse failure, just
close the editor without changing anything — easier than surfacing
a transient error inline.
-}
editCommit : Model -> ( Model, Cmd Msg )
editCommit model =
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

                                ArmorClassField ->
                                    HpChange.setArmorClass n

                                TempHpField ->
                                    HpChange.setTempHp n
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


editCancel : Model -> ( Model, Cmd Msg )
editCancel model =
    ( { model | hpEdit = Nothing }, Cmd.none )


{-| Undo the most-recent HP-change log entry: restore the
target creature's currentHp and tempHp from the entry's
`before*` snapshot, then drop that entry from the log so the
next undo click chains backwards.

If the targeted creature was deleted from the queue between the
change and the undo, the restore is a silent no-op (handled by
`Encounter.mapCreature`'s missing-name passthrough); the entry
is still dropped so the GM doesn't get stuck on an unactionable
row.

-}
undoLatest : Model -> ( Model, Cmd Msg )
undoLatest model =
    case model.hpChangeLog of
        entry :: rest ->
            ( { model
                | encounter =
                    Encounter.mapCreature entry.target
                        (HpChange.restoreHp
                            { hp = entry.beforeHp
                            , tempHp = entry.beforeTemp
                            , maxHp = entry.beforeMax
                            }
                        )
                        model.encounter
                , hpChangeLog = rest
              }
            , Cmd.none
            )

        [] ->
            ( model, Cmd.none )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Build the `Dice.Source` label for an HP-change roll, so the dice
history reads "Damage → Brakka" or "Heal → Aria, Brakka".
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

                MaxHpKind ->
                    "+Max HP"

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
selected creature (`Creature.selected = True`). Same amount across
all targets — for dice mode this means the GM rolled once and N
creatures soak the same total, which matches 5e's
single-roll-per-AOE convention (a Fireball rolls 8d6 once and each
target takes that much, not 8d6 per target).

When `applyToSelected` is False, only `ui.target` is affected (the
original single-card flow).

If no creatures match (no selection), the modal still closes
without applying to anyone — better than silently falling back to
`ui.target`, which would surprise the GM who explicitly checked the
multi-target toggle.

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

                MaxHpKind ->
                    HpChange.MaxHpDelta amount

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
                            , beforeMax = b.maxHp
                            , afterHp = a.currentHp
                            , afterTemp = a.tempHp
                            , afterMax = a.maxHp
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
        , surface = Nothing
        , hpChangeLog =
            List.reverse result.log
                ++ List.take (Basics.max 0 (HpChangeUi.maxHpLogEntries - List.length result.log)) model.hpChangeLog
    }


hpChangeTargets : HpChangeUi -> Encounter -> List String
hpChangeTargets ui enc =
    if ui.applyToSelected then
        enc.creatures
            |> List.filter .selected
            |> List.map .name

    else
        [ ui.target ]


findCreature : String -> Encounter -> Maybe Creature
findCreature name enc =
    List.filter (\c -> c.name == name) enc.creatures
        |> List.head
