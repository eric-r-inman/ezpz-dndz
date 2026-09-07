module View.Panel exposing (Header, onClickWithoutFolding, titleMarkIf, view)

{-| Shared chrome for whatever the editor column has open.

Deliberately close to `View.Modal.view`: the shared shell
fields line up, so a surface moves between the two tiers by
swapping the wrapper it calls. The signatures carry the
difference.

`subtitle` names the creature an editor is aimed at, which the
encounter-level panels leave empty. `titleTrail` is a control
or cue rendered just after the title.

`header` wires the heading row to the stack it sits in —
whether the body is folded, where the panel sits in the order,
and the controls that change either.

@docs Header, onClickWithoutFolding, titleMarkIf, view

-}

import Html exposing (Html, button, div, section, span, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (Msg)
import View.Tooltips as Tooltips


{-| The heading row's wiring from the drawer stack. Built by
`View.PanelDrawer`, which is what knows a panel's position, and
passed through the panel modules untouched.
-}
type alias Header =
    { collapsed : Bool
    , toggle : Msg
    , dragAttrs : List (Html.Attribute Msg)
    , pinned : Bool
    , pinToggle : Msg
    }


view :
    { close : Maybe Msg
    , title : String
    , titleTrail : Maybe (Html Msg)
    , subtitle : Maybe String
    , extraClass : String
    , header : Header
    , body : List (Html Msg)
    }
    -> Html Msg
view config =
    section [ class ("panel panel--drawer " ++ config.extraClass) ]
        (div
            ([ class (headerClass config.header.collapsed)
             , onClick config.header.toggle
             ]
                ++ config.header.dragAttrs
            )
            [ collapseToggle config.header
            , div [ class "panel__title panel__title--drawer" ]
                [ text config.title
                , Maybe.withDefault (text "") config.titleTrail
                ]
            , pinButton config.header
            , Maybe.withDefault (text "") (Maybe.map closeButton config.close)
            ]
            :: (if config.header.collapsed then
                    []

                else
                    [ subtitleStrip config.subtitle
                    , div [ class "panel__body panel__body--drawer" ] config.body
                    ]
               )
        )


{-| Holds a panel at the top of the column. The glyph reads as
its own state rather than as what the click will do, the way a
checkbox does — `aria-pressed` says the same thing to a reader
that cannot see the tilt.
-}
pinButton : Header -> Html Msg
pinButton header =
    let
        label =
            if header.pinned then
                Tooltips.drawerUnpinPanel

            else
                Tooltips.drawerPinPanel
    in
    button
        [ class (pinClass header.pinned)
        , type_ "button"
        , onClickWithoutFolding header.pinToggle
        , Tooltips.attr label
        , attribute "aria-label" label
        , attribute "aria-pressed"
            (if header.pinned then
                "true"

             else
                "false"
            )
        ]
        [ text "📌" ]


pinClass : Bool -> String
pinClass pinned =
    if pinned then
        "panel-drawer__pin panel-drawer__pin--on"

    else
        "panel-drawer__pin"


{-| Only a panel the GM can put back offers this — in practice
the stat block a card put there. The editors the drawer boots
with have no trigger left to reopen them, so they fold instead of
closing and never render it.
-}
closeButton : Msg -> Html Msg
closeButton msg =
    button
        [ class "panel-drawer__close"
        , type_ "button"
        , onClickWithoutFolding msg
        , Tooltips.attr Tooltips.drawerRemoveStatBlock
        , attribute "aria-label" Tooltips.drawerRemoveStatBlock
        ]
        [ text "✕" ]


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
collapseToggle header =
    button
        [ class "panel-drawer__collapse"
        , type_ "button"
        , onClickWithoutFolding header.toggle
        , attribute "aria-label" Tooltips.drawerCollapse
        , attribute "aria-expanded"
            (if header.collapsed then
                "false"

             else
                "true"
            )
        ]
        [ text
            (if header.collapsed then
                "▶"

             else
                "▼"
            )
        ]


{-| The cue a panel wears when it holds something the GM hasn't
seen. It rides `titleTrail` so a folded panel, which shows
nothing but its title row, still carries it.
-}
titleMarkIf : Bool -> Maybe (Html Msg)
titleMarkIf unseen =
    if unseen then
        Just (span [ class "panel__title-mark" ] [ text "•" ])

    else
        Nothing


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
