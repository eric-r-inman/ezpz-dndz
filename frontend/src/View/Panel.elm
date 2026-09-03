module View.Panel exposing (Collapse, view)

{-| Shared chrome for whatever the Actions column has open.

Deliberately close to `View.Modal.view`: the shared shell
fields line up, so a surface moves between the two tiers by
swapping the wrapper it calls. The signatures carry the
difference.

`subtitle` names the creature an editor is aimed at, and
`titleLead` is a control rendered just before the title — the
encounter-level panels leave both empty.

`collapse` folds the body away while leaving the panel in the
stack, so a GM can keep an editor to hand without paying its
height.

@docs Collapse, view

-}

import Html exposing (Html, button, div, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


{-| Whether this panel's body is folded away, and the message
that flips it.
-}
type alias Collapse =
    { collapsed : Bool
    , toggle : Msg
    }


view :
    { close : Msg
    , title : String
    , titleLead : Maybe (Html Msg)
    , subtitle : Maybe String
    , extraClass : String
    , collapse : Collapse
    , body : List (Html Msg)
    }
    -> Html Msg
view config =
    section [ class ("panel panel--drawer " ++ config.extraClass) ]
        (div [ class (headerClass config.collapse.collapsed) ]
            [ collapseToggle config.collapse
            , div [ class "panel__title panel__title--drawer" ]
                (Maybe.withDefault (text "") config.titleLead
                    :: [ text config.title ]
                )
            , button
                [ class "panel-drawer__close"
                , type_ "button"
                , onClick config.close
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


{-| The caret doubles as the open/closed cue, in the disclosure
vocabulary the compendium's group rows already use: ▾ points at
a revealed body, ▸ at a folded one.
-}
collapseToggle : Collapse -> Html Msg
collapseToggle collapse =
    button
        [ class "panel-drawer__collapse"
        , type_ "button"
        , onClick collapse.toggle
        , Tooltips.attr Tooltips.drawerCollapse
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
                "▸"

             else
                "▾"
            )
        ]


subtitleStrip : Maybe String -> Html Msg
subtitleStrip subtitle =
    case subtitle of
        Just label ->
            div [ class "panel-drawer__target" ] [ text label ]

        Nothing ->
            text ""
