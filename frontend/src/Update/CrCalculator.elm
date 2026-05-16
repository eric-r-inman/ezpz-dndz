module Update.CrCalculator exposing
    ( open, close
    , scopeSet
    , partyMemberAdd, partyMemberRemove
    , partyMemberLevelSet
    )

{-| Update handlers for the CR Calculator modal.

The party (`model.party`) lives on Model so a closed-and-reopened
modal keeps the GM's last roster. Scope (`ui.scope`) is modal-
local because it's a transient view-of-the-day decision.

@docs open, close
@docs scopeSet
@docs partyMemberAdd, partyMemberRemove, partyMemberLevelChanged

-}

import Encounter.Difficulty as Difficulty
import Encounter.Xp as Xp
import Model exposing (Modal(..), Model)
import Msg exposing (Msg(..))
import Ui.CrCalculator as CrCalc



-- ── OPEN / CLOSE ─────────────────────────────────────────────────────────────


open : Model -> ( Model, Cmd Msg )
open model =
    let
        -- First open seeds a sensible default party (4× level 1)
        -- so the modal isn't immediately useless.  Subsequent
        -- opens keep whatever the GM has typed.
        seeded =
            if List.isEmpty model.party then
                let
                    members =
                        List.range 1 4
                            |> List.map
                                (\i ->
                                    { id = i, level = 1 }
                                )
                in
                { model
                    | party = members
                    , nextPartyMemberId = 5
                }

            else
                model
    in
    ( { seeded | modal = Just (ModalCrCalculator CrCalc.fresh) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )



-- ── SCOPE ────────────────────────────────────────────────────────────────────


scopeSet : Xp.XpScope -> Model -> ( Model, Cmd Msg )
scopeSet scope model =
    ( Model.mapModal Model.crCalculatorLens
        (\ui -> { ui | scope = scope })
        model
    , Cmd.none
    )



-- ── PARTY EDITS ──────────────────────────────────────────────────────────────


partyMemberAdd : Model -> ( Model, Cmd Msg )
partyMemberAdd model =
    let
        newMember : Difficulty.PartyMember
        newMember =
            { id = model.nextPartyMemberId, level = 1 }
    in
    ( { model
        | party = model.party ++ [ newMember ]
        , nextPartyMemberId = model.nextPartyMemberId + 1
      }
    , Cmd.none
    )


partyMemberRemove : Int -> Model -> ( Model, Cmd Msg )
partyMemberRemove memberId model =
    ( { model | party = List.filter (\m -> m.id /= memberId) model.party }
    , Cmd.none
    )


partyMemberLevelSet : Int -> String -> Model -> ( Model, Cmd Msg )
partyMemberLevelSet memberId raw model =
    case String.toInt (String.trim raw) of
        Just lvl ->
            let
                clamped =
                    clamp Difficulty.minLevel Difficulty.maxLevel lvl
            in
            ( { model
                | party =
                    List.map
                        (\m ->
                            if m.id == memberId then
                                { m | level = clamped }

                            else
                                m
                        )
                        model.party
              }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )
