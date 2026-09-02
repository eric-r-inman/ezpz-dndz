module Update.ActionGroups exposing (toggle)

{-| Collapse / expand handler for the Actions column's trigger
groups.

The groups carry no editable state — each body re-renders from
the model — so the handler just flips the matching flag. Any
number may be collapsed at once, which is why these live beside
`surface` rather than inside it.

@docs toggle

-}

import Model exposing (Model)
import Msg exposing (ActionGroup(..), Msg)
import Ui.ActionGroups exposing (ActionGroups)


toggle : ActionGroup -> Model -> ( Model, Cmd Msg )
toggle group model =
    ( { model | actionGroups = flip group model.actionGroups }, Cmd.none )


flip : ActionGroup -> ActionGroups -> ActionGroups
flip group groups =
    case group of
        CompendiumGroup ->
            { groups | compendium = not groups.compendium }

        EncounterGroup ->
            { groups | encounter = not groups.encounter }

        CreatureGroup ->
            { groups | creature = not groups.creature }
