module View.Panel exposing (view)

{-| Shared chrome for whatever the Actions column has open.

Deliberately close to `View.Modal.view`: the shared shell
fields line up, so a surface moves between the two tiers by
swapping the wrapper it calls. The signatures carry the
difference.

`subtitle` names the creature an editor is aimed at, and
`titleLead` is a control rendered just before the title — the
encounter-level panels leave both empty.

-}

import Html exposing (Html, button, div, section, text)
import Html.Attributes exposing (attribute, class, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg)
import View.Tooltips as Tooltips


view :
    { close : Msg
    , title : String
    , titleLead : Maybe (Html Msg)
    , subtitle : Maybe String
    , extraClass : String
    , body : List (Html Msg)
    }
    -> Html Msg
view config =
    section [ class ("panel panel--drawer " ++ config.extraClass) ]
        [ div [ class "panel__header" ]
            [ div [ class "panel__title" ]
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
        , subtitleStrip config.subtitle
        , div [ class "panel__body" ] config.body
        ]


subtitleStrip : Maybe String -> Html Msg
subtitleStrip subtitle =
    case subtitle of
        Just label ->
            div [ class "panel-drawer__target" ] [ text label ]

        Nothing ->
            text ""
