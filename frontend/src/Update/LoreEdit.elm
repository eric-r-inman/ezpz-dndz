module Update.LoreEdit exposing
    ( openNew, openExisting, close
    , save, nameChanged, weightChanged
    , addSearchChanged
    , memberAdd, memberRemove, memberRoleSet
    , memberCountMinChanged, memberCountMaxChanged
    , test
    , descriptionChanged
    )

{-| Update handlers for the standalone **Edit Lore Group** modal.

The modal owns its own `LoreEditUi` substate (see `Ui.LoreEdit`);
this module pattern-matches on `model.modal == Just (ModalLoreEdit _)`
and threads draft mutations through `mapModal loreEditLens`.

Save commits the validated draft into `model.userLoreGroups`, the
same field the random-encounter generator and the soon-to-be-
removed inline editor both read from. Persistence is handled by
the standard `userLoreGroupsCmd` hook in `Main.update`, so no
extra Cmd is fired here.

@docs openNew, openExisting, close
@docs save, nameChanged, weightChanged
@docs addSearchChanged
@docs memberAdd, memberRemove, memberRoleSet
@docs memberCountMinChanged, memberCountMaxChanged
@docs test

-}

import Compendium
import Encounter.RandomEncounter.Lore as Lore
import Encounter.RandomEncounter.Lore.Suggest as Suggest
import Model exposing (Modal(..), Model)
import Msg exposing (Msg)
import Ui.Compendium as CompendiumUi
import Ui.GroupEdit as GroupEdit exposing (LoreDraft, LoreMemberDraft)
import Ui.LoreEdit as LoreEdit


openNew : Model -> ( Model, Cmd Msg )
openNew model =
    ( { model | modal = Just (ModalLoreEdit LoreEdit.freshForNew) }
    , Cmd.none
    )


{-| Open the modal pre-populated from a user-authored lore group.
Looks up by id in `model.userLoreGroups`; falls through to a
no-op if the id isn't found (would only happen on a stale UI
click after the group was deleted in another tab).
-}
openExisting : String -> Model -> ( Model, Cmd Msg )
openExisting groupId model =
    case List.filter (\g -> g.id == groupId) model.userLoreGroups of
        g :: _ ->
            ( { model | modal = Just (ModalLoreEdit (LoreEdit.freshForExisting g)) }
            , Cmd.none
            )

        [] ->
            ( model, Cmd.none )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


{-| Validate + commit the draft into `model.userLoreGroups`. The
auto-persistence hook in `Main.update` picks up the change and
PUTs the new list to the server (or localStorage for anonymous).
On validation failure, parks the error string on `submitError`
for the modal banner.
-}
save : Model -> ( Model, Cmd Msg )
save model =
    case Maybe.andThen Model.loreEditLens.extract model.modal of
        Just ui ->
            case GroupEdit.validateLoreDraft ui.draft of
                Ok newGroup ->
                    let
                        replaced =
                            if
                                List.any
                                    (\g -> g.id == newGroup.id)
                                    model.userLoreGroups
                            then
                                List.map
                                    (\g ->
                                        if g.id == newGroup.id then
                                            newGroup

                                        else
                                            g
                                    )
                                    model.userLoreGroups

                            else
                                model.userLoreGroups ++ [ newGroup ]
                    in
                    ( { model
                        | userLoreGroups = replaced
                        , modal = Nothing
                      }
                    , Cmd.none
                    )

                Err err ->
                    ( Model.mapModal Model.loreEditLens
                        (\u -> { u | submitError = Just err })
                        model
                    , Cmd.none
                    )

        Nothing ->
            ( model, Cmd.none )


nameChanged : String -> Model -> ( Model, Cmd Msg )
nameChanged raw =
    mutateDraft
        (\d -> { d | name = String.left GroupEdit.maxNameLength raw })


descriptionChanged : String -> Model -> ( Model, Cmd Msg )
descriptionChanged raw =
    mutateDraft (\d -> { d | description = raw })


weightChanged : String -> Model -> ( Model, Cmd Msg )
weightChanged raw model =
    case String.toInt (String.trim raw) of
        Just n ->
            mutateDraft (\d -> { d | weight = clamp 1 10 n }) model

        Nothing ->
            ( model, Cmd.none )


addSearchChanged : String -> Model -> ( Model, Cmd Msg )
addSearchChanged raw model =
    ( Model.mapModal Model.loreEditLens
        (\ui -> { ui | addSearch = raw })
        model
    , Cmd.none
    )


memberAdd : String -> Model -> ( Model, Cmd Msg )
memberAdd creatureName =
    mutateDraft
        (\d ->
            { d
                | members =
                    d.members
                        ++ [ { creatureName = creatureName
                             , role = Lore.Member
                             , countMin = "1"
                             , countMax = "1"
                             }
                           ]
            }
        )


memberRemove : Int -> Model -> ( Model, Cmd Msg )
memberRemove idx =
    mutateDraft
        (\d -> { d | members = removeAt idx d.members })


memberRoleSet : Int -> String -> Model -> ( Model, Cmd Msg )
memberRoleSet idx raw =
    case roleFromString raw of
        Just role ->
            mutateDraft
                (\d ->
                    { d
                        | members =
                            updateAt idx
                                (\m -> { m | role = role })
                                d.members
                    }
                )

        Nothing ->
            \model -> ( model, Cmd.none )


memberCountMinChanged : Int -> String -> Model -> ( Model, Cmd Msg )
memberCountMinChanged idx raw =
    mutateDraft
        (\d ->
            { d
                | members =
                    updateAt idx (\m -> { m | countMin = raw }) d.members
            }
        )


memberCountMaxChanged : Int -> String -> Model -> ( Model, Cmd Msg )
memberCountMaxChanged idx raw =
    mutateDraft
        (\d ->
            { d
                | members =
                    updateAt idx (\m -> { m | countMax = raw }) d.members
            }
        )


{-| Run the Suggest back-solver against the current draft and
stash the recommendation in `ui.testResult` for the panel
rendered below the action row. No-op on validation failure —
the existing submitError banner already surfaces that.
-}
test : Model -> ( Model, Cmd Msg )
test model =
    case Maybe.andThen Model.loreEditLens.extract model.modal of
        Just ui ->
            case GroupEdit.validateLoreDraft ui.draft of
                Ok group ->
                    let
                        pool =
                            case model.compendium.db of
                                CompendiumUi.CompendiumDbLoaded db ->
                                    Compendium.toList db

                                _ ->
                                    []
                    in
                    ( Model.mapModal Model.loreEditLens
                        (\u -> { u | testResult = Just (Suggest.suggestFor pool group) })
                        model
                    , Cmd.none
                    )

                Err _ ->
                    ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )



-- ── INTERNAL ────────────────────────────────────────────────────────────────


mutateDraft : (LoreDraft -> LoreDraft) -> Model -> ( Model, Cmd Msg )
mutateDraft fn model =
    ( Model.mapModal Model.loreEditLens (LoreEdit.withDraft fn) model
    , Cmd.none
    )


roleFromString : String -> Maybe Lore.Role
roleFromString s =
    case s of
        "leader" ->
            Just Lore.Leader

        "member" ->
            Just Lore.Member

        "minion" ->
            Just Lore.Minion

        "pet" ->
            Just Lore.Pet

        _ ->
            Nothing


updateAt : Int -> (a -> a) -> List a -> List a
updateAt idx fn =
    List.indexedMap
        (\i x ->
            if i == idx then
                fn x

            else
                x
        )


removeAt : Int -> List a -> List a
removeAt idx =
    List.indexedMap Tuple.pair
        >> List.filter (\( i, _ ) -> i /= idx)
        >> List.map Tuple.second
