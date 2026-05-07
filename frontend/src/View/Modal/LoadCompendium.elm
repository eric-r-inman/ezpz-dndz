module View.Modal.LoadCompendium exposing (view)

{-| Load-compendium modal.

Mirrors `View.Modal.Load`: top row offers a "from device" file
picker (which reuses the existing `CompendiumImportClick` flow);
middle is the list of server-side snapshots; clicking a row
prompts for confirmation before replacing the live library.

The MVP omits rename / delete row affordances — destructive
management lives on the Save modal's overwrite path.

-}

import Compendium.Wire exposing (SavedCompendiumMeta)
import Html exposing (Html, button, div, li, p, text, ul)
import Html.Attributes exposing (class, disabled, title)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.LoadCompendium as LoadCompendiumUi
    exposing
        ( ConfirmAction(..)
        , LoadCompendiumUi
        , LoadListState(..)
        )
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalLoadCompendium ui) ->
            View.Modal.view
                { close = LoadCompendiumClose
                , noOp = NoOp
                , title = "Load Compendium"
                , extraClass = "modal--load"
                , body =
                    [ deviceRow
                    , confirmBanner ui
                    , errorBanner ui
                    , savesSection ui
                    , closeRow
                    ]
                }

        _ ->
            text ""


{-| The "from device" path reuses the existing
`CompendiumImportClick` Msg, which kicks off the file-picker /
parse / confirm flow already wired through
`Update.Compendium.Bulk`. We close the load modal first so the
existing pending-confirm banner inside the Compendium browser
modal isn't hidden behind us.
-}
deviceRow : Html Msg
deviceRow =
    div [ class "load-modal__device" ]
        [ p [ class "load-modal__device-text" ]
            [ text "Have a compendium snapshot on your computer?" ]
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumImportClick
            ]
            [ text "📁 Choose file…" ]
        ]


confirmBanner : LoadCompendiumUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmLoad name) ->
            confirmRow
                ("Load \"" ++ name ++ "\"? This replaces the current compendium.")
                "Load"

        Just (ConfirmDelete _) ->
            text ""

        Nothing ->
            text ""


confirmRow : String -> String -> Html Msg
confirmRow message confirmLabel =
    div [ class "save-modal__confirm" ]
        [ p [ class "save-modal__confirm-msg" ] [ text message ]
        , div [ class "save-modal__confirm-actions" ]
            [ button
                [ class "action-btn action-btn--red"
                , onClick LoadCompendiumConfirmConfirm
                ]
                [ text confirmLabel ]
            , button
                [ class "action-btn"
                , onClick LoadCompendiumConfirmCancel
                ]
                [ text "Cancel" ]
            ]
        ]


errorBanner : LoadCompendiumUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "save-modal__error" ] [ text err ]

        Nothing ->
            text ""


savesSection : LoadCompendiumUi -> Html Msg
savesSection ui =
    case ui.saves of
        LoadsLoading ->
            div [ class "save-modal__list-empty" ]
                [ text "Loading saved compendiums…" ]

        LoadsFailed err ->
            div [ class "save-modal__list-empty" ]
                [ text ("Couldn't load saves: " ++ err) ]

        LoadsLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved compendiums on the server." ]

        LoadsLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ]
                    [ text "Server snapshots" ]
                , ul [ class "save-modal__list" ]
                    (List.map (saveRow ui.busy) metas)
                ]


saveRow : Bool -> SavedCompendiumMeta -> Html Msg
saveRow isBusy meta =
    li [ class "save-modal__row-item" ]
        [ button
            [ class "save-modal__row-name save-modal__row-name--clickable"
            , title Tooltips.loadRowCompendium
            , disabled isBusy
            , onClick (LoadCompendiumFromServerRequested meta.name)
            ]
            [ text meta.name ]
        ]


closeRow : Html Msg
closeRow =
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn"
            , onClick LoadCompendiumClose
            ]
            [ text "Close" ]
        ]
