module Update.Toast exposing (push, pushWith, dismiss)

{-| Transient-toast helpers used by every Update branch that needs
to surface a success / error message to the user.

A toast is just an entry in `model.toasts` plus a `Process.sleep`
Cmd that dispatches `ToastDismiss` after `Ui.Toast.duration` ms.
The id allocator on `model.nextToastId` keeps each entry uniquely
addressable so dismissal removes the right one.

@docs push, pushWith, dismiss

-}

import Model exposing (Model)
import Msg exposing (Msg(..))
import Process
import Task
import Ui.Toast as ToastUi exposing (ToastKind)


{-| Push a transient success / error toast. The toast renders
immediately and a `Process.sleep` Cmd schedules its dismissal so
the toast list cleans up on its own without per-frame timer work.
-}
push : ToastKind -> String -> Model -> ( Model, Cmd Msg )
push kind message model =
    let
        toast =
            { id = model.nextToastId, kind = kind, message = message }
    in
    ( { model
        | toasts = model.toasts ++ [ toast ]
        , nextToastId = model.nextToastId + 1
      }
    , Process.sleep ToastUi.duration
        |> Task.perform (\_ -> ToastDismiss toast.id)
    )


{-| Push a toast and continue with another Cmd. Useful when a Msg
handler wants to announce success AND dispatch follow-up work in
one move (e.g. a "Saved" toast plus a re-fetch of the persisted
state).
-}
pushWith : ToastKind -> String -> Cmd Msg -> Model -> ( Model, Cmd Msg )
pushWith kind message extraCmd model =
    let
        ( m, toastCmd ) =
            push kind message model
    in
    ( m, Cmd.batch [ toastCmd, extraCmd ] )


{-| Remove the toast with the given id from the model.
-}
dismiss : Int -> Model -> ( Model, Cmd Msg )
dismiss id model =
    ( { model | toasts = List.filter (\t -> t.id /= id) model.toasts }
    , Cmd.none
    )
