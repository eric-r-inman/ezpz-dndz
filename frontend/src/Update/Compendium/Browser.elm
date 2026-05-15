module Update.Compendium.Browser exposing
    ( addedToggle, close, focusSearch, kindToggled, loaded
    , open, panelShowCreature, searchChanged, searchId, select
    , sortChanged, withCompendium
    , bulkMenuClose, bulkMenuToggle, exportClick, rowToggle
    )

{-| Update branches for the compendium browser modal: load, open /
close, search, kind filter, sort, select, the add-count input,
and the right-pane "Show in Compendium" pinning from a creature
card.

The browser owns the persistent `model.compendium` UI state
(visible whether or not the modal is open — its filters and
selection survive a close so the next open returns the GM
to where they were). `withCompendium` is therefore a flat
field lens, not a modal lens.

@docs addedToggle, close, focusSearch, kindToggled, loaded
@docs open, panelShowCreature, searchChanged, searchId, select
@docs sortChanged, withCompendium

-}

import Browser.Dom
import Compendium
import Http
import Model exposing (Model)
import Msg
    exposing
        ( CompendiumSort
        , Msg(..)
        )
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
rather than a `Model.mapModal` call.
-}
withCompendium : (CompendiumUi -> CompendiumUi) -> Model -> Model
withCompendium fn model =
    { model | compendium = fn model.compendium }


loaded : Result Http.Error (List Compendium.Creature) -> Model -> ( Model, Cmd Msg )
loaded result model =
    ( withCompendium (loadedUpdate result) model, Cmd.none )


loadedUpdate : Result Http.Error (List Compendium.Creature) -> CompendiumUi -> CompendiumUi
loadedUpdate result ui =
    case result of
        Ok creatures ->
            { ui | db = CompendiumDbLoaded (Compendium.fromList creatures) }

        Err err ->
            { ui | db = CompendiumDbFailed err }


open : Model -> ( Model, Cmd Msg )
open model =
    ( withCompendium openUpdate model, Cmd.none )


{-| Open the modal and pick a sensible default selection so the
right pane isn't blank on first open. We pick the first item of
the currently-rendered (filter+sort applied) list.
-}
openUpdate : CompendiumUi -> CompendiumUi
openUpdate ui =
    let
        opened =
            { ui | open = True }
    in
    case ui.selectedId of
        Just _ ->
            opened

        Nothing ->
            { opened
                | selectedId =
                    CompendiumUi.compendiumVisible opened
                        |> List.head
                        |> Maybe.map .id
            }


close : Model -> ( Model, Cmd Msg )
close model =
    ( withCompendium (\ui -> { ui | open = False }) model, Cmd.none )


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


select : String -> Model -> ( Model, Cmd Msg )
select id model =
    ( withCompendium
        (\ui ->
            { ui
                | selectedId = Just id

                -- Selecting a creature clears any group selection
                -- so the right pane reads as "this creature's
                -- stat block" rather than "this group's
                -- contents".
                , selectedGroupId = Nothing
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
    ( { model
        | panelCreaturePin =
            Just { id = creatureId, name = creatureName }
      }
    , Cmd.none
    )
