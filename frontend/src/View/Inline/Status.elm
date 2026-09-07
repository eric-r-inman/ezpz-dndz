module View.Inline.Status exposing (view)

{-| Status editor body: the posture toggles (cover,
concentrating, hiding, dodging, flying + flight height) editing
a draft, with two Apply buttons writing it to the target
creature or the selection.
-}

import Encounter exposing (Cover(..))
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..), StatusFlag(..))
import Ui.Status exposing (StatusUi)
import View.FlyHeight
import View.Inline.ApplyButton as ApplyButton
import View.Tooltips as Tooltips


view : Int -> StatusUi -> Html Msg
view selectedCount ui =
    div [ class "creature-card__inline" ]
        [ div [ class "status-toggles" ]
            [ coverToggle ui
            , boolToggle "hiding" ui.hiding FlagHiding
            , boolToggle "dodging" ui.dodging FlagDodging
            ]
        , div [ class "status-toggles" ]
            [ boolToggle "concentrating" ui.concentrating FlagConcentrating
            , span [ class "flying-group" ]
                [ boolToggle "flying" ui.flying FlagFlying
                , flyHeight ui
                ]
            ]
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = StatusApplyTarget
                , tip = "Write these statuses onto the target creature"
                , label = "Target"
                }
            , ApplyButton.view
                { enabled = selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = StatusApplySelected
                , tip =
                    if selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Write these statuses onto every selected creature"
                , label = "Selected (" ++ String.fromInt selectedCount ++ ")"
                }
            ]
        ]


boolToggle : String -> Bool -> StatusFlag -> Html Msg
boolToggle label isOn flag =
    let
        ( dotGlyph, dotClass, cls ) =
            if isOn then
                ( "●"
                , "status-toggle__dot status-toggle__dot--on"
                , "status-toggle status-toggle--on"
                )

            else
                ( "○"
                , "status-toggle__dot"
                , "status-toggle"
                )

        tip =
            if isOn then
                Tooltips.statusOnTip label

            else
                Tooltips.statusOffTip label
    in
    button
        [ class cls
        , onClick (StatusToggle flag)
        , Tooltips.attr tip
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if isOn then
                "true"

             else
                "false"
            )
        ]
        [ span [ class dotClass ] [ text dotGlyph ]
        , text (" " ++ label)
        ]


coverToggle : StatusUi -> Html Msg
coverToggle ui =
    let
        ( dotGlyph, dotClass ) =
            case ui.cover of
                NoCover ->
                    ( "○", "status-toggle__dot" )

                _ ->
                    ( "●", "status-toggle__dot status-toggle__dot--on" )

        ( bodyText, label, modifier ) =
            case ui.cover of
                NoCover ->
                    ( "cover", "No cover", "status-toggle--off" )

                HalfCover ->
                    ( "½ cover", "Half cover", "status-toggle--on" )

                ThreeQuartersCover ->
                    ( "¾ cover", "Three-quarters cover", "status-toggle--on" )

                FullCover ->
                    ( "total cover", "Total cover", "status-toggle--on" )
    in
    button
        [ class ("status-toggle " ++ modifier)
        , onClick StatusCoverCycle
        , Tooltips.attr (Tooltips.coverCycleTip label)
        , attribute "aria-label" ("Cover: " ++ label)
        ]
        [ span [ class dotClass ] [ text dotGlyph ]
        , text (" " ++ bodyText)
        ]


flyHeight : StatusUi -> Html Msg
flyHeight ui =
    if ui.flying then
        View.FlyHeight.view
            { height = ui.flyHeight
            , up = StatusFlyHeightAdjust 5
            , down = StatusFlyHeightAdjust -5
            , fall = RollFallDamage ui.target
            }

    else
        text ""
