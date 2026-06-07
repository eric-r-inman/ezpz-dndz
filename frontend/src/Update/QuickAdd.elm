module Update.QuickAdd exposing (close, open, openForReplace, pick, pickPlaceholder, searchChanged, sortToggle)

{-| Update branches for the Quick Add modal — a one-click picker
that lists every compendium creature and adds the chosen one to
the encounter as a single instance.

The pick path materialises the creature at initiative 0 — the GM
sets the value manually on the card after the modal closes, which
avoids spending a dice-roll telemetry entry on every add and keeps
the queue's ordering predictable when several creatures are added
back-to-back.

-}

import Compendium
import Encounter.Roster
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.QuickAdd as QuickAddUi exposing (QuickAddUi)


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (ModalQuickAdd QuickAddUi.fresh) }, Cmd.none )


{-| Open the Quick Add modal in "replace this creature" mode.
The pick path then swaps the named creature in place rather
than appending — see `pick` / `pickPlaceholder` below.
-}
openForReplace : String -> Model -> ( Model, Cmd Msg )
openForReplace oldName model =
    ( { model | modal = Just (ModalQuickAdd (QuickAddUi.freshForReplace oldName)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


sortToggle : Model -> ( Model, Cmd Msg )
sortToggle model =
    ( withQuickAddUi QuickAddUi.toggleSort model, Cmd.none )


searchChanged : String -> Model -> ( Model, Cmd Msg )
searchChanged text model =
    ( withQuickAddUi (QuickAddUi.setSearchText text) model, Cmd.none )


withQuickAddUi : (QuickAddUi -> QuickAddUi) -> Model -> Model
withQuickAddUi =
    Model.mapModal Model.quickAddLens


{-| One-click placeholder: append a stub combatant via
`Encounter.Roster.appendPlaceholder` and close the modal. No
initiative roll, no compendium lookup — placeholder rules apply
directly. Mirrors the queue-bottom "+" button on the Workspace
so the user has two equivalent surfaces for the same gesture.

In replace mode (`ui.replaceTarget == Just oldName`) the
placeholder swaps in for the named creature instead, preserving
the old initiative.

-}
pickPlaceholder : Model -> ( Model, Cmd Msg )
pickPlaceholder model =
    let
        nextEncounter =
            case currentReplaceTarget model of
                Just oldName ->
                    Encounter.Roster.replaceWithPlaceholder oldName model.encounter

                Nothing ->
                    Encounter.Roster.appendPlaceholder model.encounter
    in
    ( { model | modal = Nothing, encounter = nextEncounter }, Cmd.none )


{-| Add one instance of the chosen creature to the encounter.

In replace mode the swap is synchronous: build a fresh instance
via `Compendium.draftToInstance` and call
`Encounter.Roster.replaceCreature`, which preserves the old
initiative value.

In normal mode (append) the creature lands at initiative 0; the
GM types the value on the card afterwards. No batched dice Cmd,
no dice-history entry, no toast — the modal close + new card
appearing is the feedback.

-}
pick : String -> Model -> ( Model, Cmd Msg )
pick creatureId model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    case currentReplaceTarget model of
                        Just oldName ->
                            replaceInPlace oldName source model

                        Nothing ->
                            appendAtZero source model

                Nothing ->
                    ( { model | modal = Nothing }, Cmd.none )

        _ ->
            ( { model | modal = Nothing }, Cmd.none )


{-| Synchronous swap path — used by both `pick` and
`pickPlaceholder` in replace mode (with different newCreature
builders). Closes the modal as a side-effect.
-}
replaceInPlace : String -> Compendium.Creature -> Model -> ( Model, Cmd Msg )
replaceInPlace oldName source model =
    let
        existing =
            List.filter (\n -> n /= oldName)
                (List.map .name model.encounter.creatures)

        provisionalName =
            Encounter.Roster.uniqueInstanceName source.name existing

        newCreature =
            -- `initiativeRoll = 0` because Roster.replaceCreature
            -- overrides it with the old creature's preserved value.
            Compendium.draftToInstance
                { displayName = provisionalName, initiativeRoll = 0 }
                source
    in
    ( { model
        | modal = Nothing
        , encounter =
            Encounter.Roster.replaceCreature oldName newCreature model.encounter
      }
    , Cmd.none
    )


appendAtZero : Compendium.Creature -> Model -> ( Model, Cmd Msg )
appendAtZero source model =
    let
        existing =
            List.map .name model.encounter.creatures

        name =
            Encounter.Roster.uniqueInstanceName source.name existing

        newCreature =
            Compendium.draftToInstance
                { displayName = name, initiativeRoll = 0 }
                source
    in
    ( { model
        | modal = Nothing
        , encounter =
            Encounter.Roster.appendCreatures [ newCreature ] model.encounter
      }
    , Cmd.none
    )


{-| Peek at the QuickAdd UI's `replaceTarget` field — present
only when the modal was opened via `QuickAddOpenForReplace`.
-}
currentReplaceTarget : Model -> Maybe String
currentReplaceTarget model =
    case model.modal of
        Just (ModalQuickAdd ui) ->
            ui.replaceTarget

        _ ->
            Nothing
