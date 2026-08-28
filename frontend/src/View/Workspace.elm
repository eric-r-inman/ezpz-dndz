module View.Workspace exposing (view)

{-| Three-pane workspace layout for the Home route: encounter pane
on the left (creature cards under the encounter title bar), control
buttons in the middle, compendium / detail pane on the right.

Each pane is a separate `View/` module — this module just wires
them together with the model fragments each one needs.

-}

import Compendium.Casters as Casters
import Effects
import Encounter exposing (Creature, Encounter)
import Encounter.DeathSaves
import Html exposing (Html, button, div, main_, section, span, text)
import Html.Attributes exposing (attribute, class, disabled, id, type_)
import Html.Events exposing (onClick)
import Model exposing (Model, Surface(..))
import Msg exposing (Msg(..))
import Set
import Ui.Compendium exposing (CompendiumDb(..))
import View.Card
import View.EncounterBar
import View.Inline.Condition
import View.Inline.Duplicate
import View.Inline.HpChange
import View.Inline.Initiative
import View.Inline.Replace
import View.Inline.SaveChain
import View.Inline.SpellList
import View.Inline.Status
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
        [ panelMain model
        , View.PanelControls.view
            model.auth
            model.dice
            model.pendingControl
            model.encounter.round
            (Encounter.rosterDirty model.encounter model.savedSnapshot)
            model.controlMenu
        , View.PanelDetail.view model
        ]


{-| The encounter pane. Builds the card context each card render
needs (inline-edit and rename states, the open surface, timer
presets), then stacks the stationary strips — title bar,
reminder banners, the action toolbar, and any docked editor —
above the scrolling card grid. `savedAs` lights up the title-bar
info icon with the source filename; the compendium DB + XP scope
let the title bar's right cluster compute the real XP total.
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
            [ View.EncounterBar.view View.EncounterBar.FullBar enc model.savedAs model.compendium.db model.xpScope model.xpFilterOpen ]
        , legendaryActionStrip enc
        , specialReactionsStrip enc
        , spellcasterStrip enc model.compendium.db (model.surface == Just SurfaceSpellList)
        , spellListPanel model
        , actionToolbar model
        , dockedEditor model
        , div
            [ class "panel__body"
            , id Effects.encounterPanelBodyId
            ]
            [ div [ class "creature-grid" ]
                (List.map (View.Card.view cardContext) enc.creatures)
            , quickAddRow
            ]
        ]


{-| Stationary action toolbar under the reminder banners. Each
trigger targets the active creature, falling back to the top of
the queue before combat starts; the editors' own "apply to
selected" buttons cover multi-creature use. Disabled with an
empty queue — there is nothing to target.
-}
actionToolbar : Model -> Html Msg
actionToolbar model =
    let
        target =
            if String.isEmpty model.encounter.activeName then
                model.encounter.creatures
                    |> List.head
                    |> Maybe.map .name
                    |> Maybe.withDefault ""

            else
                model.encounter.activeName

        noTargets =
            String.isEmpty target

        hpEditing =
            case model.surface of
                Just (SurfaceHpChange _) ->
                    True

                _ ->
                    False

        conditionEditing =
            case model.surface of
                Just (SurfaceCondition _) ->
                    True

                _ ->
                    False

        statusEditing =
            case model.surface of
                Just (SurfaceStatus _) ->
                    True

                _ ->
                    False

        saveChainEditing =
            case model.surface of
                Just (SurfaceSaveChain _) ->
                    True

                _ ->
                    False

        initiativeEditing =
            case model.surface of
                Just (SurfaceInitiative _) ->
                    True

                _ ->
                    False

        replaceEditing =
            case model.surface of
                Just (SurfaceReplace _) ->
                    True

                _ ->
                    False

        duplicateEditing =
            case model.surface of
                Just (SurfaceDuplicate _) ->
                    True

                _ ->
                    False

        trigger baseClass editing openMsg openTip label =
            button
                [ class (View.Card.editorTriggerClass baseClass editing)
                , onClick openMsg
                , disabled noTargets
                , Tooltips.attr
                    (if editing then
                        Tooltips.inlineEditCancel

                     else
                        openTip
                    )
                , attribute "aria-expanded"
                    (if editing then
                        "true"

                     else
                        "false"
                    )
                ]
                -- The triangle doubles as the open/closed cue:
                -- ▾ invites expansion, ▴ says "click to fold".
                [ text label
                , span [ class "encounter-toolbar__caret" ]
                    [ text
                        (if editing then
                            "▲"

                         else
                            "▼"
                        )
                    ]
                ]
    in
    div [ class "encounter-toolbar" ]
        [ trigger "action-btn action-btn--manage-hp" hpEditing (HpChangeOpen target) Tooltips.manageHp "Manage HP"
        , trigger "action-btn action-btn--blue" statusEditing (StatusOpen target) Tooltips.statusEditor "Status"
        , trigger "action-btn action-btn--condition" conditionEditing (ConditionOpenNew target) Tooltips.applyCondition "Condition/Effect"
        , trigger "action-btn action-btn--save-chain" saveChainEditing (SaveChainOpen target) Tooltips.saveChain "Save Chain"
        , trigger "action-btn action-btn--blue" initiativeEditing (InitiativeOpen target) Tooltips.initiativeManager "Initiative"
        , trigger "action-btn action-btn--orange" replaceEditing (ReplaceOpen target) Tooltips.queueReplace "Replace"
        , trigger "action-btn action-btn--orange" duplicateEditing (DuplicateOpen target) Tooltips.queueDuplicate "Duplicate"
        ]


{-| The docked editor area directly under the toolbar. Because
the editor no longer sits on the creature it targets, a slim
strip names the target; the editors themselves are unchanged.
Scrolls internally past 60% of the viewport so a tall condition
form can't push the queue off screen.
-}
dockedEditor : Model -> Html Msg
dockedEditor model =
    let
        selectedCount =
            List.length (List.filter .selected model.encounter.creatures)

        -- Manage HP and Save Chain still choose their scope with
        -- a checkbox, so their strip has to name the selection
        -- when it is ticked; the button-scoped editors always
        -- name their own target.
        scopedLabel targetName applyToSelected =
            if applyToSelected && selectedCount > 0 then
                "Target: Selected (" ++ String.fromInt selectedCount ++ ")"

            else
                "Target: " ++ targetName

        docked label body =
            div [ class "encounter-toolbar__editor" ]
                [ div [ class "encounter-toolbar__target" ]
                    [ text label ]
                , body
                ]
    in
    case model.surface of
        Just (SurfaceHpChange ui) ->
            docked (scopedLabel ui.target ui.applyToSelected)
                (View.Inline.HpChange.view selectedCount model.hpChangeLog ui)

        Just (SurfaceCondition ui) ->
            docked ("Target: " ++ ui.target)
                (View.Inline.Condition.view
                    { creatureNames = List.map .name model.encounter.creatures
                    , selectedCount = selectedCount
                    , presets = model.conditionPresets
                    , log = model.conditionLog
                    }
                    ui
                )

        Just (SurfaceSaveChain ui) ->
            docked (scopedLabel ui.target ui.applyToSelected)
                (View.Inline.SaveChain.view
                    { presets = model.saveChainPresets
                    , selectedCount = selectedCount
                    , log = model.saveChainLog
                    }
                    ui
                )

        Just (SurfaceStatus ui) ->
            docked ("Target: " ++ ui.target)
                (View.Inline.Status.view selectedCount ui)

        Just (SurfaceInitiative ui) ->
            docked ("Target: " ++ ui.target)
                (View.Inline.Initiative.view selectedCount ui)

        Just (SurfaceReplace ui) ->
            docked ("Target: " ++ ui.target)
                (View.Inline.Replace.view model.compendium.db
                    selectedCount
                    model.replaceLog
                    ui
                )

        Just (SurfaceDuplicate ui) ->
            docked ("Target: " ++ ui.target)
                (View.Inline.Duplicate.view selectedCount model.duplicateLog ui)

        _ ->
            text ""


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
                        :: spellListButton listOpen
                        :: (casters
                                |> List.map nameNode
                                |> List.intersperse (text ", ")
                           )
                    )

        _ ->
            text ""


spellListButton : Bool -> Html Msg
spellListButton open =
    button
        [ class (View.Card.editorTriggerClass "legendary-banner__spell-btn" open)
        , type_ "button"
        , onClick SpellListOpen
        , Tooltips.attr
            (if open then
                Tooltips.inlineEditCancel

             else
                Tooltips.encounterBarSpellList
            )
        , attribute "aria-label" Tooltips.encounterBarSpellList
        , attribute "aria-expanded"
            (if open then
                "true"

             else
                "false"
            )
        ]
        [ text "📜" ]


{-| The spell list itself, dropping down under the strip that
opens it rather than covering the queue.
-}
spellListPanel : Model -> Html Msg
spellListPanel model =
    case model.surface of
        Just SurfaceSpellList ->
            View.Inline.SpellList.view model.encounter model.compendium.db

        _ ->
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
        (text "Legendary actions: " :: nameNodes)


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
