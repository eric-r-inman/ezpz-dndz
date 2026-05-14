module View.Modal.QuickAdd exposing (view)

{-| Quick Add modal — one-click "drop a creature into the
encounter" picker.

Top: a single sort-toggle button (Alphabetical ↔ Challenge
Rating). Bottom: a scrollable list of every compendium creature
with `<name> ··· <CR>`. Clicking any row dispatches
`QuickAddPick id` and closes the modal.

The compendium's full-featured browser modal (search, filter,
edit, count) lives at `View.Modal.Compendium`; this is the
lightweight sibling for the common case.

Renders nothing when the modal isn't open.

-}

import Compendium
import Html exposing (Html, button, div, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.QuickAdd as QuickAddUi exposing (QuickAddSort(..), QuickAddUi)
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalQuickAdd ui) ->
            View.Modal.view
                { close = QuickAddClose
                , noOp = NoOp
                , title = "Quick Add"
                , extraClass = "modal--quick-add"
                , body =
                    [ sortRow ui
                    , listSection ui model
                    ]
                }

        _ ->
            text ""


sortRow : QuickAddUi -> Html Msg
sortRow ui =
    let
        ( label, tooltip ) =
            case ui.sort of
                SortAlpha ->
                    ( "Sort: A → Z", Tooltips.quickAddSortToCr )

                SortByCr ->
                    ( "Sort: CR ↑", Tooltips.quickAddSortToAlpha )
    in
    div [ class "quick-add__sort-row" ]
        [ button
            [ class "action-btn action-btn--blue quick-add__sort-toggle"
            , onClick QuickAddSortToggle
            , Tooltips.attr tooltip
            ]
            [ text label ]
        ]


listSection : QuickAddUi -> Model -> Html Msg
listSection ui model =
    case model.compendium.db of
        CompendiumDbLoading ->
            empty "Loading the compendium…"

        CompendiumDbFailed _ ->
            empty "Couldn't load the compendium."

        CompendiumDbLoaded db ->
            let
                sortedDb =
                    case ui.sort of
                        SortAlpha ->
                            Compendium.sortByName db

                        SortByCr ->
                            Compendium.sortByCr db

                creatures =
                    Compendium.toList sortedDb
            in
            if List.isEmpty creatures then
                empty "Your compendium is empty."

            else
                ul [ class "quick-add__list" ]
                    (List.map row creatures)


row : Compendium.Creature -> Html Msg
row c =
    li
        [ class "quick-add__row"
        , onClick (QuickAddPick c.id)
        , Tooltips.attr (Tooltips.quickAddCreatureRow c.name)
        , attribute "role" "button"
        , attribute "tabindex" "0"
        ]
        [ span [ class "quick-add__name" ] [ text c.name ]
        , span [ class "quick-add__cr" ] [ text (crLabel c.challengeRating) ]
        ]


{-| Render the CR string with a "CR" prefix so a row reads
"Goblin CR 1/4" rather than "Goblin 1/4". Empty CR (rare)
falls back to a muted dash so the column stays aligned.
-}
crLabel : String -> String
crLabel raw =
    if String.isEmpty (String.trim raw) then
        "—"

    else
        "CR " ++ raw


empty : String -> Html Msg
empty message =
    p [ class "quick-add__empty" ] [ text message ]
