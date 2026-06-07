module Effects exposing
    ( cardId, scrollActiveIntoView
    , autoRollCmdsFor
    , pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
    , fetchMe, cmdForRoute
    , changePassword, encounterPanelBodyId, fetchAuthMe, pushIncomingDiceRoll, rechargeRollCmd, rechargeRollCmdsFor, saveExpression, saveSource, submitLogin, submitLogout, submitRegister, updateProfile
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
import Ports
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


{-| Scroll the named creature card into view if it sits outside
the encounter panel's visible region. Two cases:

  - Card's bottom is past the panel's bottom edge → scroll _down_
    by the overflow. Covers the "Next Turn moved past where I
    was looking" case.
  - Card's top is above the panel's top edge → scroll _up_ by
    the underflow. Covers the "round just wrapped and the active
    creature is now back at the top of the queue, which is above
    the viewport" case.

Cards already fully visible are left alone. Result lands in
`ActiveCardScrollChecked`, a no-op handler; failure means the
card or the container wasn't in the DOM yet, which is benign.

Math: bounding-client rects from `Browser.Dom.getElement` are in
_window_ coordinates and reflect current scroll position, so the
overflow / underflow calculations work against the panel's
element rect without having to manually offset by the panel's
scrollTop. The correction is then applied to the _panel's_
scrollTop via `Browser.Dom.setViewportOf`.

-}
scrollActiveIntoView : String -> Cmd Msg
scrollActiveIntoView name =
    Task.map3
        (\containerElement cardElement containerVp ->
            let
                cardTop =
                    cardElement.element.y

                cardBottom =
                    cardTop + cardElement.element.height

                containerTop =
                    containerElement.element.y

                containerBottom =
                    containerTop + containerElement.element.height

                topMargin =
                    16

                bottomMargin =
                    16

                overflowBelow =
                    cardBottom - (containerBottom - bottomMargin)

                overflowAbove =
                    (containerTop + topMargin) - cardTop
            in
            if overflowBelow > 0 then
                Browser.Dom.setViewportOf
                    encounterPanelBodyId
                    containerVp.viewport.x
                    (containerVp.viewport.y + overflowBelow)

            else if overflowAbove > 0 then
                Browser.Dom.setViewportOf
                    encounterPanelBodyId
                    containerVp.viewport.x
                    (containerVp.viewport.y - overflowAbove)

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


{-| Build a `Dice.rollCmd` for every expended recharge ability on
the named creature at the start of their turn. Each roll is a
plain `1d6`; the result lands in `RechargeRollLanded` which
re-checks the ability's `low` threshold and flips `ready=True`
when the d6 meets or exceeds it. Rolls land in the dice history
with a source label like "Recharge: Fire Breath → Smaug" so the
GM can read whether the engine made the check or not.

`abilityName` doubles as the lookup key when the roll lands; the
handler does an O(n) scan over the creature's `rechargeAbilities`
matching by name. Names within a creature are assumed unique
(SRD bestiary follows this); duplicates would mean both
abilities recharge together, which is harmless.

-}
rechargeRollCmdsFor : String -> Encounter.Encounter -> List (Cmd Msg)
rechargeRollCmdsFor name enc =
    enc.creatures
        |> List.filter (\c -> c.name == name)
        |> List.concatMap
            (\c ->
                List.filterMap (rechargeRollCmd c.name) c.rechargeAbilities
            )


rechargeRollCmd : String -> Encounter.RechargeAbility -> Maybe (Cmd Msg)
rechargeRollCmd creatureName ability =
    if ability.ready then
        Nothing

    else
        Just
            (Dice.rollCmd
                (RechargeRollLanded creatureName ability.name)
                { feature = "Recharge: " ++ ability.name, target = Just creatureName }
                rechargeExpression
            )


rechargeExpression : Dice.Expression
rechargeExpression =
    { dice = [ { count = 1, faces = 6, sign = Dice.Positive } ]
    , constant = 0
    , damageType = Nothing
    }


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

Also broadcasts the roll to peer tabs via the dice
BroadcastChannel so a stat block opened in its own tab and the
main encounter tab keep a single shared log. Peer tabs receive
the broadcast via `incomingDiceRoll` and run it through
[`pushIncomingDiceRoll`](#pushIncomingDiceRoll) — same model
mutation but without the broadcast Cmd, so we don't loop.

-}
pushDiceRoll : Dice.Roll -> Model -> ( Model, Cmd Msg )
pushDiceRoll roll model =
    let
        ( next, flashCmd ) =
            pushIncomingDiceRoll roll model
    in
    ( next
    , Cmd.batch
        [ flashCmd
        , Ports.broadcastDiceRoll (Dice.encodeRoll roll)
        ]
    )


{-| Same model mutation as [`pushDiceRoll`](#pushDiceRoll) but no
broadcast Cmd — used by the inbound BroadcastChannel handler so
receiving a peer's roll doesn't bounce it back across the channel
and create an echo loop.
-}
pushIncomingDiceRoll : Dice.Roll -> Model -> ( Model, Cmd Msg )
pushIncomingDiceRoll roll model =
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


updateProfile :
    { displayName : String }
    -> (Result Http.Error Auth.User -> Msg)
    -> Cmd Msg
updateProfile { displayName } toMsg =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/auth/me"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "display_name", Encode.string displayName ) ]
                )
        , expect = Http.expectJson toMsg Auth.userDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


changePassword :
    { currentPassword : String, newPassword : String }
    -> (Result Http.Error () -> Msg)
    -> Cmd Msg
changePassword { currentPassword, newPassword } toMsg =
    Http.post
        { url = "/api/auth/password"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "current_password", Encode.string currentPassword )
                    , ( "new_password", Encode.string newPassword )
                    ]
                )
        , expect = Http.expectWhatever toMsg
        }
