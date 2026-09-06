module View.Panel.Xp exposing (view)

{-| Which creatures the encounter's XP total counts.

The four choices get room to say what they mean, and the
panel's total re-renders as each is picked, so the effect of the
choice is visible while it's being made.

-}

import Encounter exposing (Encounter)
import Encounter.Xp as Xp exposing (XpScope(..))
import Html exposing (Html, div, li, text, ul)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Panel


view : View.Panel.Header -> Encounter -> CompendiumDb -> XpScope -> Html Msg
view collapse enc db current =
    View.Panel.view
        { close = XpFilterToggle
        , title = "XP"
        , titleTrail = Nothing
        , subtitle = Nothing
        , collapse = collapse
        , extraClass = "panel-drawer--xp"
        , body =
            [ div [ class "xp-panel__total" ] [ text (label enc db current) ]
            , lairTotal enc db current
            , ul
                [ class "xp-filter__menu"
                , attribute "role" "listbox"
                ]
                [ item current ScopeXpEnemiesAndNpcs "Enemies & NPCs"
                , item current ScopeXpEnemiesOnly "Enemies Only"
                , item current ScopeXpNpcsOnly "NPCs Only"
                , item current ScopeXpSelectedOnly "Selected Only"
                ]
            ]
        }


{-| Secondary total counting each creature's in-lair XP where
it has one. Shown only when a lair actually raises the figure,
so an encounter without one carries no dead line.
-}
lairTotal : Encounter -> CompendiumDb -> XpScope -> Html Msg
lairTotal enc db scope =
    case db of
        CompendiumDbLoaded loaded ->
            let
                totals =
                    Xp.totalsFor scope enc loaded
            in
            if totals.lairTotal > totals.total then
                div [ class "xp-panel__lair" ]
                    [ text (Xp.formatThousands totals.lairTotal ++ " XP in lair") ]

            else
                text ""

        _ ->
            text ""


{-| The panel's headline XP figure.
-}
label : Encounter -> CompendiumDb -> XpScope -> String
label enc db scope =
    case db of
        CompendiumDbLoaded loaded ->
            Xp.formatThousands (Xp.totalsFor scope enc loaded).total ++ " XP"

        _ ->
            "— XP"


item : XpScope -> XpScope -> String -> Html Msg
item current scope name =
    li
        [ class "xp-filter__item"
        , attribute "role" "option"
        , attribute "aria-selected"
            (if current == scope then
                "true"

             else
                "false"
            )
        , onClick (XpScopeSet scope)
        ]
        [ text name ]
