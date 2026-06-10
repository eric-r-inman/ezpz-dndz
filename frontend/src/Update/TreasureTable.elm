module Update.TreasureTable exposing
    ( open, close, editNew, edit, backToList
    , nameChanged, entryAdd, entryRemove
    , entryLabelChanged, entryWeightChanged
    , entryGpChanged, entryRarityChanged
    , draftSubmit, draftCancel
    , delete
    , roll, customRolled, customRemove
    )

{-| Msg handlers for the user-authored Treasure Tables editor
modal + the roll-on-user-table action exposed in the main
Treasure modal.

The editor modal owns:

  - A list view of `model.userTreasureTables`.
  - An editor pane showing the in-progress draft (separate
    from the persisted list so Cancel is non-destructive).

Saving the draft replaces or appends the matching entry in
`model.userTreasureTables`; the standard
`userTreasureTablesCmd` hook in the update wrapper round-trips
the change to the server (or localStorage for anonymous
sessions).

The roll path lives here too — pressing Roll on a user table in
the main Treasure modal fires `TreasureTableRoll`, which lands
in [`roll`](#roll) below and triggers a `Random.generate` Cmd
whose result is [`customRolled`](#customRolled).

@docs open, close, editNew, edit, backToList
@docs nameChanged, entryAdd, entryRemove
@docs entryLabelChanged, entryWeightChanged
@docs entryGpChanged, entryRarityChanged
@docs draftSubmit, draftCancel
@docs delete
@docs roll, customRolled, customRemove

-}

import Encounter.Treasure as Treasure
import Encounter.Treasure.Tables exposing (Rarity(..))
import Encounter.Treasure.UserTable as UserTable exposing (Entry)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Ui.Toast exposing (ToastKind(..))
import Ui.TreasureTable as Ui exposing (Mode(..))
import Update.Toast



-- ── MODAL LIFECYCLE ─────────────────────────────────────────────────────────


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (Model.ModalTreasureTable Ui.fresh) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


editNew : Model -> ( Model, Cmd Msg )
editNew model =
    let
        nextId =
            "ut-" ++ String.fromInt model.bootMs ++ "-" ++ String.fromInt (List.length model.userTreasureTables)
    in
    ( Model.mapModal Model.treasureTableLens
        (\_ -> Ui.opening (UserTable.empty nextId))
        model
    , Cmd.none
    )


edit : String -> Model -> ( Model, Cmd Msg )
edit id model =
    case List.filter (\t -> t.id == id) model.userTreasureTables of
        existing :: _ ->
            ( Model.mapModal Model.treasureTableLens
                (\_ -> Ui.opening existing)
                model
            , Cmd.none
            )

        [] ->
            ( model, Cmd.none )


backToList : Model -> ( Model, Cmd Msg )
backToList model =
    ( Model.mapModal Model.treasureTableLens
        (\_ -> Ui.fresh)
        model
    , Cmd.none
    )



-- ── DRAFT MUTATION ──────────────────────────────────────────────────────────


nameChanged : String -> Model -> ( Model, Cmd Msg )
nameChanged name model =
    ( Model.mapModal Model.treasureTableLens
        (Ui.withDraft (\t -> { t | name = name }))
        model
    , Cmd.none
    )


entryAdd : Model -> ( Model, Cmd Msg )
entryAdd model =
    ( Model.mapModal Model.treasureTableLens
        (Ui.withDraft (\t -> { t | entries = t.entries ++ [ UserTable.emptyEntry ] }))
        model
    , Cmd.none
    )


entryRemove : Int -> Model -> ( Model, Cmd Msg )
entryRemove index model =
    ( Model.mapModal Model.treasureTableLens
        (Ui.withDraft (\t -> { t | entries = dropIndex index t.entries }))
        model
    , Cmd.none
    )


entryLabelChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryLabelChanged index value model =
    mapEntry index (\e -> { e | label = value }) model


entryWeightChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryWeightChanged index raw model =
    let
        weight =
            String.toInt raw |> Maybe.withDefault 0 |> max 0
    in
    mapEntry index (\e -> { e | weight = weight }) model


entryGpChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryGpChanged index raw model =
    let
        next =
            case String.trim raw of
                "" ->
                    Nothing

                s ->
                    String.toInt s |> Maybe.map (max 0)
    in
    mapEntry index (\e -> { e | gpValue = next }) model


entryRarityChanged : Int -> String -> Model -> ( Model, Cmd Msg )
entryRarityChanged index raw model =
    let
        next =
            case raw of
                "common" ->
                    Just Common

                "uncommon" ->
                    Just Uncommon

                "rare" ->
                    Just Rare

                "very-rare" ->
                    Just VeryRare

                "legendary" ->
                    Just Legendary

                _ ->
                    Nothing
    in
    mapEntry index (\e -> { e | rarity = next }) model


mapEntry : Int -> (Entry -> Entry) -> Model -> ( Model, Cmd Msg )
mapEntry index fn model =
    ( Model.mapModal Model.treasureTableLens
        (Ui.withDraft
            (\t ->
                { t
                    | entries =
                        t.entries
                            |> List.indexedMap
                                (\i e ->
                                    if i == index then
                                        fn e

                                    else
                                        e
                                )
                }
            )
        )
        model
    , Cmd.none
    )


dropIndex : Int -> List a -> List a
dropIndex idx xs =
    xs
        |> List.indexedMap Tuple.pair
        |> List.filter (\( i, _ ) -> i /= idx)
        |> List.map Tuple.second



-- ── DRAFT COMMIT ────────────────────────────────────────────────────────────


draftSubmit : Model -> ( Model, Cmd Msg )
draftSubmit model =
    case Maybe.andThen Model.treasureTableLens.extract model.modal of
        Just ui ->
            case ui.mode of
                Editing draft ->
                    if String.isEmpty (String.trim draft.name) then
                        Update.Toast.push ToastError
                            "Treasure tables need a name."
                            model

                    else
                        let
                            cleaned =
                                { draft
                                    | entries =
                                        List.filter
                                            (\e -> not (String.isEmpty (String.trim e.label)))
                                            draft.entries
                                }

                            tables =
                                if List.any (\t -> t.id == cleaned.id) model.userTreasureTables then
                                    List.map
                                        (\t ->
                                            if t.id == cleaned.id then
                                                cleaned

                                            else
                                                t
                                        )
                                        model.userTreasureTables

                                else
                                    model.userTreasureTables ++ [ cleaned ]
                        in
                        ( { model
                            | userTreasureTables = tables
                            , modal = Just (Model.ModalTreasureTable Ui.fresh)
                          }
                        , Cmd.none
                        )

                Listing ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


draftCancel : Model -> ( Model, Cmd Msg )
draftCancel model =
    ( Model.mapModal Model.treasureTableLens (\_ -> Ui.fresh) model
    , Cmd.none
    )



-- ── LIST OPS ────────────────────────────────────────────────────────────────


delete : String -> Model -> ( Model, Cmd Msg )
delete id model =
    ( { model
        | userTreasureTables =
            List.filter (\t -> t.id /= id) model.userTreasureTables
      }
    , Cmd.none
    )



-- ── ROLL ON A USER TABLE ────────────────────────────────────────────────────


roll : String -> Model -> ( Model, Cmd Msg )
roll id model =
    case List.filter (\t -> t.id == id) model.userTreasureTables of
        table :: _ ->
            ( model
            , Random.generate TreasureCustomRolled (UserTable.generate table)
            )

        [] ->
            Update.Toast.push ToastError
                "That treasure table is gone — refresh and try again."
                model


customRolled : Maybe UserTable.CustomRoll -> Model -> ( Model, Cmd Msg )
customRolled result model =
    case result of
        Nothing ->
            Update.Toast.push ToastError
                "That table has no entries to roll on yet."
                model

        Just row ->
            let
                encounter =
                    model.encounter

                baseRoll =
                    case encounter.treasure of
                        Just existing ->
                            existing

                        Nothing ->
                            Treasure.emptyRoll Treasure.Hoard Treasure.B1to4

                nextRoll =
                    Treasure.appendCustom row baseRoll
            in
            ( { model | encounter = { encounter | treasure = Just nextRoll } }
            , Cmd.none
            )


customRemove : Int -> Model -> ( Model, Cmd Msg )
customRemove index model =
    case model.encounter.treasure of
        Nothing ->
            ( model, Cmd.none )

        Just existing ->
            let
                encounter =
                    model.encounter

                nextRoll =
                    Treasure.removeCustom index existing
            in
            ( { model | encounter = { encounter | treasure = Just nextRoll } }
            , Cmd.none
            )
