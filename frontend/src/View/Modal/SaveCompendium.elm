module View.Modal.SaveCompendium exposing (view)

{-| Save-compendium modal.

Mirrors `View.Panel.SaveLoad` but for the creature library: the
top half picks destination + filename; the bottom half lists
existing server-side snapshots so the user can pick one to
overwrite.

The MVP omits rename / delete row affordances — re-saving under
an existing name fires the overwrite confirm prompt, which
covers the common workflow.

-}

import Auth
import Compendium.Wire exposing (SavedCompendiumMeta)
import Html exposing (Html, button, div, input, label, li, p, span, text, ul)
import Html.Attributes
    exposing
        ( attribute
        , autofocus
        , checked
        , class
        , disabled
        , id
        , maxlength
        , name
        , placeholder
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..), SaveStorage(..))
import Ui.SaveCompendium as SaveCompendiumUi
    exposing
        ( ConfirmAction(..)
        , SaveCompendiumUi
        , SaveListState(..)
        )
import Util.Keyboard
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.surface of
        Just (SurfaceSaveCompendium ui) ->
            View.Modal.view
                { close = SaveCompendiumClose
                , noOp = NoOp
                , title = "Save Compendium"
                , extraClass = "modal--save"
                , chrome = model.modalChrome
                , body =
                    [ destinationSection ui
                    , filenameSection ui
                    , confirmBanner ui
                    , errorBanner model.auth ui
                    , savesSectionFor model.auth ui
                    , submitRow model.auth ui
                    ]
                }

        _ ->
            text ""


{-| `True` when the user is anonymous AND has picked the
Server destination — the combination where Save is blocked
because the request would 401. Centralised so the error
banner and the submit button can share the predicate.
-}
serverNeedsSignIn : Auth.AuthState -> SaveCompendiumUi -> Bool
serverNeedsSignIn auth ui =
    ui.destination == StorageServer && not (Auth.isAuthenticated auth)


destinationSection : SaveCompendiumUi -> Html Msg
destinationSection ui =
    div [ class "save-modal__row save-modal__row--destination" ]
        [ label [ class "save-modal__label" ] [ text "Save to" ]
        , div [ class "save-modal__radio-group", attribute "role" "radiogroup" ]
            [ destinationRadio ui StorageServer "Server" "save-cmp-dest-server"
            , destinationRadio ui StorageDevice "Device" "save-cmp-dest-device"
            ]
        ]


destinationRadio : SaveCompendiumUi -> SaveStorage -> String -> String -> Html Msg
destinationRadio ui dest label_ idAttr =
    Html.label [ class "save-modal__radio" ]
        [ input
            [ type_ "radio"
            , id idAttr
            , name "save-compendium-destination"
            , checked (ui.destination == dest)
            , onClick (SaveCompendiumDestinationSet dest)
            ]
            []
        , span [] [ text label_ ]
        ]


filenameSection : SaveCompendiumUi -> Html Msg
filenameSection ui =
    div [ class "save-modal__row" ]
        [ label
            [ class "save-modal__label"
            , Html.Attributes.for "save-compendium-filename"
            ]
            [ text
                (case ui.destination of
                    StorageServer ->
                        "Save name"

                    StorageDevice ->
                        "Filename"
                )
            ]
        , input
            [ id "save-compendium-filename"
            , class "save-modal__input"
            , type_ "text"
            , value ui.filename
            , maxlength SaveCompendiumUi.maxNameLength
            , placeholder "e.g. Curse of Strahd Bestiary"
            , autofocus True
            , onInput SaveCompendiumFilenameChanged
            , Html.Events.on "keydown" (Util.Keyboard.enterKey SaveCompendiumSubmit)
            ]
            []
        ]


confirmBanner : SaveCompendiumUi -> Html Msg
confirmBanner ui =
    case ui.confirm of
        Just (ConfirmOverwrite name) ->
            confirmRow
                ("Overwrite \"" ++ name ++ "\" with the current compendium?")
                "Overwrite"

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
                , onClick SaveCompendiumConfirmConfirm
                ]
                [ text confirmLabel ]
            , button
                [ class "action-btn"
                , onClick SaveCompendiumConfirmCancel
                ]
                [ text "Cancel" ]
            ]
        ]


errorBanner : Auth.AuthState -> SaveCompendiumUi -> Html Msg
errorBanner auth ui =
    if serverNeedsSignIn auth ui then
        -- Replace any inflight 401 / "not authorised" text from
        -- a prior submit attempt with the friendlier sign-in
        -- hint.  Anonymous Server is a precondition failure, not
        -- a server error.
        p [ class "save-modal__error save-modal__error--auth" ]
            [ text "Sign in to save your compendium to the eZpZ-dndZ server." ]

    else
        case ui.error of
            Just err ->
                p [ class "save-modal__error" ] [ text err ]

            Nothing ->
                text ""


{-| Server-side snapshot list, gated on destination and auth.

  - Device destination → hide (saves don't apply to a one-shot
    file download).
  - Anonymous + Server → hide (the sign-in hint above already
    covers it; no point showing "Couldn't load saves: Server
    returned 401" alongside).
  - Authenticated + Server → render the snapshot list normally.

-}
savesSectionFor : Auth.AuthState -> SaveCompendiumUi -> Html Msg
savesSectionFor auth ui =
    case ui.destination of
        StorageDevice ->
            text ""

        StorageServer ->
            if Auth.isAuthenticated auth then
                savesSection ui

            else
                text ""


savesSection : SaveCompendiumUi -> Html Msg
savesSection ui =
    case ui.saves of
        SavesLoading ->
            div [ class "save-modal__list-empty" ]
                [ text "Loading saved compendiums…" ]

        SavesFailed _ ->
            -- Per user request: never surface "Couldn't load saves:
            -- Server returned 401" (or any other raw error string).
            -- For authenticated users with a real network failure
            -- this empty-state read is friendlier; the close-and-
            -- retry path is more useful than a raw error code.
            div [ class "save-modal__list-empty" ]
                [ text "No saved compendiums yet." ]

        SavesLoaded [] ->
            div [ class "save-modal__list-empty" ]
                [ text "No saved compendiums yet." ]

        SavesLoaded metas ->
            div [ class "save-modal__list-wrap" ]
                [ p [ class "save-modal__list-title" ]
                    [ text "Existing snapshots" ]
                , ul [ class "save-modal__list" ]
                    (List.map saveRow metas)
                ]


saveRow : SavedCompendiumMeta -> Html Msg
saveRow meta =
    li [ class "save-modal__row-item" ]
        [ span [ class "save-modal__row-name" ] [ text meta.name ]
        , div [ class "save-modal__row-actions" ]
            [ button
                [ class "icon-btn"
                , attribute "aria-label" "Overwrite"
                , onClick (SaveCompendiumOverwriteRequested meta.name)
                ]
                [ text "💾" ]
            ]
        ]


submitRow : Auth.AuthState -> SaveCompendiumUi -> Html Msg
submitRow auth ui =
    let
        blocked =
            ui.busy || serverNeedsSignIn auth ui

        tooltip =
            if serverNeedsSignIn auth ui then
                "Sign in to save your compendium to the eZpZ-dndZ server"

            else if ui.busy then
                "Saving…"

            else
                case ui.destination of
                    StorageServer ->
                        "Save to the eZpZ-dndZ server"

                    StorageDevice ->
                        "Save the compendium to a file on this device"
    in
    div [ class "save-modal__buttons" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick SaveCompendiumSubmit
            , disabled blocked
            , Tooltips.attr tooltip
            ]
            [ text "Save" ]
        , button
            [ class "action-btn"
            , onClick SaveCompendiumClose
            ]
            [ text "Close" ]
        ]
