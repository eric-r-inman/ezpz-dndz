port module Ports exposing
    ( savePreferences, persistLocalEncounter
    , broadcastDiceRoll, broadcastEncounter, broadcastPanelShow, clearLocalCompendium, clearLocalEncounter, clearLocalEncounterSaves, copyToClipboard, incomingDiceRoll, incomingEncounter, incomingPanelShow, openCompendiumTab, persistLocalCompendium, persistLocalConditionPresets, persistLocalDiceHistory, persistLocalEncounterSaves, persistLocalParty, persistLocalSaveChainPresets, persistLocalTimerPresets, persistLocalUserLoreGroups, persistLocalUserTreasureTable
    )

{-| Outbound ports for the JS host to consume.

  - `savePreferences` — the AppBar settings popover fires this
    whenever the user picks a new theme (or, eventually, density /
    sound / etc.). The JS side in `index.html` listens and writes
    the value to `localStorage` plus mirrors it to
    `<html data-theme>` so the next reload's pre-Elm FOUC script
    picks it up.
  - `persistLocalEncounter` — used by anonymous-mode sessions to
    keep the live encounter in `localStorage` instead of the
    server. The Elm side hands over the same JSON shape the
    server would receive on `PUT /api/encounter`; JS just stores
    it under a fixed key.

When `/api/me/preferences` lands, `savePreferences` will become a
no-op fallback for unauthenticated sessions; the canonical
persistence path will be HTTP.

@docs savePreferences, persistLocalEncounter

-}

import Json.Decode as D
import Json.Encode as E


{-| Send a preference snapshot to the JS host. The Elm side is
responsible for serializing the relevant fields; the JS side
just persists what arrives. Today the only field is `theme`.
-}
port savePreferences : E.Value -> Cmd msg


{-| Persist the live encounter into `localStorage` (anonymous
mode). The payload is the encoded `Encounter` — same shape the
server's `PUT /api/encounter` would receive — so a future
authenticated migration can replay it without translation.
-}
port persistLocalEncounter : E.Value -> Cmd msg


{-| Remove the locally-persisted encounter from `localStorage`.
Fired after a successful login-time migration: the anonymous
encounter has been copied into a named server save so the local
copy is no longer load-bearing, and we don't want to migrate the
same encounter again on the next reload.

Passes a unit payload so the JS side knows when to fire — the
value itself is ignored.

-}
port clearLocalEncounter : () -> Cmd msg


{-| Persist the dice-history entries into `localStorage` for
anonymous sessions. Mirrors the server-side `/api/dice/history`
shape: a JSON array of encoded rolls. Sign-in deliberately does
NOT migrate this — per the launch plan, anonymous roll history is
discarded once the user promotes to an authenticated session
(the server's history takes over).
-}
port persistLocalDiceHistory : E.Value -> Cmd msg


{-| Persist the anonymous compendium snapshot (creatures + groups

  - next-local-id counter) into `localStorage` on every CRUD edit
    in an anonymous session. The shape is

    { "creatures": [...], "groups": [...], "next\_local\_id": N }

mirroring the server's export wire format with one extra field for
the local-id counter so a reload doesn't reuse ids.

-}
port persistLocalCompendium : E.Value -> Cmd msg


{-| Drop the locally-persisted compendium after a successful
login-time migration. Same role as `clearLocalEncounter`.
-}
port clearLocalCompendium : () -> Cmd msg


{-| Persist the anonymous named-encounter-saves dict
(`{ name → { encounter, created_at, updated_at } }`) to
localStorage. Fired by `Update.Save` / `Update.Load` after any
local mutation.
-}
port persistLocalEncounterSaves : E.Value -> Cmd msg


{-| Drop the whole anonymous named-encounter-saves dict. Fired
after a successful login-time migration that has copied every
local save into the server.
-}
port clearLocalEncounterSaves : () -> Cmd msg


{-| Persist the user-named condition presets dict to
`localStorage.conditionPresets`. Body is an object whose keys
are the preset names and whose values are the encoded preset
records — see `Ui.Condition.Wire.encodePresets`. Anonymous and
authenticated sessions both use this same client-side store
today; if a server-side store is added later, the encoded
payload shape can be reused as the wire body.
-}
port persistLocalConditionPresets : E.Value -> Cmd msg


{-| Persist the user-named timer presets dict to
`localStorage.timerPresets`. Same dual-session usage and wire
contract as `persistLocalConditionPresets` but for the
Timer-setup modal — see `Ui.Timer.Wire.encodePresets`.
-}
port persistLocalTimerPresets : E.Value -> Cmd msg


{-| Persist the Save Chain presets dict to
`localStorage.saveChainPresets`. Body shape matches
`Encounter.SaveChain.Wire.encodePresets` — `{ name → SaveChain }`.
Fires on every Save / Delete in the Save Chain modal.
-}
port persistLocalSaveChainPresets : E.Value -> Cmd msg


{-| Copy the supplied string to the system clipboard via
`navigator.clipboard.writeText`. Fire-and-forget: the JS side
swallows rejections (Firefox's clipboard API can refuse a write
that isn't part of a "trusted" click gesture, and there's
nothing sensible for the Elm side to do about it). Used by the
Save Chain modal's "Export as Elm" button to drop a
copy-pasteable `SaveChain` value into the GM's clipboard for
promotion into `Encounter.SaveChain.Bundled.elm`.
-}
port copyToClipboard : String -> Cmd msg


{-| Persist the party roster — the level-per-character list
shared by the CR Calculator and Random Encounter modals — to
`localStorage.party`. Body is `{ "members": [...],
"next_id": N }` so the auto-increment id counter survives a
reload alongside the actual members. Anonymous and
authenticated sessions both use this client-side store today;
a future server-side `/api/me/preferences` can reuse the same
payload shape.
-}
port persistLocalParty : E.Value -> Cmd msg


{-| Persist user-authored Lore groups to
`localStorage.userLoreGroups`. Body is a JSON array of group
records (see `Encounter.RandomEncounter.Lore.Wire`). Fires on
every Save / Delete in the Create/Edit Group modal's Lore
section.
-}
port persistLocalUserLoreGroups : E.Value -> Cmd msg


{-| Persist the user's singular treasure table to
`localStorage.userTreasureTable`. Body is the full table
encoded by [`Encounter.Treasure.TableWire`](Encounter-Treasure-TableWire).
Fires on every edit in the Treasure Table editor.
-}
port persistLocalUserTreasureTable : E.Value -> Cmd msg


{-| Broadcast a freshly-landed `Dice.Roll` to every other tab of
this app open in the same browser profile. JS bridges the value
through a `BroadcastChannel("ezpz-dndz-dice")`; peer tabs receive
it via [`incomingDiceRoll`](#incomingDiceRoll) and push it into
their own dice history. Without this, the stat-block page (opened
in its own tab) would log rolls only into its own dice modal —
the main encounter tab would never see them. The originating tab
is NOT notified by the channel, so no echo filtering is needed.
-}
port broadcastDiceRoll : E.Value -> Cmd msg


{-| Subscription for `Dice.Roll` values that another tab broadcast
via [`broadcastDiceRoll`](#broadcastDiceRoll). The receiving tab
should push the decoded roll into its dice history without
re-persisting or re-broadcasting (the originating tab already
handled both). Payload shape is whatever `Dice.encodeRoll`
produces.
-}
port incomingDiceRoll : (D.Value -> msg) -> Sub msg


{-| Broadcast the current encounter to every other tab so a
quick-list window can stay in sync with the main combat tab.
Wire shape is whatever `Encounter.Wire.encodeEncounter`
produces. Fires from the main update loop's persist wrapper
whenever `model.encounter` mutates AND the source Msg should
trigger a broadcast (the receive Msg is excluded so the two
tabs don't loop back at each other).
-}
port broadcastEncounter : E.Value -> Cmd msg


{-| Subscription for `Encounter` values broadcast by other tabs
via [`broadcastEncounter`](#broadcastEncounter). The receiving
tab decodes the payload and replaces its own
`model.encounter` — no persist, no re-broadcast.
-}
port incomingEncounter : (D.Value -> msg) -> Sub msg


{-| Ask the JS host to open the standalone `/compendium` route
in a named browser window. If a window with that name already
exists, the call brings it to focus instead of opening a new
one (browser-defined for tabs vs popups). Fired by the Actions
column's Compendium Open trigger.
-}
port openCompendiumTab : () -> Cmd msg


{-| Cross-tab request from the QuickList (`/quick-list`) tab to
the main encounter tab: "the GM clicked creature X, please pin
its stat block + scroll to it in the queue." The JS host
posts the payload on the `ezpz-dndz-panel-show` BroadcastChannel
and calls `window.opener.focus()` so the main tab surfaces to
the front. Payload shape: `{ id: String, name: String }`.
-}
port broadcastPanelShow : E.Value -> Cmd msg


{-| Subscription the main tab uses to receive panel-show
requests posted by a QuickList tab. Payload is the same JSON
`broadcastPanelShow` sends.
-}
port incomingPanelShow : (D.Value -> msg) -> Sub msg
