module Update.Compendium.Paste exposing (apply, cancel, open, textChanged)

{-| Paste-stat-block modal: the GM pastes a 5e block of text, the
parser validates it, and Apply hands the result over to the edit
modal pre-filled.

This is the smallest of the compendium update sections — four
short Msg branches, no Cmds beyond the modal swap on Apply.

@docs apply, cancel, open, textChanged

-}

import Compendium.Parser
import Model exposing (Model, Surface(..))
import Msg exposing (Msg)
import Ui.Compendium as CompendiumUi exposing (EditMode(..))


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | surface = Just (SurfaceCompendiumPaste CompendiumUi.emptyPaste) }
    , Cmd.none
    )


cancel : Model -> ( Model, Cmd Msg )
cancel model =
    ( { model | surface = Nothing }, Cmd.none )


textChanged : String -> Model -> ( Model, Cmd Msg )
textChanged text model =
    ( { model
        | surface =
            Just
                (SurfaceCompendiumPaste
                    { text = text
                    , parseResult = Compendium.Parser.parseStatBlock text
                    }
                )
      }
    , Cmd.none
    )


{-| Hand the parsed stat block over to the edit modal so the GM can
review and save. We pre-fill via `CompendiumUi.editFromCreature`
then flip the mode back to `CreateMode` (the parsed creature has
no server-side id yet) and reset the source to "Pasted" so the
provenance is preserved through save.
-}
apply : Model -> ( Model, Cmd Msg )
apply model =
    case model.surface of
        Just (SurfaceCompendiumPaste { parseResult }) ->
            case parseResult of
                Ok creature ->
                    let
                        editUi =
                            CompendiumUi.editFromCreature creature

                        recreated =
                            { editUi | mode = CreateMode }
                    in
                    ( { model | surface = Just (SurfaceCompendiumEdit recreated) }
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
