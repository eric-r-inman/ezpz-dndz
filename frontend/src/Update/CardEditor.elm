module Update.CardEditor exposing
    ( open, close, save, reset
    , focusRow
    , rowAdd, rowRemove, rowMoveUp, rowMoveDown
    , rowAlignmentSet
    , widgetAdd, widgetRemove
    , queueViewSet
    , delete, layoutDeleted, layoutFetched, layoutSaved, layoutsLoaded, load, overwriteCancel, overwriteConfirm, saveAs, saveNameChanged
    )

{-| **Prototype** update handlers for the Creature Card Editor.

Each Msg branch in `Main` delegates to one of these one-liner-ish
helpers; the work itself is a thin map over `Card.Layout`'s pure
mutators. Persistence is not wired yet — `save` copies the
in-progress UI state onto `Model.cardLayout` / `Model.queueView`
and that's it. Reloading the page resets to defaults until we
add a localStorage port or the server-side store.

@docs open, close, save, reset
@docs focusRow
@docs rowAdd, rowRemove, rowMoveUp, rowMoveDown
@docs rowAlignmentSet
@docs widgetAdd, widgetRemove
@docs queueViewSet

-}

import Card.Layout as Layout exposing (CardWidget, QueueView, RowAlignment)
import Card.Wire as CardWire
import Http
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.CardEditor as CardEditor exposing (CardEditorUi)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast
import Util.Http



-- ── OPEN / CLOSE / SAVE ──────────────────────────────────────────────────────


open : Model -> ( Model, Cmd Msg )
open model =
    ( { model
        | modal =
            Just
                (ModalCardEditor
                    (CardEditor.fromCurrent model.cardLayout model.queueView)
                )
      }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


{-| Copy the editor's in-progress layout + queue view onto the
model, then close. Phase 2 will also fire a persistence Cmd —
either a localStorage port write or a `PUT /api/me/preferences`.
-}
save : Model -> ( Model, Cmd Msg )
save model =
    case Maybe.andThen Model.cardEditorLens.extract model.modal of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            ( { model
                | cardLayout = ui.layout
                , queueView = ui.queueView
                , modal = Nothing
              }
            , Cmd.none
            )


reset : Model -> ( Model, Cmd Msg )
reset model =
    ( withEditor (\ui -> { ui | layout = Layout.defaultLayout }) model
    , Cmd.none
    )



-- ── ROW MUTATORS ─────────────────────────────────────────────────────────────


focusRow : Int -> Model -> ( Model, Cmd Msg )
focusRow index model =
    ( withEditor (\ui -> { ui | focusRow = Just index }) model, Cmd.none )


rowAdd : Model -> ( Model, Cmd Msg )
rowAdd model =
    ( withEditor
        (\ui ->
            let
                newLayout =
                    Layout.addRow ui.layout

                newFocus =
                    Just (List.length newLayout.rows - 1)
            in
            { ui | layout = newLayout, focusRow = newFocus }
        )
        model
    , Cmd.none
    )


rowRemove : Int -> Model -> ( Model, Cmd Msg )
rowRemove index model =
    ( withEditor
        (\ui ->
            let
                newLayout =
                    Layout.removeRow index ui.layout
            in
            { ui
                | layout = newLayout
                , focusRow =
                    -- After removal, snap focus to the row at the
                    -- same index if one exists, otherwise the row
                    -- just before it; `Nothing` when the layout
                    -- becomes empty.
                    if List.isEmpty newLayout.rows then
                        Nothing

                    else
                        Just (min index (List.length newLayout.rows - 1))
            }
        )
        model
    , Cmd.none
    )


rowMoveUp : Int -> Model -> ( Model, Cmd Msg )
rowMoveUp index model =
    ( withEditor
        (\ui ->
            { ui
                | layout = Layout.moveRowUp index ui.layout
                , focusRow = Just (max 0 (index - 1))
            }
        )
        model
    , Cmd.none
    )


rowMoveDown : Int -> Model -> ( Model, Cmd Msg )
rowMoveDown index model =
    ( withEditor
        (\ui ->
            let
                last =
                    List.length ui.layout.rows - 1
            in
            { ui
                | layout = Layout.moveRowDown index ui.layout
                , focusRow = Just (min last (index + 1))
            }
        )
        model
    , Cmd.none
    )


rowAlignmentSet : Int -> String -> Model -> ( Model, Cmd Msg )
rowAlignmentSet index key model =
    case Layout.rowAlignmentFromKey key of
        Just alignment ->
            ( withEditor
                (\ui ->
                    { ui
                        | layout =
                            Layout.setRowAlignment index alignment ui.layout
                    }
                )
                model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )



-- ── WIDGET MUTATORS ──────────────────────────────────────────────────────────


widgetAdd : Int -> String -> Model -> ( Model, Cmd Msg )
widgetAdd rowIndex widgetKey model =
    case Layout.widgetFromKey widgetKey of
        Just widget ->
            ( withEditor
                (\ui ->
                    { ui | layout = Layout.addWidget rowIndex widget ui.layout }
                )
                model
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


widgetRemove : Int -> Int -> Model -> ( Model, Cmd Msg )
widgetRemove rowIndex widgetIndex model =
    ( withEditor
        (\ui ->
            { ui
                | layout =
                    Layout.removeWidget rowIndex widgetIndex ui.layout
            }
        )
        model
    , Cmd.none
    )



-- ── QUEUE VIEW ───────────────────────────────────────────────────────────────


queueViewSet : String -> Model -> ( Model, Cmd Msg )
queueViewSet key model =
    case Layout.queueViewFromKey key of
        Just qv ->
            ( withEditor (\ui -> { ui | queueView = qv }) model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )



-- ── SAVED-LAYOUT PERSISTENCE ─────────────────────────────────────────────────


saveNameChanged : String -> Model -> ( Model, Cmd Msg )
saveNameChanged raw model =
    ( withEditor (\ui -> { ui | saveName = String.left 120 raw }) model
    , Cmd.none
    )


{-| User clicked Save. If the typed name collides with an
existing saved layout, stash it in `confirmOverwrite` and
surface the confirm banner; the actual PUT only fires once the
user clicks Overwrite. Otherwise (fresh name), the PUT goes
through immediately via `firePut` with `overwrite = False`.

Collision detection is client-side against
`model.savedCardLayouts` — the metadata list we already fetched
on boot — so we skip the 409-then-confirm round trip.

-}
saveAs : Model -> ( Model, Cmd Msg )
saveAs model =
    case Maybe.andThen Model.cardEditorLens.extract model.modal of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            let
                trimmed =
                    String.trim ui.saveName
            in
            if String.isEmpty trimmed then
                ( withEditor
                    (\u -> { u | error = Just "Enter a name to save." })
                    model
                , Cmd.none
                )

            else if nameAlreadyExists trimmed model.savedCardLayouts then
                ( withEditor
                    (\u ->
                        { u
                            | confirmOverwrite = Just trimmed
                            , error = Nothing
                        }
                    )
                    model
                , Cmd.none
                )

            else
                firePut trimmed False model


{-| Continuation when the user confirms an overwrite. Fires the
same PUT with `overwrite=True` so the server replaces the
existing record in place (preserving its `created_at`).
-}
overwriteConfirm : Model -> ( Model, Cmd Msg )
overwriteConfirm model =
    case Maybe.andThen Model.cardEditorLens.extract model.modal of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            case ui.confirmOverwrite of
                Just name ->
                    firePut name True model

                Nothing ->
                    ( model, Cmd.none )


overwriteCancel : Model -> ( Model, Cmd Msg )
overwriteCancel model =
    ( withEditor (\u -> { u | confirmOverwrite = Nothing }) model
    , Cmd.none
    )


firePut : String -> Bool -> Model -> ( Model, Cmd Msg )
firePut name overwrite model =
    case Maybe.andThen Model.cardEditorLens.extract model.modal of
        Nothing ->
            ( model, Cmd.none )

        Just ui ->
            ( withEditor
                (\u ->
                    { u
                        | busy = True
                        , error = Nothing
                        , confirmOverwrite = Nothing
                    }
                )
                model
            , CardWire.save
                { name = name
                , overwrite = overwrite
                , layout = ui.layout
                , queueView = ui.queueView
                }
                CardEditorLayoutSaved
            )


nameAlreadyExists :
    String
    -> List CardWire.SavedLayoutMeta
    -> Bool
nameAlreadyExists name metas =
    List.any (\m -> m.name == name) metas


load : String -> Model -> ( Model, Cmd Msg )
load name model =
    ( withEditor (\u -> { u | busy = True, error = Nothing }) model
    , CardWire.fetchOne name CardEditorLayoutFetched
    )


delete : String -> Model -> ( Model, Cmd Msg )
delete name model =
    ( withEditor (\u -> { u | busy = True, error = Nothing }) model
    , CardWire.delete_ name (CardEditorLayoutDeleted name)
    )


layoutsLoaded :
    Result Http.Error (List CardWire.SavedLayoutMeta)
    -> Model
    -> ( Model, Cmd Msg )
layoutsLoaded result model =
    case result of
        Ok metas ->
            ( { model | savedCardLayouts = metas }, Cmd.none )

        Err _ ->
            -- Silent on boot — a fresh user with no saved
            -- layouts gets a 200 with `[]`, so a real error
            -- means the network's off; the editor's empty
            -- "no saved layouts yet" state is the right UX
            -- to fall through to.
            ( model, Cmd.none )


layoutFetched :
    Result Http.Error CardWire.SavedLayout
    -> Model
    -> ( Model, Cmd Msg )
layoutFetched result model =
    case result of
        Ok record ->
            ( withEditor
                (\u ->
                    { u
                        | layout = record.layout
                        , queueView = record.queueView
                        , saveName = record.name
                        , busy = False
                        , error = Nothing
                        , focusRow =
                            if List.isEmpty record.layout.rows then
                                Nothing

                            else
                                Just 0
                    }
                )
                model
            , Cmd.none
            )

        Err err ->
            ( withEditor
                (\u ->
                    { u
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


layoutSaved :
    Result Http.Error CardWire.SavedLayout
    -> Model
    -> ( Model, Cmd Msg )
layoutSaved result model =
    case result of
        Ok record ->
            let
                refreshedMetas =
                    upsertMeta record model.savedCardLayouts

                applied =
                    { model
                        | cardLayout = record.layout
                        , queueView = record.queueView
                        , savedCardLayouts = refreshedMetas
                    }
            in
            applied
                |> withEditor
                    (\u ->
                        { u
                            | busy = False
                            , error = Nothing
                            , saveName = record.name
                        }
                    )
                |> Update.Toast.push ToastSuccess
                    ("Saved card layout \"" ++ record.name ++ "\".")

        Err err ->
            ( withEditor
                (\u ->
                    { u
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


layoutDeleted :
    String
    -> Result Http.Error ()
    -> Model
    -> ( Model, Cmd Msg )
layoutDeleted name result model =
    case result of
        Ok () ->
            let
                kept =
                    List.filter (\m -> m.name /= name) model.savedCardLayouts

                applied =
                    { model | savedCardLayouts = kept }
            in
            applied
                |> withEditor
                    (\u -> { u | busy = False, error = Nothing })
                |> Update.Toast.push ToastSuccess
                    ("Deleted card layout \"" ++ name ++ "\".")

        Err err ->
            ( withEditor
                (\u ->
                    { u
                        | busy = False
                        , error = Just (Util.Http.errorToString err)
                    }
                )
                model
            , Cmd.none
            )


{-| Insert or update the metadata for a freshly-saved record so
the editor's "Saved layouts" list reflects the change without
a refetch.
-}
upsertMeta :
    CardWire.SavedLayout
    -> List CardWire.SavedLayoutMeta
    -> List CardWire.SavedLayoutMeta
upsertMeta record metas =
    let
        newMeta =
            { name = record.name
            , createdAt = record.createdAt
            , updatedAt = record.updatedAt
            }
    in
    if List.any (\m -> m.name == record.name) metas then
        List.map
            (\m ->
                if m.name == record.name then
                    newMeta

                else
                    m
            )
            metas

    else
        newMeta :: metas



-- ── INTERNAL ─────────────────────────────────────────────────────────────────


withEditor : (CardEditorUi -> CardEditorUi) -> Model -> Model
withEditor fn model =
    Model.mapModal Model.cardEditorLens fn model
