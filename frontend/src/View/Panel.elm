module View.Panel exposing (Header, onClickWithoutFolding, view)

{-| Shared chrome for whatever the Actions column has open.

Deliberately close to `View.Modal.view`: the shared shell
fields line up, so a surface moves between the two tiers by
swapping the wrapper it calls. The signatures carry the
difference.

`subtitle` names the creature an editor is aimed at, and
`titleTrail` is a control rendered just after the title — the
encounter-level panels leave both empty.

`header` wires the heading row to the stack it sits in: the
fold state (a folded panel keeps its place without paying its
height) and the drag attributes that let the row be picked up
and dropped into a new slot.

@docs Header, onClickWithoutFolding, view

-}

import Html exposing (Html, button, div, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (Msg)
import View.Tooltips as Tooltips


{-| The heading row's wiring from the drawer stack: whether the
body is folded away, the message that flips it, and the drag
attributes that make the row the panel's reorder handle. Built
by `View.PanelDrawer`, which knows the panel's position; passed
through the panel modules untouched.
-}
type alias Header =
    { collapsed : Bool
    , toggle : Msg
    , dragAttrs : List (Html.Attribute Msg)
    }


view :
    { close : Msg
    , title : String
    , titleTrail : Maybe (Html Msg)
    , subtitle : Maybe String
    , extraClass : String
    , collapse : Header
    , body : List (Html Msg)
    }
    -> Html Msg
view config =
    section [ class ("panel panel--drawer " ++ config.extraClass) ]
        (div
            ([ class (headerClass config.collapse.collapsed)
             , onClick config.collapse.toggle
             , Tooltips.attr Tooltips.drawerCollapse
             ]
                ++ config.collapse.dragAttrs
            )
            [ collapseToggle config.collapse
            , div [ class "panel__title panel__title--drawer" ]
                [ text config.title
                , Maybe.withDefault (text "") config.titleTrail
                ]
            , button
                [ class "panel-drawer__close"
                , type_ "button"
                , onClickWithoutFolding config.close
                , Tooltips.attr Tooltips.drawerClose
                , attribute "aria-label" Tooltips.drawerClose
                ]
                [ text "✕" ]
            ]
            :: (if config.collapse.collapsed then
                    []

                else
                    [ subtitleStrip config.subtitle
                    , div [ class "panel__body panel__body--drawer" ] config.body
                    ]
               )
        )


{-| A folded panel is header and nothing else, so the header's
divider would land against the panel's own bottom border and
read as a doubled line.
-}
headerClass : Bool -> String
headerClass collapsed =
    if collapsed then
        "panel__header panel__header--drawer panel__header--collapsed"

    else
        "panel__header panel__header--drawer"


{-| The header row is what a mouse folds the panel with, so the
caret is mostly the open/closed cue — in the disclosure
vocabulary the compendium's group rows already use, where ▼
points at a revealed body and ▶ at a folded one. It is a button
and not a span because it is also the panel's keyboard control:
a bare clickable row leaves nothing to tab to.
-}
collapseToggle : Header -> Html Msg
collapseToggle collapse =
    button
        [ class "panel-drawer__collapse"
        , type_ "button"
        , onClickWithoutFolding collapse.toggle
        , attribute "aria-label" Tooltips.drawerCollapse
        , attribute "aria-expanded"
            (if collapse.collapsed then
                "false"

             else
                "true"
            )
        ]
        [ text
            (if collapse.collapsed then
                "▶"

             else
                "▼"
            )
        ]


{-| Click handler for a control sitting inside the header row,
including anything a panel supplies as its `titleTrail`. Plain
`onClick` there bubbles into the row's own handler, so the
control would fold the panel as a side effect of doing its own
job.
-}
onClickWithoutFolding : Msg -> Html.Attribute Msg
onClickWithoutFolding msg =
    stopPropagationOn "click" (Decode.succeed ( msg, True ))


subtitleStrip : Maybe String -> Html Msg
subtitleStrip subtitle =
    case subtitle of
        Just label ->
            div [ class "panel-drawer__target" ] [ text label ]

        Nothing ->
            text ""
