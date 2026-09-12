module Update.HpChange exposing
    ( amountChanged
    , applyAs
    , applyToSelectedToggle
    , editCancel
    , editChange
    , editCommit
    , editStart
    , freshRollLanded
    , freshRollToggle
    , logToggle
    , manualApplySelected
    , manualApplyTarget
    , manualChanged
    , manualRollChanged
    , manualRollClear
    , manualRollLanded
    , openFor
    , rollLanded
    , setToggle
    , undoLatest
    )

{-| Update branches for the Manage HP editor and the inline AC
edit on each creature card.

The verb buttons share one smart amount input: on apply, the raw
text is either parsed as an integer (applied immediately) or as
a dice expression (rolled, then the total is applied), so the
parse itself decides the path. Parse errors are surfaced next to
the input. The Manual section bypasses the verbs entirely and
writes the typed pools straight onto its targets.

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
import Ui.HpChange as HpChangeUi exposing (HpChangeUi, HpLogKind(..))


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.hpChangeLens model
        |> Maybe.map SurfaceHpChange


withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model
withHpChange =
    Model.mapSurface Model.hpChangeLens


{-| Type into one of the three manual pool fields. `HpField`
names which; the card's inline AC edit reuses the same
discriminator, and `ArmorClassField` has no manual row here.
-}
manualChanged : HpField -> String -> Model -> ( Model, Cmd Msg )
manualChanged field text model =
    ( withHpChange
        (\u ->
            case field of
                CurrentHpField ->
                    { u | manualHpText = text }

                MaxHpField ->
                    { u | manualMaxHpText = text }

                TempHpField ->
                    { u | manualTempHpText = text }

                ArmorClassField ->
                    u
        )
        model
    , Cmd.none
    )


{-| Apply the Set section to the editor's own target.
-}
manualApplyTarget : Model -> ( Model, Cmd Msg )
manualApplyTarget model =
    case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            manualApplyTo [ ui.target ] ui model

        _ ->
            ( model, Cmd.none )


{-| Apply the Set section to every selected creature.
-}
manualApplySelected : Model -> ( Model, Cmd Msg )
manualApplySelected model =
    case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            manualApplyTo
                (model.encounter.creatures
                    |> List.filter .selected
                    |> List.map .name
                )
                ui
                model

        _ ->
            ( model, Cmd.none )


{-| The Set section's apply: with a formula in the Roll field,
roll it once per named creature and let each landing set that
creature's hit points; otherwise stamp whichever typed pools
parsed onto each of them. A blank or unparseable pool field
leaves its pool untouched, so the GM can set one pool without
restating the other two.
-}
manualApplyTo : List String -> HpChangeUi -> Model -> ( Model, Cmd Msg )
manualApplyTo rawNames ui model =
    let
        names =
            Encounter.excludingPlaceholderNames model.encounter rawNames

        rollText =
            String.trim ui.manualRollText
    in
    if String.isEmpty rollText then
        ( setPools names ui model, Cmd.none )

    else
        case Dice.parse rollText of
            Ok expr ->
                ( model
                , names
                    |> List.map
                        (\name ->
                            Dice.rollCmd (HpChangeManualRollLanded name)
                                { feature = "HP roll", target = Just name }
                                expr
                        )
                    |> Cmd.batch
                )

            Err err ->
                ( withHpChange (\u -> { u | manualRollError = Just err }) model
                , Cmd.none
                )


setPools : List String -> HpChangeUi -> Model -> Model
setPools names ui model =
    let
        parse =
            String.toInt << String.trim

        setters =
            List.filterMap identity
                [ Maybe.map HpChange.setMaxHp (parse ui.manualMaxHpText)
                , Maybe.map HpChange.setCurrentHp (parse ui.manualHpText)
                , Maybe.map HpChange.setTempHp (parse ui.manualTempHpText)
                ]
    in
    if List.isEmpty setters then
        model

    else
        applyTransform SetPools
            Nothing
            False
            names
            (\creature -> List.foldl (\set c -> set c) creature setters)
            model


{-| One landing of the Set section's roll: the creature's hit
points become the total, both current and maximum, as a monster
rolled instead of taking its average. The roll joins the dice
history like any other.
-}
manualRollLanded : String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
manualRollLanded name roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model
    in
    ( applyTransform RolledHp
        (Just roll.total)
        True
        [ name ]
        (HpChange.setMaxHp roll.total >> HpChange.setCurrentHp roll.total)
        logged
    , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]
    )


manualRollChanged : String -> Model -> ( Model, Cmd Msg )
manualRollChanged text model =
    ( withHpChange (\u -> { u | manualRollText = text, manualRollError = Nothing }) model
    , Cmd.none
    )


manualRollClear : Model -> ( Model, Cmd Msg )
manualRollClear model =
    manualRollChanged "" model


logToggle : Model -> ( Model, Cmd Msg )
logToggle model =
    ( { model | hpLogOpen = not model.hpLogOpen }, Cmd.none )


setToggle : Model -> ( Model, Cmd Msg )
setToggle model =
    ( { model | hpSetOpen = not model.hpSetOpen }, Cmd.none )


{-| A card's HP value: it aims the editor at its own creature,
so an editor already open for someone else re-aims. Every path
unfolds and scrolls the panel fully into view — a card control
asks to see a creature's editor, whether that means showing what
is already open, re-aiming it, or opening it fresh.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    let
        nextModel =
            Model.ackHpLog
                (case drawerSurface model of
                    Just (SurfaceHpChange ui) ->
                        if ui.target == target then
                            Model.unfoldDrawer Model.hpChangeLens model

                        else
                            Model.openDrawer Model.hpChangeLens (HpChangeUi.fresh target) model

                    _ ->
                        Model.openDrawer Model.hpChangeLens (HpChangeUi.fresh target) model
                )
    in
    ( nextModel
    , Effects.scrollDrawerIndex (Model.drawerIndexOf Model.hpChangeLens nextModel)
    )


{-| Mirror the raw text for the controlled input. Clears any
prior parse error on every keystroke so the "invalid formula"
hint disappears the moment the GM starts fixing it.
-}
amountChanged : String -> Model -> ( Model, Cmd Msg )
amountChanged text model =
    ( withHpChange (\u -> { u | amountText = text, parseError = Nothing }) model
    , Cmd.none
    )


applyToSelectedToggle : Model -> ( Model, Cmd Msg )
applyToSelectedToggle model =
    ( withHpChange (\u -> { u | applyToSelected = not u.applyToSelected }) model
    , Cmd.none
    )


freshRollToggle : Model -> ( Model, Cmd Msg )
freshRollToggle model =
    ( withHpChange (\u -> { u | freshRollPerTarget = not u.freshRollPerTarget }) model
    , Cmd.none
    )


{-| Footer action-button click: commit the editor's amount text
as `kind`. Sets `ui.kind = kind` first (so the dice-source
label + log entry reflect the chosen kind), then routes based
on what the input looks like:

  - integer → apply immediately with that value
  - dice formula → roll, land in `rollLanded`, apply the total
  - parse failure → set `parseError`

The editor stays open after every path so the GM can keep
applying.

-}
applyAs : HpKind -> Model -> ( Model, Cmd Msg )
applyAs kind model =
    case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            let
                withKind =
                    { ui | kind = kind }

                modelWithKind =
                    Model.openDrawer Model.hpChangeLens withKind model

                trimmed =
                    String.trim withKind.amountText
            in
            case String.toInt trimmed of
                Just n ->
                    ( applyHpChange withKind n False modelWithKind
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
                        ( applyHpChange withKind 0 False modelWithKind
                        , Cmd.none
                        )

                    else
                        case Dice.parse trimmed of
                            Ok expr ->
                                if withKind.applyToSelected && withKind.freshRollPerTarget then
                                    -- One independent roll per selected
                                    -- creature.  Each landing carries
                                    -- everything it needs to apply on
                                    -- its own, so the editor is free to
                                    -- close (or not) in the meantime.
                                    ( modelWithKind
                                    , hpChangeTargets withKind modelWithKind.encounter
                                        |> List.map
                                            (\name ->
                                                Dice.rollCmd
                                                    (HpChangeFreshRollLanded kind name)
                                                    { feature = kindLabel kind, target = Just name }
                                                    expr
                                            )
                                        |> Cmd.batch
                                    )

                                else
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
`/api/dice/history` pipe the dice roller uses. If the editor is
gone mid-flight (defensive), still log/persist so we don't drop
rolls on the floor.
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model

        committed =
            case drawerSurface logged of
                Just (SurfaceHpChange ui) ->
                    applyHpChange ui roll.total True logged

                _ ->
                    logged
    in
    ( committed
    , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]
    )


{-| One landing of a fresh-per-creature roll batch. Everything
needed to commit rides in the message itself — the editor may
have been closed between dispatch and landing — so each landing
applies, logs, and persists its own roll independently of its
siblings.
-}
freshRollLanded : HpKind -> String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
freshRollLanded kind target roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model
    in
    ( applyAmountTo kind [ target ] roll.total True logged
    , Cmd.batch [ Effects.persistDiceRoll roll, broadcastCmd ]
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
            let
                restoreOne snapshot enc =
                    Encounter.mapCreature snapshot.name
                        (HpChange.restoreHp
                            { hp = snapshot.beforeHp
                            , tempHp = snapshot.beforeTemp
                            , maxHp = snapshot.beforeMax
                            }
                        )
                        enc
            in
            ( { model
                | encounter =
                    List.foldl restoreOne model.encounter entry.targets
                , hpChangeLog = rest

                -- Undo uncovers an older row, which remounts under
                -- a different key.  Acknowledging it here is what
                -- stops that remount reading as a fresh apply.
                , flashedHpLogSeq =
                    List.head rest
                        |> Maybe.map .seq
                        |> Maybe.withDefault model.flashedHpLogSeq
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
    { feature = kindLabel ui.kind, target = Just targetLabel }


kindLabel : HpKind -> String
kindLabel kind =
    case kind of
        DamageKind ->
            "Damage"

        HealKind ->
            "Heal"

        TempHpKind ->
            "Temp HP"

        MaxHpKind ->
            "+Max HP"


{-| Resolve the editor's kind into an `HpChange.Change`,
hand it to the engine, write the updated creature back through
`Encounter.mapCreature`, push a log entry capturing the before/after
snapshot. The caller decides the amount — it comes from the manual
input on the manual path or from the rolled total on the dice
path.

When `ui.applyToSelected` is True, the change is applied to every
selected creature (`Creature.selected = True`). Same amount across
all targets — for dice mode this means the GM rolled once and N
creatures soak the same total, which matches 5e's
single-roll-per-AOE convention (a Fireball rolls 8d6 once and each
target takes that much, not 8d6 per target).

When `applyToSelected` is False, only `ui.target` is affected (the
original single-card flow).

If no creatures match (no selection), nothing is applied — better
than silently falling back to `ui.target`, which would surprise
the GM who explicitly checked the multi-target toggle.

-}
applyHpChange : HpChangeUi -> Int -> Bool -> Model -> Model
applyHpChange ui amount rolled model =
    applyAmountTo ui.kind
        (hpChangeTargets ui model.encounter)
        amount
        rolled
        model


{-| The verb buttons' commit: resolve the kind into an
`HpChange.Change` and write it through the engine for each target.
`rolled` says whether the dice roller produced the amount.
-}
applyAmountTo : HpKind -> List String -> Int -> Bool -> Model -> Model
applyAmountTo kind targets amount rolled model =
    let
        change =
            case kind of
                DamageKind ->
                    HpChange.Damage amount

                HealKind ->
                    HpChange.Heal amount

                TempHpKind ->
                    HpChange.TempHp amount

                MaxHpKind ->
                    HpChange.MaxHpDelta amount
    in
    applyTransform (Applied kind) (Just amount) rolled targets (HpChange.apply change) model


{-| The commit core shared by every apply path: write `transform`
through `Encounter.mapCreature` for each target, and push one log
entry capturing the before/after snapshots — which unfolds the
log, so the GM sees what just landed.
-}
applyTransform : HpLogKind -> Maybe Int -> Bool -> List String -> (Creature -> Creature) -> Model -> Model
applyTransform kind amount rolled targets transform model =
    let
        applyOne name acc =
            let
                before =
                    findCreature name acc.encounter

                newEnc =
                    Encounter.mapCreature name transform acc.encounter

                after =
                    findCreature name newEnc

                snapshot =
                    Maybe.map2
                        (\b a ->
                            { name = name
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
            , snapshots =
                case snapshot of
                    Just s ->
                        s :: acc.snapshots

                    Nothing ->
                        acc.snapshots
            }

        result =
            List.foldl applyOne { encounter = model.encounter, snapshots = [] } targets
    in
    -- One entry per application, however many creatures it
    -- touched; nothing is logged when no target resolved.
    if List.isEmpty result.snapshots then
        { model | encounter = result.encounter }

    else
        { model
            | encounter = result.encounter
            , nextHpLogSeq = model.nextHpLogSeq + 1
            , hpLogOpen = True
            , hpChangeLog =
                { kind = kind
                , amount = amount
                , rolled = rolled
                , targets = List.reverse result.snapshots
                , rollsBefore = model.dice.history.pushed
                , seq = model.nextHpLogSeq
                }
                    :: List.take (HpChangeUi.maxHpLogEntries - 1) model.hpChangeLog
        }


hpChangeTargets : HpChangeUi -> Encounter -> List String
hpChangeTargets ui enc =
    Encounter.excludingPlaceholderNames enc
        (if ui.applyToSelected then
            enc.creatures
                |> List.filter .selected
                |> List.map .name

         else
            [ ui.target ]
        )


findCreature : String -> Encounter -> Maybe Creature
findCreature name enc =
    List.filter (\c -> c.name == name) enc.creatures
        |> List.head
