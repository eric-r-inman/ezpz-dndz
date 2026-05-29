module Update.QuickAdd exposing (close, open, pick, pickPlaceholder, searchChanged, sortToggle)

{-| Update branches for the Quick Add modal — a one-click picker
that lists every compendium creature and adds the chosen one to
the encounter as a single instance.

The pick path piggybacks on the existing
[`CompendiumInitiativeRolled`](Msg#CompendiumInitiativeRolled)
landing handler: build a single-instance roll spec, fire the
batched dice Cmd, and let the shared landing path do the
draftToInstance + appendCreatures + toast work. No new
infrastructure needed.

-}

import Compendium
import Dice
import Encounter.Roster
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.QuickAdd as QuickAddUi exposing (QuickAddUi)
import Update.Initiative


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (ModalQuickAdd QuickAddUi.fresh) }, Cmd.none )


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
-}
pickPlaceholder : Model -> ( Model, Cmd Msg )
pickPlaceholder model =
    ( { model
        | modal = Nothing
        , encounter = Encounter.Roster.appendPlaceholder model.encounter
      }
    , Cmd.none
    )


{-| Add one instance of the chosen creature to the encounter:
allocate a unique display name, build a single-creature batch
roll spec, fire the Cmd, and close the modal. When the roll
lands, the existing `CompendiumInitiativeRolled` handler does
the draftToInstance + queue append + toast.
-}
pick : String -> Model -> ( Model, Cmd Msg )
pick creatureId model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        existing =
                            List.map .name model.encounter.creatures

                        name =
                            Encounter.Roster.uniqueInstanceName source.name existing

                        spec =
                            ( name
                            , Update.Initiative.source name
                            , Dice.generator (Update.Initiative.initiativeExpression source.initiativeBonus)
                            )
                    in
                    ( { model | modal = Nothing }
                    , Dice.batchRollCmd
                        (CompendiumInitiativeRolled creatureId)
                        [ spec ]
                    )

                Nothing ->
                    ( { model | modal = Nothing }, Cmd.none )

        _ ->
            ( { model | modal = Nothing }, Cmd.none )
