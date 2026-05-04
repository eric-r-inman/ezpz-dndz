module Ui.Toast exposing (Toast, ToastKind(..), duration)

{-| Transient success / error notification. Each toast carries
its own id so a delayed `ToastDismiss` Cmd lands on the right
one even if other toasts have shifted in/out of the list while
the timer was running.

@docs Toast, ToastKind, duration

-}


type alias Toast =
    { id : Int
    , kind : ToastKind
    , message : String
    }


type ToastKind
    = ToastSuccess
    | ToastError


{-| How long a toast stays on screen before its auto-dismiss
fires (milliseconds).
-}
duration : Float
duration =
    3500
