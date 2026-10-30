module Update.QuickAdd exposing (open, pick, pickPlaceholder, searchChanged, sortToggle)

{-| Update branches for the Quick Add panel — a one-click picker
that lists every compendium creature and adds the chosen one to
the encounter as a single instance.

The pick path materialises the creature at initiative 0 — the GM
sets the value manually on the card, which avoids spending a
dice-roll telemetry entry on every add and keeps the queue's
ordering predictable when several creatures are added
back-to-back.

-}

import Compendium
import Effects
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.QuickAdd as QuickAddUi exposing (QuickAddUi)


{-| The queue's "+" row sits far from the panel's heading, so an
open that lands off screen reads as nothing having happened.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    let
        next =
            Model.openDrawer Model.quickAddLens QuickAddUi.fresh model
    in
    ( next
    , Effects.scrollDrawerTo Model.quickAddLens next
    )


sortToggle : Model -> ( Model, Cmd Msg )
sortToggle model =
    ( withQuickAddUi QuickAddUi.toggleSort model, Cmd.none )


searchChanged : String -> Model -> ( Model, Cmd Msg )
searchChanged text model =
    ( withQuickAddUi (QuickAddUi.setSearchText text) model, Cmd.none )


withQuickAddUi : (QuickAddUi -> QuickAddUi) -> Model -> Model
withQuickAddUi =
    Model.mapSurface Model.quickAddLens


{-| One-click placeholder: append a stub combatant via
`Encounter.Roster.appendPlaceholder`. No initiative roll, no
compendium lookup — placeholder rules apply directly. Mirrors
the queue-bottom "+" button on the Workspace so the user has two
equivalent surfaces for the same gesture.
-}
pickPlaceholder : Model -> ( Model, Cmd Msg )
pickPlaceholder model =
    ( Model.reaimStale { model | encounter = Encounter.Roster.appendPlaceholder model.encounter }
    , Cmd.none
    )


{-| Add one instance of the chosen creature to the encounter.
The creature lands at initiative 0, and the GM types the value
on the card afterwards. It fires no dice Cmd, writes no
dice-history entry and raises no toast. The new card appearing is
the feedback.

A pick leaves the panel up. It is one of the editors the drawer
boots with, and a GM adding a party's worth of monsters should
not have to reopen it.

-}
pick : String -> Model -> ( Model, Cmd Msg )
pick creatureId model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            Compendium.find creatureId db
                |> Maybe.map (\source -> appendAtZero source model)
                |> Maybe.withDefault ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


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
    ( Model.reaimStale
        { model
            | encounter =
                Encounter.Roster.appendCreatures [ newCreature ] model.encounter
        }
    , Cmd.none
    )
