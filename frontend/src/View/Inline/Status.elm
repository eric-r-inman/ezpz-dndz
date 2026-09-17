module View.Inline.Status exposing (view)

{-| Status editor body: the posture toggles editing a draft, with
two Apply buttons adding it to the target creature or the
selection.
-}

import Encounter exposing (Cover(..))
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, maxlength, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (Msg(..), StatusFlag(..))
import Set exposing (Set)
import Ui.Status exposing (StatusLogEntry, StatusUi)
import Update.Status
import View.FlyHeight
import View.Inline.ApplyButton as ApplyButton
import View.StatusLog
import View.Tooltips as Tooltips


{-| The model fragments the editor consumes beyond its own Ui
record.
-}
type alias Context =
    { selectedCount : Int
    , placeholderWarning : Bool
    , log : List StatusLogEntry
    , logOpen : Bool
    , expanded : Set String
    }


view : Context -> StatusUi -> Html Msg
view ctx ui =
    div [ class "editor-body" ]
        [ div [ class "status-toggle-rows" ]
            [ div [ class "status-toggles" ]
                [ coverToggle ui
                , boolToggle "hiding" ui.hiding FlagHiding
                , boolToggle "dodging" ui.dodging FlagDodging
                , span [ class "flying-group" ]
                    [ boolToggle "flying" ui.flying FlagFlying
                    , flyHeight ui
                    ]
                ]
            , div [ class "status-toggles" ]
                [ boolToggle "concentrating" ui.concentrating FlagConcentrating
                , input
                    [ class "cond-input status-toggles__note"
                    , type_ "text"
                    , value ui.concentrationNote
                    , maxlength Update.Status.maxConcentrationNoteLength
                    , placeholder "on..."
                    , onInput StatusConcentrationNoteChanged
                    , attribute "aria-label" "What the creature is concentrating on"
                    ]
                    []
                ]
            ]
        , ApplyButton.row "Apply to:"
            [ ApplyButton.view
                { enabled = True
                , cls = "action-btn action-btn--green"
                , msg = StatusApplyTarget
                , tip = "Add these statuses to the target creature"
                , label = "Target"
                }
            , ApplyButton.view
                { enabled = ctx.selectedCount > 0
                , cls = "action-btn action-btn--green"
                , msg = StatusApplySelected
                , tip =
                    if ctx.selectedCount == 0 then
                        "Select creatures first"

                    else
                        "Add these statuses to every selected creature"
                , label = "Selected (" ++ String.fromInt ctx.selectedCount ++ ")"
                }
            ]
        , ApplyButton.placeholderNotice ctx.placeholderWarning
        , View.StatusLog.section
            { open = ctx.logOpen
            , expanded = ctx.expanded
            }
            ctx.log
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
        -- The caret says the toggle climbs through the cover
        -- levels rather than flipping between two, which a filled
        -- dot would not; past total it wraps back to none.
        ( dotGlyph, dotClass ) =
            case ui.cover of
                NoCover ->
                    ( "○", "status-toggle__dot" )

                _ ->
                    ( "▲", "status-toggle__dot status-toggle__dot--on" )

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
