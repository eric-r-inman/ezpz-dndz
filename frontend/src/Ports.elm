port module Ports exposing (savePreferences)

{-| Outbound ports for the JS host to consume.

Currently only the preferences-persistence channel: the AppBar
settings popover fires `savePreferences` whenever the user picks
a new theme (or, eventually, density / sound / etc.). The JS
side in `index.html` listens and writes the value to
`localStorage` plus mirrors it to `<html data-theme>` so the
next reload's pre-Elm FOUC script picks it up.

When `/api/me/preferences` lands (Phase 11 of the modularization
plan), this port becomes a no-op fallback for unauthenticated
sessions; the canonical persistence path will be HTTP.

@docs savePreferences

-}

import Json.Encode as E


{-| Send a preference snapshot to the JS host. The Elm side is
responsible for serializing the relevant fields; the JS side
just persists what arrives. Today the only field is `theme`.
-}
port savePreferences : E.Value -> Cmd msg
