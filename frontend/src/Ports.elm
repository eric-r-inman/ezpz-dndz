port module Ports exposing
    ( savePreferences, persistLocalEncounter
    , broadcastDiceRoll, clearLocalCardLayout, clearLocalCardLayoutSaves, clearLocalCompendium, clearLocalEncounter, clearLocalEncounterSaves, incomingDiceRoll, persistLocalCardLayout, persistLocalCardLayoutSaves, persistLocalCompendium, persistLocalConditionPresets, persistLocalDiceHistory, persistLocalEncounterSaves, persistLocalTimerPresets
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


{-| Persist the active card layout, queue view, and
`useCustomCardLayout` toggle into `localStorage` for anonymous
sessions. Authenticated users persist saved layouts to the
server (with a name) via `Card.Wire`; anonymous users get a
single in-place snapshot that restores their customizations on
the next reload.
-}
port persistLocalCardLayout : E.Value -> Cmd msg


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


{-| Drop the locally-persisted card-layout snapshot from
`localStorage`. Fired after a successful login-time migration of
the anonymous card layout into a named server save, mirroring
`clearLocalEncounter`'s role for the encounter.
-}
port clearLocalCardLayout : () -> Cmd msg


{-| Persist the anonymous compendium snapshot (creatures + groups

  - next-local-id counter) into `localStorage` on every CRUD edit
    in an anonymous session. The shape is

    { "creatures": [...], "groups": [...], "next\_local\_id": N }

mirroring the server's export wire format with one extra field for
the local-id counter so a reload doesn't reuse ids.

-}
port persistLocalCompendium : E.Value -> Cmd msg


{-| Drop the locally-persisted compendium after a successful
login-time migration. Same role as `clearLocalEncounter` /
`clearLocalCardLayout`.
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


{-| Same shape as `persistLocalEncounterSaves` but for named
card-layout saves
(`{ name → { body, queue_view, created_at, updated_at } }`).
-}
port persistLocalCardLayoutSaves : E.Value -> Cmd msg


{-| Drop the whole anonymous named-card-layout-saves dict.
-}
port clearLocalCardLayoutSaves : () -> Cmd msg


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
