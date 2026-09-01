module View.Panel.CrCalculator exposing (view)

{-| **CR Calculator** panel — encounter-difficulty calculator
based on the D&D 2024 XP Budget per Character system.

Three sections, top to bottom:

  - **Party** — one row per character (level dropdown + remove).
    "+ Add character" appends a fresh level-1 row. The roster
    lives on `Model.party` so edits persist across panel opens.
  - **Scope** — which creatures count toward the encounter XP.
    Reuses `Encounter.Xp.XpScope` so the toggle reads exactly the
    same as the XP panel's scope.
  - **Result** — encounter XP for the chosen scope, the party's
    per-tier budgets, the resulting difficulty bucket, and a
    short GM-facing description of what that bucket means.

Renders nothing when `model.surface` isn't `Just SurfaceCrCalculator`.

-}

import Encounter.Difficulty as Difficulty exposing (Difficulty(..), PartyMember)
import Encounter.Xp as Xp exposing (XpScope(..))
import Html
    exposing
        ( Html
        , button
        , div
        , label
        , option
        , p
        , section
        , select
        , span
        , text
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , class
        , selected
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.CrCalculator exposing (CrCalculatorUi)
import View.Panel


view : Model -> Html Msg
view model =
    case Model.drawerGet Model.crCalculatorLens model of
        Just ui ->
            View.Panel.view
                { close = CrCalculatorClose
                , title = "Encounter Difficulty"
                , titleLead = Nothing
                , subtitle = Nothing
                , extraClass = "panel-drawer--cr-calculator"
                , body =
                    [ blurb
                    , partySection model.party
                    , scopeSection ui
                    , resultSection model ui
                    ]
                }

        _ ->
            text ""


blurb : Html Msg
blurb =
    p [ class "cr-calc__blurb" ]
        [ text
            "Compares the encounter's total monster XP against the party's per-tier XP budgets from the SRD."
        ]



-- ── PARTY ────────────────────────────────────────────────────────────────────


partySection : List PartyMember -> Html Msg
partySection party =
    section [ class "cr-calc__section" ]
        [ div [ class "cr-calc__section-header" ]
            [ Html.h2 [ class "cr-calc__section-title" ] [ text "Party" ]
            , button
                [ class "action-btn action-btn--blue"
                , onClick CrCalculatorPartyAdd
                ]
                [ text "+ Add character" ]
            ]
        , if List.isEmpty party then
            p [ class "cr-calc__empty" ]
                [ text "No characters yet. Add one to start the calculation." ]

          else
            div [ class "cr-calc__party-list" ]
                (List.indexedMap partyRow party)
        ]


partyRow : Int -> PartyMember -> Html Msg
partyRow index member =
    div [ class "cr-calc__party-row" ]
        [ span [ class "cr-calc__party-index" ]
            [ text ("Player " ++ String.fromInt (index + 1)) ]
        , label [ class "cr-calc__party-level-label" ] [ text "Level" ]
        , select
            [ class "cr-calc__party-level"
            , onInput (CrCalculatorPartyLevelSet member.id)
            , attribute "aria-label" ("Level for Player " ++ String.fromInt (index + 1))
            ]
            (List.range Difficulty.minLevel Difficulty.maxLevel
                |> List.map (levelOption member.level)
            )
        , button
            [ class "icon-btn icon-btn--danger cr-calc__party-remove"
            , onClick (CrCalculatorPartyRemove member.id)
            , attribute "aria-label" "Remove character"
            ]
            [ text "×" ]
        ]


levelOption : Int -> Int -> Html Msg
levelOption currentLevel lvl =
    option
        [ value (String.fromInt lvl), selected (lvl == currentLevel) ]
        [ text (String.fromInt lvl) ]



-- ── SCOPE ────────────────────────────────────────────────────────────────────


scopeSection : CrCalculatorUi -> Html Msg
scopeSection ui =
    section [ class "cr-calc__section" ]
        [ Html.h2 [ class "cr-calc__section-title" ] [ text "Scope" ]
        , div [ class "cr-calc__scope-group", attribute "role" "radiogroup" ]
            [ scopeButton ui.scope ScopeXpEnemiesAndNpcs "Enemies & NPCs"
            , scopeButton ui.scope ScopeXpEnemiesOnly "Enemies only"
            , scopeButton ui.scope ScopeXpNpcsOnly "NPCs only"
            , scopeButton ui.scope ScopeXpSelectedOnly "Selected only"
            ]
        ]


scopeButton : XpScope -> XpScope -> String -> Html Msg
scopeButton current option_ label_ =
    let
        isActive =
            current == option_

        cls =
            "cr-calc__scope-btn"
                ++ (if isActive then
                        " cr-calc__scope-btn--active"

                    else
                        ""
                   )
    in
    button
        [ class cls
        , onClick (CrCalculatorScopeSet option_)
        , attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ text label_ ]



-- ── RESULT ───────────────────────────────────────────────────────────────────


resultSection : Model -> CrCalculatorUi -> Html Msg
resultSection model ui =
    let
        encounterXp =
            case model.compendium.db of
                CompendiumDbLoaded db ->
                    (Xp.totalsFor ui.scope model.encounter db).total

                _ ->
                    0

        budget =
            Difficulty.partyBudget model.party

        difficulty =
            Difficulty.classify encounterXp budget

        partyEmpty =
            List.isEmpty model.party
    in
    section [ class "cr-calc__section cr-calc__result" ]
        [ Html.h2 [ class "cr-calc__section-title" ] [ text "Result" ]
        , div [ class "cr-calc__result-row" ]
            [ span [ class "cr-calc__result-label" ] [ text "Encounter XP" ]
            , span [ class "cr-calc__result-value" ]
                [ text (Xp.formatThousands encounterXp ++ " XP") ]
            ]
        , div [ class "cr-calc__budget-grid" ]
            [ budgetCell "Low" budget.low
            , budgetCell "Moderate" budget.moderate
            , budgetCell "High" budget.high
            ]
        , if partyEmpty then
            p [ class "cr-calc__empty" ]
                [ text "Add at least one character to see a difficulty rating." ]

          else
            difficultyPanel difficulty
        ]


budgetCell : String -> Int -> Html Msg
budgetCell tier amount =
    div [ class "cr-calc__budget-cell" ]
        [ span [ class "cr-calc__budget-tier" ] [ text tier ]
        , span [ class "cr-calc__budget-amount" ]
            [ text (Xp.formatThousands amount ++ " XP") ]
        ]


difficultyPanel : Difficulty -> Html Msg
difficultyPanel d =
    let
        cls =
            "cr-calc__difficulty cr-calc__difficulty--"
                ++ Difficulty.difficultyKey d
    in
    div [ class cls ]
        [ span [ class "cr-calc__difficulty-label" ]
            [ text (Difficulty.difficultyLabel d) ]
        , p [ class "cr-calc__difficulty-description" ]
            [ text (Difficulty.difficultyDescription d) ]
        ]
