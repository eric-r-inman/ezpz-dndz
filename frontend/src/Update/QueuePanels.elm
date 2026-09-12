module Update.QueuePanels exposing (toggle)

{-| Open / close handlers for the encounter queue's reference
drop-downs.

They carry no editable state — each body re-renders from
`model.encounter` + `model.compendium.db` — so the handler just
flips the matching flag. Several may be open at once, which is
why these live beside `surface` rather than inside it.

@docs toggle

-}

import Model exposing (Model)
import Msg exposing (Msg, QueuePanel(..))
import Ui.QueuePanels exposing (QueuePanels)


toggle : QueuePanel -> Model -> ( Model, Cmd Msg )
toggle panel model =
    ( { model | queuePanels = flip panel model.queuePanels }, Cmd.none )


flip : QueuePanel -> QueuePanels -> QueuePanels
flip panel panels =
    case panel of
        LegendaryActionsPanel ->
            { panels | legendaryActions = not panels.legendaryActions }

        SpecialReactionsPanel ->
            { panels | specialReactions = not panels.specialReactions }

        SpellsPanel ->
            { panels | spells = not panels.spells }
