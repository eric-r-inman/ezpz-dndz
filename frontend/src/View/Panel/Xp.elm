module View.Panel.Xp exposing (view)

{-| Which creatures the encounter's XP total counts.

The four choices get room to say what they mean, and the
panel's total re-renders as each is picked, so the effect of the
choice is visible while it's being made.

-}

import Encounter exposing (Encounter)
import Encounter.Xp as Xp exposing (XpScope(..))
import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Compendium exposing (CompendiumDb(..))
import View.Inline.Field as Field
import View.Panel
import View.Tooltips as Tooltips


view : View.Panel.Header -> Encounter -> CompendiumDb -> XpScope -> { open : Bool, excluded : Set String } -> Html Msg
view header enc db current calc =
    View.Panel.view
        { title = "Encounter XP"
        , titleTrail = Nothing
        , subtitle = Nothing
        , header = header
        , extraClass = "panel-drawer--xp"
        , body =
            [ div [ class "xp-panel__total" ] [ text (label enc db current) ]
            , lairTotal enc db current
            , ul
                [ class "xp-filter__menu"
                , attribute "role" "listbox"
                ]
                [ item current ScopeXpEnemiesOnly "Enemies Only"
                , item current ScopeXpEnemiesAndNpcs "Enemies & NPCs"
                , item current ScopeXpNpcsOnly "NPCs Only"
                , item current ScopeXpSelectedOnly "Selected Only"
                ]
            , calculations enc db current calc
            ]
        }


{-| The total's working, behind a fold: what each creature in
scope is worth, and a sum the GM can take creatures out of.
-}
calculations : Encounter -> CompendiumDb -> XpScope -> { open : Bool, excluded : Set String } -> Html Msg
calculations enc db scope calc =
    case db of
        CompendiumDbLoaded loaded ->
            let
                lines =
                    Xp.breakdownFor scope enc loaded

                counted =
                    List.filter (\line -> not (Set.member line.name calc.excluded)) lines
            in
            div [ class "xp-calc" ]
                (Field.foldHead
                    { open = calc.open
                    , title = "Show calculations"
                    , msg = XpCalculationsToggle
                    , trail = []
                    }
                    :: (if not calc.open then
                            []

                        else if List.isEmpty lines then
                            [ div [ class "log-empty" ] [ text "Nothing in scope." ] ]

                        else
                            List.map (calcRow calc.excluded) lines
                                ++ [ div [ class "xp-calc__total" ]
                                        [ text (Xp.formatThousands (List.sum (List.map .xp counted)) ++ " XP") ]
                                   ]
                       )
                )

        _ ->
            text ""


calcRow : Set String -> Xp.Line -> Html Msg
calcRow excluded line =
    let
        isExcluded =
            Set.member line.name excluded
    in
    div
        [ class
            (if isExcluded then
                "xp-calc__row xp-calc__row--excluded"

             else
                "xp-calc__row"
            )
        ]
        [ span [ class "xp-calc__name" ] [ text line.name ]
        , span [ class "xp-calc__xp" ] [ text (Xp.formatThousands line.xp) ]
        , button
            [ class "xp-calc__toggle"
            , type_ "button"
            , onClick (XpExcludeToggle line.name)
            , Tooltips.attr
                (if isExcluded then
                    "include"

                 else
                    "exclude"
                )
            , attribute "aria-label"
                (if isExcluded then
                    "Include " ++ line.name ++ " in the tally"

                 else
                    "Exclude " ++ line.name ++ " from the tally"
                )
            ]
            [ text
                (if isExcluded then
                    "+"

                 else
                    "×"
                )
            ]
        ]


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
