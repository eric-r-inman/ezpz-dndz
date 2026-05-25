module Update.Preferences exposing (themeKey, themeSet)

{-| Update branches for the user-preferences blob on
`Model.preferences`. Currently a one-function module — the only
preference plumbed through to the UI today is `theme`, set from
the AppBar settings popover.

The function lives in its own module (rather than in
`Update.Shell`) so the next preference (`cardDensity`) and any
that follow have an obvious home.

@docs themeKey, themeSet

-}

import Json.Encode as E
import Model exposing (Model)
import Msg exposing (Msg, Theme(..))
import Ports
import Preferences


{-| Replace the user's theme choice on the in-memory
preferences blob and fire the `savePreferences` port so the JS
host writes it to `localStorage` (and mirrors to
`<html data-theme>`). CSS picks up the in-app change
automatically via the `data-theme` attribute on `.app-shell`
(see `Main.themeAttr`); the localStorage write is what makes
the next reload pick the same theme without a flash.
-}
themeSet : Theme -> Model -> ( Model, Cmd Msg )
themeSet theme model =
    let
        prefs =
            model.preferences

        nextPrefs : Preferences.Preferences
        nextPrefs =
            { prefs | theme = theme }
    in
    ( { model | preferences = nextPrefs }
    , Ports.savePreferences (E.object [ ( "theme", E.string (themeKey theme) ) ])
    )


{-| Stable string key for a `Theme`. Used both as the
`localStorage` value (via the port encoder above) and as the
`data-theme` HTML attribute. Matches the strings the FOUC
script in `index.html` reads back.
-}
themeKey : Theme -> String
themeKey theme =
    case theme of
        Modern ->
            "modern"

        Dark ->
            "dark"

        Auto ->
            "auto"

        Accessible ->
            "accessible"
