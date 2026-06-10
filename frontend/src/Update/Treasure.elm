module Update.Treasure exposing
    ( open, close
    , kindSet, bracketSet
    , roll, rolled
    , categoryRolled, rerollCategory
    , artRemove, coinRemove, gemRemove, magicRemove
    )

{-| Msg handlers for the Treasure modal.

The modal owns:

  - The dropdown selections (Kind + Bracket), which live on
    `Ui.Treasure.TreasureUi`.
  - A pure handler that fires the random `Generator` and lands
    the result into `model.encounter.treasure`.

The treasure result persists with the encounter (it's a field on
`Encounter`), so the standard `persistEncounterCmd` hook in the
update wrapper round-trips it to the server or localStorage
without anything extra from this module.

@docs open, close
@docs kindSet, bracketSet
@docs roll, rolled
@docs categoryRolled, rerollCategory

-}

import Compendium
import Encounter.Treasure as Treasure exposing (Bracket)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Ui.Compendium
import Ui.Treasure


{-| Open the modal. Seeds the UI with the bracket suggested
from the encounter's toughest creature (the modal opens to a
sensible default even when the GM didn't think about it).
-}
open : Model -> ( Model, Cmd Msg )
open model =
    let
        bracket =
            suggestedBracketFor model
    in
    ( { model | modal = Just (Model.ModalTreasure (Ui.Treasure.fresh bracket)) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


{-| Resolve CR floats from the encounter's creatures + the
compendium DB, then ask `Encounter.Treasure` which bracket
covers the toughest one.
-}
suggestedBracketFor : Model -> Bracket
suggestedBracketFor model =
    let
        db =
            loadedDb model
    in
    model.encounter.creatures
        |> List.filterMap (\c -> c.creatureId |> Maybe.andThen (\id -> Compendium.find id db))
        |> List.map (.challengeRating >> Compendium.crToFloat)
        |> Treasure.suggestedBracket


loadedDb : Model -> Compendium.Db
loadedDb model =
    case model.compendium.db of
        Ui.Compendium.CompendiumDbLoaded db ->
            db

        _ ->
            Compendium.fromList []


{-| Update the Kind dropdown ("individual" / "hoard"). Unknown
strings collapse to Hoard, the safer default for a typo.
-}
kindSet : String -> Model -> ( Model, Cmd Msg )
kindSet wire model =
    let
        kind =
            case wire of
                "individual" ->
                    Treasure.Individual

                _ ->
                    Treasure.Hoard
    in
    ( Model.mapModal Model.treasureLens (\ui -> { ui | kind = kind }) model
    , Cmd.none
    )


{-| Update the Bracket dropdown. Same fallback story as
[`kindSet`](#kindSet) — typos collapse to the default
suggestion the modal opened with rather than guessing.
-}
bracketSet : String -> Model -> ( Model, Cmd Msg )
bracketSet wire model =
    let
        bracket =
            case wire of
                "1to4" ->
                    Treasure.B1to4

                "5to10" ->
                    Treasure.B5to10

                "11to16" ->
                    Treasure.B11to16

                "17plus" ->
                    Treasure.B17plus

                _ ->
                    suggestedBracketFor model
    in
    ( Model.mapModal Model.treasureLens (\ui -> { ui | bracket = bracket }) model
    , Cmd.none
    )


{-| Fire the random Generator with the current Kind + Bracket.
The runtime feeds the result into `TreasureRolled` via the
standard `Random.generate` glue.
-}
roll : Model -> ( Model, Cmd Msg )
roll model =
    case model.modal of
        Just (Model.ModalTreasure ui) ->
            ( model
            , Random.generate TreasureRolled
                (Treasure.generate ui.kind ui.bracket (activeTable model))
            )

        _ ->
            ( model, Cmd.none )


{-| Resolve the table to roll against — the user's edited copy
when they have one, otherwise the bundled default. Centralised
here so all the per-category / re-roll handlers stay in sync.
-}
activeTable : Model -> Treasure.TreasureTable
activeTable model =
    Maybe.withDefault Treasure.bundledTable model.userTreasureTable


{-| Materialised roll landed — save it onto the encounter.
-}
rolled : Treasure.TreasureRoll -> Model -> ( Model, Cmd Msg )
rolled treasureRoll model =
    let
        encounter =
            model.encounter
    in
    ( { model | encounter = { encounter | treasure = Just treasureRoll } }
    , Cmd.none
    )


{-| Fire a fresh random Generator targeting the chosen category.
Re-uses the originating row's spec (stored on `roll.source`) so
the gem tier / dice count stay consistent with the original
roll — only the specific stone / object / item names change.

Pre-source rolls (legacy saved encounters) fall through to a
fresh full-row regen, since there's no spec to re-use.

The runtime lands the result in `TreasureCategoryRolled`, which
[`categoryRolled`](#categoryRolled) below merges into the
existing roll.

-}
rerollCategory : Treasure.Category -> Model -> ( Model, Cmd Msg )
rerollCategory category model =
    case model.encounter.treasure of
        Just currentRoll ->
            ( model
            , Random.generate (TreasureCategoryRolled category)
                (Treasure.generateRerollCategory (activeTable model) currentRoll category)
            )

        Nothing ->
            ( model, Cmd.none )


{-| Per-row delete: zero out one coin denomination from the
encounter's current roll.
-}
coinRemove : String -> Model -> ( Model, Cmd Msg )
coinRemove denomination =
    mutateRoll (Treasure.clearCoin denomination)


gemRemove : Int -> Model -> ( Model, Cmd Msg )
gemRemove index =
    mutateRoll (Treasure.removeGem index)


artRemove : Int -> Model -> ( Model, Cmd Msg )
artRemove index =
    mutateRoll (Treasure.removeArt index)


magicRemove : Int -> Model -> ( Model, Cmd Msg )
magicRemove index =
    mutateRoll (Treasure.removeMagic index)


mutateRoll : (Treasure.TreasureRoll -> Treasure.TreasureRoll) -> Model -> ( Model, Cmd Msg )
mutateRoll fn model =
    case model.encounter.treasure of
        Just current ->
            let
                encounter =
                    model.encounter
            in
            ( { model | encounter = { encounter | treasure = Just (fn current) } }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Materialised single-category re-roll landed. Replace only
the chosen category's data on the existing `TreasureRoll`,
leaving the other categories untouched.
-}
categoryRolled :
    Treasure.Category
    -> Treasure.TreasureRoll
    -> Model
    -> ( Model, Cmd Msg )
categoryRolled category fresh model =
    case model.encounter.treasure of
        Nothing ->
            ( model, Cmd.none )

        Just existing ->
            let
                nextRoll =
                    case category of
                        Treasure.CoinsCategory ->
                            { existing | coins = fresh.coins }

                        Treasure.GemsCategory ->
                            { existing | gems = fresh.gems }

                        Treasure.ArtCategory ->
                            { existing | art = fresh.art }

                        Treasure.MagicCategory ->
                            { existing | magic = fresh.magic }

                encounter =
                    model.encounter
            in
            ( { model | encounter = { encounter | treasure = Just nextRoll } }
            , Cmd.none
            )
