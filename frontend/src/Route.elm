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
    block, opened via the ↗ link in the Actions panel.
  - `Compendium` — standalone full-page compendium browser,
    opened via the ↗ button in the Compendium modal header.
    Same interactive surface as the modal body (search, sort,
    filters, paste, edit) but laid out as a full page so the
    GM can park it on a second monitor. The AppBar is
    suppressed on this route, matching `QuickList`.
  - `QuickList` — standalone read-only condensed view of the
    combat queue, opened via the ↗ button in the encounter
    title bar. Cross-tab synced through the
    `broadcastEncounter` / `incomingEncounter` port pair so
    the page auto-updates as the GM mutates state in the
    main tab.
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
    | Compendium
    | QuickList
    | NotFound


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Url.Parser.map Home top
        , Url.Parser.map Login (Url.Parser.s "login")
        , Url.Parser.map Me (Url.Parser.s "me")
        , Url.Parser.map Donate (Url.Parser.s "donate")
        , Url.Parser.map About (Url.Parser.s "about")
        , Url.Parser.map QuickList (Url.Parser.s "quick-list")
        , Url.Parser.map CompendiumCreaturePage
            (Url.Parser.s "compendium" </> Url.Parser.s "creatures" </> Url.Parser.string)
        , Url.Parser.map Compendium (Url.Parser.s "compendium")
        ]


fromUrl : Url -> Route
fromUrl url =
    Url.Parser.parse parser url
        |> Maybe.withDefault NotFound
