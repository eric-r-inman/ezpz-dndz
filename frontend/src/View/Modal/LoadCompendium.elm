module View.Modal.LoadCompendium exposing (view)

{-| Load-compendium modal.

Mirrors `View.Modal.SaveCompendium` for visual consistency:
the top row carries a Server / Device radio pair, the body
changes shape based on which is picked.

  - **Server** — server-side snapshots list (existing flow).
    Anonymous users see a sign-in hint instead and the row
    list is suppressed so a 401 "Couldn't load saves" never
    surfaces.
  - **Device** — a file-picker button that kicks off the
    existing `CompendiumImportClick` parse → confirm → replace
    flow inside the parent Compendium modal.

The destructive replace-the-library step still goes through
the inline confirmation banner; that hasn't changed.

-}

import Auth
import Compendium.Wire exposing (SavedCompendiumMeta)
import Html exposing (Html, button, div, input, label, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , checked
        , class
        , disabled
        , id
        , name
        , type_
        )
import Html.Events exposing (onClick)
import Model exposing (Model, Surface(..))
import Msg exposing (LoadSource(..), Msg(..))
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
    case model.surface of
        Just (SurfaceLoadCompendium ui) ->
            View.Modal.view
                { close = LoadCompendiumClose
                , noOp = NoOp
                , title = "Load Compendium"
                , extraClass = "modal--load"
                , chrome = model.modalChrome
                , body =
                    [ sourceSection ui
                    , confirmBanner ui
                    , errorBanner model.auth ui
                    , bodyForSource model.auth ui
                    , closeRow
                    ]
                }

        _ ->
            text ""


{-| `True` when the user is anonymous AND has picked the
Server source — the combination where the server fetch
returns 401. Centralised so the error banner and the body
share the predicate.
-}
serverNeedsSignIn : Auth.AuthState -> LoadCompendiumUi -> Bool
serverNeedsSignIn auth ui =
    ui.source == LoadSourceServer && not (Auth.isAuthenticated auth)


sourceSection : LoadCompendiumUi -> Html Msg
sourceSection ui =
    div [ class "save-modal__row save-modal__row--destination" ]
        [ label [ class "save-modal__label" ] [ text "Load from" ]
        , div [ class "save-modal__radio-group", attribute "role" "radiogroup" ]
            [ sourceRadio ui LoadSourceServer "Server" "load-cmp-src-server"
            , sourceRadio ui LoadSourceDevice "Device" "load-cmp-src-device"
            ]
        ]


sourceRadio : LoadCompendiumUi -> LoadSource -> String -> String -> Html Msg
sourceRadio ui source label_ idAttr =
    Html.label [ class "save-modal__radio" ]
        [ input
            [ type_ "radio"
            , id idAttr
            , name "load-compendium-source"
            , checked (ui.source == source)
            , onClick (LoadCompendiumSourceSet source)
            ]
            []
        , span [] [ text label_ ]
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


errorBanner : Auth.AuthState -> LoadCompendiumUi -> Html Msg
errorBanner auth ui =
    if serverNeedsSignIn auth ui then
        -- Anonymous + Server: replace any stale 401 / network
        -- text with the friendlier sign-in hint, same wording
        -- shape as the Save Compendium modal.
        p [ class "save-modal__error save-modal__error--auth" ]
            [ text "Sign in to load your compendium from the eZpZ-dndZ server." ]

    else
        case ui.error of
            Just err ->
                p [ class "save-modal__error" ] [ text err ]

            Nothing ->
                text ""


{-| Body changes based on the picked source. Server: show the
list of server snapshots (or auth-gated empty). Device: a
single file-picker button that reuses the existing
`CompendiumImportClick` parse flow.
-}
bodyForSource : Auth.AuthState -> LoadCompendiumUi -> Html Msg
bodyForSource auth ui =
    case ui.source of
        LoadSourceServer ->
            if Auth.isAuthenticated auth then
                savesSection ui

            else
                -- Suppress the savesSection entirely for anonymous
                -- users.  The error banner above already explains
                -- they need to sign in; no point also rendering a
                -- "Couldn't load saves: Server returned 401" strip.
                text ""

        LoadSourceDevice ->
            deviceRow


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


savesSection : LoadCompendiumUi -> Html Msg
savesSection ui =
    case ui.saves of
        LoadsLoading ->
            div [ class "save-modal__list-empty" ]
                [ text "Loading saved compendiums…" ]

        LoadsFailed _ ->
            -- Per user request: don't surface 401 / generic
            -- "Couldn't load saves" text.  Authenticated users
            -- with a real network failure see an empty state;
            -- the close-and-retry path is more useful than a
            -- raw error code.
            div [ class "save-modal__list-empty" ]
                [ text "No saved compendiums on the server." ]

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
            , Tooltips.attr Tooltips.loadRowCompendium
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
