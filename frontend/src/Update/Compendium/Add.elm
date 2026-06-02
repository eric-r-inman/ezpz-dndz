module Update.Compendium.Add exposing
    ( addToQueue
    , addSelectedToQueue
    )

{-| Add-to-queue flow for the compendium browser: the GM picks a
creature (or bulk-selects several), clicks Add, and we append them
to the encounter at initiative 0 — no dice roll. The GM types the
real initiative on the card afterwards. Same convention as the
Quick Add modal.

`addSelectedToQueue` is the bulk-add path: every checkbox-selected
creature is materialised in one shot with a single summary toast.
The single-creature `addToQueue` skips the toast and lets the new
card itself be the feedback, matching the "modal stays open for
back-to-back adds" pattern.

@docs addToQueue
@docs addSelectedToQueue

-}

import Compendium
import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg(..))
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Toast exposing (ToastKind(..))
import Update.Toast


{-| Single-creature add from the compendium browser. Materialises
the creature at initiative 0 and appends it to the encounter
queue; the browser modal stays open so the GM can queue several
different creatures back-to-back.
-}
addToQueue : String -> Model -> ( Model, Cmd Msg )
addToQueue creatureId model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            case Compendium.find creatureId db of
                Just source ->
                    let
                        existing =
                            List.map .name model.encounter.creatures

                        displayName =
                            Encounter.Roster.uniqueInstanceName source.name existing

                        instance =
                            Compendium.draftToInstance
                                { displayName = displayName, initiativeRoll = 0 }
                                source
                    in
                    ( { model
                        | encounter =
                            Encounter.Roster.appendCreatures [ instance ] model.encounter
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| Bulk-add: materialise every checkbox-selected creature in
`ui.selectedIds` at initiative 0 and append them in one shot.
Display names are assigned by folding left so collisions resolve
deterministically (three goblins become Goblin, Goblin 2,
Goblin 3 rather than three Goblins). A single summary toast
reports the count.
-}
addSelectedToQueue : Model -> ( Model, Cmd Msg )
addSelectedToQueue model =
    case model.compendium.db of
        CompendiumDbLoaded db ->
            let
                sources =
                    Set.toList model.compendium.selectedIds
                        |> List.filterMap (\id -> Compendium.find id db)

                existingNames =
                    List.map .name model.encounter.creatures

                ( instancesRev, _ ) =
                    List.foldl
                        (\source ( acc, takenNames ) ->
                            let
                                displayName =
                                    Encounter.Roster.uniqueInstanceName
                                        source.name
                                        takenNames

                                instance =
                                    Compendium.draftToInstance
                                        { displayName = displayName
                                        , initiativeRoll = 0
                                        }
                                        source
                            in
                            ( instance :: acc, displayName :: takenNames )
                        )
                        ( [], existingNames )
                        sources

                instances =
                    List.reverse instancesRev
            in
            if List.isEmpty instances then
                ( model, Cmd.none )

            else
                { model
                    | encounter =
                        Encounter.Roster.appendCreatures instances model.encounter
                }
                    |> Update.Toast.push ToastSuccess
                        ("Added "
                            ++ String.fromInt (List.length instances)
                            ++ " creatures to encounter"
                        )

        _ ->
            ( model, Cmd.none )
