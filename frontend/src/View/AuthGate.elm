module View.AuthGate exposing (clickWhenAuthed, tooltipWhenAuthed)

{-| Helpers for gating UI controls behind an authenticated session.

Server-only actions (Save to Server, Load from Server, save a card
layout to the cloud, etc.) stay visible in the UI when the user is
anonymous so the affordance doesn't disappear and reappear after
sign-in. These helpers swap the click handler for a redirect to
the login route, and swap the tooltip for a "sign in to use this"
nudge, so the gate is informative rather than silent.

The pattern lets call sites keep their existing `onClick` /
`Tooltips.attr` shape — just wrap the Msg and tooltip with these
two functions.

  - `clickWhenAuthed auth normalMsg` — yields `normalMsg` for
    authenticated users, `NavigateToLogin` for anonymous /
    loading.
  - `tooltipWhenAuthed auth normalTooltip signInTooltip` —
    yields the normal tooltip for authenticated users, the
    sign-in nudge for anyone else.

`AuthLoading` is treated like anonymous on purpose: gated actions
fired before the auth probe lands would race the cookie and
likely 401, so nudging to login is the safer default.

@docs clickWhenAuthed, tooltipWhenAuthed

-}

import Auth
import Msg exposing (Msg(..))


{-| Return the given Msg when the user is authenticated; return
`NavigateToLogin` otherwise. Use in `onClick` slots on server-
only controls so anonymous users land on `/login` instead of
firing a request that would 401.
-}
clickWhenAuthed : Auth.AuthState -> Msg -> Msg
clickWhenAuthed auth normalMsg =
    if Auth.isAuthenticated auth then
        normalMsg

    else
        NavigateToLogin


{-| Pick the tooltip text based on auth state. Authenticated
users see the normal tooltip; anonymous users see the sign-in
nudge so the swap of behavior on click isn't a surprise.
-}
tooltipWhenAuthed : Auth.AuthState -> String -> String -> String
tooltipWhenAuthed auth normalTooltip signInTooltip =
    if Auth.isAuthenticated auth then
        normalTooltip

    else
        signInTooltip
