module View.Modal.LoreEdit exposing (view)

{-| Standalone Edit Lore Group modal.

Form layout mirrors the inline editor that previously lived
inside the Create/Edit Group modal — name, weight slider,
members editor, member picker, and a Test panel for the
back-solver — all wired to the dedicated `LoreEdit*` msgs so
the modal's UI substate is independent of the regular
group-edit flow.

Renders nothing when the modal isn't open.

-}

import Compendium
import Encounter.Difficulty
import Encounter.RandomEncounter.Lore as Lore
import Encounter.RandomEncounter.Lore.Suggest as Suggest
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
        , select
        , span
        , text
        , ul
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , autofocus
        , class
        , maxlength
        , placeholder
        , selected
        , step
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium as CompendiumUi exposing (CompendiumDb(..))
import Ui.GroupEdit as GroupEdit exposing (LoreDraft, LoreMemberDraft)
import Ui.LoreEdit exposing (LoreEditUi)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalLoreEdit ui) ->
            let
                creatures =
                    case model.compendium.db of
                        CompendiumDbLoaded db ->
                            Compendium.toList db

                        _ ->
                            []

                title_ =
                    case ui.draft.id of
                        Just _ ->
                            "📖 Edit Lore Group"

                        Nothing ->
                            "📖 Create Lore Group"
            in
            View.Modal.view
                { close = LoreEditClose
                , noOp = NoOp
                , title = title_
                , extraClass = "modal--lore-edit"
                , chrome = model.modalChrome
                , body =
                    [ nameRow ui.draft
                    , weightRow ui.draft
                    , membersEditor ui.draft
                    , addMemberPicker ui.addSearch creatures ui.draft.members
                    , errorBanner ui.submitError
                    , actionsRow
                    , testPanel ui.testResult
                    ]
                }

        _ ->
            text ""



-- ── FORM ROWS ────────────────────────────────────────────────────────────────


nameRow : LoreDraft -> Html Msg
nameRow draft =
    div [ class "group-edit__row" ]
        [ label [ class "group-edit__label" ] [ text "Name" ]
        , input
            [ class "group-edit__input"
            , type_ "text"
            , value draft.name
            , maxlength GroupEdit.maxNameLength
            , placeholder "e.g. Kobold Skirmishers"
            , autofocus True
            , onInput LoreEditNameChanged
            ]
            []
        ]


weightRow : LoreDraft -> Html Msg
weightRow draft =
    div [ class "group-edit__row group-edit__lore-weight-row" ]
        [ label [ class "group-edit__label" ]
            [ text ("Weight (" ++ String.fromInt draft.weight ++ ")") ]
        , input
            [ class "group-edit__lore-weight-slider"
            , type_ "range"
            , Attr.min "1"
            , Attr.max "10"
            , step "1"
            , value (String.fromInt draft.weight)
            , onInput LoreEditWeightChanged
            ]
            []
        , span [ class "group-edit__lore-weight-hint" ]
            [ text "1 = rare · 10 = common" ]
        ]


membersEditor : LoreDraft -> Html Msg
membersEditor draft =
    if List.isEmpty draft.members then
        p [ class "group-edit__lore-empty" ]
            [ text "Add at least one creature to the lore group." ]

    else
        div [ class "group-edit__lore-members-editor" ]
            (List.indexedMap memberRow draft.members)


memberRow : Int -> LoreMemberDraft -> Html Msg
memberRow idx m =
    div [ class "group-edit__lore-member-row" ]
        [ span [ class "group-edit__lore-member-name" ]
            [ text m.creatureName ]
        , select
            [ class "group-edit__lore-role-select"
            , onInput (LoreEditMemberRoleSet idx)
            , attribute "aria-label" "Role"
            ]
            (List.map (roleOption m.role) allRoles)
        , label [ class "group-edit__lore-count-label" ] [ text "min" ]
        , input
            [ class "group-edit__lore-count-input"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "50"
            , value m.countMin
            , onInput (LoreEditMemberCountMinChanged idx)
            , attribute "aria-label" "Minimum count"
            ]
            []
        , label [ class "group-edit__lore-count-label" ] [ text "max" ]
        , input
            [ class "group-edit__lore-count-input"
            , type_ "number"
            , Attr.min "0"
            , Attr.max "50"
            , value m.countMax
            , onInput (LoreEditMemberCountMaxChanged idx)
            , attribute "aria-label" "Maximum count"
            ]
            []
        , button
            [ class "icon-btn icon-btn--danger"
            , type_ "button"
            , onClick (LoreEditMemberRemove idx)
            , attribute "title" "Remove this member"
            , attribute "aria-label" "Remove member"
            ]
            [ text "×" ]
        ]


addMemberPicker :
    String
    -> List Compendium.Creature
    -> List LoreMemberDraft
    -> Html Msg
addMemberPicker search creatures already =
    let
        alreadyNames =
            List.map .creatureName already

        matches =
            if String.isEmpty (String.trim search) then
                []

            else
                creatures
                    |> List.filter
                        (\c ->
                            String.contains
                                (String.toLower search)
                                (String.toLower c.name)
                        )
                    |> List.filter (\c -> not (List.member c.name alreadyNames))
                    |> List.sortBy .name
                    |> List.take 12
    in
    div [ class "group-edit__lore-add-row" ]
        [ input
            [ class "group-edit__input"
            , type_ "search"
            , placeholder "🔍 Search a creature to add…"
            , value search
            , onInput LoreEditAddSearchChanged
            ]
            []
        , if List.isEmpty matches then
            text ""

          else
            ul [ class "group-edit__lore-add-results" ]
                (List.map addResultRow matches)
        ]


addResultRow : Compendium.Creature -> Html Msg
addResultRow c =
    li
        [ class "group-edit__lore-add-result"
        , onClick (LoreEditMemberAdd c.name)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ span [] [ text c.name ]
        , span [ class "group-edit__lore-add-result-cr" ]
            [ text ("CR " ++ c.challengeRating) ]
        ]


errorBanner : Maybe String -> Html Msg
errorBanner maybeErr =
    case maybeErr of
        Just err ->
            p [ class "group-edit__error" ] [ text err ]

        Nothing ->
            text ""


actionsRow : Html Msg
actionsRow =
    div [ class "group-edit__lore-editor-actions" ]
        [ button
            [ class "action-btn group-edit__lore-test"
            , type_ "button"
            , onClick LoreEditTest
            , attribute "title" "Estimate the generator settings most likely to roll this group"
            ]
            [ text "Test" ]
        , span [ class "group-edit__lore-actions-spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , type_ "button"
            , onClick LoreEditSave
            ]
            [ text "Save Lore Group" ]
        , button
            [ class "action-btn"
            , type_ "button"
            , onClick LoreEditClose
            ]
            [ text "Cancel" ]
        ]


testPanel : Maybe Suggest.Suggestion -> Html Msg
testPanel maybeResult =
    case maybeResult of
        Nothing ->
            text ""

        Just s ->
            let
                resolvedSomething =
                    s.maxXp > 0
            in
            div [ class "group-edit__lore-test-panel" ]
                (if resolvedSomething then
                    [ p [ class "group-edit__lore-test-title" ]
                        [ text "Settings most likely to roll this group:" ]
                    ]
                        ++ testRows s
                        ++ unresolvedBanner s.unresolved

                 else
                    [ p [ class "group-edit__lore-test-title" ]
                        [ text "Can't compute settings — no members resolved against the compendium." ]
                    ]
                        ++ unresolvedBanner s.unresolved
                )


testRows : Suggest.Suggestion -> List (Html Msg)
testRows s =
    [ testRow "Lore Leaning" "Enable the toggle (required for any lore group to fire)"
    , testRow "Habitat" (formatHabitats s.habitats)
    , testRow "Creature Type" (formatTypes s.creatureTypes)
    , testRow "Party"
        (String.fromInt s.partyCount
            ++ " characters at level "
            ++ String.fromInt s.partyLevel
        )
    , testRow "Difficulty" (formatDifficulty s.difficulty)
    , testRow "Suggested budget"
        ("≈ "
            ++ String.fromInt s.budgetAtSuggestion
            ++ " XP  (group natural range "
            ++ String.fromInt s.minXp
            ++ "–"
            ++ String.fromInt s.maxXp
            ++ " XP)"
        )
    ]


testRow : String -> String -> Html Msg
testRow label_ value_ =
    div [ class "group-edit__lore-test-row" ]
        [ span [ class "group-edit__lore-test-row-label" ] [ text label_ ]
        , span [ class "group-edit__lore-test-row-value" ] [ text value_ ]
        ]


formatHabitats : List Compendium.Habitat -> String
formatHabitats habitats =
    if List.isEmpty habitats then
        "Any (none of the members carry habitat tags)"

    else
        String.join ", " (List.map Compendium.habitatLabel habitats)


formatTypes : List String -> String
formatTypes types =
    if List.isEmpty types then
        "Any"

    else
        String.join ", " types


formatDifficulty : Encounter.Difficulty.Difficulty -> String
formatDifficulty d =
    case d of
        Encounter.Difficulty.LowDifficulty ->
            "Low"

        Encounter.Difficulty.HighDifficulty ->
            "High"

        _ ->
            "Moderate"


unresolvedBanner : List String -> List (Html Msg)
unresolvedBanner names =
    if List.isEmpty names then
        []

    else
        [ p [ class "group-edit__lore-test-unresolved" ]
            [ text
                ("⚠  Couldn't find these members in the compendium: "
                    ++ String.join ", " names
                    ++ ".  The generator silently drops unresolved members, so the recommendation above only reflects the rest."
                )
            ]
        ]



-- ── HELPERS ──────────────────────────────────────────────────────────────────


allRoles : List Lore.Role
allRoles =
    [ Lore.Leader, Lore.Member, Lore.Minion, Lore.Pet ]


roleOption : Lore.Role -> Lore.Role -> Html Msg
roleOption current role =
    option
        [ value (roleKey role)
        , selected (role == current)
        ]
        [ text (roleLabel role) ]


roleKey : Lore.Role -> String
roleKey r =
    case r of
        Lore.Leader ->
            "leader"

        Lore.Member ->
            "member"

        Lore.Minion ->
            "minion"

        Lore.Pet ->
            "pet"


roleLabel : Lore.Role -> String
roleLabel r =
    case r of
        Lore.Leader ->
            "leader"

        Lore.Member ->
            "member"

        Lore.Minion ->
            "minion"

        Lore.Pet ->
            "pet"
