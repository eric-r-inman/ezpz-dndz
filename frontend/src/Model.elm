module Model exposing
    ( Surface(..), Model
    , DragState, DrawerPanel, PanelPin, PendingControl(..), PopupColor(..), RollPopup, SurfaceLens, ackHpLog, aimEditorsAtTarget, applyDrawerLayout, closeDrawer, collapseAt, compendiumEditLens, conditionLens, crCalculatorLens, defaultDrawer, defaultTarget, diceLens, drawerDropIndex, drawerGet, drawerIndexOf, drawerLayout, drawerPanelAt, drawerShows, duplicateLens, foldAllDrawer, foldDrawer, groupEditLens, hpChangeLens, initiativeLens, loadCompendiumLens, loreEditLens, mapDrawer, mapSurface, mapSurfaceAt, memoLens, moveDrawerPanel, newestShowing, noteLens, openDrawer, parkCreatureEditor, quickAddLens, randomEncounterLens, reaimStale, replaceLens, roundSetLens, saveChainLens, saveCompendiumLens, saveLoadLens, statBlockLens, statusLens, surfaceKey, timerLens, toggleCollapsedAt, togglePinnedAt, treasureLens, treasureTableLens, unfoldDrawer, xpLens
    )

{-| The single source of truth for the running app.

`encounter` holds all D&D-specific state (queue, active
creature, round). Everything else is presentation, auth, or
modal-state plumbing. The discipline mirrors the larger
layering rule: domain state goes through `Encounter`,
everything else stays here.

The `surface` field is a `Maybe Surface` ADT — the constructor
identifies which modal is open and carries its UI state.
`Nothing` means no modal is open. This shape replaces the
older "one `Maybe XxxUi` field per modal" scheme and bakes
the "only one modal open at a time" invariant into the type
system rather than leaving it as a convention.

The exceptions — `dice` and `compendium` — sit outside the
ADT because their substate has to survive a close (dice
history, compendium cache + filter selection). The dice
substate carries its own `open : Bool`; the compendium browser
renders as the standalone /compendium tab, so it has no open
flag at all. The `*Draft` fields are the same exception
in another form: they hold the settings of editors that are
CLOSED, which by definition cannot live inside the ADT that
models what is open.

`savedSnapshot` is the last-known persisted state of the
encounter — the result of the user's most recent Save (or
Load) action. It backs the Encounter Saves panel's dirty mark,
which lights when the live roster differs from it. `savedAs`
parallels it, recording the name the encounter was last saved
under so re-saving doesn't make the user retype the filename.

@docs Surface, Model

-}

import Auth exposing (AuthState)
import Browser.Navigation as Nav
import Dict exposing (Dict)
import DrawerLayout
import Encounter exposing (Encounter)
import Encounter.Difficulty as Difficulty
import Encounter.RandomEncounter.Lore as Lore
import Encounter.SaveChain exposing (SaveChain)
import Encounter.Treasure
import Encounter.Wire as EncounterWire
import Encounter.Xp exposing (XpScope)
import Json.Decode as Decode
import Msg exposing (MeStatus)
import Preferences exposing (Preferences)
import Route exposing (Route)
import Set exposing (Set)
import Ui.Account exposing (AccountUi)
import Ui.Compendium exposing (CompendiumEditUi, CompendiumPasteUi, CompendiumUi)
import Ui.Condition as UiCondition exposing (ConditionUi)
import Ui.CrCalculator exposing (CrCalculatorUi)
import Ui.Dice exposing (DiceUi)
import Ui.Duplicate exposing (DuplicateUi)
import Ui.GroupEdit exposing (GroupEditUi)
import Ui.HpChange exposing (HpChangeEntry, HpChangeUi, HpEdit)
import Ui.Initiative exposing (InitiativeUi)
import Ui.LoadCompendium exposing (LoadCompendiumUi)
import Ui.Login exposing (LoginUi)
import Ui.LoreEdit exposing (LoreEditUi)
import Ui.Memo exposing (MemoEditUi)
import Ui.ModalChrome exposing (ModalChrome)
import Ui.Note exposing (NoteEditUi)
import Ui.PlaceholderRename exposing (PlaceholderRenameState)
import Ui.QueuePanels exposing (QueuePanels)
import Ui.QuickAdd exposing (QuickAddUi)
import Ui.RandomEncounter exposing (RandomEncounterUi)
import Ui.Replace exposing (ReplaceUi)
import Ui.RoundSet exposing (RoundSetUi)
import Ui.SaveChain exposing (SaveChainUi)
import Ui.SaveCompendium exposing (SaveCompendiumUi)
import Ui.SaveLoad exposing (SaveLoadUi)
import Ui.Status exposing (StatusUi)
import Ui.Timer as UiTimer exposing (TimerSetupUi)
import Ui.Toast exposing (Toast)
import Ui.Treasure exposing (TreasureUi)
import Ui.TreasureTable exposing (TreasureTableUi)
import Url exposing (Url)


{-| The creature a card put in the drawer's stat-block panel
(`SurfaceStatBlock`). Carries both the compendium `id` (for the
canonical UUID lookup) and the encounter creature's display
`name` (so we can fall back to a name match when an old saved
encounter's `creatureId` no longer matches anything in the
current bundled compendium — otherwise the panel would silently
revert to the placeholder mock).
-}
type alias PanelPin =
    { id : String
    , name : String
    }


{-| Which destructive action the confirmation modal
(`SurfaceConfirm`) is staging, so a mis-click on Reset or Clear
can't drop combat state. Cleared by the user picking Confirm or
Cancel.
-}
type PendingControl
    = PendingReset
    | PendingClear


{-| One constructor per surface, each carrying its UI state.

A surface lives in one of two homes. Modal and card-inline
variants occupy `model.surface`, where "only one open at a
time" is type-enforced: opening surface X assigns
`Just (SurfaceX uiX)`, which by construction wipes out whatever
was open before. Drawer variants live in the `model.drawer`
stack instead, where coexisting is the point.

-}
type Surface
    = SurfaceHpChange HpChangeUi
    | SurfaceInitiative InitiativeUi
    | SurfaceNoteEdit NoteEditUi
    | SurfaceCondition ConditionUi
    | SurfaceMemoEdit MemoEditUi
    | SurfaceTimerSetup TimerSetupUi
    | SurfaceCompendiumEdit CompendiumEditUi
    | SurfaceCompendiumPaste CompendiumPasteUi
    | SurfaceSaveCompendium SaveCompendiumUi
    | SurfaceLoadCompendium LoadCompendiumUi
    | SurfaceQuickAdd QuickAddUi
    | SurfaceDuplicate DuplicateUi
    | SurfaceReplace ReplaceUi
    | SurfaceStatus StatusUi
    | SurfaceGroupEdit GroupEditUi
    | SurfaceLoreEdit LoreEditUi
    | SurfaceCrCalculator CrCalculatorUi
    | SurfaceRandomEncounter RandomEncounterUi
    | SurfaceTreasure TreasureUi
    | SurfaceTreasureTable TreasureTableUi
    | SurfaceSaveLoad SaveLoadUi
      -- Save Chain editor: reusable "creature makes a save;
      -- something happens" recipe.  Loads / edits / saves named
      -- presets from `model.saveChainPresets` and applies
      -- fail/success outcomes to the target (or the selection).
    | SurfaceSaveChain SaveChainUi
      -- The dice roller.  A marker: the roller's substate has to
      -- outlive a close (history, unread flag), so it stays on
      -- `model.dice` and this variant only records openness and
      -- stack position.
    | SurfaceDice
      -- The XP-scope picker.  Also a marker — the scope
      -- outlives a close, so it lives on `model.xpScope`.
    | SurfaceXp
      -- The stat block a card put there.
    | SurfaceStatBlock PanelPin
      -- The Reset / Clear confirmation.  A modal, not a drawer
      -- panel.
    | SurfaceConfirm PendingControl
      -- Round-setter: correct the round counter directly.
    | SurfaceRoundSet RoundSetUi


{-| Something being dragged to a new position in a list: where it
started, and the slot it would land in — which, in the drawer,
the pinned boundary can pull off the slot the pointer is actually
over. Shared by the editor column and the creature queue, the two
places the GM reorders by hand. Lives on the model rather than in
either list, because a drag is about order, not about what any
one item holds.
-}
type alias DragState =
    { from : Int
    , over : Maybe Int
    }


{-| One panel in the drawer stack. `collapsed` rides the panel
rather than a separate keyed set, so folding state can't outlive
the panel it describes.
-}
type alias DrawerPanel =
    { surface : Surface
    , collapsed : Bool

    -- Pinned panels hold the top of the column as a block, in
    -- their own order.  Nothing else distinguishes them: the
    -- stack stays one list, and every move is clamped to the
    -- side of the boundary the panel started on.
    , pinned : Bool
    }


{-| Close the creature editor if it is open. The editor mirrors
its form into `compendiumEditDraft` on every edit, so closing it
here parks the work rather than losing it — selecting something
else mid-edit is a pause, not a cancel.
-}
parkCreatureEditor : Model -> Model
parkCreatureEditor model =
    case Maybe.andThen compendiumEditLens.extract model.surface of
        Just _ ->
            { model | surface = Nothing }

        Nothing ->
            model


{-| The drawer's boot contents, folded to their heading rows.

The per-creature editors take no target here — the encounter
arrives after `init` — so they come up unaimed and
`Update.PanelDrawer.toggleCollapse` aims them at whatever is in
the queue the first time one is expanded.

-}
defaultDrawer : List DrawerPanel
defaultDrawer =
    List.map (\s -> { surface = s, collapsed = True, pinned = False })
        [ SurfaceDice
        , SurfaceHpChange (Ui.HpChange.fresh "")
        , SurfaceStatus (Ui.Status.fresh "")
        , SurfaceCondition (UiCondition.fresh "")
        , SurfaceSaveChain (Ui.SaveChain.fresh "")
        , SurfaceInitiative (Ui.Initiative.fresh "")
        , SurfaceDuplicate (Ui.Duplicate.fresh "")
        , SurfaceReplace (Ui.Replace.fresh "")
        , SurfaceCrCalculator Ui.CrCalculator.fresh
        , SurfaceXp
        , SurfaceSaveLoad Ui.SaveLoad.fresh
        , SurfaceQuickAdd Ui.QuickAdd.fresh

        -- Panels a fight never leans on sit last.
        , SurfaceTreasure Ui.Treasure.fresh
        , SurfaceRandomEncounter Ui.RandomEncounter.fresh
        ]


{-| Move the panel at `from` so it sits at `to`, or as near it
as the pinned boundary allows — `drawerDropIndex` has the rule.
Out-of-range indices leave the stack unchanged.
-}
moveDrawerPanel : Int -> Int -> Model -> Model
moveDrawerPanel from to model =
    case
        if from < 0 then
            -- See `Encounter.Roster.moveCreature`: a negative
            -- source would duplicate the panel rather than move
            -- it.
            Nothing

        else
            model.drawer |> List.drop from |> List.head
    of
        Just moved ->
            let
                rest =
                    List.take from model.drawer
                        ++ List.drop (from + 1) model.drawer

                target =
                    drawerDropIndex from to model.drawer
            in
            { model
                | drawer =
                    List.take target rest ++ moved :: List.drop target rest
            }

        Nothing ->
            model


{-| A stable identity for one drawer panel. Each drawer-eligible
surface appears in the stack at most once (`openDrawer` re-aims
an existing panel rather than adding a twin), so the variant
alone is identity enough.

These strings are persisted as the saved column layout, so
renaming one silently discards every GM's arrangement for that
panel. Change them only deliberately.

-}
surfaceKey : Surface -> String
surfaceKey surface =
    case surface of
        SurfaceHpChange _ ->
            "hp-change"

        SurfaceStatus _ ->
            "status"

        SurfaceCondition _ ->
            "condition"

        SurfaceSaveChain _ ->
            "save-chain"

        SurfaceInitiative _ ->
            "initiative"

        SurfaceReplace _ ->
            "replace"

        SurfaceDuplicate _ ->
            "duplicate"

        SurfaceCrCalculator _ ->
            "cr-calculator"

        SurfaceTreasure _ ->
            "treasure"

        SurfaceQuickAdd _ ->
            "quick-add"

        SurfaceSaveLoad _ ->
            "save-load"

        SurfaceRandomEncounter _ ->
            "random-encounter"

        SurfaceDice ->
            "dice"

        SurfaceXp ->
            "xp"

        SurfaceStatBlock _ ->
            "stat-block"

        -- Modal and card-inline surfaces never enter the stack.
        -- Enumerated rather than caught by a wildcard: these keys
        -- are persisted, so a new drawer-eligible surface has to
        -- fail the compile here rather than quietly inherit
        -- another panel's saved slot.
        SurfaceNoteEdit _ ->
            "note-edit"

        SurfaceMemoEdit _ ->
            "memo-edit"

        SurfaceTimerSetup _ ->
            "timer-setup"

        SurfaceCompendiumEdit _ ->
            "compendium-edit"

        SurfaceCompendiumPaste _ ->
            "compendium-paste"

        SurfaceSaveCompendium _ ->
            "save-compendium"

        SurfaceLoadCompendium _ ->
            "load-compendium"

        SurfaceGroupEdit _ ->
            "group-edit"

        SurfaceLoreEdit _ ->
            "lore-edit"

        SurfaceTreasureTable _ ->
            "treasure-table"

        SurfaceConfirm _ ->
            "confirm"

        SurfaceRoundSet _ ->
            "round-set"


{-| Mark the HP log as shown. The newest row flashes only past
this, so every path that puts the panel's body back on screen has
to call it — otherwise reopening a folded panel replays the cue
for a change that landed minutes ago.
-}
ackHpLog : Model -> Model
ackHpLog model =
    { model
        | flashedHpLogSeq =
            List.head model.hpChangeLog
                |> Maybe.map .seq
                |> Maybe.withDefault 0
    }


{-| The column as the GM arranged it, in the shape that survives
a reload.
-}
drawerLayout : Model -> List DrawerLayout.Entry
drawerLayout model =
    List.map
        (\panel -> { key = surfaceKey panel.surface, pinned = panel.pinned })
        model.drawer


{-| Re-order and re-pin the boot drawer to match a saved layout.

The saved order leads; anything it doesn't mention follows in the
order the build ships, which is what lets a release add an editor
without disturbing arrangements already saved. A key the build no
longer knows is simply absent from the result, since the panels
come from the current drawer rather than from the layout.

-}
applyDrawerLayout : List DrawerLayout.Entry -> Model -> Model
applyDrawerLayout layout model =
    let
        entryFor panel =
            layout
                |> List.filter (\e -> e.key == surfaceKey panel.surface)
                |> List.head

        ( known, rest ) =
            List.partition (\panel -> entryFor panel /= Nothing) model.drawer

        pinnedFor panel =
            entryFor panel
                |> Maybe.map .pinned
                |> Maybe.withDefault False

        rank panel =
            layout
                |> List.indexedMap (\i e -> ( i, e ))
                |> List.filter (\( _, e ) -> e.key == surfaceKey panel.surface)
                |> List.head
                |> Maybe.map Tuple.first
                |> Maybe.withDefault 0

        ordered =
            List.map
                (\panel -> { panel | pinned = pinnedFor panel })
                (List.sortBy rank known)
                ++ rest

        -- The final partition rebuilds the contiguous pinned
        -- prefix `drawerDropIndex` relies on, whatever the stored
        -- layout looked like and whatever the build's own panels
        -- boot as. `List.partition` is stable, so the order
        -- within each group survives.
        ( held, loose ) =
            List.partition .pinned ordered
    in
    { model | drawer = held ++ loose }


{-| Re-aim every per-creature editor whose creature has left the
queue, at whatever the queue makes the default target — the
active creature, or its head before combat starts. An editor
still aimed at someone present is left alone.

Every write that can drop or rename a creature runs this —
removals and replacements, and the wholesale swaps too: a load, a
sign-in, an encounter arriving from another tab. That is the
property to preserve when adding one, because an editor already
unfolded is never unfolded again: without this it keeps a
departed creature's name on its target strip, and Apply silently
resolves nothing. Writes that only change a creature in place
need no call.

-}
reaimStale : Model -> Model
reaimStale model =
    reaimWhere (\aimed -> not (Encounter.hasCreature aimed model.encounter))
        (dropDeadTarget model)


{-| Point every per-creature editor at the current default target,
whatever it was aimed at before. Picking a target is what calls
this: the pick is the GM saying "this one now", so an editor
already aimed elsewhere is re-aimed too.
-}
aimEditorsAtTarget : Model -> Model
aimEditorsAtTarget =
    reaimWhere (always True)


{-| The creature an editor should aim at absent a better idea:
the picked target while it is still in the queue, else the
active creature, else the queue's head.
-}
defaultTarget : Model -> String
defaultTarget model =
    case model.targetName of
        Just name ->
            if Encounter.hasCreature name model.encounter then
                name

            else
                Encounter.defaultTarget model.encounter

        Nothing ->
            Encounter.defaultTarget model.encounter


{-| A picked target that has left the queue is no target.
-}
dropDeadTarget : Model -> Model
dropDeadTarget model =
    case model.targetName of
        Just name ->
            if Encounter.hasCreature name model.encounter then
                model

            else
                { model | targetName = Nothing }

        Nothing ->
            model


reaimWhere : (String -> Bool) -> Model -> Model
reaimWhere stale model =
    let
        target =
            defaultTarget model

        reaim wrap fresh aimed surface =
            if stale aimed then
                wrap (fresh target)

            else
                surface

        reaimOne surface =
            case surface of
                SurfaceHpChange ui ->
                    reaim SurfaceHpChange Ui.HpChange.fresh ui.target surface

                SurfaceStatus ui ->
                    reaim SurfaceStatus Ui.Status.fresh ui.target surface

                SurfaceCondition ui ->
                    reaim SurfaceCondition UiCondition.fresh ui.target surface

                SurfaceSaveChain ui ->
                    reaim SurfaceSaveChain Ui.SaveChain.fresh ui.target surface

                SurfaceInitiative ui ->
                    reaim SurfaceInitiative Ui.Initiative.fresh ui.target surface

                SurfaceDuplicate ui ->
                    reaim SurfaceDuplicate Ui.Duplicate.fresh ui.target surface

                SurfaceReplace ui ->
                    reaim SurfaceReplace Ui.Replace.fresh ui.target surface

                -- Enumerated for the same reason `surfaceKey` is:
                -- a new per-creature editor has to fail the
                -- compile here rather than quietly never re-aim.
                -- These surfaces aim at no creature.
                SurfaceDice ->
                    surface

                SurfaceXp ->
                    surface

                SurfaceCrCalculator _ ->
                    surface

                SurfaceRandomEncounter _ ->
                    surface

                SurfaceTreasure _ ->
                    surface

                SurfaceTreasureTable _ ->
                    surface

                SurfaceSaveLoad _ ->
                    surface

                SurfaceQuickAdd _ ->
                    surface

                SurfaceStatBlock _ ->
                    surface

                SurfaceNoteEdit _ ->
                    surface

                SurfaceMemoEdit _ ->
                    surface

                SurfaceTimerSetup _ ->
                    surface

                SurfaceCompendiumEdit _ ->
                    surface

                SurfaceCompendiumPaste _ ->
                    surface

                SurfaceSaveCompendium _ ->
                    surface

                SurfaceLoadCompendium _ ->
                    surface

                SurfaceGroupEdit _ ->
                    surface

                SurfaceLoreEdit _ ->
                    surface

                SurfaceConfirm _ ->
                    surface

                SurfaceRoundSet _ ->
                    surface
    in
    { model
        | drawer =
            List.map
                (\panel -> { panel | surface = reaimOne panel.surface })
                model.drawer
    }


{-| Where a panel dragged from `from` actually lands when the GM
lets go over `to`. Dropping a pinned panel below the block clamps
it to the bottom of the block rather than refusing the drop,
which is what "pinned to the top" has to mean once the drag is
already under way; an unpinned panel clamps the same way at the
other end. The drop cue reads this too, so the slot the GM sees
lit is the slot the panel takes.
-}
drawerDropIndex : Int -> Int -> List DrawerPanel -> Int
drawerDropIndex from to panels =
    let
        rest =
            List.take from panels ++ List.drop (from + 1) panels

        boundary =
            List.length (List.filter .pinned rest)
    in
    case panels |> List.drop from |> List.head of
        Just moved ->
            if moved.pinned then
                Basics.min to boundary

            else
                Basics.max to boundary

        Nothing ->
            to


{-| Pin a panel to the top of the column, or release it. Either
way it lands at the boundary — the bottom of the pinned block
when pinning, the top of the rest when releasing — so the panel
the GM just acted on is the one nearest the line they moved it
across.
-}
togglePinnedAt : Int -> Model -> Model
togglePinnedAt index model =
    case model.drawer |> List.drop index |> List.head of
        Just panel ->
            moveDrawerPanel index
                (if panel.pinned then
                    0

                 else
                    List.length model.drawer
                )
                { model
                    | drawer =
                        List.indexedMap
                            (\i p ->
                                if i == index then
                                    { p | pinned = not p.pinned }

                                else
                                    p
                            )
                            model.drawer
                }

        Nothing ->
            model


{-| Where the panel matching `lens` sits in the stack, if it is
open. Position is the drawer's own identifier for a panel, so
this is what addresses one for scrolling.
-}
drawerIndexOf : SurfaceLens a -> Model -> Maybe Int
drawerIndexOf lens model =
    model.drawer
        |> List.indexedMap
            (\i panel -> Maybe.map (\_ -> i) (lens.extract panel.surface))
        |> List.filterMap identity
        |> List.head


{-| The open drawer panel matching `lens`, if any.
-}
drawerGet : SurfaceLens a -> Model -> Maybe a
drawerGet lens model =
    model.drawer
        |> List.filterMap (.surface >> lens.extract)
        |> List.head


drawerHas : SurfaceLens a -> Model -> Bool
drawerHas lens model =
    drawerGet lens model /= Nothing


{-| Whether a panel's body is on screen. `drawerHas` answers a
weaker question: whether the panel exists at all.
-}
drawerShows : SurfaceLens a -> Model -> Bool
drawerShows lens model =
    List.any
        (\panel -> lens.extract panel.surface /= Nothing && not panel.collapsed)
        model.drawer


{-| Apply `fn` to the matching drawer panel's substate, leaving
its stack position alone. No-op when that panel isn't open.
-}
mapDrawer : SurfaceLens a -> (a -> a) -> Model -> Model
mapDrawer lens fn model =
    { model
        | drawer =
            List.map
                (\panel ->
                    lens.extract panel.surface
                        |> Maybe.map
                            (\ui -> { panel | surface = lens.wrap (fn ui) })
                        |> Maybe.withDefault panel
                )
                model.drawer
    }


{-| Open a drawer panel with the given substate. A panel already
open keeps its stack position and takes the new substate (the
re-aim case); otherwise the panel joins the bottom of the stack.
Either way the panel comes unfolded, so an open the GM asked for
actually lands on screen.
-}
openDrawer : SurfaceLens a -> a -> Model -> Model
openDrawer lens ui model =
    if drawerHas lens model then
        mapDrawer lens (\_ -> ui) (setFolded False lens model)

    else
        { model
            | drawer =
                model.drawer
                    ++ [ { surface = lens.wrap ui
                         , collapsed = False
                         , pinned = False
                         }
                       ]
        }


{-| Show a panel that is already in the stack, keeping whatever it
holds. A card control aimed at the creature the panel already
targets asks for exactly this — see it, don't reset it.
-}
unfoldDrawer : SurfaceLens a -> Model -> Model
unfoldDrawer =
    setFolded False


{-| Fold a panel already in the stack, or unfold it. The editors
the drawer boots with have no trigger to reopen them, so both
"show me this" and "done with this" have to move the fold rather
than the stack.
-}
setFolded : Bool -> SurfaceLens a -> Model -> Model
setFolded folded lens model =
    { model
        | drawer =
            List.map
                (\panel ->
                    if lens.extract panel.surface /= Nothing then
                        { panel | collapsed = folded }

                    else
                        panel
                )
                model.drawer
    }


foldDrawer : SurfaceLens a -> Model -> Model
foldDrawer =
    setFolded True


closeDrawer : SurfaceLens a -> Model -> Model
closeDrawer lens model =
    { model
        | drawer =
            List.filter
                (\panel -> lens.extract panel.surface == Nothing)
                model.drawer
    }


{-| The panel a dismissal acts on: the last one still showing
its body, since the stack reads newest-last. Esc consults it to
pick its behaviour and `foldNewest` folds what it names, so the
two cannot drift apart.
-}
newestShowing : Model -> Maybe ( Int, DrawerPanel )
newestShowing model =
    model.drawer
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, panel ) -> not panel.collapsed)
        |> List.reverse
        |> List.head


{-| Fold every panel in the stack at once.
-}
foldAllDrawer : Model -> Model
foldAllDrawer model =
    { model | drawer = List.map (\panel -> { panel | collapsed = True }) model.drawer }


{-| Fold the panel at `index`, where `toggleCollapsedAt` would
flip it. Saying which one is meant keeps the caller readable.
-}
collapseAt : Int -> Model -> Model
collapseAt index model =
    { model
        | drawer =
            List.indexedMap
                (\i panel ->
                    if i == index then
                        { panel | collapsed = True }

                    else
                        panel
                )
                model.drawer
    }


{-| Fold the panel at `index` away, or unfold it. The index is
the panel's position in the rendered stack, which is what the
click that produced it was aimed at.
-}
toggleCollapsedAt : Int -> Model -> Model
toggleCollapsedAt index model =
    { model
        | drawer =
            List.indexedMap
                (\i panel ->
                    if i == index then
                        { panel | collapsed = not panel.collapsed }

                    else
                        panel
                )
                model.drawer
    }


{-| The panel at `index` in the stack, if there is one.
-}
drawerPanelAt : Int -> Model -> Maybe DrawerPanel
drawerPanelAt index model =
    model.drawer |> List.drop index |> List.head


{-| Replace the surface of the panel at `index`, leaving its fold
state and its neighbours alone.
-}
mapSurfaceAt : Int -> (Surface -> Surface) -> Model -> Model
mapSurfaceAt index fn model =
    { model
        | drawer =
            List.indexedMap
                (\i panel ->
                    if i == index then
                        { panel | surface = fn panel.surface }

                    else
                        panel
                )
                model.drawer
    }


{-| Pair of `extract` / `wrap` functions identifying one variant
of the `Surface` ADT. Lets `mapSurface` be a single generic helper
shared by every Update module instead of each rolling its own
`withFooUi`. See `mapSurface` and the per-variant `*Lens` values.
-}
type alias SurfaceLens a =
    { extract : Surface -> Maybe a
    , wrap : a -> Surface
    }


{-| Apply `fn` to the matching surface's substate wherever it
lives — the `model.surface` slot or the drawer stack. No-op when
neither holds it.

Replaces the per-Update-module `with*Ui` helpers.

-}
mapSurface : SurfaceLens a -> (a -> a) -> Model -> Model
mapSurface lens fn model =
    case Maybe.andThen lens.extract model.surface of
        Just ui ->
            { model | surface = Just (lens.wrap (fn ui)) }

        Nothing ->
            mapDrawer lens fn model


compendiumEditLens : SurfaceLens CompendiumEditUi
compendiumEditLens =
    { extract =
        \m ->
            case m of
                SurfaceCompendiumEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCompendiumEdit
    }


roundSetLens : SurfaceLens RoundSetUi
roundSetLens =
    { extract =
        \m ->
            case m of
                SurfaceRoundSet ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceRoundSet
    }


statusLens : SurfaceLens StatusUi
statusLens =
    { extract =
        \m ->
            case m of
                SurfaceStatus ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceStatus
    }


saveLoadLens : SurfaceLens SaveLoadUi
saveLoadLens =
    { extract =
        \s ->
            case s of
                SurfaceSaveLoad ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSaveLoad
    }


saveChainLens : SurfaceLens SaveChainUi
saveChainLens =
    { extract =
        \m ->
            case m of
                SurfaceSaveChain ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSaveChain
    }


replaceLens : SurfaceLens ReplaceUi
replaceLens =
    { extract =
        \m ->
            case m of
                SurfaceReplace ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceReplace
    }


diceLens : SurfaceLens ()
diceLens =
    { extract =
        \m ->
            case m of
                SurfaceDice ->
                    Just ()

                _ ->
                    Nothing
    , wrap = \() -> SurfaceDice
    }


xpLens : SurfaceLens ()
xpLens =
    { extract =
        \m ->
            case m of
                SurfaceXp ->
                    Just ()

                _ ->
                    Nothing
    , wrap = \() -> SurfaceXp
    }


statBlockLens : SurfaceLens PanelPin
statBlockLens =
    { extract =
        \m ->
            case m of
                SurfaceStatBlock pin ->
                    Just pin

                _ ->
                    Nothing
    , wrap = SurfaceStatBlock
    }


duplicateLens : SurfaceLens DuplicateUi
duplicateLens =
    { extract =
        \m ->
            case m of
                SurfaceDuplicate ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceDuplicate
    }


groupEditLens : SurfaceLens GroupEditUi
groupEditLens =
    { extract =
        \m ->
            case m of
                SurfaceGroupEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceGroupEdit
    }


loreEditLens : SurfaceLens LoreEditUi
loreEditLens =
    { extract =
        \m ->
            case m of
                SurfaceLoreEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceLoreEdit
    }


crCalculatorLens : SurfaceLens CrCalculatorUi
crCalculatorLens =
    { extract =
        \m ->
            case m of
                SurfaceCrCalculator ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCrCalculator
    }


randomEncounterLens : SurfaceLens RandomEncounterUi
randomEncounterLens =
    { extract =
        \m ->
            case m of
                SurfaceRandomEncounter ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceRandomEncounter
    }


treasureLens : SurfaceLens TreasureUi
treasureLens =
    { extract =
        \m ->
            case m of
                SurfaceTreasure ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTreasure
    }


treasureTableLens : SurfaceLens TreasureTableUi
treasureTableLens =
    { extract =
        \m ->
            case m of
                SurfaceTreasureTable ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTreasureTable
    }


conditionLens : SurfaceLens ConditionUi
conditionLens =
    { extract =
        \m ->
            case m of
                SurfaceCondition ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceCondition
    }


hpChangeLens : SurfaceLens HpChangeUi
hpChangeLens =
    { extract =
        \m ->
            case m of
                SurfaceHpChange ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceHpChange
    }


initiativeLens : SurfaceLens InitiativeUi
initiativeLens =
    { extract =
        \m ->
            case m of
                SurfaceInitiative ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceInitiative
    }


memoLens : SurfaceLens MemoEditUi
memoLens =
    { extract =
        \m ->
            case m of
                SurfaceMemoEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceMemoEdit
    }


noteLens : SurfaceLens NoteEditUi
noteLens =
    { extract =
        \m ->
            case m of
                SurfaceNoteEdit ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceNoteEdit
    }


quickAddLens : SurfaceLens QuickAddUi
quickAddLens =
    { extract =
        \m ->
            case m of
                SurfaceQuickAdd ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceQuickAdd
    }


timerLens : SurfaceLens TimerSetupUi
timerLens =
    { extract =
        \m ->
            case m of
                SurfaceTimerSetup ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceTimerSetup
    }


saveCompendiumLens : SurfaceLens SaveCompendiumUi
saveCompendiumLens =
    { extract =
        \m ->
            case m of
                SurfaceSaveCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceSaveCompendium
    }


loadCompendiumLens : SurfaceLens LoadCompendiumUi
loadCompendiumLens =
    { extract =
        \m ->
            case m of
                SurfaceLoadCompendium ui ->
                    Just ui

                _ ->
                    Nothing
    , wrap = SurfaceLoadCompendium
    }


type alias Model =
    { key : Nav.Key
    , url : Url
    , route : Route
    , me : MeStatus
    , auth : AuthState
    , loginUi : LoginUi
    , encounter : Encounter
    , savedSnapshot : Maybe Encounter
    , savedAs : Maybe String
    , dice : DiceUi

    -- The creature the GM has picked out by clicking its card,
    -- which the per-creature editors aim at ahead of the active
    -- one.  Distinct from the cards' checkboxes, which choose a
    -- set for "apply to selected"; this is one creature, and it
    -- is what "the target" means until the GM clears it.
    , targetName : Maybe String

    -- The condition chips — each a bearer name and condition id —
    -- pulsing right now as the reminder that the GM has to roll a
    -- save nothing auto-fires.  Cleared by `SaveFlashExpired` once
    -- the pulse finishes.
    , flashConditions : List ( String, Int )
    , hpChangeLog : List HpChangeEntry

    -- Hands out `HpChangeEntry.seq`.  A counter rather than a
    -- read of the log's head, because undo and a history clear
    -- both shrink the log, and a derived number would hand out
    -- one the mark below has already passed.
    , nextHpLogSeq : Int

    -- How far the Manage HP panel has shown its log.  The newest
    -- row flashes only past this, so reopening a folded panel
    -- doesn't replay the cue for a change that landed minutes
    -- ago.  Lives here rather than on `HpChangeUi` because it is
    -- bookkeeping about the log, and every path that re-aims the
    -- editor rebuilds that record.
    , flashedHpLogSeq : Int

    -- The dice roller's counterpart: the roll count its panel
    -- has already shown, so a roll landing while the panel is
    -- open flashes and one it reopens on does not.
    , flashedRollSeq : Int

    -- Log rows the GM has unfolded to read in full, by the row
    -- key each log builds.  One set for both logs, since a row
    -- has one identity wherever it renders.
    , expandedLogRows : Set String

    -- Twin of `hpChangeLog` for the Save Chain modal.  The
    -- three apply paths (Fail button, Pass button, 🎲 Roll
    -- saves button) each prepend one entry per target so the
    -- GM can scan back a few rounds of resolutions without
    -- flipping between modals.  Capped at
    -- `Ui.SaveChain.maxSaveChainLogEntries`.
    , saveChainLog : List Ui.SaveChain.SaveChainLogEntry

    -- Whether the Save Chain editor shows its recent-applies log.
    -- It starts folded and opens itself when an apply lands, so
    -- the log takes no room until there is something to read.
    , saveChainLogOpen : Bool
    , hpEdit : Maybe HpEdit
    , compendium : CompendiumUi
    , surface : Maybe Surface

    -- Recent condition applications, newest first — the
    -- condition editor's counterpart to `hpChangeLog`, carrying
    -- the created condition ids so undo can remove exactly the
    -- instances one application added.
    , conditionLog : List UiCondition.ConditionLogEntry

    -- Same pattern for the Duplicate and Replace editors:
    -- newest first, capped in their Update modules.
    , duplicateLog : List Ui.Duplicate.DuplicateLogEntry
    , replaceLog : List Ui.Replace.ReplaceLogEntry
    , modalChrome : ModalChrome
    , placeholderRename : Maybe PlaceholderRenameState
    , xpScope : XpScope
    , settingsOpen : Bool

    -- The editor column's drawer: every open panel, oldest
    -- first, rendered top to bottom.  A stack rather than a
    -- single slot — drawer panels deliberately coexist, so the
    -- one-at-a-time invariant `surface` enforces stops at the
    -- drawer's edge.  Only drawer-eligible variants belong here;
    -- their Update modules are the only writers.
    , drawer : List DrawerPanel

    -- The drawer reorder in progress, if any.
    , drawerDrag : Maybe DragState

    -- The creature card being dragged to a new queue position.
    , queueDrag : Maybe DragState

    -- The creature editor's work in progress, mirrored on every
    -- edit so closing the editor by any route — selecting
    -- something else, opening another editor — loses nothing.
    -- Cleared only by Cancel and by a completed save or delete,
    -- the two ways an editing session actually ends.
    , compendiumEditDraft : Maybe CompendiumEditUi

    -- Read-only drop-downs under the queue's reminder strips.
    -- Independent of `surface`: several can be open at once.
    , queuePanels : QueuePanels
    , toasts : List Toast
    , nextToastId : Int
    , rollPopups : List RollPopup
    , nextRollPopupId : Int
    , preferences : Preferences

    -- Account page (`/me`) form state.  Independent of the auth
    -- ADT — `auth` holds *who's signed in*; `accountUi` holds
    -- *what the GM has typed into the profile / password forms
    -- on the Account page*.
    , accountUi : AccountUi

    -- Player party — used by the CR Calculator modal to compute
    -- the per-tier XP budgets the encounter is measured against.
    -- Lives on Model (rather than only inside the calculator's
    -- modal state) so edits persist across modal opens within a
    -- session.  Backend persistence is a follow-up; the in-memory
    -- shape will round-trip cleanly when added.
    , party : List Difficulty.PartyMember
    , nextPartyMemberId : Int

    -- Anonymous-mode bootstrap: the raw localStorage encounter
    -- snapshot from boot flags.  Held verbatim until the auth probe
    -- resolves — if the user is anonymous we decode and adopt it;
    -- if authenticated we discard it (the server is the source of
    -- truth, the migration prompt lives in a later phase).
    , localEncounterRaw : Maybe Decode.Value

    -- Pre-formatted "today" string from the JS host (e.g.
    -- "May 26, 2026"), used to label the named server save slot
    -- when an anonymous encounter is migrated into a freshly-
    -- authenticated session.  Held until the migration fires;
    -- otherwise inert.
    , migrationDateLabel : String

    -- One-shot stash for the anonymous dice-history snapshot from
    -- localStorage.  Adopted on the anonymous boot branch and
    -- discarded on the authenticated branch (server history wins).
    , localDiceHistoryRaw : Maybe Decode.Value

    -- One-shot stash for the anonymous compendium snapshot.  If
    -- present, the anonymous boot branch decodes it and uses it
    -- in place of the bundled-creatures fetch; if absent we fall
    -- back to `/bundled-creatures.json`.
    , localCompendiumRaw : Maybe Decode.Value

    -- Set on the anonymous boot branch when the local snapshot was
    -- written under an older `bundledVersion` than the running
    -- build.  We adopt the snapshot as initial state AND fire a
    -- `/bundled-creatures.json` fetch; when the fetch lands the
    -- `CompendiumLoaded` handler replaces bundled-id creatures
    -- with the fresh data while preserving user-created ones
    -- (id not in the bundle).  Cleared once the merge runs so
    -- subsequent in-session fetches (post sign-in, etc.) keep
    -- the standard replace-everything behaviour.
    , pendingBundleMerge : Bool

    -- Monotonic counter handing out ids for anonymously-created
    -- creatures.  Persisted to localStorage as part of the
    -- compendium snapshot so reloads don't reuse ids.  Server
    -- creatures use full UUIDs; anonymous use `"local-N"`.
    , nextLocalCreatureId : Int

    -- Anonymous named encounter saves keyed by name.  Authed
    -- sessions use the server's `/api/encounter/saves` endpoints;
    -- anonymous sessions mutate this dict and the update-loop
    -- wrapper persists it to `localStorage.encounterSaves`.
    , localEncounterSaves : Dict String EncounterWire.LocalEncounterSave

    -- User-named presets for the Add-Condition modal, keyed by
    -- the name the GM gave each save.  Mirrors the pattern of
    -- the other localStorage-backed dicts: the modal's Save and
    -- Load buttons mutate this dict; the update-loop wrapper
    -- persists it under `localStorage.conditionPresets`.  Anonymous
    -- and authenticated sessions both use this same client-side
    -- dict for now — there's no server endpoint yet because the
    -- preset shape is small and per-device defaults are reasonable.
    , conditionPresets : Dict String UiCondition.ConditionPreset

    -- Twin of `conditionPresets` for the Timer-setup modal.
    -- Persisted under `localStorage.timerPresets`.
    , timerPresets : Dict String UiTimer.TimerPreset

    -- Save Chain presets — reusable "creature makes a save;
    -- something happens" recipes.  Persisted under
    -- `localStorage.saveChainPresets`.
    , saveChainPresets : Dict String SaveChain

    -- User-authored Lore groupings for the Random Encounter
    -- generator's _Lore-leaning_ toggle.  Bundled groups
    -- live in `Encounter.RandomEncounter.Lore.bundled`;
    -- these are the player's additions, edited in the
    -- Create/Edit Group modal and persisted under
    -- `localStorage.userLoreGroups`.
    , userLoreGroups : List Lore.Group

    -- Singular per-user treasure table.  `Nothing` means the
    -- user has nothing saved yet — the generator falls back to
    -- `Encounter.Treasure.bundledTable` in that case.  Edited
    -- in the Treasure Table modal and persisted to
    -- `/api/treasure-table` (or `localStorage.userTreasureTable`
    -- for anonymous sessions).
    , userTreasureTable : Maybe Encounter.Treasure.TreasureTable

    -- Per-user named profiles of "Tune your rolls" settings.
    -- Empty dict means the user hasn't saved any yet.  Loaded
    -- from `/api/treasure-profiles` on authed boot; saved back
    -- via the standard persistence hook in `Main.update`.
    , userTreasureProfiles : Dict.Dict String Encounter.Treasure.TreasureSettings

    -- Draft text for the "Save current as profile…" input.
    , userTreasureProfileNameDraft : String

    -- JS `Date.now()` captured at boot, used as the timestamp for
    -- all anonymous named-save writes done in this session.  All
    -- saves in one session share this timestamp (cosmetic-only;
    -- the migration uploads to the server which assigns its own).
    , bootMs : Int
    }


{-| Floating "+N" popup spawned at the cursor when an inline
dice-link, attack roll, ability check, or saving throw in a
creature stat block is clicked. Animated up + out via CSS;
expired by a `Process.sleep` Msg matched on `id`.

`x` / `y` are captured at click time from the DOM event's
`clientX` / `clientY`, so the popup anchors to where the user
clicked even if they've moved the mouse since.

-}
type alias RollPopup =
    { id : Int
    , x : Int
    , y : Int
    , total : Int
    , color : PopupColor
    }


{-| A popup's colour. `PopupPlain` is the original single-roll
yellow (inline damage/dice-link clicks). The other three mark one
member of a triple-roll (standard / advantage / disadvantage,
fired together from one attack-roll, ability-check, or
saving-throw click) so the three floating numbers read as a set
rather than three unrelated rolls.
-}
type PopupColor
    = PopupPlain
    | PopupStandard
    | PopupAdvantage
    | PopupDisadvantage
