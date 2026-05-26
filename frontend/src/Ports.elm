port module Ports exposing
    ( savePreferences, persistLocalEncounter
    , clearLocalEncounter, persistLocalCardLayout
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
