module Update.TreasureTable exposing
    ( open, close
    , toggleSection
    , gemAdd, gemEdit, gemRemove
    , artAdd, artEdit, artRemove
    , magicAdd, magicEdit, magicRemove
    , resetToBundled
    )

{-| Msg handlers for the singular per-user Treasure Table
editor.

There's exactly one editable treasure table per user — initialised
from `Encounter.Treasure.bundledTable` and mutated through this
modal. The editor exposes per-section name-list editing for the
gem / art / magic tiers (the parts a GM most commonly customises:
add a homebrew item to Table B, rename gems for setting flavor).
Individual + hoard rows render read-only for now; a later phase
will add a row-editor for weights and coin formulas.

Saves are persisted by the standard `userTreasureTableCmd` hook
in `Main.update` — server PUT for authed sessions, localStorage
for anonymous.

@docs open, close
@docs toggleSection
@docs gemAdd, gemEdit, gemRemove
@docs artAdd, artEdit, artRemove
@docs magicAdd, magicEdit, magicRemove
@docs resetToBundled

-}

import Dict
import Encounter.Treasure as Treasure exposing (TreasureTable)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.TreasureTable as Ui


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (Model.ModalTreasureTable Ui.fresh) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


toggleSection : String -> String -> Model -> ( Model, Cmd Msg )
toggleSection kind key model =
    let
        section =
            case kind of
                "individual" ->
                    Ui.IndividualSection key

                "hoard" ->
                    Ui.HoardSection key

                "gem" ->
                    Ui.GemSection key

                "art" ->
                    Ui.ArtSection key

                _ ->
                    Ui.MagicSection key
    in
    ( Model.mapModal Model.treasureTableLens
        (Ui.toggleSection section)
        model
    , Cmd.none
    )



-- ── NAME-LIST EDITS ─────────────────────────────────────────────────────────


{-| Apply `fn` to the user's treasure table, using the bundled
default when the user has nothing saved yet. The result becomes
the new working copy and triggers the persistence hook.
-}
mutateTable : (TreasureTable -> TreasureTable) -> Model -> ( Model, Cmd Msg )
mutateTable fn model =
    let
        current =
            model.userTreasureTable
                |> Maybe.withDefault Treasure.bundledTable
    in
    ( { model | userTreasureTable = Just (fn current) }
    , Cmd.none
    )


gemAdd : String -> Model -> ( Model, Cmd Msg )
gemAdd tierKey =
    mutateTable
        (\table ->
            { table
                | gems = updateDictList tierKey (\names -> names ++ [ "" ]) table.gems
            }
        )


gemEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
gemEdit tierKey idx value =
    mutateTable
        (\table ->
            { table
                | gems =
                    updateDictList tierKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.gems
            }
        )


gemRemove : String -> Int -> Model -> ( Model, Cmd Msg )
gemRemove tierKey idx =
    mutateTable
        (\table ->
            { table | gems = updateDictList tierKey (dropIndex idx) table.gems }
        )


artAdd : String -> Model -> ( Model, Cmd Msg )
artAdd tierKey =
    mutateTable
        (\table ->
            { table | art = updateDictList tierKey (\names -> names ++ [ "" ]) table.art }
        )


artEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
artEdit tierKey idx value =
    mutateTable
        (\table ->
            { table
                | art =
                    updateDictList tierKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.art
            }
        )


artRemove : String -> Int -> Model -> ( Model, Cmd Msg )
artRemove tierKey idx =
    mutateTable
        (\table ->
            { table | art = updateDictList tierKey (dropIndex idx) table.art }
        )


magicAdd : String -> Model -> ( Model, Cmd Msg )
magicAdd tableKey =
    mutateTable
        (\table ->
            { table | magic = updateDictList tableKey (\names -> names ++ [ "" ]) table.magic }
        )


magicEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
magicEdit tableKey idx value =
    mutateTable
        (\table ->
            { table
                | magic =
                    updateDictList tableKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.magic
            }
        )


magicRemove : String -> Int -> Model -> ( Model, Cmd Msg )
magicRemove tableKey idx =
    mutateTable
        (\table ->
            { table | magic = updateDictList tableKey (dropIndex idx) table.magic }
        )


resetToBundled : Model -> ( Model, Cmd Msg )
resetToBundled model =
    ( { model | userTreasureTable = Just Treasure.bundledTable }
    , Cmd.none
    )



-- ── HELPERS ────────────────────────────────────────────────────────────────


updateDictList :
    String
    -> (List String -> List String)
    -> Dict.Dict String (List String)
    -> Dict.Dict String (List String)
updateDictList key fn dict =
    Dict.update key
        (\existing ->
            Just (fn (Maybe.withDefault [] existing))
        )
        dict


dropIndex : Int -> List a -> List a
dropIndex idx xs =
    xs
        |> List.indexedMap Tuple.pair
        |> List.filter (\( i, _ ) -> i /= idx)
        |> List.map Tuple.second
