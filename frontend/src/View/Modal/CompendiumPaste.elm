module View.Modal.CompendiumPaste exposing (view)

{-| Paste-stat-block modal. Two-column layout: textarea input on
the left, live preview / parse-error on the right. Apply hands
the parsed creature off to the edit modal pre-filled.
-}

import Compendium.Parser
import Html exposing (Html, button, div, text)
import Html.Attributes as Attr exposing (attribute, class, disabled, placeholder, title, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumPasteUi)
import View.Modal
import View.StatBlock


view : Maybe CompendiumPasteUi -> Html Msg
view maybeUi =
    case maybeUi of
        Nothing ->
            text ""

        Just ui ->
            View.Modal.view
                { close = CompendiumPasteCancel
                , noOp = NoOp
                , title = "📋 Paste Stat Block"
                , extraClass = "modal--compendium-paste"
                , body =
                    [ div [ class "paste-modal__columns" ]
                        [ pasteInput ui
                        , preview ui
                        ]
                    , footer ui
                    ]
                }


pasteInput : CompendiumPasteUi -> Html Msg
pasteInput ui =
    div [ class "paste-modal__input-col" ]
        [ div [ class "paste-modal__hint" ]
            [ text "Paste a 5e stat block here. Lines like \"Armor Class 15 (leather armor, shield)\" and \"STR 8 (-1) DEX 14 (+2) …\" parse automatically." ]
        , Html.textarea
            [ class "paste-modal__textarea"
            , value ui.text
            , onInput CompendiumPasteTextChanged
            , placeholder "Goblin\nSmall humanoid (goblinoid), neutral evil\nArmor Class 15 (leather armor, shield)\nHit Points 7 (2d6)\nSpeed 30 ft.\nSTR 8 (-1) DEX 14 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1)\n…"
            , attribute "rows" "20"
            , attribute "spellcheck" "false"
            ]
            []
        ]


preview : CompendiumPasteUi -> Html Msg
preview ui =
    div [ class "paste-modal__preview-col" ]
        [ div [ class "paste-modal__preview-heading" ] [ text "Live preview" ]
        , case ui.parseResult of
            Ok creature ->
                div [ class "paste-modal__preview" ]
                    [ View.StatBlock.view RollFromStatBlock creature ]

            Err err ->
                div [ class "paste-modal__preview paste-modal__preview--error" ]
                    [ text (parseErrorLabel err) ]
        ]


parseErrorLabel : Compendium.Parser.ParseError -> String
parseErrorLabel err =
    case err of
        Compendium.Parser.EmptyInput ->
            "Paste a stat block to see the live preview."

        Compendium.Parser.MissingHeader ->
            "Need at least two lines: a name and a type line (e.g. \"Small humanoid, neutral evil\")."


footer : CompendiumPasteUi -> Html Msg
footer ui =
    let
        isOk =
            case ui.parseResult of
                Ok _ ->
                    True

                Err _ ->
                    False
    in
    div [ class "paste-modal__footer" ]
        [ div [ class "paste-modal__footer-spacer" ] []
        , button
            [ class "action-btn action-btn--blue"
            , onClick CompendiumPasteCancel
            ]
            [ text "Cancel" ]
        , button
            [ class "action-btn action-btn--green"
            , onClick CompendiumPasteApply
            , disabled (not isOk)
            , title
                (if isOk then
                    "Open the edit modal pre-filled with the parsed data"

                 else
                    "Fix the parse errors first"
                )
            ]
            [ text "Apply to Form" ]
        ]
