module Update.Memo exposing (cancel, change, clear, commit, open)

{-| Update branches for the per-creature memo modal (the
short-lived note that renders as a pill in card row 3). Distinct
from the long-lived `note` annotation in `Update.Note`.
-}

import Encounter
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Memo as MemoUi exposing (MemoEditUi)


withMemoEdit : (MemoEditUi -> MemoEditUi) -> Model -> Model
withMemoEdit =
    Model.mapSurface Model.memoLens


open : String -> Model -> ( Model, Cmd Msg )
open name model =
    let
        current =
            model.encounter.creatures
                |> List.filter (\c -> c.name == name)
                |> List.head
                |> Maybe.map .memo
                |> Maybe.withDefault ""
    in
    ( { model | surface = Just (SurfaceMemoEdit (MemoUi.fresh name current)) }
    , Cmd.none
    )


change : String -> Model -> ( Model, Cmd Msg )
change text model =
    ( withMemoEdit (\u -> { u | text = String.left MemoUi.maxMemoLength text }) model
    , Cmd.none
    )


commit : Model -> ( Model, Cmd Msg )
commit model =
    case model.surface of
        Just (SurfaceMemoEdit ui) ->
            let
                trimmed =
                    String.trim ui.text
            in
            ( { model
                | encounter =
                    Encounter.mapCreature ui.target
                        (\c -> { c | memo = trimmed })
                        model.encounter
                , surface = Nothing
              }
            , Cmd.none
            )

        _ ->
            ( model, Cmd.none )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | surface = Nothing }, Cmd.none )


{-| Drop the memo from the named creature (the inline ✕ on the
memo pill in card row 3).
-}
clear : String -> Model -> ( Model, Cmd Msg )
clear name model =
    ( { model
        | encounter =
            Encounter.mapCreature name (\c -> { c | memo = "" }) model.encounter
      }
    , Cmd.none
    )
