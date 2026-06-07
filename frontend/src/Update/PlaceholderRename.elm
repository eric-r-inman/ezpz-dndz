module Update.PlaceholderRename exposing (open, change, commit, cancel)

{-| Update branches for the inline Placeholder N rename flow.

The user clicks a `Placeholder N` creature card's name. The name
span flips to an `<input>` (rendered by `View.Card` when the
creature's name equals `model.placeholderRename`'s target). The
user types, then Enter or blur commits via
`Encounter.Roster.renameCreature`. Esc cancels.

@docs open, change, commit, cancel

-}

import Encounter.Roster
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.PlaceholderRename as Rename


{-| Click handler on the placeholder name. Seed the rename state
with the current display name so the user can edit-in-place
rather than blank the field.
-}
open : String -> Model -> ( Model, Cmd Msg )
open name model =
    ( { model | placeholderRename = Just (Rename.fresh name) }, Cmd.none )


{-| `onInput` handler: track the in-progress text. No commit yet.
-}
change : String -> Model -> ( Model, Cmd Msg )
change text model =
    case model.placeholderRename of
        Just state ->
            ( { model
                | placeholderRename =
                    Just { state | draft = String.left Rename.maxNameLength text }
              }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Enter / blur: write the new name to the encounter and close
the inline edit. Empty / whitespace-only drafts are dropped
silently by the `renameCreature` helper, so the user falls back
to the original name without any error UI.
-}
commit : Model -> ( Model, Cmd Msg )
commit model =
    case model.placeholderRename of
        Just state ->
            ( { model
                | encounter =
                    Encounter.Roster.renameCreature state.target state.draft model.encounter
                , placeholderRename = Nothing
              }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Esc: close the inline edit without writing.
-}
cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | placeholderRename = Nothing }, Cmd.none )
