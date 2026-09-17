module Update.Xp exposing (calculationsToggle, excludeToggle, scopeSet)

{-| Which creatures the encounter's XP total counts.

The scope itself is not panel state — it outlives a fold, so it
lives on the model, and so do the tally's exclusions for the same
reason.

@docs calculationsToggle, excludeToggle, scopeSet

-}

import Encounter.Xp exposing (XpScope)
import Model exposing (Model)
import Msg exposing (Msg)
import Set


{-| Picking a scope leaves the panel unfolded: the total it shows
is the reason to pick one, so folding on the pick would hide the
answer.
-}
scopeSet : XpScope -> Model -> ( Model, Cmd Msg )
scopeSet scope model =
    ( { model | xpScope = scope }, Cmd.none )


{-| Fold the tally that shows the total's working away or back.
-}
calculationsToggle : Model -> ( Model, Cmd Msg )
calculationsToggle model =
    ( { model | xpCalculationsOpen = not model.xpCalculationsOpen }
    , Cmd.none
    )


{-| Take a creature out of the tally's sum, or put it back.
-}
excludeToggle : String -> Model -> ( Model, Cmd Msg )
excludeToggle name model =
    ( { model
        | xpExcluded =
            if Set.member name model.xpExcluded then
                Set.remove name model.xpExcluded

            else
                Set.insert name model.xpExcluded
      }
    , Cmd.none
    )
