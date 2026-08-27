module View.Inline.Status exposing (view)

{-| Status editor as a docked toolbar expansion: the posture
toggles (cover, concentrating, hiding, dodging, flying + flight
height) editing a draft, with two Apply buttons writing it to
the active creature or the selection.
-}

import Encounter exposing (Cover(..))
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, disabled)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..), StatusFlag(..))
import Ui.Status exposing (StatusUi)
import View.Tooltips as Tooltips


view : Int -> StatusUi -> Html Msg
view selectedCount ui =
    div [ class "creature-card__inline" ]
        [ div [ class "cond-row" ]
            [ coverToggle ui
            , sep
            , boolToggle "concentrating" ui.concentrating FlagConcentrating
            , sep
            , boolToggle "hiding" ui.hiding FlagHiding
            , sep
            , boolToggle "dodging" ui.dodging FlagDodging
            , sep
            , span [ class "flying-group" ]
                [ boolToggle "flying" ui.flying FlagFlying
                , flyHeight ui
                ]
            ]
        , div [ class "note-edit__buttons note-edit__buttons--start" ]
            [ button
                [ class "action-btn action-btn--green"
                , onClick StatusApplyActive
                , Tooltips.attr "Write these statuses onto the active creature"
                ]
                [ text "Apply to Active" ]
            , button
                [ class "action-btn action-btn--green"
                , onClick StatusApplySelected
                , disabled (selectedCount == 0)
                , Tooltips.attr
                    (if selectedCount == 0 then
                        "Select creatures first"

                     else
                        "Write these statuses onto every selected creature"
                    )
                ]
                [ text ("Apply to Selected (" ++ String.fromInt selectedCount ++ ")") ]
            ]
        ]


sep : Html Msg
sep =
    span [ class "status-toggles__sep" ] [ text "|" ]


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
        span [ class "fly-height" ]
            [ button
                [ class "fly-height__btn"
                , onClick (StatusFlyHeightAdjust 5)
                , Tooltips.attr Tooltips.flyHeightUp
                , attribute "aria-label" "Increase flight height by 5 feet"
                ]
                [ text "▲" ]
            , span [ class "fly-height__value" ]
                [ text (String.fromInt ui.flyHeight) ]
            , button
                [ class "fly-height__btn"
                , onClick (StatusFlyHeightAdjust -5)
                , Tooltips.attr Tooltips.flyHeightDown
                , attribute "aria-label" "Decrease flight height by 5 feet"
                ]
                [ text "▼" ]
            , span [ class "fly-height__unit" ] [ text "ft" ]
            , button
                [ class "icon-btn icon-btn--sm fly-height__fall"
                , onClick (RollFallDamage ui.target)
                , Tooltips.attr Tooltips.fallDamage
                , attribute "aria-label" "Roll falling damage"
                ]
                [ text "↯" ]
            ]

    else
        text ""
