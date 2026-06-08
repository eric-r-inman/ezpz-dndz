module View.Page.Compendium exposing (view)

{-| Standalone full-page Compendium browser.

Lives at `/compendium` and is opened from the ↗ button in the
Compendium modal header. The GM parks this on a second monitor
so they can search / browse / edit the library without
covering the encounter grid in the main tab.

The render uses [`View.Modal.Compendium.pageBody`](View-Modal-Compendium#pageBody)
so this page and the modal share the same interactive surface
(search, sort, filters, paste, edit) — only the wrapper
differs. The AppBar is suppressed on this route, matching
`QuickList`.

**Cross-tab caveat.** Each tab runs its own Elm app with its
own `model.compendium`. Edits made on the standalone page show
up in that tab immediately, but the main tab's compendium
panel won't reflect them until a reload (no live sync today).
Adding a creature to the encounter from this page targets
the standalone tab's encounter, not the main tab's — so the
"Add to encounter" flows are best avoided here. A future port
pair could broadcast compendium / encounter updates between
tabs the same way the dice + encounter ports already do for
`QuickList`.

-}

import Auth
import Html exposing (Html, div, section, text)
import Html.Attributes exposing (class)
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumUi)
import View.Modal.Compendium


view : Auth.AuthState -> CompendiumUi -> List String -> Html Msg
view auth ui encounterIds =
    div [ class "workspace workspace--compendium-page" ]
        [ section [ class "panel panel--compendium-page" ]
            [ div [ class "panel__body compendium-page__body" ]
                (View.Modal.Compendium.pageBody auth ui encounterIds)
            ]
        ]
