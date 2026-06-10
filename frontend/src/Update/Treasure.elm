module Update.Treasure exposing
    ( open, close
    , kindSet, bracketSet
    , roll, rolled
    , toggleDistributed
    , rerollRequest, rerollConfirm, rerollCancel
    , categoryRolled, rerollCategory
    )

{-| Msg handlers for the Treasure modal.

The modal owns:

  - The dropdown selections (Kind + Bracket), which live on
    `Ui.Treasure.TreasureUi`.
  - The re-roll confirmation flag, also on `TreasureUi`.
  - A pure handler that fires the random `Generator` and lands
    the result into `model.encounter.treasure`.
  - Per-row "mark distributed" toggling, which mutates the
    `distributed : Set String` carried in
    `Encounter.TreasureState`.

The treasure result persists with the encounter (it's a field on
`Encounter`), so the standard `persistEncounterCmd` hook in the
update wrapper round-trips it to the server or localStorage
without anything extra from this module.

@docs open, close
@docs kindSet, bracketSet
@docs roll, rolled
@docs toggleDistributed
@docs rerollRequest, rerollConfirm, rerollCancel

-}

import Compendium
import Encounter.Treasure as Treasure exposing (Bracket)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Random
import Set
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
            , Random.generate TreasureRolled (Treasure.generate ui.kind ui.bracket)
            )

        _ ->
            ( model, Cmd.none )


{-| Materialised roll landed — save it onto the encounter and
clear the re-roll confirmation banner if it was open.
-}
rolled : Treasure.TreasureRoll -> Model -> ( Model, Cmd Msg )
rolled treasureRoll model =
    let
        encounter =
            model.encounter

        nextState =
            { roll = treasureRoll
            , distributed = Set.empty
            }

        withTreasure =
            { model | encounter = { encounter | treasure = Just nextState } }
    in
    ( Model.mapModal Model.treasureLens
        (\ui -> { ui | confirmingRereroll = False })
        withTreasure
    , Cmd.none
    )


{-| Flip the per-row distributed flag. `slug` identifies the
row uniquely ("coins", "gem:0", "art:3", "magic:1") — the view
encodes that, and the domain just toggles set membership.
-}
toggleDistributed : String -> Model -> ( Model, Cmd Msg )
toggleDistributed slug model =
    let
        encounter =
            model.encounter
    in
    case encounter.treasure of
        Just state ->
            let
                nextDistributed =
                    if Set.member slug state.distributed then
                        Set.remove slug state.distributed

                    else
                        Set.insert slug state.distributed

                nextState =
                    { state | distributed = nextDistributed }
            in
            ( { model | encounter = { encounter | treasure = Just nextState } }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Re-roll button clicked. If the existing roll has anything
marked distributed, show a confirm banner before discarding it.
Otherwise re-roll immediately.
-}
rerollRequest : Model -> ( Model, Cmd Msg )
rerollRequest model =
    let
        hasDistributed =
            case model.encounter.treasure of
                Just state ->
                    not (Set.isEmpty state.distributed)

                Nothing ->
                    False
    in
    if hasDistributed then
        ( Model.mapModal Model.treasureLens
            (\ui -> { ui | confirmingRereroll = True })
            model
        , Cmd.none
        )

    else
        roll model


rerollConfirm : Model -> ( Model, Cmd Msg )
rerollConfirm model =
    roll model


rerollCancel : Model -> ( Model, Cmd Msg )
rerollCancel model =
    ( Model.mapModal Model.treasureLens
        (\ui -> { ui | confirmingRereroll = False })
        model
    , Cmd.none
    )


{-| Fire a fresh random Generator targeting the chosen category.
The runtime lands the result in `TreasureCategoryRolled`, which
[`categoryRolled`](#categoryRolled) below merges into the
existing roll.
-}
rerollCategory : Treasure.Category -> Model -> ( Model, Cmd Msg )
rerollCategory category model =
    case model.modal of
        Just (Model.ModalTreasure ui) ->
            ( model
            , Random.generate (TreasureCategoryRolled category)
                (Treasure.generateCategory ui.kind ui.bracket category)
            )

        _ ->
            ( model, Cmd.none )


{-| Materialised single-category re-roll landed. Replace only
the chosen category's data on the existing `TreasureState`
(merging slices from a fresh full roll), and drop the
distributed marks for the replaced rows so the GM doesn't see
stale checkmarks on freshly-rolled items.
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

        Just state ->
            let
                existing =
                    state.roll

                ( nextRoll, droppedSlugPrefix ) =
                    case category of
                        Treasure.CoinsCategory ->
                            ( { existing | coins = fresh.coins }
                            , "coins"
                            )

                        Treasure.GemsCategory ->
                            ( { existing | gems = fresh.gems }
                            , "gem:"
                            )

                        Treasure.ArtCategory ->
                            ( { existing | art = fresh.art }
                            , "art:"
                            )

                        Treasure.MagicCategory ->
                            ( { existing | magic = fresh.magic }
                            , "magic:"
                            )

                nextDistributed =
                    Set.filter
                        (\slug ->
                            if droppedSlugPrefix == "coins" then
                                slug /= "coins"

                            else
                                not (String.startsWith droppedSlugPrefix slug)
                        )
                        state.distributed

                nextState =
                    { roll = nextRoll, distributed = nextDistributed }

                encounter =
                    model.encounter
            in
            ( { model | encounter = { encounter | treasure = Just nextState } }
            , Cmd.none
            )
