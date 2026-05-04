module Update.Memo exposing (cancel, change, clear, commit, open)

{-| Update branches for the per-creature memo modal (the
short-lived note that renders as a pill in card row 3). Distinct
from the long-lived `note` annotation in `Update.Note`.
-}

import Encounter
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Memo as MemoUi exposing (MemoEditUi)


withMemoEdit : (MemoEditUi -> MemoEditUi) -> Model -> Model
withMemoEdit fn model =
    { model | memoEdit = Maybe.map fn model.memoEdit }


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
    ( { model | memoEdit = Just (MemoUi.fresh name current) }
    , Cmd.none
    )


change : String -> Model -> ( Model, Cmd Msg )
change text model =
    ( withMemoEdit (\u -> { u | text = String.left MemoUi.maxMemoLength text }) model
    , Cmd.none
    )


commit : Model -> ( Model, Cmd Msg )
commit model =
    case model.memoEdit of
        Just ui ->
            let
                trimmed =
                    String.trim ui.text
            in
            ( { model
                | encounter =
                    Encounter.mapCreature ui.target
                        (\c -> { c | memo = trimmed })
                        model.encounter
                , memoEdit = Nothing
              }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | memoEdit = Nothing }, Cmd.none )


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
