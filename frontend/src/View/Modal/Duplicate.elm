module View.Modal.Duplicate exposing (view)

{-| Duplicate-picker modal: shown when the GM clicks a creature
card's ⧉ button. Five list rows, each fires its own Msg and the
modal closes. Renders nothing when the modal isn't open.

Styled like the Quick Add picker — a vertical list of clickable
rows rather than horizontal buttons — so a longer label like
"Minion (½ max hp)" doesn't get crowded.

The Fresh / Minion rows are dimmed (visually + functionally)
when the source creature lacks a `creatureId` or the compendium
hasn't loaded — those flows need a compendium source to draw
from. Exact and Pudding are always available since they
operate on the encounter creature alone.

-}

import Encounter exposing (Creature)
import Html exposing (Html, li, p, span, text, ul)
import Html.Attributes exposing (attribute, class, title)
import Html.Events exposing (onClick)
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.Duplicate exposing (DuplicateUi)
import View.Modal


view : Model -> Html Msg
view model =
    case model.modal of
        Just (ModalDuplicate ui) ->
            View.Modal.view
                { close = DuplicateClose
                , noOp = NoOp
                , title = "Duplicate — " ++ ui.creatureName
                , extraClass = "modal--duplicate"
                , body = [ list (freshAvailable ui model) ]
                }

        _ ->
            text ""


list : Bool -> Html Msg
list freshOk =
    ul [ class "duplicate__list" ]
        [ row
            { msg = DuplicateExact
            , available = True
            , label = "Exact"
            , description = "Same HP, conditions, notes."
            }
        , row
            { msg = DuplicateFresh
            , available = freshOk
            , label = "Fresh"
            , description = "Full HP, no conditions."
            }
        , row
            { msg = DuplicateMinionHalf
            , available = freshOk
            , label = "Minion (½ max hp)"
            , description = "Fresh, max HP halved."
            }
        , row
            { msg = DuplicateMinionOne
            , available = freshOk
            , label = "Minion (1 hp)"
            , description = "Fresh, max HP = 1."
            }
        , row
            { msg = DuplicatePudding
            , available = True
            , label = "Pudding"
            , description = "Split in two; original removed."
            }
        ]


row :
    { msg : Msg
    , available : Bool
    , label : String
    , description : String
    }
    -> Html Msg
row args =
    let
        baseAttrs =
            [ class
                (if args.available then
                    "duplicate__row"

                 else
                    "duplicate__row duplicate__row--disabled"
                )
            , title
                (if args.available then
                    args.description

                 else
                    args.description ++ " — unavailable: no compendium source for this creature"
                )
            ]

        clickAttrs =
            if args.available then
                [ onClick args.msg
                , attribute "role" "button"
                , attribute "tabindex" "0"
                ]

            else
                [ attribute "aria-disabled" "true" ]
    in
    li (baseAttrs ++ clickAttrs)
        [ span [ class "duplicate__label" ] [ text args.label ]
        , span [ class "duplicate__hint" ] [ text args.description ]
        ]


{-| `True` when the source creature has a `creatureId` AND the
compendium is loaded. Fresh / Minion modes need both; Exact and
Pudding do not.
-}
freshAvailable : DuplicateUi -> Model -> Bool
freshAvailable ui model =
    case findCreature ui.creatureName model.encounter.creatures of
        Nothing ->
            False

        Just src ->
            case ( src.creatureId, model.compendium.db ) of
                ( Just _, CompendiumDbLoaded _ ) ->
                    True

                _ ->
                    False


findCreature : String -> List Creature -> Maybe Creature
findCreature name =
    List.filter (\c -> c.name == name) >> List.head
