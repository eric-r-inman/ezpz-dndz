module Update.Concentration exposing (savePrompts)

{-| The prompt for the Constitution save a concentrating creature
owes after damage.

@docs savePrompts

-}

import Effects
import Encounter.Concentration as Concentration
import Model exposing (Model)
import Msg exposing (Msg)
import Ui.Toast exposing (ToastKind(..))
import Update.Toast


{-| The pass `Main.update` runs after every message. Damage reaches
the encounter through many handlers, so the check compares the
encounter before and after rather than hooking each one.
-}
savePrompts : Msg -> Model -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
savePrompts msg before ( after, cmd ) =
    if Effects.couldDealDamage msg then
        Concentration.savesOwed before.encounter after.encounter
            |> List.foldl prompt ( after, cmd )

    else
        ( after, cmd )


prompt : Concentration.SaveOwed -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
prompt owed ( model, cmd ) =
    Update.Toast.push ToastSuccess
        (owed.name
            ++ " makes a DC "
            ++ String.fromInt owed.dc
            ++ " Constitution save to keep concentrating."
        )
        model
        |> Tuple.mapSecond (\toastCmd -> Cmd.batch [ cmd, toastCmd ])
