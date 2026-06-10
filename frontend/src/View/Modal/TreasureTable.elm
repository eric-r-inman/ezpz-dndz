module View.Modal.TreasureTable exposing (view)

{-| User-authored Treasure Tables editor modal.

Two pages, switched by `Ui.TreasureTable.Mode`:

  - **Listing** — every table the GM has saved, with Edit /
    Delete affordances and a "+ New table" button. Empty list
    surfaces a one-line prompt.
  - **Editing** — the in-progress draft for one table: name +
    weighted entry rows. "Cancel" pops back to the list view
    without touching `model.userTreasureTables`; "Save" commits.

Renders nothing when the modal isn't open.

-}

import Encounter.Treasure.Tables exposing (Rarity(..), rarityLabel)
import Encounter.Treasure.UserTable as UserTable
    exposing
        ( Entry
        , UserTable
        )
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
        , autofocus
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
import Ui.TreasureTable as Ui exposing (Mode(..), TreasureTableUi)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalTreasureTable ui) ->
            View.Modal.view
                { close = TreasureTableClose
                , noOp = NoOp
                , title = "📜 " ++ titleFor ui
                , extraClass = "modal--treasure-table"
                , chrome = model.modalChrome
                , body = body model.userTreasureTables ui
                }

        _ ->
            text ""


titleFor : TreasureTableUi -> String
titleFor ui =
    case ui.mode of
        Listing ->
            "Treasure Tables"

        Editing draft ->
            if String.isEmpty (String.trim draft.name) then
                "New treasure table"

            else
                "Edit \"" ++ draft.name ++ "\""


body : List UserTable -> TreasureTableUi -> List (Html Msg)
body tables ui =
    case ui.mode of
        Listing ->
            [ listing tables ]

        Editing draft ->
            [ editor draft ]



-- ── LIST VIEW ───────────────────────────────────────────────────────────────


listing : List UserTable -> Html Msg
listing tables =
    section [ class "treasure-table__listing" ]
        [ if List.isEmpty tables then
            p [ class "treasure-table__empty" ]
                [ text "No treasure tables yet — author one to roll on it from the main Treasure modal." ]

          else
            ul [ class "treasure-table__list" ]
                (List.map row tables)
        , div [ class "treasure-table__list-actions" ]
            [ button
                [ class "treasure-table__new"
                , onClick TreasureTableEditNew
                ]
                [ text "+ New table" ]
            ]
        ]


row : UserTable -> Html Msg
row table =
    let
        entryCount =
            List.length table.entries

        weightTotal =
            UserTable.totalWeight table

        summary =
            String.fromInt entryCount
                ++ " entr"
                ++ (if entryCount == 1 then
                        "y"

                    else
                        "ies"
                   )
                ++ " · "
                ++ String.fromInt weightTotal
                ++ " total weight"
    in
    li [ class "treasure-table__row" ]
        [ div [ class "treasure-table__row-meta" ]
            [ span [ class "treasure-table__row-name" ]
                [ text
                    (if String.isEmpty (String.trim table.name) then
                        "(unnamed)"

                     else
                        table.name
                    )
                ]
            , span [ class "treasure-table__row-summary" ] [ text summary ]
            ]
        , div [ class "treasure-table__row-actions" ]
            [ button
                [ class "treasure-table__row-edit"
                , onClick (TreasureTableEdit table.id)
                ]
                [ text "Edit" ]
            , button
                [ class "treasure-table__row-delete"
                , onClick (TreasureTableDelete table.id)
                , attribute "aria-label" "Delete table"
                , attribute "title" "Delete table"
                ]
                [ text "✕" ]
            ]
        ]



-- ── EDITOR VIEW ─────────────────────────────────────────────────────────────


editor : UserTable -> Html Msg
editor draft =
    section [ class "treasure-table__editor" ]
        [ nameRow draft
        , entriesSection draft
        , buttonRow draft
        ]


nameRow : UserTable -> Html Msg
nameRow draft =
    div [ class "treasure-table__editor-row" ]
        [ label
            [ class "treasure-table__editor-label"
            , Attr.for "treasure-table-name"
            ]
            [ text "Name" ]
        , input
            [ Attr.id "treasure-table-name"
            , class "treasure-table__editor-input"
            , type_ "text"
            , value draft.name
            , placeholder "e.g. Pirate Cove Loot"
            , autofocus True
            , onInput TreasureTableNameChanged
            ]
            []
        ]


entriesSection : UserTable -> Html Msg
entriesSection draft =
    section [ class "treasure-table__entries" ]
        [ div [ class "treasure-table__entries-header" ]
            [ span [ class "treasure-table__entries-title" ] [ text "Entries" ]
            , span [ class "treasure-table__entries-hint" ]
                [ text "Weights drive the roll. Higher = more likely. gp value + rarity are display-only flair." ]
            ]
        , ul [ class "treasure-table__entries-list" ]
            (List.indexedMap (entryRow draft) draft.entries)
        , button
            [ class "treasure-table__entries-add"
            , onClick TreasureTableEntryAdd
            ]
            [ text "+ Add entry" ]
        ]


entryRow : UserTable -> Int -> Entry -> Html Msg
entryRow draft index entry =
    let
        weightPct =
            UserTable.normalisedWeight entry draft
    in
    li [ class "treasure-table__entry-row" ]
        [ input
            [ class "treasure-table__entry-label"
            , type_ "text"
            , value entry.label
            , placeholder "e.g. Iridescent Pearl"
            , onInput (TreasureTableEntryLabelChanged index)
            , attribute "aria-label" "Entry label"
            ]
            []
        , input
            [ class "treasure-table__entry-weight"
            , type_ "number"
            , Attr.min "0"
            , value (String.fromInt entry.weight)
            , onInput (TreasureTableEntryWeightChanged index)
            , attribute "aria-label" "Weight"
            , attribute "title" "Weight (relative pick probability)"
            ]
            []
        , span [ class "treasure-table__entry-pct" ]
            [ text (String.fromInt weightPct ++ "%") ]
        , input
            [ class "treasure-table__entry-gp"
            , type_ "number"
            , Attr.min "0"
            , value (Maybe.withDefault "" (Maybe.map String.fromInt entry.gpValue))
            , placeholder "gp"
            , onInput (TreasureTableEntryGpChanged index)
            , attribute "aria-label" "gp value (optional)"
            , attribute "title" "gp value (optional)"
            ]
            []
        , select
            [ class "treasure-table__entry-rarity"
            , onInput (TreasureTableEntryRarityChanged index)
            , attribute "aria-label" "Rarity (optional)"
            ]
            [ rarityOption entry.rarity Nothing "" "—"
            , rarityOption entry.rarity (Just Common) "common" (rarityLabel Common)
            , rarityOption entry.rarity (Just Uncommon) "uncommon" (rarityLabel Uncommon)
            , rarityOption entry.rarity (Just Rare) "rare" (rarityLabel Rare)
            , rarityOption entry.rarity (Just VeryRare) "very-rare" (rarityLabel VeryRare)
            , rarityOption entry.rarity (Just Legendary) "legendary" (rarityLabel Legendary)
            ]
        , button
            [ class "treasure-table__entry-remove"
            , onClick (TreasureTableEntryRemove index)
            , attribute "aria-label" "Remove entry"
            , attribute "title" "Remove entry"
            ]
            [ text "✕" ]
        ]


rarityOption : Maybe Rarity -> Maybe Rarity -> String -> String -> Html Msg
rarityOption current targetRarity wire label_ =
    option
        [ value wire
        , selected (current == targetRarity)
        ]
        [ text label_ ]


buttonRow : UserTable -> Html Msg
buttonRow draft =
    div [ class "treasure-table__editor-buttons" ]
        [ button
            [ class "treasure-table__editor-cancel"
            , onClick TreasureTableDraftCancel
            ]
            [ text "Cancel" ]
        , button
            [ class "treasure-table__editor-save"
            , onClick TreasureTableDraftSubmit
            , disabled (String.isEmpty (String.trim draft.name))
            ]
            [ text "Save table" ]
        ]
