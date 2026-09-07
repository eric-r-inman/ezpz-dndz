module Update.CrCalculator exposing
    ( scopeSet
    , partyMemberAdd, partyMemberRemove, partyMemberLevelSet
    )

{-| Update handlers for the CR Calculator panel.

The party (`model.party`) lives on Model because the Random
Encounter panel shares it. Scope (`ui.scope`) is panel-local.

@docs scopeSet
@docs partyMemberAdd, partyMemberRemove, partyMemberLevelSet

-}

import Encounter.Difficulty as Difficulty
import Encounter.Xp as Xp
import Model exposing (Model)
import Msg exposing (Msg(..))



-- ── SCOPE ────────────────────────────────────────────────────────────────────


scopeSet : Xp.XpScope -> Model -> ( Model, Cmd Msg )
scopeSet scope model =
    ( Model.mapSurface Model.crCalculatorLens
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
