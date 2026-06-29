module View.Modal.CardEditor exposing (view)

{-| **Prototype** Creature Card Editor modal.

Two-column layout:

  - **Left pane** — the editor. Top: queue-view picker
    (List / Grid). Below: one block per row, with controls
    for the row's alignment, an in-line list of widgets that
    each have a remove button, an "Add widget" picker, and
    row-level move-up / move-down / remove affordances. At
    the bottom: "Add row" and "Reset to defaults".
  - **Right pane** — a live preview rendered by
    [`Card.Preview`](Card-Preview) against `Card.Preview.sampleCreature`.
    The preview re-renders every time the editor's layout
    mutates, so the GM sees the effect of each change
    immediately.

Save copies the editor's in-progress state onto the model;
Close discards it.

-}

import Auth
import Card.Layout as Layout
    exposing
        ( CardLayout
        , CardRow
        , CardWidget
        , QueueView(..)
        , RowAlignment(..)
        )
import Card.Preview
import Card.Wire as CardWire
import Html
    exposing
        ( Html
        , button
        , div
        , input
        , label
        , option
        , p
        , select
        , span
        , text
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , class
        , disabled
        , maxlength
        , placeholder
        , selected
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.CardEditor exposing (CardEditorUi)
import View.AuthGate as AuthGate
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalCardEditor ui) ->
            View.Modal.view
                { close = CardEditorClose
                , noOp = NoOp
                , title = "🎨 Customize Creature Card"
                , extraClass = "modal--card-editor"
                , chrome = model.modalChrome
                , body =
                    [ banner
                    , errorBanner ui
                    , overwriteBanner ui
                    , savedLayoutsSection model.auth ui model.savedCardLayouts
                    , twoColumn ui
                    , footer ui
                    ]
                }

        _ ->
            text ""


banner : Html Msg
banner =
    p [ class "card-editor__banner" ]
        [ text "Edits are local until you Save. "
        , text "A subset of widgets render fully; the rest show as labeled placeholders for now."
        ]


errorBanner : CardEditorUi -> Html Msg
errorBanner ui =
    case ui.error of
        Just err ->
            p [ class "card-editor__error" ] [ text err ]

        Nothing ->
            text ""


overwriteBanner : CardEditorUi -> Html Msg
overwriteBanner ui =
    case ui.confirmOverwrite of
        Just name ->
            div [ class "card-editor__confirm" ]
                [ span [ class "card-editor__confirm-msg" ]
                    [ text
                        ("A layout named \""
                            ++ name
                            ++ "\" already exists. Replace it?"
                        )
                    ]
                , div [ class "card-editor__confirm-actions" ]
                    [ button
                        [ class "action-btn action-btn--red"
                        , onClick CardEditorOverwriteConfirm
                        , disabled ui.busy
                        ]
                        [ text "Overwrite" ]
                    , button
                        [ class "action-btn"
                        , onClick CardEditorOverwriteCancel
                        , disabled ui.busy
                        ]
                        [ text "Cancel" ]
                    ]
                ]

        Nothing ->
            text ""



-- ── SAVED LAYOUTS ────────────────────────────────────────────────────────────


savedLayoutsSection : Auth.AuthState -> CardEditorUi -> List CardWire.SavedLayoutMeta -> Html Msg
savedLayoutsSection auth ui metas =
    div [ class "card-editor__saved" ]
        [ div [ class "card-editor__saved-header" ]
            [ label [ class "card-editor__label" ] [ text "Saved layouts" ]
            , saveAsControls auth ui
            ]
        , if List.isEmpty metas then
            p [ class "card-editor__saved-empty" ]
                [ text "No saved layouts yet. Type a name above and click Save." ]

          else
            div [ class "card-editor__saved-list" ]
                (List.map (savedLayoutRow ui.busy) metas)
        ]


saveAsControls : Auth.AuthState -> CardEditorUi -> Html Msg
saveAsControls auth ui =
    let
        tooltip =
            case auth of
                Auth.AuthAuthenticated _ ->
                    "Save this card layout to the server under the entered name."

                _ ->
                    "Save this card layout in this browser under the entered name."
    in
    div [ class "card-editor__save-as" ]
        [ input
            [ class "card-editor__save-as-input"
            , type_ "text"
            , value ui.saveName
            , maxlength 120
            , placeholder "Layout name…"
            , onInput CardEditorLayoutNameChanged
            , disabled ui.busy
            ]
            []
        , button
            [ class "action-btn action-btn--green"
            , onClick CardEditorSaveAs
            , Tooltips.attr tooltip
            , disabled ui.busy
            ]
            [ text
                (if ui.busy then
                    "Saving…"

                 else
                    "💾 Save"
                )
            ]
        ]


savedLayoutRow : Bool -> CardWire.SavedLayoutMeta -> Html Msg
savedLayoutRow busy meta =
    div [ class "card-editor__saved-row" ]
        [ button
            [ class "card-editor__saved-name"
            , onClick (CardEditorLoad meta.name)
            , disabled busy
            , attribute "aria-label" ("Load " ++ meta.name)
            ]
            [ text meta.name ]
        , button
            [ class "icon-btn icon-btn--danger"
            , onClick (CardEditorDelete meta.name)
            , disabled busy
            , attribute "aria-label" ("Delete " ++ meta.name)
            ]
            [ text "🗑" ]
        ]



-- ── TWO COLUMNS ──────────────────────────────────────────────────────────────


twoColumn : CardEditorUi -> Html Msg
twoColumn ui =
    div [ class "card-editor__columns" ]
        [ editorPane ui
        , previewPane ui
        ]



-- ── EDITOR PANE ──────────────────────────────────────────────────────────────


editorPane : CardEditorUi -> Html Msg
editorPane ui =
    div [ class "card-editor__pane card-editor__pane--editor" ]
        [ queueViewSection ui
        , sideColumnsSection ui
        , rowsSection ui
        , rowFooterControls ui
        ]


{-| Two checkboxes for the death-saves and legendary side
columns. These columns are toggle-only — when on, they appear
in the same slot the non-custom card uses with the same fixed
pip content; when off, the column is hidden entirely. The
contents are NOT user-customisable.
-}
sideColumnsSection : CardEditorUi -> Html Msg
sideColumnsSection ui =
    div [ class "card-editor__side-columns" ]
        [ label [ class "card-editor__label" ] [ text "Side columns" ]
        , div [ class "card-editor__side-toggles" ]
            [ sideColumnToggle
                "Death-save pips"
                ui.layout.deathSavesEnabled
                CardEditorToggleDeathSaves
            , sideColumnToggle
                "Legendary pips (LA + LR)"
                ui.layout.legendaryEnabled
                CardEditorToggleLegendary
            ]
        ]


sideColumnToggle : String -> Bool -> Msg -> Html Msg
sideColumnToggle text_ checkedFlag msg =
    label [ class "card-editor__side-toggle" ]
        [ Html.input
            [ type_ "checkbox"
            , Attr.checked checkedFlag
            , onClick msg
            ]
            []
        , Html.span [] [ text text_ ]
        ]


queueViewSection : CardEditorUi -> Html Msg
queueViewSection ui =
    div [ class "card-editor__queue-view" ]
        [ label [ class "card-editor__label" ] [ text "Queue view" ]
        , div [ class "card-editor__queue-view-toggle", attribute "role" "radiogroup" ]
            (List.map (queueViewOption ui.queueView) Layout.queueViewAllValues)
        ]


queueViewOption : QueueView -> QueueView -> Html Msg
queueViewOption current option_ =
    let
        isActive =
            current == option_

        cls =
            "card-editor__queue-view-btn"
                ++ (if isActive then
                        " card-editor__queue-view-btn--active"

                    else
                        ""
                   )
    in
    button
        [ class cls
        , onClick (CardEditorQueueViewSet (Layout.queueViewKey option_))
        , attribute "aria-pressed"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ text (Layout.queueViewLabel option_) ]


rowsSection : CardEditorUi -> Html Msg
rowsSection ui =
    div [ class "card-editor__rows" ]
        (if List.isEmpty ui.layout.centerRows then
            [ p [ class "card-editor__empty" ]
                [ text "No rows yet. Click \"+ Add Row\" below to start." ]
            ]

         else
            List.indexedMap (rowBlock ui.focusRow) ui.layout.centerRows
        )


rowBlock : Maybe Int -> Int -> CardRow -> Html Msg
rowBlock focusRow_ index row =
    let
        isFocused =
            focusRow_ == Just index

        cls =
            "card-editor__row"
                ++ (if isFocused then
                        " card-editor__row--focused"

                    else
                        ""
                   )
    in
    div
        [ class cls
        , onClick (CardEditorFocusRow index)
        ]
        [ rowHeader index row
        , widgetList index row.widgets
        , widgetPickerRow index
        ]


rowHeader : Int -> CardRow -> Html Msg
rowHeader index row =
    div [ class "card-editor__row-header" ]
        [ span [ class "card-editor__row-label" ]
            [ text ("Row " ++ String.fromInt (index + 1)) ]
        , alignmentPicker index row.alignment
        , div [ class "card-editor__row-actions" ]
            [ smallButton (CardEditorRowMoveUp index) "▲" "Move row up"
            , smallButton (CardEditorRowMoveDown index) "▼" "Move row down"
            , smallButton (CardEditorRowRemove index) "×" "Remove row"
            ]
        ]


alignmentPicker : Int -> RowAlignment -> Html Msg
alignmentPicker index current =
    let
        opt a =
            option
                [ value (Layout.rowAlignmentKey a)
                , selected (current == a)
                ]
                [ text (Layout.rowAlignmentLabel a) ]
    in
    select
        [ class "card-editor__alignment"
        , onInput (CardEditorRowAlignmentSet index)
        , attribute "aria-label" "Row alignment"
        ]
        (List.map opt Layout.rowAlignmentAllValues)


widgetList : Int -> List CardWidget -> Html Msg
widgetList rowIndex widgets =
    if List.isEmpty widgets then
        p [ class "card-editor__row-empty" ]
            [ text "(empty row — pick a widget below to add one)" ]

    else
        div [ class "card-editor__widget-list" ]
            (List.indexedMap (widgetChip rowIndex) widgets)


widgetChip : Int -> Int -> CardWidget -> Html Msg
widgetChip rowIndex widgetIndex widget =
    span [ class "card-editor__widget-chip" ]
        [ span [ class "card-editor__widget-label" ]
            [ text (Layout.widgetLabel widget) ]
        , button
            [ class "card-editor__widget-remove"
            , onClick (CardEditorWidgetRemove rowIndex widgetIndex)
            , attribute "aria-label" "Remove widget"
            ]
            [ text "×" ]
        ]


{-| Per-row widget picker. Categorized `<select>` with one
`<optgroup>` per `WidgetCategory`; picking an option fires
`CardEditorWidgetAdd` and the `<select>` is reset to its
placeholder by the Elm re-render (the option is `selected`
based on the layout, not the DOM's current value).
-}
widgetPickerRow : Int -> Html Msg
widgetPickerRow rowIndex =
    div [ class "card-editor__widget-picker" ]
        [ select
            [ class "card-editor__widget-picker-select"
            , onInput (CardEditorWidgetAdd rowIndex)
            , attribute "aria-label" "Add widget"
            ]
            (option [ value "", selected True ]
                [ text "+ Add widget…" ]
                :: List.concatMap widgetGroup Layout.widgetCategoryAllValues
            )
        ]


widgetGroup : Layout.WidgetCategory -> List (Html Msg)
widgetGroup category =
    let
        members =
            -- Centre-column picker only — rail widgets (move,
            -- ×, etc.) and side-column widgets (death saves,
            -- LA, LR) live in fixed shells and aren't user-
            -- placeable inside a centre row.
            Layout.centerEditableWidgets
                |> List.filter (\w -> Layout.widgetCategory w == category)

        opt w =
            option
                [ value (Layout.widgetKey w) ]
                [ text (Layout.widgetLabel w) ]
    in
    if List.isEmpty members then
        []

    else
        [ Html.optgroup
            [ attribute "label" (Layout.widgetCategoryLabel category) ]
            (List.map opt members)
        ]


rowFooterControls : CardEditorUi -> Html Msg
rowFooterControls ui =
    let
        rowCount =
            List.length ui.layout.centerRows

        atCap =
            rowCount >= 3
    in
    div [ class "card-editor__row-footer" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick CardEditorRowAdd
            , disabled atCap
            , Tooltips.attr
                (if atCap then
                    "Maximum of 3 centre rows"

                 else
                    "Append a new centre row"
                )
            ]
            [ text
                ("+ Add Row ("
                    ++ String.fromInt rowCount
                    ++ "/3)"
                )
            ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick CardEditorReset
            ]
            [ text "↺ Reset to defaults" ]
        ]



-- ── PREVIEW PANE ─────────────────────────────────────────────────────────────


previewPane : CardEditorUi -> Html Msg
previewPane ui =
    let
        queueClass =
            case ui.queueView of
                ListView ->
                    "card-editor__preview-queue card-editor__preview-queue--list"

                GridView ->
                    "card-editor__preview-queue card-editor__preview-queue--grid"
    in
    div [ class "card-editor__pane card-editor__pane--preview" ]
        [ label [ class "card-editor__label" ] [ text "Live preview" ]
        , div [ class queueClass ]
            -- Render two copies so the user can see how the
            -- queue arrangement (list vs grid) actually looks
            -- with multiple cards.  Same sample creature each
            -- time — proving the layout, not the data.
            [ Card.Preview.view ui.layout Card.Preview.sampleCreature
            , Card.Preview.view ui.layout Card.Preview.sampleCreature
            ]
        ]



-- ── FOOTER ───────────────────────────────────────────────────────────────────


footer : CardEditorUi -> Html Msg
footer ui =
    div [ class "card-editor__footer" ]
        [ button
            [ class "action-btn action-btn--blue"
            , onClick CardEditorSave
            , disabled ui.busy
            , Tooltips.attr
                "Apply this layout to the running app (in-memory until you Save by name)."
            ]
            [ text "Apply (no save)" ]
        , button
            [ class "action-btn"
            , onClick CardEditorClose
            , disabled ui.busy
            ]
            [ text "Close" ]
        ]



-- ── INTERNAL ─────────────────────────────────────────────────────────────────


smallButton : Msg -> String -> String -> Html Msg
smallButton msg label_ ariaLabel =
    button
        [ class "icon-btn card-editor__row-action"
        , onClick msg
        , attribute "aria-label" ariaLabel
        ]
        [ text label_ ]
