module View.Landmark exposing (mainRegion, pageHeading)

{-| Landmarks every page shares.

@docs mainRegion, pageHeading

-}

import Effects
import Html exposing (Html, h1, main_, text)
import Html.Attributes exposing (attribute, class, id)


{-| The page's main landmark. The app bar's skip link targets its
id. The tabindex lets the skip link move focus into it.
-}
mainRegion : List (Html.Attribute msg) -> List (Html msg) -> Html msg
mainRegion attrs =
    main_ (id Effects.mainRegionId :: attribute "tabindex" "-1" :: attrs)


{-| A level-one heading for a page that shows its name only in the
app bar. It is hidden from sight.
-}
pageHeading : String -> Html msg
pageHeading title =
    h1 [ class "visually-hidden" ] [ text title ]
