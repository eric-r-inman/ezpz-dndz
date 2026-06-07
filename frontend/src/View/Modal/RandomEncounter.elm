module View.Modal.RandomEncounter exposing (view)

{-| **Random Encounter** modal — generator for "what walks out
of the woods" rolls.

Sections, top to bottom:

  - **Party** — same level-per-character roster the CR
    Calculator owns. Shared with [`Update.CrCalculator`](Update-CrCalculator)
    because the underlying `model.party` is one list.
  - **Parameters** — target difficulty (Low / Moderate / High)
    and habitat filter (Any wildcard or one of the 11 Material-
    Plane + 13 Planar habitats). The XP budget for the chosen
    difficulty appears next to the difficulty buttons so the
    GM sees what they're targeting before rolling.
  - **Result** — the rolled `(creature, count)` groups, total
    XP, and Reroll / Add-to-Encounter actions. Empty pool gets
    a friendly "no matches" notice instead of a stale prior
    roll.

Renders nothing when `model.modal` isn't
`Just ModalRandomEncounter`.

-}

import Compendium exposing (Creature, Habitat)
import Encounter.Difficulty as Difficulty exposing (PartyMember)
import Encounter.RandomEncounter as RE exposing (Scale(..), TargetDifficulty(..))
import Encounter.Xp as Xp
import Html
    exposing
        ( Html
        , button
        , div
        , input
        , label
        , li
        , option
        , p
        , section
        , select
        , span
        , text
        , ul
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , checked
        , class
        , disabled
        , placeholder
        , selected
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.RandomEncounter exposing (RandomEncounterUi, RollState(..))
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalRandomEncounter ui) ->
            View.Modal.view
                { close = RandomEncounterClose
                , noOp = NoOp
                , title = "Random Encounter"
                , extraClass = "modal--random-encounter"
                , chrome = model.modalChrome
                , body =
                    [ blurb
                    , partySection model.party
                    , parametersSection model ui
                    , pinnedSection model ui
                    , resultSection model ui
                    ]
                }

        _ ->
            text ""


blurb : Html Msg
blurb =
    p [ class "random-encounter__blurb" ]
        [ text
            "Pick a difficulty and habitat, then roll the dice. "
        , text "The generator draws from your bundled compendium "
        , text "sized to fit your party's XP budget. "
        , text
            ("Algorithm derived from online public discussions, "
                ++ "and may not reflect guidance in official sources."
            )
        ]



-- ── PARTY ────────────────────────────────────────────────────────────────────


partySection : List PartyMember -> Html Msg
partySection party =
    section [ class "random-encounter__section" ]
        [ div [ class "random-encounter__section-header" ]
            [ Html.h2 [ class "random-encounter__section-title" ] [ text "Party" ]
            , button
                [ class "action-btn action-btn--blue"
                , onClick CrCalculatorPartyAdd
                ]
                [ text "+ Add character" ]
            ]
        , if List.isEmpty party then
            p [ class "random-encounter__empty" ]
                [ text "No characters yet. Add one to set a budget." ]

          else
            div [ class "random-encounter__party-list" ]
                (List.indexedMap partyRow party)
        ]


partyRow : Int -> PartyMember -> Html Msg
partyRow index member =
    div [ class "random-encounter__party-row" ]
        [ span [ class "random-encounter__party-index" ]
            [ text ("PC " ++ String.fromInt (index + 1)) ]
        , label [ class "random-encounter__party-level-label" ] [ text "Level" ]
        , select
            [ class "random-encounter__party-level"
            , onInput (CrCalculatorPartyLevelSet member.id)
            , attribute "aria-label" ("Level for PC " ++ String.fromInt (index + 1))
            ]
            (List.range Difficulty.minLevel Difficulty.maxLevel
                |> List.map (levelOption member.level)
            )
        , button
            [ class "icon-btn icon-btn--danger random-encounter__party-remove"
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



-- ── PARAMETERS ───────────────────────────────────────────────────────────────


parametersSection : Model -> RandomEncounterUi -> Html Msg
parametersSection model ui =
    section [ class "random-encounter__section" ]
        [ Html.h2 [ class "random-encounter__section-title" ] [ text "Parameters" ]
        , difficultyRow model ui
        , scaleRow ui
        , habitatRow ui
        , creatureTypeRow ui
        , minionsRow ui
        ]


difficultyRow : Model -> RandomEncounterUi -> Html Msg
difficultyRow model ui =
    let
        budget =
            RE.budgetFor model.party ui.difficulty
    in
    div [ class "random-encounter__param-row" ]
        [ label [ class "random-encounter__param-label" ] [ text "Difficulty" ]
        , div
            [ class "random-encounter__difficulty-group"
            , attribute "role" "radiogroup"
            ]
            (List.map (difficultyButton ui.difficulty) RE.allTargets)
        , span [ class "random-encounter__budget-pill" ]
            [ text ("Budget: " ++ Xp.formatThousands budget ++ " XP") ]
        ]


difficultyButton : TargetDifficulty -> TargetDifficulty -> Html Msg
difficultyButton current option_ =
    let
        active =
            current == option_

        cls =
            "random-encounter__difficulty-btn"
                ++ (if active then
                        " random-encounter__difficulty-btn--active"

                    else
                        ""
                   )
    in
    button
        [ class cls
        , onClick (RandomEncounterDifficultySet (difficultyWire option_))
        , attribute "aria-pressed"
            (if active then
                "true"

             else
                "false"
            )
        ]
        [ text (RE.targetLabel option_) ]


difficultyWire : TargetDifficulty -> String
difficultyWire t =
    case t of
        Low ->
            "low"

        Moderate ->
            "moderate"

        High ->
            "high"


scaleRow : RandomEncounterUi -> Html Msg
scaleRow ui =
    div [ class "random-encounter__param-row" ]
        [ label [ class "random-encounter__param-label" ] [ text "Scale" ]
        , div
            [ class "random-encounter__difficulty-group"
            , attribute "role" "radiogroup"
            ]
            (List.map (scaleButton ui.scale) RE.allScales)
        ]


scaleButton : Scale -> Scale -> Html Msg
scaleButton current option_ =
    let
        active =
            current == option_

        cls =
            "random-encounter__difficulty-btn"
                ++ (if active then
                        " random-encounter__difficulty-btn--active"

                    else
                        ""
                   )
    in
    button
        [ class cls
        , onClick (RandomEncounterScaleSet (RE.scaleWire option_))
        , attribute "aria-pressed"
            (if active then
                "true"

             else
                "false"
            )
        ]
        [ text (RE.scaleLabel option_) ]


habitatRow : RandomEncounterUi -> Html Msg
habitatRow ui =
    div [ class "random-encounter__param-row" ]
        [ label
            [ class "random-encounter__param-label"
            , Attr.for "random-encounter-habitat"
            ]
            [ text "Habitat" ]
        , select
            [ Attr.id "random-encounter-habitat"
            , class "random-encounter__habitat-select"
            , onInput RandomEncounterHabitatSet
            ]
            (anyOption "Any" (ui.habitat == Nothing)
                :: List.map (habitatOption ui.habitat) Compendium.allHabitats
            )
        ]


{-| Multi-type picker. Renders one `<select>` per currently-
selected type plus a trailing blank `<select>` so the GM can
add another. Picking a value in the trailing slot appends it
to the list; picking the blank option in a non-trailing slot
removes that slot. Only the first row gets the "Type" label
so the indentation stays clean.
-}
creatureTypeRow : RandomEncounterUi -> Html Msg
creatureTypeRow ui =
    let
        slots =
            List.indexedMap
                (\i t -> creatureTypeSlot { isFirst = i == 0, index = i, current = t })
                ui.creatureTypes

        trailing =
            creatureTypeSlot
                { isFirst = List.isEmpty ui.creatureTypes
                , index = List.length ui.creatureTypes
                , current = ""
                }
    in
    div [ class "random-encounter__type-rows" ]
        (slots ++ [ trailing ])


creatureTypeSlot :
    { isFirst : Bool, index : Int, current : String }
    -> Html Msg
creatureTypeSlot { isFirst, index, current } =
    let
        -- "Any" only labels the first slot — there a blank
        -- entry genuinely means "no type filter, any creature
        -- counts."  On additional slots a blank entry just
        -- means "this slot adds nothing," so labelling it
        -- "Any" would imply a redundant wildcard filter on top
        -- of whatever's already selected.
        blankLabel =
            if isFirst then
                "Any"

            else
                ""
    in
    div [ class "random-encounter__param-row" ]
        [ label [ class "random-encounter__param-label" ]
            [ text
                (if isFirst then
                    "Type"

                 else
                    ""
                )
            ]
        , select
            [ class "random-encounter__habitat-select"
            , onInput (RandomEncounterCreatureTypeAt index)
            , attribute "aria-label"
                ("Creature type filter " ++ String.fromInt (index + 1))
            ]
            (anyOption blankLabel (current == "")
                :: List.map (creatureTypeOption current) RE.allCreatureTypes
            )
        ]


minionsRow : RandomEncounterUi -> Html Msg
minionsRow ui =
    label [ class "random-encounter__minions-row" ]
        [ input
            [ type_ "checkbox"
            , checked ui.includeMinions
            , onClick RandomEncounterMinionsToggle
            , class "random-encounter__minions-checkbox"
            ]
            []
        , span [ class "random-encounter__minions-label" ]
            [ text "Include minions" ]
        , span [ class "random-encounter__minions-hint" ]
            [ text "(adds 2–6 low-CR creatures from the same habitat)" ]
        ]


anyOption : String -> Bool -> Html Msg
anyOption labelText isSelected =
    option
        [ value "", selected isSelected ]
        [ text labelText ]


habitatOption : Maybe Habitat -> Habitat -> Html Msg
habitatOption selectedHabitat h =
    option
        [ value (Compendium.habitatToWire h)
        , selected (selectedHabitat == Just h)
        ]
        [ text (Compendium.habitatLabel h) ]


creatureTypeOption : String -> String -> Html Msg
creatureTypeOption current t =
    option
        [ value t, selected (current == t) ]
        [ text t ]



-- ── PINNED CREATURES ─────────────────────────────────────────────────────────


pinnedSection : Model -> RandomEncounterUi -> Html Msg
pinnedSection model ui =
    section [ class "random-encounter__section" ]
        [ Html.h2 [ class "random-encounter__section-title" ]
            [ text "Specific creatures (optional)" ]
        , pinnedHint
        , pinnedList ui
        , if List.isEmpty ui.pinned then
            text ""

          else
            pinnedBudgetRow model ui
        , pinPicker model ui
        ]


pinnedHint : Html Msg
pinnedHint =
    p [ class "random-encounter__pinned-hint" ]
        [ text
            ("Pin specific creatures to lock them into the roll. "
                ++ "Their XP comes off the budget before the random "
                ++ "fill rolls."
            )
        ]


pinnedList : RandomEncounterUi -> Html Msg
pinnedList ui =
    if List.isEmpty ui.pinned then
        text ""

    else
        ul [ class "random-encounter__pinned-list" ]
            (List.map pinnedRow ui.pinned)


pinnedRow : ( Creature, Int ) -> Html Msg
pinnedRow ( creature, count ) =
    li [ class "random-encounter__pinned-row" ]
        [ div [ class "random-encounter__pinned-counter" ]
            [ button
                [ class "random-encounter__pinned-counter-btn"
                , onClick (RandomEncounterPinDecrement creature.id)
                , disabled (count <= 1)
                , attribute "aria-label" ("One fewer " ++ creature.name)
                , Attr.title "Remove one"
                ]
                [ text "−" ]
            , span [ class "random-encounter__pinned-count" ]
                [ text (String.fromInt count) ]
            , button
                [ class "random-encounter__pinned-counter-btn"
                , onClick (RandomEncounterPinAdd creature.id)
                , attribute "aria-label" ("One more " ++ creature.name)
                , Attr.title "Add one"
                ]
                [ text "+" ]
            ]
        , span [ class "random-encounter__pinned-name" ]
            [ text creature.name ]
        , span [ class "random-encounter__pinned-cr" ]
            [ text ("CR " ++ creature.challengeRating) ]
        , span [ class "random-encounter__pinned-xp" ]
            [ text (Xp.formatThousands (count * creature.xp) ++ " XP") ]
        , button
            [ class "icon-btn icon-btn--danger random-encounter__pinned-remove"
            , onClick (RandomEncounterPinRemove creature.id)
            , attribute "aria-label" ("Remove " ++ creature.name)
            , Attr.title "Remove this pin"
            ]
            [ text "×" ]
        ]


{-| One-line summary of how much of the encounter budget the
pinned creatures have spent. Renders only when at least one
creature is pinned — there's nothing useful to say otherwise.

If pinned XP exceeds the budget the generator clamps the
remainder to zero and skips the random fill; the over-budget
copy says exactly that so the GM isn't surprised by a roll
that only contains their pins.

-}
pinnedBudgetRow : Model -> RandomEncounterUi -> Html Msg
pinnedBudgetRow model ui =
    let
        pinnedXp =
            List.foldl
                (\( c, n ) acc -> acc + c.xp * n)
                0
                ui.pinned

        budget =
            RE.budgetFor model.party ui.difficulty

        remaining =
            budget - pinnedXp

        cls =
            if remaining < 0 then
                "random-encounter__pinned-budget random-encounter__pinned-budget--over"

            else
                "random-encounter__pinned-budget"

        message =
            if remaining < 0 then
                "Pinned: "
                    ++ Xp.formatThousands pinnedXp
                    ++ " XP · "
                    ++ Xp.formatThousands (abs remaining)
                    ++ " XP over the "
                    ++ Xp.formatThousands budget
                    ++ " XP budget — random fill will be skipped."

            else
                "Pinned: "
                    ++ Xp.formatThousands pinnedXp
                    ++ " XP of "
                    ++ Xp.formatThousands budget
                    ++ " budget · "
                    ++ Xp.formatThousands remaining
                    ++ " XP remaining for random fill."
    in
    p [ class cls ] [ text message ]


{-| Search-as-you-type picker. The full alphabetized list of
the loaded compendium is visible at all times — same shape as
[`View.Modal.QuickAdd`](View-Modal-QuickAdd) — and typing in
the search input narrows it via `Compendium.search`. Click
any row to pin; the search resets so the GM can pin several
in a row.

The list is height-bounded by CSS (`max-height` + scroll);
there's no cap on the row count because the natural
alphabetical ordering is what the GM wants to scan.

-}
pinPicker : Model -> RandomEncounterUi -> Html Msg
pinPicker model ui =
    let
        matches =
            case model.compendium.db of
                CompendiumDbLoaded db ->
                    Compendium.search ui.pinSearch db
                        |> Compendium.sortByName
                        |> Compendium.toList

                _ ->
                    []

        searchActive =
            not (String.isEmpty (String.trim ui.pinSearch))
    in
    div [ class "random-encounter__pin-picker" ]
        [ input
            [ class "random-encounter__pin-search"
            , type_ "search"
            , placeholder "🔍 Search creatures to pin…"
            , value ui.pinSearch
            , onInput RandomEncounterPinSearchChanged
            , attribute "aria-label" "Search creatures to pin"
            ]
            []
        , if List.isEmpty matches then
            if searchActive then
                p [ class "random-encounter__pin-empty" ]
                    [ text
                        ("No matches for \""
                            ++ String.trim ui.pinSearch
                            ++ "\"."
                        )
                    ]

            else
                text ""

          else
            ul [ class "random-encounter__pin-results" ]
                (List.map pinResultRow matches)
        ]


pinResultRow : Creature -> Html Msg
pinResultRow c =
    li
        [ class "random-encounter__pin-result"
        , onClick (RandomEncounterPinAdd c.id)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ span [ class "random-encounter__pin-result-name" ] [ text c.name ]
        , span [ class "random-encounter__pin-result-cr" ]
            [ text ("CR " ++ c.challengeRating) ]
        ]



-- ── RESULT ───────────────────────────────────────────────────────────────────


resultSection : Model -> RandomEncounterUi -> Html Msg
resultSection model ui =
    let
        compendiumLoaded =
            case model.compendium.db of
                CompendiumDbLoaded _ ->
                    True

                _ ->
                    False

        canGenerate =
            compendiumLoaded && not (List.isEmpty model.party)
    in
    section [ class "random-encounter__section random-encounter__result" ]
        [ Html.h2 [ class "random-encounter__section-title" ] [ text "Result" ]
        , resultBody ui
        , actionsRow ui canGenerate
        ]


resultBody : RandomEncounterUi -> Html Msg
resultBody ui =
    case ui.roll of
        RollIdle ->
            p [ class "random-encounter__hint" ]
                [ text "Hit Generate to roll." ]

        RollEmptyPool ->
            p [ class "random-encounter__hint random-encounter__hint--warn" ]
                [ text
                    ("No creatures match that habitat at the chosen budget. "
                        ++ "Try Any, a different habitat, or a lower difficulty."
                    )
                ]

        RollOk groups ->
            div [ class "random-encounter__groups" ]
                (List.map groupRow groups
                    ++ [ totalRow groups ]
                )


groupRow : ( Creature, Int ) -> Html Msg
groupRow ( creature, count ) =
    let
        groupXp =
            count * creature.xp
    in
    div [ class "random-encounter__group-row" ]
        [ span [ class "random-encounter__group-count" ]
            [ text (String.fromInt count ++ "×") ]
        , span [ class "random-encounter__group-name" ] [ text creature.name ]
        , span [ class "random-encounter__group-cr" ]
            [ text ("CR " ++ creature.challengeRating) ]
        , span [ class "random-encounter__group-xp" ]
            [ text (Xp.formatThousands groupXp ++ " XP") ]
        ]


totalRow : List ( Creature, Int ) -> Html Msg
totalRow groups =
    let
        total =
            List.foldl (\( c, n ) acc -> acc + n * c.xp) 0 groups
    in
    div [ class "random-encounter__total-row" ]
        [ span [ class "random-encounter__total-label" ] [ text "Total" ]
        , span [ class "random-encounter__total-value" ]
            [ text (Xp.formatThousands total ++ " XP") ]
        ]


actionsRow : RandomEncounterUi -> Bool -> Html Msg
actionsRow ui canGenerate =
    let
        generateLabel =
            case ui.roll of
                RollOk _ ->
                    "Reroll"

                _ ->
                    "Generate"

        addEnabled =
            case ui.roll of
                RollOk _ ->
                    True

                _ ->
                    False
    in
    div [ class "random-encounter__actions" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick RandomEncounterGenerate
            , disabled (not canGenerate)
            ]
            [ text ("🎲 " ++ generateLabel) ]
        , button
            [ class "action-btn action-btn--green"
            , onClick RandomEncounterAddToEncounter
            , disabled (not addEnabled)
            ]
            [ text "Add to Encounter" ]
        ]
