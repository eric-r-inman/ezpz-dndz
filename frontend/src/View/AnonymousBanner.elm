module View.AnonymousBanner exposing (view)

{-| Top-of-page reminder strip shown to anonymous users.

The banner makes the persistence model explicit so a guest GM
doesn't accumulate a full encounter, clear cookies, and wonder
where their work went. Sign-in upgrades the experience without
data loss — the existing anonymous-to-server migration paths in
[`Update.Auth`](Update-Auth) handle that.

Rendered between the AppBar and the page body so it's the first
thing visible on every guest session. Dismissable for the
session via the × button; reappears on the next reload by design
(the persistence reality doesn't change between reloads, so the
reminder shouldn't either).

@docs view

-}

import Auth exposing (AuthState(..))
import Html exposing (Html, a, button, div, span, text)
import Html.Attributes exposing (attribute, class, href)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))


{-| Render the banner when the session is anonymous and the user
hasn't dismissed it. Returns `text ""` (no markup) otherwise so
the caller doesn't have to wrap the call in its own conditional.
-}
view : { auth : AuthState, dismissed : Bool } -> Html Msg
view cfg =
    case ( cfg.auth, cfg.dismissed ) of
        ( AuthAnonymous, False ) ->
            div
                [ class "anonymous-banner"
                , attribute "role" "status"
                , attribute "aria-live" "polite"
                ]
                [ span [ class "anonymous-banner__message" ]
                    [ text "You're browsing as a guest — your encounters and compendium edits live only in this browser. "
                    , a
                        [ class "anonymous-banner__link"
                        , href "/login"
                        ]
                        [ text "Create an account" ]
                    , text " to keep your work across devices."
                    ]
                , button
                    [ class "anonymous-banner__dismiss"
                    , onClick AnonymousBannerDismiss
                    , attribute "aria-label" "Dismiss the guest-mode reminder for this session"
                    ]
                    [ text "×" ]
                ]

        _ ->
            text ""
