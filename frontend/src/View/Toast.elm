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
import View.Tooltips as Tooltips


{-| The toast stack lives in its own `aria-live` region so screen
readers announce new messages as they appear. `polite` is the
default — error toasts get `assertive` further down so urgent
problems interrupt whatever the reader is currently saying. The
stack container is always present in the DOM (the empty-list
branch still renders the container) so SR clients have a stable
anchor to observe; without that, a freshly-created live region
won't be announced consistently.
-}
list : List Toast -> Html Msg
list toasts =
    div
        [ class "toast-stack"
        , attribute "role" "region"
        , attribute "aria-live" "polite"
        , attribute "aria-label" "Notifications"
        ]
        (List.map one toasts)


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
    div
        [ class toastClass
        , attribute "role"
            (case toast.kind of
                ToastError ->
                    "alert"

                ToastSuccess ->
                    "status"
            )
        , attribute "aria-live"
            (case toast.kind of
                ToastError ->
                    "assertive"

                ToastSuccess ->
                    "polite"
            )
        ]
        [ span [ class "toast__icon" ] [ text icon ]
        , span [ class "toast__msg" ] [ text toast.message ]
        , button
            [ class "toast__dismiss"
            , onClick (ToastDismiss toast.id)
            , Tooltips.attr Tooltips.toastDismiss
            , attribute "aria-label" "Dismiss notification"
            ]
            [ text "×" ]
        ]
