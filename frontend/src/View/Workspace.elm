module View.Workspace exposing (view)

{-| Three-pane workspace layout for the Home route: encounter pane
on the left (creature cards under the encounter title bar), control
buttons in the middle, compendium / detail pane on the right.

Each pane is a separate `View/` module — this module just wires
them together with the model fragments each one needs.

-}

import Card.Layout exposing (CardLayout, QueueView(..))
import Compendium
import Effects
import Encounter exposing (Creature, Encounter)
import Encounter.Xp exposing (XpScope)
import Html exposing (Html, button, div, main_, section, span, text)
import Html.Attributes exposing (attribute, class, id, type_)
import Html.Events exposing (onClick)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import Ui.HpChange exposing (HpEdit)
import Ui.PlaceholderRename exposing (PlaceholderRenameState)
import View.Card
import View.Card.Custom
import View.EncounterBar
import View.PanelControls
import View.PanelDetail
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    main_
        [ class "workspace"
        , id "main"
        , attribute "tabindex" "-1"
        ]
        [ panelMain
            model.encounter
            model.hpEdit
            model.placeholderRename
            model.savedAs
            model.compendium.db
            model.xpScope
            model.xpFilterOpen
            model.useCustomCardLayout
            model.cardLayout
            model.queueView
        , View.PanelControls.view
            model.auth
            model.dice
            model.pendingControl
            model.encounter.round
            (Encounter.rosterDirty model.encounter model.savedSnapshot)
            model.controlMenu
        , View.PanelDetail.view model
        ]


{-| The encounter pane. `hpEdit` is threaded through so any open
inline-edit input (current/max HP) renders on the right card.
`savedAs` lights up the title-bar info icon with the source
filename when the encounter was loaded from / saved to a name.
The compendium DB + XP scope let the title bar's right cluster
compute the real XP total; `xpFilterOpen` controls the
hand-rolled XP-scope dropdown's visibility so the global
Esc / click-outside handlers in `Main.subscriptions` can close
it without touching DOM state.
-}
panelMain :
    Encounter
    -> Maybe HpEdit
    -> Maybe PlaceholderRenameState
    -> Maybe String
    -> CompendiumDb
    -> XpScope
    -> Bool
    -> Bool
    -> CardLayout
    -> QueueView
    -> Html Msg
panelMain enc hpEdit renameState savedAs db xpScope xpFilterOpen useCustom layout queueView =
    let
        -- Custom-card renderer needs the loaded compendium to
        -- resolve tag widgets (tags live on the compendium
        -- source).  Boot-fetch hasn't finished and load-failed
        -- both produce an empty Db here, so the tag lookup just
        -- misses and the widget renders nothing.
        compendiumDb =
            case db of
                CompendiumDbLoaded loaded ->
                    loaded

                _ ->
                    Compendium.fromList []

        renderCard =
            -- Customize-card feature hidden for launch.  Always
            -- use the non-custom `View.Card` renderer regardless
            -- of `model.useCustomCardLayout`.  Restore the
            -- branch below when the feature is re-enabled:
            --
            -- if useCustom then
            --     View.Card.Custom.view layout enc.activeName hpEdit compendiumDb
            -- else
            --     View.Card.view enc.activeName hpEdit renameState
            View.Card.view enc.activeName hpEdit renameState

        -- Queue-view picker (List / Grid) is meaningful only when
        -- the custom renderer is on; the classic card has fixed
        -- dimensions and ignores the modifier class.  Either way
        -- the class lands on `.creature-grid` and the CSS decides
        -- whether to honour it.
        gridClass =
            case queueView of
                ListView ->
                    "creature-grid creature-grid--list"

                GridView ->
                    "creature-grid creature-grid--grid"
    in
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ View.EncounterBar.view View.EncounterBar.FullBar enc savedAs db xpScope xpFilterOpen ]
        , div
            [ class "panel__body"
            , id Effects.encounterPanelBodyId
            ]
            [ div [ class gridClass ]
                (let
                    laCreatures =
                        List.filter hasAvailableLegendaryAction enc.creatures
                 in
                 List.concatMap
                    (renderCardWithLaBanners renderCard laCreatures)
                    enc.creatures
                )
            , quickAddRow
            ]
        ]


hasAvailableLegendaryAction : Creature -> Bool
hasAvailableLegendaryAction c =
    let
        total =
            c.legendaryActionsCount + c.legendaryActionsLairBonus
    in
    total > 0 && Set.size c.legendaryActionsUsed < total


{-| Render a creature card followed by a single banner listing
every OTHER queue member that still has an un-spent legendary
action. Multiple LA-haver names are comma-separated inside the
one banner; the card's own creature is filtered out — a creature
can't take a legendary action triggered by its own turn ending.

Returns a list so the encounter-grid can splice card + banner
inline without restructuring the layout.

-}
renderCardWithLaBanners :
    (Creature -> Html Msg)
    -> List Creature
    -> Creature
    -> List (Html Msg)
renderCardWithLaBanners renderCard laCreatures c =
    let
        others =
            List.filter (\la -> la.name /= c.name) laCreatures
    in
    if List.isEmpty others then
        [ renderCard c ]

    else
        [ renderCard c, legendaryActionBanner others ]


legendaryActionBanner : List Creature -> Html Msg
legendaryActionBanner creatures =
    let
        nameNodes =
            creatures
                |> List.map nameNode
                |> List.intersperse (text ", ")
    in
    div
        [ class "legendary-banner"
        , attribute "role" "note"
        ]
        (text "⚜ Legendary Action available: " :: nameNodes)


nameNode : Creature -> Html Msg
nameNode c =
    case c.creatureId of
        Just creatureId ->
            button
                [ class "legendary-banner__name"
                , type_ "button"
                , onClick (PanelShowCreature creatureId c.name)
                , attribute "title" ("Pin " ++ c.name ++ "'s stat block to the side panel")
                , attribute "aria-label"
                    ("Show stat block for " ++ c.name)
                ]
                [ text c.name ]

        Nothing ->
            -- Placeholder rows have no compendium id to pin, so
            -- the name stays plain text.
            span [ class "legendary-banner__name legendary-banner__name--plain" ]
                [ text c.name ]


{-| Full-width "+" row appended below the last creature card in
the queue. Opens the Quick Add modal — same affordance as the
"+ Quick Add" button in the encounter-controls panel, surfaced
inside the queue itself so the GM doesn't have to track across to
the middle column to add another creature. Hover text doubles as
the aria-label so screen-reader users hear the intent rather than
just "+".
-}
quickAddRow : Html Msg
quickAddRow =
    button
        [ class "add-placeholder-row"
        , type_ "button"
        , onClick QuickAddOpen
        , Tooltips.attr Tooltips.quickAddButton
        , attribute "aria-label" "Quick Add"
        ]
        [ text "+" ]
