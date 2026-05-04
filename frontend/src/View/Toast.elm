module View.Toast exposing (list)

{-| Render the toast stack — one entry per active toast. Each toast
has a kind (success / error), a message, and a dismiss button that
fires `ToastDismiss`. An empty list renders nothing rather than an
empty container so the page never reserves layout space for toasts
that aren't there.
-}

import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Toast exposing (Toast, ToastKind(..))


list : List Toast -> Html Msg
list toasts =
    if List.isEmpty toasts then
        text ""

    else
        div [ class "toast-stack" ] (List.map one toasts)


one : Toast -> Html Msg
one toast =
    let
        toastClass =
            case toast.kind of
                ToastSuccess ->
                    "toast toast--success"

                ToastError ->
                    "toast toast--error"

        icon =
            case toast.kind of
                ToastSuccess ->
                    "✓"

                ToastError ->
                    "⚠"
    in
    div [ class toastClass, attribute "role" "status" ]
        [ span [ class "toast__icon" ] [ text icon ]
        , span [ class "toast__msg" ] [ text toast.message ]
        , button
            [ class "toast__dismiss"
            , onClick (ToastDismiss toast.id)
            , title "Dismiss"
            , attribute "aria-label" "Dismiss notification"
            ]
            [ text "×" ]
        ]
