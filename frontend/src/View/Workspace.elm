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
import Encounter.DeathSaves
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
        , legendaryActionStrip enc
        , specialReactionsStrip enc
        , div
            [ class "panel__body"
            , id Effects.encounterPanelBodyId
            ]
            [ div [ class gridClass ]
                (List.map renderCard enc.creatures)
            , quickAddRow
            ]
        ]


{-| Sticky orange strip sandwiched between the encounter title
bar and the scrolling card grid. Lists every queue member with
un-spent legendary actions (excluding the currently-active
creature, since you can't take an LA on your own turn-end, and
excluding Surprised creatures, since the rule bars LA use while
surprised). Each name is clickable to pin the creature's stat
block; the parenthesised count is remaining pips. Empty when
no creature qualifies, so the panel layout is unchanged for
vanilla encounters.

Lives outside `panel__body` so it doesn't scroll with the cards
— same affordance the title bar uses.

-}
legendaryActionStrip : Encounter -> Html Msg
legendaryActionStrip enc =
    let
        eligible =
            enc.creatures
                |> List.filter hasAvailableLegendaryAction
                |> List.filter (\c -> c.name /= enc.activeName)
    in
    if List.isEmpty eligible then
        text ""

    else
        legendaryActionBanner eligible


{-| Sticky orange strip that sits directly under the LA strip.
Lists every queue member whose compendium source has
`hasSpecialReactions` flipped on — Hydra, Marilith, Vampire,
mephits, … — so the GM has a one-line reminder to consult the
stat block instead of relying on the single-pip UX.

Filters out creatures who literally can't react (down at 0 HP
or dead). The active creature stays — unlike legendary actions,
reactions can fire on the creature's own turn (e.g. an OA on
a fleeing target).

-}
specialReactionsStrip : Encounter -> Html Msg
specialReactionsStrip enc =
    let
        eligible =
            List.filter specialReactionsEligible enc.creatures
    in
    if List.isEmpty eligible then
        text ""

    else
        specialReactionsBanner eligible


specialReactionsEligible : Creature -> Bool
specialReactionsEligible c =
    let
        down =
            c.currentHp == 0 && not c.acceptingDeathSaves

        dead =
            Encounter.DeathSaves.isDead c.deathSaves
    in
    c.hasSpecialReactions && not down && not dead


specialReactionsBanner : List Creature -> Html Msg
specialReactionsBanner creatures =
    div
        [ class "legendary-banner legendary-banner--special-reactions"
        , attribute "role" "note"
        ]
        (text "Special reactions: "
            :: (creatures
                    |> List.map nameNode
                    |> List.intersperse (text ", ")
               )
        )


hasAvailableLegendaryAction : Creature -> Bool
hasAvailableLegendaryAction c =
    let
        total =
            c.legendaryActionsCount + c.legendaryActionsLairBonus

        down =
            -- At 0 HP and not actively burning death saves
            -- (which means the creature is treated as dead for
            -- non-Player kinds, and as unconscious for Players
            -- between rolls).  Either state bars LA use.
            c.currentHp == 0 && not c.acceptingDeathSaves

        dead =
            Encounter.DeathSaves.isDead c.deathSaves
    in
    -- Surprised, down, or dead creatures are suppressed from
    -- the reminder banner: 5e bars them from using LA until
    -- those conditions clear.  Once the lifecycle (or the GM)
    -- clears the relevant flag, they re-appear in the banner
    -- without any further state change.
    total
        > 0
        && Set.size c.legendaryActionsUsed
        < total
        && not c.surprised
        && not down
        && not dead


legendaryActionBanner : List Creature -> Html Msg
legendaryActionBanner creatures =
    let
        nameNodes =
            creatures
                |> List.concatMap nameWithCount
                |> dropTrailingComma
    in
    div
        [ class "legendary-banner"
        , attribute "role" "note"
        ]
        (text "⚜ Legendary Action available: " :: nameNodes)


{-| Render `<Name> (N),` where N is the count of un-spent
legendary-action pips on this creature. The trailing comma /
space is stripped off the last entry by `dropTrailingComma`
below so the banner reads cleanly.
-}
nameWithCount : Creature -> List (Html Msg)
nameWithCount c =
    let
        total =
            c.legendaryActionsCount + c.legendaryActionsLairBonus

        available =
            total - Set.size c.legendaryActionsUsed
    in
    [ nameNode c
    , span [ class "legendary-banner__count" ]
        [ text (" (" ++ String.fromInt available ++ ")") ]
    , text ", "
    ]


dropTrailingComma : List (Html msg) -> List (Html msg)
dropTrailingComma nodes =
    -- The comma-space text node is the last item produced by
    -- `nameWithCount`; trim it so the banner doesn't end with
    -- a dangling separator.
    case List.reverse nodes of
        _ :: rest ->
            List.reverse rest

        [] ->
            []


nameNode : Creature -> Html Msg
nameNode c =
    case c.creatureId of
        Just creatureId ->
            button
                [ class "legendary-banner__name"
                , type_ "button"
                , onClick (PanelShowCreature creatureId c.name)
                , Tooltips.attr ("Pin " ++ c.name ++ "'s stat block to the side panel")
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
