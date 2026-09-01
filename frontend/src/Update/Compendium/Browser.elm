module Update.Compendium.Browser exposing
    ( addedToggle, focusSearch, kindToggled, loaded
    , open, panelShowCreature, searchChanged, searchId, select
    , sortChanged, withCompendium
    , bulkMenuClose, bulkMenuToggle, exportClick, rowToggle, showCreature, tagFilterChanged
    )

{-| Update branches for the compendium browser's list-side
interactions, plus the "Show in Compendium" pinning from a
creature card.

The browser owns the persistent `model.compendium` UI state —
permanent rather than surface-scoped, since the browser is its
own tab. `withCompendium` is therefore a flat field lens, not a
surface lens.

@docs addedToggle, focusSearch, kindToggled, loaded
@docs open, panelShowCreature, searchChanged, searchId, select
@docs sortChanged, withCompendium

-}

import Browser.Dom
import Compendium
import Effects
import Http
import Model exposing (Model)
import Msg
    exposing
        ( CompendiumSort
        , Msg(..)
        )
import Ports
import Route
import Set
import Task
import Ui.Compendium as CompendiumUi
    exposing
        ( CompendiumDb(..)
        , CompendiumUi
        )


{-| HTML id of the compendium search input. Exposed so the view
layer can wire up `id` and the `CompendiumFocusSearch` Msg can
focus it via `Browser.Dom.focus`.
-}
searchId : String
searchId =
    "compendium-search"


{-| Flat lens over `model.compendium`. The browser substate is
always present (no `Maybe`), so this is a direct field update
rather than a `Model.mapSurface` call.
-}
withCompendium : (CompendiumUi -> CompendiumUi) -> Model -> Model
withCompendium fn model =
    { model | compendium = fn model.compendium }


loaded : Result Http.Error (List Compendium.Creature) -> Model -> ( Model, Cmd Msg )
loaded result model =
    let
        effectiveResult =
            mergedResult result model
    in
    ( { model | pendingBundleMerge = False }
        |> withCompendium (loadedUpdate effectiveResult)
        |> syncEncounterFromCompendium effectiveResult
      -- A tab opened on a specific creature (the URL's
      -- ?creature= seed) can only scroll to its row once the
      -- library has landed and the rows exist.
    , if model.route == Route.Compendium then
        model.compendium.selectedId
            |> Maybe.map Effects.scrollCompendiumRowIntoView
            |> Maybe.withDefault Cmd.none

      else
        Cmd.none
    )


loadedUpdate : Result Http.Error (List Compendium.Creature) -> CompendiumUi -> CompendiumUi
loadedUpdate result ui =
    case result of
        Ok creatures ->
            { ui | db = CompendiumDbLoaded (Compendium.fromList creatures) }

        Err err ->
            { ui | db = CompendiumDbFailed err }


{-| When the anonymous boot path detected a stale-bundled-version
snapshot (`pendingBundleMerge = True`), the freshly-fetched
bundle has to be unioned with the user-created creatures in the
snapshot instead of replacing the whole DB. Otherwise the user
would lose every creature they'd authored in anonymous mode
every time the bundle version bumped.

The merge: take all fetched creatures (they win on id collisions
— bundled-id creatures get refreshed) plus any creatures in the
current DB whose ids aren't in the fetched set (user-created).
We return a fresh `Ok merged` so the downstream `loadedUpdate`
and `syncEncounterFromCompendium` both see the unioned list.

When `pendingBundleMerge = False` or the fetch failed, fall
through to the standard replace-everything behaviour by passing
the original result through untouched.

-}
mergedResult :
    Result Http.Error (List Compendium.Creature)
    -> Model
    -> Result Http.Error (List Compendium.Creature)
mergedResult result model =
    case ( result, model.pendingBundleMerge ) of
        ( Ok fetched, True ) ->
            let
                fetchedIds =
                    fetched |> List.map .id |> Set.fromList

                preserved =
                    model.compendium.db
                        |> loadedCreaturesOrEmpty
                        |> List.filter (\c -> not (Set.member c.id fetchedIds))
            in
            Ok (fetched ++ preserved)

        _ ->
            result


loadedCreaturesOrEmpty : CompendiumDb -> List Compendium.Creature
loadedCreaturesOrEmpty db =
    case db of
        CompendiumDbLoaded loaded_ ->
            Compendium.toList loaded_

        _ ->
            []


{-| Refresh the stat-block-derived legendary counters on every
roster creature against the freshly-loaded compendium DB.

In-progress encounters persist creature snapshots to
localStorage, so a saved roster from before the bundle grew
lair-bonus data would stay stuck at `legendaryActionsLairBonus
= 0` until the GM removed and re-added each creature. Re-syncing
here makes the lair pip appear as soon as the new bundle loads,
without touching the "used" sets (which are encounter state the
GM owns).

A decode failure leaves the encounter alone — without a fresh DB
there's nothing to sync against.

-}
syncEncounterFromCompendium : Result Http.Error (List Compendium.Creature) -> Model -> Model
syncEncounterFromCompendium result model =
    case result of
        Err _ ->
            model

        Ok creatures ->
            let
                db =
                    Compendium.fromList creatures

                encounter =
                    model.encounter

                synced =
                    { encounter
                        | creatures =
                            List.map (Compendium.syncLegendaryFields db) encounter.creatures
                    }
            in
            { model | encounter = synced }


{-| Open the standalone /compendium browser tab via the JS
port, or focus it if it is already open. The tab decides its
own selection — nothing is highlighted on the GM's behalf.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    ( model, Ports.openCompendiumTab Nothing )


{-| Open the /compendium browser tab on a specific creature —
the drawer's stat-block panel hands off to the full browser
with its creature already selected.
-}
showCreature : String -> Model -> ( Model, Cmd Msg )
showCreature id model =
    ( model, Ports.openCompendiumTab (Just id) )


searchChanged : String -> Model -> ( Model, Cmd Msg )
searchChanged text model =
    ( withCompendium
        (\ui -> { ui | searchText = text, selectedId = Nothing })
        model
    , Cmd.none
    )


kindToggled : Compendium.CreatureKind -> Model -> ( Model, Cmd Msg )
kindToggled kind model =
    ( withCompendium (toggleKindFilter kind) model, Cmd.none )


toggleKindFilter : Compendium.CreatureKind -> CompendiumUi -> CompendiumUi
toggleKindFilter kind ui =
    let
        key =
            CompendiumUi.kindToString kind

        next =
            if Set.member key ui.kindFilter then
                Set.remove key ui.kindFilter

            else
                Set.insert key ui.kindFilter
    in
    { ui | kindFilter = next, selectedId = Nothing }


sortChanged : CompendiumSort -> Model -> ( Model, Cmd Msg )
sortChanged sort model =
    ( withCompendium (\ui -> { ui | sort = sort }) model, Cmd.none )


tagFilterChanged : String -> Model -> ( Model, Cmd Msg )
tagFilterChanged wire model =
    ( withCompendium
        (\ui ->
            { ui
                | tagFilter = CompendiumUi.tagFilterFromWire wire
                , selectedId = Nothing
            }
        )
        model
    , Cmd.none
    )


select : String -> Model -> ( Model, Cmd Msg )
select id model =
    ( withCompendium
        (\ui ->
            { ui
                | selectedId = Just id

                -- Selecting a creature clears any group / lore
                -- selection so the right pane reads as "this
                -- creature's stat block" rather than carrying a
                -- stale group / lore-group detail alongside.
                , selectedGroupId = Nothing
                , selectedLoreId = Nothing
            }
        )
        model
    , Cmd.none
    )


{-| Flip the "Added" filter — when on, the visible compendium
list narrows to only creatures that have at least one instance
in the current encounter. Filter resolution lives in the view
since it needs `model.encounter`; this branch just toggles the
flag.
-}
addedToggle : Model -> ( Model, Cmd Msg )
addedToggle model =
    ( withCompendium (\ui -> { ui | showOnlyAdded = not ui.showOnlyAdded })
        model
    , Cmd.none
    )


{-| Toggle the bulk-selection checkbox on one creature row.

  - **Plain click** — flip just that creature's membership in
    `selectedIds`.
  - **Shift+click on an unselected row** — select every visible
    creature. "Visible" means after the search / kind /
    --added / --only filters apply.
  - **Shift+click on a selected row** — clear the entire
    selection.

The `shift` flag arrives from a custom event decoder that
reads `event.shiftKey`.

-}
rowToggle : String -> Bool -> Model -> ( Model, Cmd Msg )
rowToggle id shift model =
    let
        ui =
            model.compendium

        nextSelected =
            if shift then
                if Set.member id ui.selectedIds then
                    Set.empty

                else
                    CompendiumUi.compendiumVisible ui
                        |> List.map .id
                        |> Set.fromList

            else if Set.member id ui.selectedIds then
                Set.remove id ui.selectedIds

            else
                Set.insert id ui.selectedIds
    in
    ( withCompendium (\u -> { u | selectedIds = nextSelected }) model
    , Cmd.none
    )


{-| Open / close one of the Compendium-modal split-button
dropdowns (Clear / Import / Export). Toggling the same menu
that's already open closes it; toggling a different menu swaps
to it (the "only one open at a time" invariant is enforced
here so callers don't have to thread two messages). Esc +
click-outside close subscriptions live in `Main.subscriptions`.
-}
bulkMenuToggle : Msg.CompendiumBulkMenu -> Model -> ( Model, Cmd Msg )
bulkMenuToggle which model =
    let
        next =
            if model.compendium.bulkMenu == Just which then
                Nothing

            else
                Just which
    in
    ( withCompendium (\ui -> { ui | bulkMenu = next }) model
    , Cmd.none
    )


bulkMenuClose : Model -> ( Model, Cmd Msg )
bulkMenuClose model =
    ( withCompendium (\ui -> { ui | bulkMenu = Nothing }) model
    , Cmd.none
    )


{-| Mark the in-memory dirty flag clean. Fired by the Export
anchor's onClick (which still triggers the native download via
its `href` + `download` attributes). The yellow border on
Export comes off the moment the GM commits to a download.
-}
exportClick : Model -> ( Model, Cmd Msg )
exportClick model =
    ( withCompendium (\ui -> { ui | compendiumDirty = False }) model
    , Cmd.none
    )


focusSearch : Model -> ( Model, Cmd Msg )
focusSearch model =
    ( model
    , Browser.Dom.focus searchId
        |> Task.attempt (\_ -> NoOp)
    )


panelShowCreature : String -> String -> Model -> ( Model, Cmd Msg )
panelShowCreature creatureId creatureName model =
    ( Model.openDrawer Model.statBlockLens
        { id = creatureId, name = creatureName }
        model
    , Cmd.none
    )
