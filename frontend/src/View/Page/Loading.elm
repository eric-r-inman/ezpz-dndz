module View.Page.Loading exposing (view)

{-| Boot-time loading placeholder.

Rendered while the `/api/auth/me` cookie probe is still in
flight (`AuthLoading`). Every data destination — server route
vs. public bundle vs. localStorage — depends on the probe's
result, so the app shows this quiet placeholder instead of
flashing a shell it might immediately have to redraw.

@docs view

-}

import Html exposing (Html, div, p, text)
import Html.Attributes exposing (class)


view : Html msg
view =
    div [ class "auth-login" ]
        [ div [ class "auth-login__panel" ]
            [ p [ class "auth-login__tagline" ]
                [ text "Loading…" ]
            ]
        ]
