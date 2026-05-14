module Effects exposing
    ( cardId, scrollActiveIntoView
    , autoRollCmdsFor
    , pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
    , fetchMe, cmdForRoute
    , encounterPanelBodyId, fetchAuthMe, saveExpression, saveSource, submitLogin, submitLogout, submitRegister
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

import Auth
import Browser.Dom
import Dice
import Encounter
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model)
import Msg exposing (MeInfo, Msg(..))
import Process
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


{-| DOM id stamped onto the encounter panel's scrollable body
(=View.Workspace=). Cards live inside this scroll container, so
auto-scroll-to-active has to target it explicitly —
document-level setViewport doesn't reach an inner overflow-auto
div.
-}
encounterPanelBodyId : String
encounterPanelBodyId =
    "encounter-panel-body"


{-| Scroll the named creature card into view if (and only if) its
bottom edge is past the encounter panel's visible bottom edge.
Cards already fully visible — including those above the viewport
top — are left alone. Result lands in `ActiveCardScrollChecked`,
a no-op handler; failure means the card or the container wasn't
in the DOM yet, which is benign.

Math: bounding-client rects from `Browser.Dom.getElement` are in
_window_ coordinates and reflect current scroll position, so the
overflow calculation works against the panel's element rect
without having to manually offset by the panel's scrollTop. The
correction is then applied to the _panel's_ scrollTop via
`Browser.Dom.setViewportOf`.

-}
scrollActiveIntoView : String -> Cmd Msg
scrollActiveIntoView name =
    Task.map3
        (\containerElement cardElement containerVp ->
            let
                cardBottom =
                    cardElement.element.y + cardElement.element.height

                containerBottom =
                    containerElement.element.y + containerElement.element.height

                bottomMargin =
                    16

                overflow =
                    cardBottom - (containerBottom - bottomMargin)
            in
            if overflow > 0 then
                Browser.Dom.setViewportOf
                    encounterPanelBodyId
                    containerVp.viewport.x
                    (containerVp.viewport.y + overflow)

            else
                Task.succeed ()
        )
        (Browser.Dom.getElement encounterPanelBodyId)
        (Browser.Dom.getElement (cardId name))
        (Browser.Dom.getViewportOf encounterPanelBodyId)
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
pushDiceRoll : Dice.Roll -> Model -> ( Model, Cmd Msg )
pushDiceRoll roll model =
    let
        d =
            model.dice
    in
    ( { model
        | dice =
            { d
                | history = Dice.push roll d.history
                , unread =
                    if d.open then
                        d.unread

                    else
                        True
                , flashLatest = True
            }
      }
    , Process.sleep flashDurationMs
        |> Task.perform (\_ -> DiceLastTotalFlashCleared)
    )


{-| Duration in milliseconds for the panel-header
"last-roll-total" yellow blink. Should match the CSS
`animation-duration` on `.dice-last-total--flash`. Lives here
(rather than in `Update.Dice`) because `pushDiceRoll` is the
universal "a roll just landed" entry point, and putting the
flash trigger right alongside it means every roll source gets
the flash automatically without each handler remembering to
fire it.
-}
flashDurationMs : Float
flashDurationMs =
    700


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



-- ── /api/auth/* ──────────────────────────────────────────────────────────────


{-| Boot probe. Returns the current user when the session
cookie is good, 401 otherwise. The 401 path goes to
`AuthMeReceived (Err _)` and switches the model into
`AuthAnonymous`.
-}
fetchAuthMe : Cmd Msg
fetchAuthMe =
    Http.get
        { url = "/api/auth/me"
        , expect = Http.expectJson AuthMeReceived Auth.userDecoder
        }


submitLogin : { email : String, password : String } -> Cmd Msg
submitLogin { email, password } =
    Http.post
        { url = "/api/auth/login"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "email", Encode.string email )
                    , ( "password", Encode.string password )
                    ]
                )
        , expect = Http.expectJson AuthLoginResponse Auth.userDecoder
        }


submitRegister :
    { email : String, password : String, displayName : String }
    -> Cmd Msg
submitRegister { email, password, displayName } =
    Http.post
        { url = "/api/auth/register"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "email", Encode.string email )
                    , ( "password", Encode.string password )
                    , ( "display_name", Encode.string displayName )
                    ]
                )
        , expect = Http.expectJson AuthLoginResponse Auth.userDecoder
        }


submitLogout : Cmd Msg
submitLogout =
    Http.post
        { url = "/api/auth/logout"
        , body = Http.emptyBody
        , expect = Http.expectWhatever AuthLogoutDone
        }
