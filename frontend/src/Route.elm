module Route exposing (Route(..), fromUrl)

{-| URL routing for the SPA shell.

Pulled out of `Main.elm` so `Model` (which has a `route :
Route` field) can live in its own module without dragging the
URL-parsing machinery along with it.

@docs Route, fromUrl

-}

import Url exposing (Url)
import Url.Parser exposing ((</>), Parser, oneOf, top)


{-| Every URL the SPA recognizes.

  - `Home` — the encounter manager (default).
  - `Login` — sign-in / register form, reachable from the AppBar's
    Sign-in button when the user is anonymous.
  - `Me` — placeholder for a future profile page.
  - `About` — static "about this app" page, linked from the
    AppBar nav.
  - `CompendiumCreaturePage id` — standalone read-only stat
    block, opened via the ↗ link in the side panel.
  - `NotFound` — fallback that the server falls back to
    `index.html` for, so deep-link reloads still work.

-}
type Route
    = Home
    | Login
    | Me
    | Donate
    | About
    | CompendiumCreaturePage String
    | NotFound


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Url.Parser.map Home top
        , Url.Parser.map Login (Url.Parser.s "login")
        , Url.Parser.map Me (Url.Parser.s "me")
        , Url.Parser.map Donate (Url.Parser.s "donate")
        , Url.Parser.map About (Url.Parser.s "about")
        , Url.Parser.map CompendiumCreaturePage
            (Url.Parser.s "compendium" </> Url.Parser.s "creatures" </> Url.Parser.string)
        ]


fromUrl : Url -> Route
fromUrl url =
    Url.Parser.parse parser url
        |> Maybe.withDefault NotFound
