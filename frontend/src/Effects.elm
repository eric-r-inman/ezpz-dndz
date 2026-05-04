module Effects exposing
    ( cardId, scrollActiveIntoView
    , autoRollCmdsFor
    , pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
    , fetchMe, cmdForRoute
    , saveExpression, saveSource
    )

{-| Cmd-emitting helpers for the application.

Centralized here so per-feature `Update/*` modules can call into
them without importing `Main.elm` (which would be a cycle: Main
imports Update.Foo, Update.Foo would import Main).

Each function in this module has the shape `... -> Cmd Msg` (or
`... -> Model -> Model` for the dice-history push, which mutates
state but is conceptually part of the same "roll lands" flow).

Imports `Msg` for the constructors that Cmds dispatch back into,
and `Model` for the small set of model-level helpers. Doesn't
import any `Update/*` module — the dependency arrow points one
way: Update modules → Effects.

@docs cardId, scrollActiveIntoView
@docs autoRollCmdsFor
@docs pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
@docs fetchMe, cmdForRoute

-}

import Browser.Dom
import Dice
import Encounter
import Http
import Json.Decode as Decode
import Model exposing (Model)
import Msg exposing (MeInfo, Msg(..))
import Route exposing (Route(..))
import Task



-- ── DOM IDS + SCROLL ─────────────────────────────────────────────────────────


{-| Stable HTML id for the per-creature card. Used by
`scrollActiveIntoView` to look the card up via
`Browser.Dom.getElement`.
-}
cardId : String -> String
cardId name =
    "creature-card-" ++ slugifyName name


slugifyName : String -> String
slugifyName name =
    name
        |> String.toList
        |> List.map
            (\c ->
                if Char.isAlphaNum c then
                    c

                else
                    '_'
            )
        |> String.fromList


{-| Compose `Browser.Dom.getViewport` and
`Browser.Dom.getElement` to scroll the named creature card into
view if its bottom edge is below the viewport. Result lands in
`ActiveCardScrollChecked`, which is a no-op handler (we don't
care whether it succeeded — failure just means the card wasn't
in the DOM yet, which is benign).
-}
scrollActiveIntoView : String -> Cmd Msg
scrollActiveIntoView name =
    Task.map2
        (\viewport element ->
            let
                cardBottom =
                    element.element.y + element.element.height

                viewportBottom =
                    viewport.viewport.y + viewport.viewport.height

                bottomMargin =
                    16

                overflow =
                    cardBottom - (viewportBottom - bottomMargin)
            in
            if overflow > 0 then
                Browser.Dom.setViewport
                    viewport.viewport.x
                    (viewport.viewport.y + overflow)

            else
                Task.succeed ()
        )
        Browser.Dom.getViewport
        (Browser.Dom.getElement (cardId name))
        |> Task.andThen identity
        |> Task.attempt ActiveCardScrollChecked



-- ── AUTO-ROLL SAVES ──────────────────────────────────────────────────────────


{-| Build a list of Cmds that fire auto-roll saves for one
creature in one turn-phase. Each result lands in
`ConditionSaveLanded`, which applies the success / failure
logic and updates the dice history.

`mode` filters: only conditions whose `saveToEnd.autoRoll`
matches `mode` produce a Cmd. The two phases (`AutoRollAtBegin`
and `AutoRollAtEnd`) are fired separately — see the `NextTurn`
update branch.

Returns `[]` when the named creature isn't in the queue or has
no matching auto-roll saves, which is the common case.

-}
autoRollCmdsFor : Encounter.AutoRollMode -> String -> Encounter.Encounter -> List (Cmd Msg)
autoRollCmdsFor mode name enc =
    enc.creatures
        |> List.filter (\c -> c.name == name)
        |> List.concatMap
            (\c ->
                List.filterMap (autoRollCmdForCondition mode c.name) c.conditions
            )


autoRollCmdForCondition : Encounter.AutoRollMode -> String -> Encounter.Condition -> Maybe (Cmd Msg)
autoRollCmdForCondition mode bearer cond =
    case cond.saveToEnd of
        Just spec ->
            if spec.autoRoll == mode then
                Just
                    (Dice.rollCmd
                        (ConditionSaveLanded bearer cond.id spec.dc True)
                        (saveSource cond bearer spec)
                        (saveExpression spec.bonus)
                    )

            else
                Nothing

        Nothing ->
            Nothing


{-| Source label for save-to-end rolls: "Save: WIS DC 13 →
Brakka". The history reads informatively without the GM
having to remember which condition the save was for.
-}
saveSource : Encounter.Condition -> String -> Encounter.SaveToEnd -> Dice.Source
saveSource cond target spec =
    { feature =
        "Save: " ++ spec.ability ++ " DC " ++ String.fromInt spec.dc ++ " (" ++ cond.name ++ ")"
    , target = Just target
    }


{-| Build a `1d20 + bonus` expression for a save roll. Bonus
may be 0; in that case `expressionToString` will render just
"1d20".
-}
saveExpression : Int -> Dice.Expression
saveExpression bonus =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = bonus
    , damageType = Nothing
    }



-- ── DICE HISTORY ─────────────────────────────────────────────────────────────


{-| Land one roll into the dice history. Single chokepoint so
the "unread" indicator on the encounter-controls Roll button
stays in sync — every Cmd that returns a Roll funnels through
here.

`unread = True` only when the modal is closed at land time.
When the modal is already open, the user can already see the
roll, so no indicator is needed.

-}
pushDiceRoll : Dice.Roll -> Model -> Model
pushDiceRoll roll model =
    let
        d =
            model.dice
    in
    { model
        | dice =
            { d
                | history = Dice.push roll d.history
                , unread =
                    if d.open then
                        d.unread

                    else
                        True
            }
    }


{-| GET the persisted dice history. Result lands in
`DiceHistoryLoaded`.
-}
fetchDiceHistory : Cmd Msg
fetchDiceHistory =
    Http.get
        { url = "/api/dice/history"
        , expect = Http.expectJson DiceHistoryLoaded (Decode.list Dice.decodeRoll)
        }


{-| POST a fresh roll to the server's history endpoint. The
response body is the new (truncated) list, which we use to
overwrite the local view in `DicePersistResponse`.
-}
persistDiceRoll : Dice.Roll -> Cmd Msg
persistDiceRoll roll =
    Http.post
        { url = "/api/dice/history"
        , body = Http.jsonBody (Dice.encodeRoll roll)
        , expect = Http.expectJson DicePersistResponse (Decode.list Dice.decodeRoll)
        }


{-| DELETE the persisted history. Wraps `Http.request` because
elm/http doesn't ship an `Http.delete` shorthand.
-}
clearDiceHistory : Cmd Msg
clearDiceHistory =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/dice/history"
        , body = Http.emptyBody
        , expect = Http.expectWhatever DiceClearResponse
        , timeout = Nothing
        , tracker = Nothing
        }



-- ── /me ──────────────────────────────────────────────────────────────────────


fetchMe : Cmd Msg
fetchMe =
    Http.get
        { url = "/me"
        , expect = Http.expectJson GotMe meDecoder
        }


meDecoder : Decode.Decoder MeInfo
meDecoder =
    Decode.map2 MeInfo
        (Decode.field "name" Decode.string)
        (Decode.field "auth_enabled" Decode.bool)


cmdForRoute : Route -> Cmd Msg
cmdForRoute route =
    case route of
        Me ->
            fetchMe

        _ ->
            Cmd.none
