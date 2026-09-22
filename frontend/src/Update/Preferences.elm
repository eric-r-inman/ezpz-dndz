module Update.Preferences exposing (profileKey, profileSet, themeKey, themeSet)

{-| Update branches for the user-preferences blob on
`Model.preferences`, set from the AppBar settings popover.

@docs profileKey, profileSet, themeKey, themeSet

-}

import Json.Encode as E
import Model exposing (Model)
import Msg exposing (Msg, Profile(..), Theme(..))
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

        Accessible ->
            "accessible"


{-| Replace the profile choice and snap the column to it: the
panels the profile hides are folded on the spot, so picking one
takes effect where the GM is looking rather than on the next
fold. The `localStorage` write is what makes the next reload
boot into the same profile.
-}
profileSet : Profile -> Model -> ( Model, Cmd Msg )
profileSet profile model =
    let
        prefs =
            model.preferences
    in
    ( { model
        | preferences = { prefs | profile = profile }
        , drawer = Model.foldProfileHidden profile model.drawer
      }
    , Ports.savePreferences (E.object [ ( "profile", E.string (profileKey profile) ) ])
    )


{-| Stable string key for a `Profile`, as `themeKey` is for a
`Theme`: the `localStorage` value, and what the boot flag reads
back.
-}
profileKey : Profile -> String
profileKey profile =
    case profile of
        Session ->
            "session"

        Builder ->
            "builder"

        Beta ->
            "beta"
