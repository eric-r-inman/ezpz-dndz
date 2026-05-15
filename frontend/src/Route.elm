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
  - `Me` — placeholder for a future profile page.
  - `CompendiumCreaturePage id` — standalone read-only stat
    block, opened via the ↗ link in the side panel.
  - `NotFound` — fallback that the server falls back to
    `index.html` for, so deep-link reloads still work.

-}
type Route
    = Home
    | Me
    | Donate
    | CompendiumCreaturePage String
    | NotFound


parser : Parser (Route -> a) a
parser =
    oneOf
        [ Url.Parser.map Home top
        , Url.Parser.map Me (Url.Parser.s "me")
        , Url.Parser.map Donate (Url.Parser.s "donate")
        , Url.Parser.map CompendiumCreaturePage
            (Url.Parser.s "compendium" </> Url.Parser.s "creatures" </> Url.Parser.string)
        ]


fromUrl : Url -> Route
fromUrl url =
    Url.Parser.parse parser url
        |> Maybe.withDefault NotFound
