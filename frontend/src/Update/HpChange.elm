module Update.HpChange exposing
    ( amountChanged
    , applyAs
    , applyToSelectedToggle
    , close
    , editCancel
    , editChange
    , editCommit
    , editStart
    , freshRollLanded
    , freshRollToggle
    , ignoreTempToggle
    , manualApplySelected
    , manualApplyTarget
    , manualChanged
    , open
    , openFor
    , rollLanded
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
import Ui.HpChange as HpChangeUi exposing (HpChangeUi)


{-| The editor's own drawer entry, in the `Maybe Surface`
shape the pattern matches below were written against.
-}
drawerSurface : Model -> Maybe Surface
drawerSurface model =
    Model.drawerGet Model.hpChangeLens model
        |> Maybe.map SurfaceHpChange


{-| Apply `fn` to the open HP-change modal. No-op when the modal
is closed (or a different modal is open). Every form mutation
routes through here, so the applied-and-untouched flag clears
itself the moment the GM edits anything.
-}
withHpChange : (HpChangeUi -> HpChangeUi) -> Model -> Model
withHpChange fn =
    Model.mapSurface Model.hpChangeLens
        (fn >> (\u -> { u | applied = False }))


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


{-| Write the typed pools onto the editor's own target.
-}
manualApplyTarget : Model -> ( Model, Cmd Msg )
manualApplyTarget model =
    ( case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            manualApplyTo [ ui.target ] ui model

        _ ->
            model
    , Cmd.none
    )


{-| Write the typed pools onto every selected creature.
-}
manualApplySelected : Model -> ( Model, Cmd Msg )
manualApplySelected model =
    ( case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            manualApplyTo
                (model.encounter.creatures
                    |> List.filter .selected
                    |> List.map .name
                )
                ui
                model

        _ ->
            model
    , Cmd.none
    )


{-| Stamp whichever pools parsed onto each named creature. A
blank or unparseable field leaves its pool untouched, so the GM
can set one pool without restating the other two.
-}
manualApplyTo : List String -> HpChangeUi -> Model -> Model
manualApplyTo names ui model =
    let
        step parsed setter enc =
            case parsed of
                Just n ->
                    List.foldl
                        (\name acc -> Encounter.mapCreature name (setter n) acc)
                        enc
                        names

                Nothing ->
                    enc

        parse =
            String.toInt << String.trim
    in
    markApplied
        { model
            | encounter =
                model.encounter
                    |> step (parse ui.manualMaxHpText) HpChange.setMaxHp
                    |> step (parse ui.manualHpText) HpChange.setCurrentHp
                    |> step (parse ui.manualTempHpText) HpChange.setTempHp
        }


{-| The column trigger: clicking it while any Manage HP editor
is expanded closes it — the button wears the open ring and
Cancel hover text whenever the editor is open, so it must close
regardless of which creature a card's HP value aimed it at. A
fresh open restores the stashed draft when the last close left
un-applied settings.
-}
open : String -> Model -> ( Model, Cmd Msg )
open target model =
    ( case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            stashAndClose ui model

        _ ->
            Model.openDrawer Model.hpChangeLens (reopened target model) model
    , Cmd.none
    )


{-| A card's HP value: it aims the editor at its own creature,
so an editor already open for someone else re-aims. One already
aimed here scrolls into view instead of closing — a card control
asks to see a creature's editor, which is the opposite of what
dismissing it would do. The Actions column's own trigger still
toggles.
-}
openFor : String -> Model -> ( Model, Cmd Msg )
openFor target model =
    case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            if ui.target == target then
                ( model
                , Effects.scrollDrawerIndex
                    (Model.drawerIndexOf Model.hpChangeLens model)
                )

            else
                ( Model.openDrawer Model.hpChangeLens (reopened target model) model
                , Cmd.none
                )

        _ ->
            ( Model.openDrawer Model.hpChangeLens (reopened target model) model
            , Cmd.none
            )


reopened : String -> Model -> HpChangeUi
reopened target model =
    case model.hpChangeDraft of
        Just draft ->
            { draft | target = target, parseError = Nothing, applied = False }

        Nothing ->
            HpChangeUi.fresh target


{-| Closing keeps un-applied settings as the draft the next open
restores; once the settings were applied (and untouched since),
closing resets to defaults instead.
-}
stashAndClose : HpChangeUi -> Model -> Model
stashAndClose ui model =
    Model.closeDrawer Model.hpChangeLens
        { model
            | hpChangeDraft =
                if ui.applied then
                    Nothing

                else
                    Just ui
        }


{-| Applying marks the open editor so a subsequent close resets
rather than stashes, and drops any stale draft.
-}
markApplied : Model -> Model
markApplied model =
    case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            Model.mapDrawer Model.hpChangeLens
                (\u -> { u | applied = True })
                { model | hpChangeDraft = Nothing }

        _ ->
            { model | hpChangeDraft = Nothing }


close : Model -> ( Model, Cmd Msg )
close model =
    ( case drawerSurface model of
        Just (SurfaceHpChange ui) ->
            stashAndClose ui model

        _ ->
            Model.closeDrawer Model.hpChangeLens model
    , Cmd.none
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


freshRollToggle : Model -> ( Model, Cmd Msg )
freshRollToggle model =
    ( withHpChange (\u -> { u | freshRollPerTarget = not u.freshRollPerTarget }) model
    , Cmd.none
    )


{-| Footer action-button click: commit the modal's amount text
as `kind`. Sets `ui.kind = kind` first (so the dice-source
label + log entry reflect the chosen kind), then routes based
on what the input looks like:

  - integer → apply immediately with that value
  - dice formula → roll, land in `rollLanded`, apply the total
  - parse failure → set `parseError`

The editor stays open after every path so the GM can keep
applying; the trigger toggle and Escape close it.

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
                    ( applyHpChange withKind n modelWithKind |> markApplied
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
                        ( applyHpChange withKind 0 modelWithKind |> markApplied
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
                                                    (HpChangeFreshRollLanded kind withKind.ignoreTemp name)
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
`/api/dice/history` pipe the dice modal uses. If the modal got
closed mid-flight (defensive), still log/persist so we don't drop
rolls on the floor.
-}
rollLanded : Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model

        committed =
            case logged.surface of
                Just (SurfaceHpChange ui) ->
                    applyHpChange ui roll.total logged |> markApplied

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
freshRollLanded : HpKind -> Bool -> String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
freshRollLanded kind ignoreTemp target roll model =
    let
        ( logged, broadcastCmd ) =
            Effects.pushDiceRoll roll model
    in
    ( applyAmountTo kind ignoreTemp [ target ] roll.total logged |> markApplied
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
applyHpChange : HpChangeUi -> Int -> Model -> Model
applyHpChange ui amount model =
    applyAmountTo ui.kind
        ui.ignoreTemp
        (hpChangeTargets ui model.encounter)
        amount
        model


{-| The commit core shared by every apply path: resolve the kind

  - ignore-temp flag into an `HpChange.Change`, write it through
    `Encounter.mapCreature` for each target, and push log entries
    capturing the before/after snapshots. Does not touch the
    surface — the shared-roll path closes it here-abouts, the
    fresh-per-creature path already closed it at dispatch.

-}
applyAmountTo : HpKind -> Bool -> List String -> Int -> Model -> Model
applyAmountTo kind ignoreTemp targets amount model =
    let
        change =
            case kind of
                DamageKind ->
                    HpChange.Damage
                        { amount = amount
                        , ignoreTemp = ignoreTemp
                        }

                HealKind ->
                    HpChange.Heal amount

                TempHpKind ->
                    HpChange.TempHp amount

                MaxHpKind ->
                    HpChange.MaxHpDelta amount

        applyOne name acc =
            let
                before =
                    findCreature name acc.encounter

                newEnc =
                    Encounter.mapCreature name (HpChange.apply change) acc.encounter

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
    { model
        | encounter = result.encounter
        , hpChangeLog =
            -- One entry per application, however many creatures it
            -- touched; nothing is logged when no target resolved.
            if List.isEmpty result.snapshots then
                model.hpChangeLog

            else
                { kind = kind
                , amount = amount
                , targets = List.reverse result.snapshots
                }
                    :: List.take (HpChangeUi.maxHpLogEntries - 1) model.hpChangeLog
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
