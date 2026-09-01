module Update.PanelDrawer exposing (clearCreature, soleOpen)

{-| Keeps the Actions column's drawer showing one panel.

Its candidates live in separate fields rather than in one ADT —
the dice roller's substate has to outlive a close, and the pin
and the XP panel's open flag have not been folded in yet (see
the straggler entry in `tasks.org`) — so the invariant the
`Surface` ADT gets from its type has to be enforced by hand
here. Whichever of those fields just became set wins and the
rest are cleared, centrally, because an opener added later
would forget.

A staged Reset / Clear is deliberately not one of them: it
interrupts rather than replaces, so `View.PanelDrawer.current`
gives it precedence and hands the drawer back when it clears.

Only drawer-eligible surfaces count: a card's note editor is a
`Surface` too, and opening one must not unpin a stat block.

@docs clearCreature, soleOpen

-}

import Model exposing (Model)
import Msg exposing (Msg)


clearCreature : Model -> ( Model, Cmd Msg )
clearCreature model =
    ( { model | panelCreaturePin = Nothing }, Cmd.none )


soleOpen : Model -> Model -> Model
soleOpen before after =
    let
        closeDice m =
            { m | dice = closedDice m.dice }

        closedDice dice =
            { dice | open = False }

        drawerSurface m =
            Maybe.map Model.isDrawerSurface m.surface == Just True
    in
    if not before.dice.open && after.dice.open then
        { after | surface = Nothing, panelCreaturePin = Nothing, xpFilterOpen = False }

    else if not (drawerSurface before) && drawerSurface after then
        closeDice { after | panelCreaturePin = Nothing, xpFilterOpen = False }

    else if before.panelCreaturePin /= after.panelCreaturePin && after.panelCreaturePin /= Nothing then
        closeDice { after | surface = Nothing, xpFilterOpen = False }

    else if not before.xpFilterOpen && after.xpFilterOpen then
        closeDice { after | surface = Nothing, panelCreaturePin = Nothing }

    else
        after
