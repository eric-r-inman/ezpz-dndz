module View.Modal.ConditionPreset exposing (view)

{-| Naming a Condition/Effect preset.

A modal rather than rows in the editor: naming is a detour from
the form the GM was filling in, and the commit either creates a
preset or replaces one they already have. The button says which,
so the modal is the confirmation as well as the form.

@docs view

-}

import Dict exposing (Dict)
import Html exposing (Html, button, div, input, text)
import Html.Attributes as Attr exposing (autofocus, class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Condition exposing (ConditionPreset, ConditionUi)
import Ui.Condition.Bundled as Bundled
import Ui.ModalChrome exposing (ModalChrome)
import Util.Keyboard
import View.Modal
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    case Maybe.andThen pendingName (Model.drawerGet Model.conditionLens model) of
        Just ( ui, typed ) ->
            body model.modalChrome model.conditionPresets ui typed

        Nothing ->
            text ""


pendingName : ConditionUi -> Maybe ( ConditionUi, String )
pendingName ui =
    Maybe.map (Tuple.pair ui) ui.pendingSaveName


body : ModalChrome -> Dict String ConditionPreset -> ConditionUi -> String -> Html Msg
body chrome presets ui typed =
    let
        trimmed =
            String.trim typed

        categoryPicked =
            not (String.isEmpty (String.trim ui.pendingSaveCategory))

        overwriting =
            Dict.member trimmed presets || Dict.member trimmed Bundled.defaults

        ( commitLabel, commitTip ) =
            if String.isEmpty trimmed then
                ( "Save new preset", Tooltips.conditionPresetNameFirst )

            else if not categoryPicked then
                ( "Save new preset", Tooltips.conditionPresetPickFirst )

            else if overwriting then
                ( "Overwrite existing preset", Tooltips.conditionPresetOverwrite )

            else
                ( "Save new preset", Tooltips.conditionPresetSave )
    in
    View.Modal.view
        { close = ConditionPresetSaveCancel
        , noOp = NoOp
        , title = "Save Preset"
        , extraClass = "modal--condition-preset"
        , chrome = chrome
        , body =
            [ div [ class "cond-row" ]
                [ input
                    [ class "cond-input cond-input--w20"
                    , type_ "text"
                    , value typed
                    , placeholder "Name this preset"
                    , autofocus True
                    , onInput ConditionPresetSaveNameChanged
                    , Html.Events.on "keydown" (Util.Keyboard.enterKey ConditionPresetSaveSubmit)
                    ]
                    []
                ]
            , div [ class "cond-row" ]
                [ Html.label [ for "cond-preset-category", class "cond-label" ] [ text "Category:" ]
                , Html.select
                    [ id "cond-preset-category"
                    , class "cond-select cond-select--grow"
                    , onInput ConditionPresetSaveCategoryChanged
                    , Tooltips.attr Tooltips.conditionPresetCategory
                    ]
                    (Html.option
                        [ value ""
                        , Attr.selected (String.isEmpty ui.pendingSaveCategory)
                        , Attr.disabled True
                        ]
                        [ text "Pick category…" ]
                        :: List.map (categoryOption ui.pendingSaveCategory) Bundled.categories
                    )
                ]
            , div [ class "note-edit__buttons note-edit__buttons--start" ]
                [ button
                    [ class "action-btn action-btn--green"
                    , onClick ConditionPresetSaveSubmit
                    , disabled (String.isEmpty trimmed || not categoryPicked)
                    , Tooltips.attr commitTip
                    ]
                    [ text commitLabel ]
                , button
                    [ class "action-btn"
                    , onClick ConditionPresetSaveCancel
                    , Tooltips.attr Tooltips.conditionPresetCancel
                    ]
                    [ text "Cancel" ]
                ]
            ]
        }


categoryOption : String -> String -> Html Msg
categoryOption pickedCategory category =
    Html.option
        [ value category
        , Attr.selected (pickedCategory == category)
        ]
        [ text category ]
