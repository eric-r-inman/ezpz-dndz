module Effects exposing
    ( cardId, compendiumRowId, scrollActiveIntoView, scrollCompendiumRowIntoView
    , drawerStackId, drawerPanelId, scrollDrawerPanelIntoView, scrollDrawerIndex
    , autoRollCmdsFor
    , pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
    , fetchMe, cmdForRoute
    , persistEncounterFor, persistDiceHistoryFor, persistCompendiumFor, persistEncounterSavesFor
    , compendiumChanged, shouldPersistAfter, shouldBroadcastAfter
    , postCompendiumCreature, putCompendiumCreature, deleteCompendiumCreature
    , importCompendiumBundle, clearCompendiumCreatures, resetCompendium
    , changePassword, compendiumListId, encounterPanelBodyId, fetchAuthMe, fetchConditionPresets, fetchLoreGroups, fetchSaveChainPresets, fetchTreasureProfiles, fetchTreasureTable, pushIncomingDiceRoll, putConditionPresets, putLoreGroups, putSaveChainPresets, putTreasureProfiles, putTreasureTable, rechargeRollCmd, rechargeRollCmdsFor, saveExpression, saveSource, submitLogin, submitLogout, submitRegister, updateProfile
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

@docs cardId, compendiumRowId, scrollActiveIntoView, scrollCompendiumRowIntoView
@docs drawerStackId, drawerPanelId, scrollDrawerPanelIntoView, scrollDrawerIndex
@docs autoRollCmdsFor
@docs pushDiceRoll, persistDiceRoll, fetchDiceHistory, clearDiceHistory
@docs fetchMe, cmdForRoute
@docs persistEncounterFor, persistDiceHistoryFor, persistCompendiumFor, persistEncounterSavesFor
@docs compendiumChanged, shouldPersistAfter, shouldBroadcastAfter
@docs postCompendiumCreature, putCompendiumCreature, deleteCompendiumCreature
@docs importCompendiumBundle, clearCompendiumCreatures, resetCompendium

-}

import Auth
import Browser.Dom
import Compendium
import Compendium.Group
import Compendium.GroupWire
import Compendium.Wire
import Dice
import Dict exposing (Dict)
import Encounter
import Encounter.RandomEncounter.Lore
import Encounter.RandomEncounter.Lore.Wire
import Encounter.SaveChain
import Encounter.SaveChain.Wire
import Encounter.Treasure exposing (TreasureTable)
import Encounter.Treasure.TableWire
import Encounter.Wire
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Model exposing (Model)
import Msg exposing (MeInfo, Msg(..))
import Ports
import Process
import Route exposing (Route(..))
import Task
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Condition
import Ui.Condition.Wire



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


{-| DOM id of the compendium page's scrollable creature list.
-}
compendiumListId : String
compendiumListId =
    "compendium-list"


{-| Stable HTML id for one compendium list row, keyed by the
creature's compendium id.
-}
compendiumRowId : String -> String
compendiumRowId id =
    "compendium-row-" ++ id


{-| DOM id of the drawer column's scroll container. The stack
scrolls independently of the page, so bringing a panel into view
means moving this element's viewport rather than the window's.
-}
drawerStackId : String
drawerStackId =
    "drawer-stack"


{-| Stable id for one drawer panel, keyed by its position in the
stack. Position is what a click on a panel's own chrome already
identifies it by, so nothing has to carry an identity of its own.
-}
drawerPanelId : Int -> String
drawerPanelId index =
    "drawer-panel-" ++ String.fromInt index


{-| Scroll the drawer panel at `index` into view when it sits
outside the stack's visible region, leaving one that already fits
alone. A newly opened panel lands at the bottom of a stack that
may already be taller than the column, so without this the only
feedback for opening one is a scrollbar that got shorter.

Same geometry as `scrollActiveIntoView`. Failure means the panel
or the stack isn't in the DOM yet, which is benign.

-}
scrollDrawerPanelIntoView : Int -> Cmd Msg
scrollDrawerPanelIntoView index =
    Task.map3
        (\containerElement panelElement containerVp ->
            let
                margin =
                    8

                overflowBelow =
                    (panelElement.element.y + panelElement.element.height)
                        - (containerElement.element.y
                            + containerElement.element.height
                            - margin
                          )

                overflowAbove =
                    (containerElement.element.y + margin) - panelElement.element.y
            in
            if overflowBelow > 0 then
                Browser.Dom.setViewportOf
                    drawerStackId
                    containerVp.viewport.x
                    (containerVp.viewport.y + overflowBelow)

            else if overflowAbove > 0 then
                Browser.Dom.setViewportOf
                    drawerStackId
                    containerVp.viewport.x
                    (containerVp.viewport.y - overflowAbove)

            else
                Task.succeed ()
        )
        (Browser.Dom.getElement drawerStackId)
        (Browser.Dom.getElement (drawerPanelId index))
        (Browser.Dom.getViewportOf drawerStackId)
        |> Task.andThen identity
        |> Task.attempt (always NoOp)


{-| Scroll the panel at `index` into view, or do nothing when
there is no panel to scroll to.
-}
scrollDrawerIndex : Maybe Int -> Cmd Msg
scrollDrawerIndex =
    Maybe.map scrollDrawerPanelIntoView >> Maybe.withDefault Cmd.none


{-| Scroll a compendium list row to the top region of the list.
Fired once, after the library loads in a tab whose URL names a
creature — an alphabetically late creature would otherwise be
selected but out of sight. Failure means the row isn't in the
DOM (filtered out, or an unknown id), which is benign.
-}
scrollCompendiumRowIntoView : String -> Cmd Msg
scrollCompendiumRowIntoView creatureId =
    Task.map3
        (\containerElement rowElement containerVp ->
            Browser.Dom.setViewportOf
                compendiumListId
                containerVp.viewport.x
                (containerVp.viewport.y
                    + rowElement.element.y
                    - containerElement.element.y
                    - 16
                )
        )
        (Browser.Dom.getElement compendiumListId)
        (Browser.Dom.getElement (compendiumRowId creatureId))
        (Browser.Dom.getViewportOf compendiumListId)
        |> Task.andThen identity
        |> Task.attempt (always NoOp)


{-| Scroll the named creature card into view if it sits outside
the encounter panel's visible region. Two cases:

  - Card's bottom is past the panel's bottom edge → scroll _down_
    by the overflow. Covers the "turn moved past where I was
    looking" case.
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
the "unread" indicator on the Actions column's Roll button
stays in sync — every Cmd that returns a Roll funnels through
here.

`unread = True` only when the roller is closed at land time.
When it is already open, the user can see the roll, so no
indicator is needed.

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
                    if Model.drawerHas Model.diceLens model then
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



-- ── /api/lore-groups + /api/condition-presets ────────────────────────────────


{-| GET the caller's saved Lore groups. The server returns
`null` when the user has nothing persisted yet — the
`Decode.oneOf` here folds that into an empty list so the caller
doesn't have to special-case it.
-}
fetchLoreGroups : Cmd Msg
fetchLoreGroups =
    Http.get
        { url = "/api/lore-groups"
        , expect =
            Http.expectJson LoreGroupsLoaded
                (Decode.oneOf
                    [ Decode.null []
                    , Encounter.RandomEncounter.Lore.Wire.decodeGroups
                    ]
                )
        }


{-| PUT the caller's full Lore-group list, replacing whatever
the server held. Response body is the body we sent — we don't
read it; failure raises a toast via `LoreGroupsPersisted` so the
GM knows the change didn't make it server-side.
-}
putLoreGroups : List Encounter.RandomEncounter.Lore.Group -> Cmd Msg
putLoreGroups groups =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/lore-groups"
        , body =
            Http.jsonBody
                (Encounter.RandomEncounter.Lore.Wire.encodeGroups groups)
        , expect = Http.expectWhatever LoreGroupsPersisted
        , timeout = Nothing
        , tracker = Nothing
        }


{-| GET the caller's saved condition presets. The payload is
passed through as a raw `Decode.Value` because the typed
preset record type lives in `Ui.Condition` (which imports `Msg`,
so adding a typed Msg variant would cycle). The `Main` handler
decodes via `Ui.Condition.Wire.decodePresets` before adopting.
-}
fetchConditionPresets : Cmd Msg
fetchConditionPresets =
    Http.get
        { url = "/api/condition-presets"
        , expect = Http.expectJson ConditionPresetsLoaded Decode.value
        }


{-| PUT the caller's full condition-preset map.
-}
putConditionPresets : Dict String Ui.Condition.ConditionPreset -> Cmd Msg
putConditionPresets presets =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/condition-presets"
        , body = Http.jsonBody (Ui.Condition.Wire.encodePresets presets)
        , expect = Http.expectWhatever ConditionPresetsPersisted
        , timeout = Nothing
        , tracker = Nothing
        }



-- ── /api/save-chain-presets ──────────────────────────────────────────────────


{-| GET the caller's saved Save Chain presets. Payload is
returned as a raw `Decode.Value` for the same reason as
`fetchConditionPresets` — the typed record lives in
`Encounter.SaveChain`, which the `Msg` variant would cycle on
if we tried to name it directly. `Update.UserSync` decodes via
`Encounter.SaveChain.Wire.decodePresets` before adopting.
-}
fetchSaveChainPresets : Cmd Msg
fetchSaveChainPresets =
    Http.get
        { url = "/api/save-chain-presets"
        , expect = Http.expectJson SaveChainPresetsLoaded Decode.value
        }


{-| PUT the caller's full Save Chain preset map. Bundled +
user-authored entries are sent together — the server round-trips
the whole payload verbatim, and this lets the client survive a
purge of the bundled module without losing the copy the GM has
been iterating on locally.
-}
putSaveChainPresets : Dict String Encounter.SaveChain.SaveChain -> Cmd Msg
putSaveChainPresets presets =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/save-chain-presets"
        , body = Http.jsonBody (Encounter.SaveChain.Wire.encodePresets presets)
        , expect = Http.expectWhatever SaveChainPresetsPersisted
        , timeout = Nothing
        , tracker = Nothing
        }



-- ── /api/treasure-table ──────────────────────────────────────────────────────


{-| GET the caller's saved treasure table. Returns `Nothing`
when the server has no record yet, in which case the
generator falls back to `Encounter.Treasure.bundledTable`.
-}
fetchTreasureTable : Cmd Msg
fetchTreasureTable =
    Http.get
        { url = "/api/treasure-table"
        , expect =
            Http.expectJson TreasureTableLoaded
                (Decode.oneOf
                    [ Decode.null Nothing
                    , Decode.map Just Encounter.Treasure.TableWire.decodeTable
                    ]
                )
        }


{-| PUT the caller's full treasure table.
-}
putTreasureTable : TreasureTable -> Cmd Msg
putTreasureTable table =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/treasure-table"
        , body =
            Http.jsonBody (Encounter.Treasure.TableWire.encodeTable table)
        , expect = Http.expectWhatever TreasureTablePersisted
        , timeout = Nothing
        , tracker = Nothing
        }


{-| GET the caller's saved Treasure-roller settings profiles
("Tune your rolls" presets) as opaque JSON. The frontend decodes
the value into a `Dict String TreasureSettings`; null + decode
failures fall back to an empty dict.
-}
fetchTreasureProfiles : Cmd Msg
fetchTreasureProfiles =
    Http.get
        { url = "/api/treasure-profiles"
        , expect = Http.expectJson TreasureProfilesLoaded Decode.value
        }


{-| PUT the caller's full profile dict back to the server.
-}
putTreasureProfiles : Decode.Value -> Cmd Msg
putTreasureProfiles encoded =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/treasure-profiles"
        , body = Http.jsonBody encoded
        , expect = Http.expectWhatever TreasureProfilesPersisted
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



-- ── /api/compendium/* ────────────────────────────────────────────────────────


{-| POST a freshly created creature. The response body is the
stored creature (with its server-assigned id); it lands in
`CompendiumEditSubmitResponse`.
-}
postCompendiumCreature : Compendium.Creature -> Cmd Msg
postCompendiumCreature creature =
    Http.post
        { url = "/api/compendium/creatures"
        , body = Http.jsonBody (Compendium.Wire.encodeDraft creature)
        , expect = Http.expectJson CompendiumEditSubmitResponse Compendium.Wire.decodeCreature
        }


{-| PUT an edited creature over its existing id. Response lands
in `CompendiumEditSubmitResponse`, same as the create path.
-}
putCompendiumCreature : String -> Compendium.Creature -> Cmd Msg
putCompendiumCreature id creature =
    Http.request
        { method = "PUT"
        , headers = []
        , url = "/api/compendium/creatures/" ++ id
        , body = Http.jsonBody (Compendium.Wire.encodeCreature creature)
        , expect = Http.expectJson CompendiumEditSubmitResponse Compendium.Wire.decodeCreature
        , timeout = Nothing
        , tracker = Nothing
        }


{-| DELETE one creature by id. The id rides along in the Msg so
`CompendiumEditDeleteResponse` can clear it from selections.
-}
deleteCompendiumCreature : String -> Cmd Msg
deleteCompendiumCreature id =
    Http.request
        { method = "DELETE"
        , headers = []
        , url = "/api/compendium/creatures/" ++ id
        , body = Http.emptyBody
        , expect = Http.expectWhatever (CompendiumEditDeleteResponse id)
        , timeout = Nothing
        , tracker = Nothing
        }


{-| POST `/api/compendium/reset` — restore the bundled creature
set. The response body is the restored list, landing in
`CompendiumResetResponse`.
-}
resetCompendium : Cmd Msg
resetCompendium =
    Http.post
        { url = "/api/compendium/reset"
        , body = Http.emptyBody
        , expect =
            Http.expectJson CompendiumResetResponse
                (Decode.list Compendium.Wire.decodeCreature)
        }


{-| Import-from-file / load-snapshot path. Sends the **full**
body shape (`{ creatures, groups }`) so both the shared bestiary
and the caller's groups get replaced server-side in one wire
call. The response lands in `CompendiumImportResponse`, which
clears the dirty flag and refetches both stores.
-}
importCompendiumBundle : List Compendium.Creature -> List Compendium.Group.Group -> Cmd Msg
importCompendiumBundle creatures groups =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "creatures"
                      , Encode.list Compendium.Wire.encodeCreature creatures
                      )
                    , ( "groups"
                      , Encode.list Compendium.GroupWire.encodeGroup groups
                      )
                    ]
                )
        , expect =
            Http.expectJson CompendiumImportResponse
                (Decode.field "imported" Decode.int)
        }


{-| Clear-All / Clear-Selected wire path. Sends the **legacy**
bare-array body shape so the server's `import_compendium`
handler keeps groups untouched — a clear is about creatures
only. The response shape (`{ imported }`) is the same as
`importCompendiumBundle`, but the Msg is tagged so the frontend
dirty-flag semantics differ: Clear keeps dirty=True, file-import
clears it.
-}
clearCompendiumCreatures : List Compendium.Creature -> Cmd Msg
clearCompendiumCreatures creatures =
    Http.post
        { url = "/api/compendium/import"
        , body =
            Http.jsonBody (Encode.list Compendium.Wire.encodeCreature creatures)
        , expect =
            Http.expectJson CompendiumClearResponse
                (Decode.field "imported" Decode.int)
        }



-- ── DIFF-AND-PERSIST HELPERS ─────────────────────────────────────────────────
--
-- Used by the top-level update wrapper in `Main.elm`, which
-- diffs the model before / after each Msg and fires the matching
-- persist Cmd when a persistent slice changed.


persistEncounterFor : Auth.AuthState -> Encounter.Encounter -> Cmd Msg
persistEncounterFor auth encounter =
    case auth of
        Auth.AuthAuthenticated _ ->
            Encounter.Wire.persistEncounterCmd EncounterPersisted encounter

        Auth.AuthAnonymous ->
            Ports.persistLocalEncounter (Encounter.Wire.encodeEncounter encounter)

        Auth.AuthLoading ->
            Cmd.none


{-| Persist the full dice-history list to `localStorage` when
anonymous. Authenticated users hit `/api/dice/history` per-roll
via `Effects.persistDiceRoll` (the server appends + truncates,
and the response re-syncs the local view).
-}
persistDiceHistoryFor : Model -> Cmd Msg
persistDiceHistoryFor model =
    case model.auth of
        Auth.AuthAnonymous ->
            Ports.persistLocalDiceHistory
                (Encode.list Dice.encodeRoll model.dice.history.entries)

        _ ->
            Cmd.none


{-| Did the compendium DB change in a way that should be
persisted? Compare the loaded creature list and the per-user
groups dict; transient CompendiumDbLoading / CompendiumDbFailed
transitions don't trigger a write.
-}
compendiumChanged : Model -> Model -> Bool
compendiumChanged before after =
    loadedCreatures before.compendium.db
        /= loadedCreatures after.compendium.db
        || before.compendium.groups
        /= after.compendium.groups


loadedCreatures : CompendiumDb -> List Compendium.Creature
loadedCreatures db =
    case db of
        CompendiumDbLoaded inner ->
            Compendium.toList inner

        _ ->
            []


{-| Persist the full compendium snapshot (creatures + groups +
next-local-id counter) to `localStorage` when anonymous.
Authenticated users persist per-mutation via the existing
`/api/compendium/*` endpoints.
-}
persistCompendiumFor : Model -> Cmd Msg
persistCompendiumFor model =
    case model.auth of
        Auth.AuthAnonymous ->
            -- Snapshot only carries creatures the user authored or
            -- imported locally — bundled SRD creatures are always
            -- refetched from `/bundled-creatures.json` on boot,
            -- never stored client-side.  Filtering by `isBundled`
            -- keeps the snapshot small AND ensures stale bundled
            -- bytes can't shadow a corrected bundle after an app
            -- update.
            Ports.persistLocalCompendium
                (Compendium.Wire.encodeLocalCompendiumSnapshot
                    { creatures =
                        loadedCreatures model.compendium.db
                            |> List.filter (\c -> not c.isBundled)
                    , groups = Dict.values model.compendium.groups
                    , nextLocalId = model.nextLocalCreatureId
                    , bundledVersion = Compendium.Wire.currentBundledVersion
                    }
                )

        _ ->
            Cmd.none


persistEncounterSavesFor : Model -> Cmd Msg
persistEncounterSavesFor model =
    case model.auth of
        Auth.AuthAnonymous ->
            Ports.persistLocalEncounterSaves
                (Encounter.Wire.encodeLocalEncounterSaves model.localEncounterSaves)

        _ ->
            Cmd.none


shouldPersistAfter : Msg -> Bool
shouldPersistAfter msg =
    case msg of
        EncounterLoaded _ ->
            False

        EncounterPersisted _ ->
            False

        -- Auth probe response on an anonymous boot adopts the
        -- local-storage encounter directly into the model.  The
        -- diff would trigger a persist back into the same
        -- localStorage slot — idempotent but wasteful, so we skip
        -- it.
        AuthMeReceived _ ->
            False

        -- Login-time migration response only fires a toast and a
        -- clear-local port; the encounter itself is untouched, so
        -- there's nothing to persist here either.
        LocalEncounterMigrated _ _ ->
            False

        LocalCompendiumMigrated _ _ ->
            False

        -- The encounter just arrived from another tab via the
        -- BroadcastChannel; the originating tab already persisted
        -- (and already broadcast), so re-doing either from this
        -- tab would loop.
        EncounterFromOtherTab _ ->
            False

        _ ->
            True


{-| Whether to fire `broadcastEncounter` after this Msg has been
processed. Excludes the inbound side of the BroadcastChannel
(re-broadcasting receives would loop) and the QuickList tab's
own reception (it's read-only).
-}
shouldBroadcastAfter : Msg -> Bool
shouldBroadcastAfter msg =
    case msg of
        EncounterFromOtherTab _ ->
            False

        _ ->
            True
