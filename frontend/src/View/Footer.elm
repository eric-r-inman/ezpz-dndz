module View.Footer exposing (view)

{-| Thin app-wide footer anchored to the bottom of the viewport.

Three slots:

  - Left: copyright + license short-form.
  - Centre: beta-stability disclaimer.
  - Right: contact mailto link.

The footer is `position: fixed`, so encounter-queue cards (and any
other scrollable content) slide _behind_ it rather than getting
pushed out of view. The corresponding `.workspace`/`.panel__body`
CSS reserves bottom padding equal to the footer height so cards
aren't permanently hidden under it.

The view takes no model fragment — every piece of content is
static — but lives in its own module rather than inline in `Main`
to match the per-feature `View/Foo.elm` discipline.

-}

import Html exposing (Html, a, div, footer, span, text)
import Html.Attributes exposing (class, href, rel, target)


view : Html msg
view =
    footer [ class "app-footer" ]
        [ span [ class "app-footer__copyright" ]
            [ text "© 2026 Eric Inman · Source-available under "
            , a
                [ class "app-footer__license-link"
                , href "https://polyformproject.org/licenses/strict/1.0.0"
                , target "_blank"
                , rel "noopener noreferrer"
                ]
                [ text "PolyForm Strict 1.0.0" ]
            ]
        , span [ class "app-footer__beta" ]
            [ text "Beta Version — features may change or break, and save files could be lost, without notice." ]
        , div [ class "app-footer__contact" ]
            [ a [ href "mailto:feedback@ezpzdndz" ]
                [ text "Contact" ]
            ]
        ]
