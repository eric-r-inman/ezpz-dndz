module View.Workspace exposing (view)

{-| Workspace layout for the Home route: the Actions column, the
panel it opens, and the encounter queue.

Each pane is a separate `View/` module — this module just wires
them together with the model fragments each one needs. The
drawer's column only exists while it has something to show,
which is why the grid template is conditional.

-}

import Compendium.Casters as Casters
import Effects
import Encounter exposing (Creature, Encounter)
import Encounter.DeathSaves
import Html exposing (Html, button, div, main_, section, span, text)
import Html.Attributes exposing (attribute, class, id, type_)
import Html.Events exposing (onClick)
import Model exposing (Model)
import Msg exposing (Msg(..), QueuePanel(..))
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import View.Card
import View.EncounterBar
import View.Inline.QueueReference
import View.Inline.SpellList
import View.PanelActions
import View.PanelDrawer
import View.Tooltips as Tooltips


view : Model -> Html Msg
view model =
    main_
        [ class
            (if View.PanelDrawer.isOpen model then
                "workspace workspace--drawer"

             else
                "workspace"
            )
        , id "main"
        , attribute "tabindex" "-1"
        ]
        [ View.PanelActions.view model
        , View.PanelDrawer.view model
        , panelMain model
        ]


{-| The encounter pane. Builds the card context each card render
needs (inline-edit and rename states, the open surface, timer
presets), then stacks the stationary strips above the scrolling
card grid. `savedAs` lights up the title-bar info icon with the
source filename; the compendium DB + XP scope let the title
bar's right cluster compute the real XP total.
-}
panelMain : Model -> Html Msg
panelMain model =
    let
        enc =
            model.encounter

        cardContext =
            { activeName = enc.activeName
            , hpEdit = model.hpEdit
            , renameState = model.placeholderRename
            , surface = model.surface
            , timerPresets = model.timerPresets
            , compendium = model.compendium.db
            }
    in
    section [ class "panel panel--main" ]
        [ div [ class "panel__header panel__header--encounter" ]
            [ View.EncounterBar.view View.EncounterBar.FullBar enc model.savedAs ]
        , legendaryActionStrip enc model.queuePanels.legendaryActions
        , specialReactionsStrip enc model.queuePanels.specialReactions
        , spellcasterStrip enc model.compendium.db model.queuePanels.spells
        , panelIf model.queuePanels.legendaryActions
            (View.Inline.QueueReference.legendaryActions enc model.compendium.db)
        , panelIf model.queuePanels.specialReactions
            (View.Inline.QueueReference.specialReactions enc model.compendium.db)
        , panelIf model.queuePanels.spells
            (View.Inline.SpellList.view enc model.compendium.db)
        , div
            [ class "panel__body"
            , id Effects.encounterPanelBodyId
            ]
            [ div [ class "creature-grid" ]
                (List.map (View.Card.view cardContext) enc.creatures)
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
legendaryActionStrip : Encounter -> Bool -> Html Msg
legendaryActionStrip enc panelOpen =
    let
        eligible =
            enc.creatures
                |> List.filter hasAvailableLegendaryAction
                |> List.filter (\c -> c.name /= enc.activeName)
    in
    if List.isEmpty eligible then
        text ""

    else
        legendaryActionBanner eligible panelOpen


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
specialReactionsStrip : Encounter -> Bool -> Html Msg
specialReactionsStrip enc panelOpen =
    let
        eligible =
            List.filter specialReactionsEligible enc.creatures
    in
    if List.isEmpty eligible then
        text ""

    else
        specialReactionsBanner eligible panelOpen


{-| Sticky orange strip under the special-reactions one, naming
every queue member whose source can cast. The spell-list button
sits inside the strip rather than in the title bar, so the
reminder and the reference it opens read as one affordance.
Counts stay out of it — the compendium pane has the detail once
the GM clicks a name.
-}
spellcasterStrip : Encounter -> CompendiumDb -> Bool -> Html Msg
spellcasterStrip enc db listOpen =
    case db of
        CompendiumDbLoaded loaded ->
            let
                casters =
                    enc.creatures
                        |> List.filterMap (Casters.resolve loaded)
                        |> List.map .creature
            in
            if List.isEmpty casters then
                text ""

            else
                div
                    [ class "legendary-banner legendary-banner--spells"
                    , attribute "role" "note"
                    ]
                    (text "Spells: "
                        :: stripButton SpellsPanel listOpen "📜" Tooltips.encounterBarSpellList
                        :: (casters
                                |> List.map nameNode
                                |> List.intersperse (text ", ")
                           )
                    )

        _ ->
            text ""


{-| One strip's drop-down toggle, sitting between the strip's
label and its creature names. Wears the shared open-editor ring
so an open panel is as visible as an open editor.
-}
stripButton : QueuePanel -> Bool -> String -> String -> Html Msg
stripButton panel open glyph openTip =
    button
        [ class (View.Card.editorTriggerClass "legendary-banner__panel-btn" open)
        , type_ "button"
        , onClick (QueuePanelToggle panel)
        , Tooltips.attr
            (if open then
                Tooltips.inlineEditCancel

             else
                openTip
            )
        , attribute "aria-label" openTip
        , attribute "aria-expanded"
            (if open then
                "true"

             else
                "false"
            )
        ]
        [ text glyph ]


{-| The reference drop-downs render below every strip, so the
strips stay together, and in the strips' own order when more
than one is open.
-}
panelIf : Bool -> Html Msg -> Html Msg
panelIf open panel =
    if open then
        panel

    else
        text ""


specialReactionsEligible : Creature -> Bool
specialReactionsEligible c =
    let
        down =
            c.currentHp == 0 && not c.acceptingDeathSaves

        dead =
            Encounter.DeathSaves.isDead c.deathSaves
    in
    c.hasSpecialReactions && not down && not dead


specialReactionsBanner : List Creature -> Bool -> Html Msg
specialReactionsBanner creatures panelOpen =
    div
        [ class "legendary-banner legendary-banner--special-reactions"
        , attribute "role" "note"
        ]
        (text "Special reactions: "
            :: stripButton SpecialReactionsPanel panelOpen "⚡" Tooltips.specialReactionsPanel
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


legendaryActionBanner : List Creature -> Bool -> Html Msg
legendaryActionBanner creatures panelOpen =
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
        (text "Legendary actions: "
            :: stripButton LegendaryActionsPanel panelOpen "⚜" Tooltips.legendaryActionsPanel
            :: nameNodes
        )


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
                , Tooltips.attr (Tooltips.pinStatBlock c.name)
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
the queue. Opens the same Quick Add panel the Actions column
does, surfaced inside the queue itself so the GM doesn't have to
track across to add another creature. Hover text doubles as the
aria-label so screen-reader users hear the intent rather than
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
