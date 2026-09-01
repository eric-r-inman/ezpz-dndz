module View.Panel.Xp exposing (label, view)

{-| Which creatures the encounter's XP total counts.

The four choices get room to say what they mean, and the title
bar's total re-renders as each is picked, so the effect of the
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


view : Encounter -> CompendiumDb -> XpScope -> Html Msg
view enc db current =
    View.Panel.view
        { close = XpFilterToggle
        , title = "XP"
        , subtitle = Nothing
        , extraClass = "panel-drawer--xp"
        , body =
            [ div [ class "xp-panel__total" ] [ text (label enc db current) ]
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


{-| The scoped total, as both this panel's headline and the
Actions column's XP button face — one string so the two can't
drift apart.
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
