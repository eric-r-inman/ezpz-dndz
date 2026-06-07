module Encounter.Difficulty exposing
    ( PartyMember
    , XpBudget, Difficulty(..)
    , xpBudgetForLevel, partyBudget
    , classify
    , difficultyKey, difficultyLabel, difficultyDescription
    , maxLevel, minLevel
    , encodePartyState, decodePartyState
    )

{-| Encounter-difficulty math.

D&D 2024's encounter-building model is an _XP budget per
character_: each character level has Low / Moderate / High
budgets, summed across the party, compared against the
encounter's total monster XP. 2024 dropped the 2014-era
multi-monster multiplier — a fight is exactly as hard as the sum
of its monsters' XP, no number-of-foes adjustment.

This module owns:

  - the per-level XP budget table (clamped 1–20),
  - party-level aggregation,
  - the encounter-XP-to-difficulty classifier,
  - difficulty-label / key helpers for the view layer.

No `Html`, no `Msg` — same discipline as
[`Encounter.Xp`](Encounter-Xp).

@docs PartyMember
@docs XpBudget, Difficulty
@docs xpBudgetForLevel, partyBudget
@docs classify
@docs difficultyKey, difficultyLabel, difficultyDescription
@docs maxLevel, minLevel
@docs encodePartyState, decodePartyState

-}

import Json.Decode as D
import Json.Encode as E


type alias PartyMember =
    { id : Int
    , level : Int
    }


type alias XpBudget =
    { low : Int
    , moderate : Int
    , high : Int
    }


type Difficulty
    = Trivial
    | LowDifficulty
    | ModerateDifficulty
    | HighDifficulty
    | BeyondHigh



-- ── BUDGET TABLE ─────────────────────────────────────────────────────────────


{-| Approximate D&D 2024 DMG XP Budget per Character. Values are
the per-character budgets at the three difficulty tiers (Low /
Moderate / High); sum across the party gives the encounter
budget.

If specific numbers turn out to be off from the printed table,
this is a one-line correction per row. The shape — three tiers,
monotone-increasing — is fixed by the system.

-}
xpBudgetForLevel : Int -> XpBudget
xpBudgetForLevel raw =
    let
        level =
            clamp minLevel maxLevel raw
    in
    case level of
        1 ->
            XpBudget 50 75 100

        2 ->
            XpBudget 100 150 200

        3 ->
            XpBudget 150 225 400

        4 ->
            XpBudget 250 375 500

        5 ->
            XpBudget 500 750 1100

        6 ->
            XpBudget 600 1000 1400

        7 ->
            XpBudget 750 1300 1700

        8 ->
            XpBudget 1000 1700 2100

        9 ->
            XpBudget 1300 2000 2600

        10 ->
            XpBudget 1600 2300 3100

        11 ->
            XpBudget 1900 2900 4100

        12 ->
            XpBudget 2200 3700 4700

        13 ->
            XpBudget 2600 4200 5400

        14 ->
            XpBudget 2900 4900 6200

        15 ->
            XpBudget 3300 5400 7800

        16 ->
            XpBudget 3800 6100 9800

        17 ->
            XpBudget 4500 7200 11700

        18 ->
            XpBudget 5000 8700 14200

        19 ->
            XpBudget 5500 10700 17200

        _ ->
            -- Level 20 (and out-of-range clamp target).
            XpBudget 6400 13200 22000


minLevel : Int
minLevel =
    1


maxLevel : Int
maxLevel =
    20



-- ── AGGREGATION ──────────────────────────────────────────────────────────────


{-| Sum the per-character XP budgets across an entire party. An
empty party returns a zero budget (the view should hide the
classifier in that case rather than reporting "Beyond high" for
every encounter).
-}
partyBudget : List PartyMember -> XpBudget
partyBudget members =
    List.foldl
        (\m acc ->
            let
                b =
                    xpBudgetForLevel m.level
            in
            { low = acc.low + b.low
            , moderate = acc.moderate + b.moderate
            , high = acc.high + b.high
            }
        )
        { low = 0, moderate = 0, high = 0 }
        members



-- ── CLASSIFIER ───────────────────────────────────────────────────────────────


{-| Bucket `encounterXp` against the party's `budget`:

  - 0 (or no monsters in scope) → `Trivial`
  - `<= low` → `LowDifficulty`
  - `<= moderate` → `ModerateDifficulty`
  - `<= high` → `HighDifficulty`
  - `> high` → `BeyondHigh`

The strict-inequality boundary (`<=`) means an encounter that
exactly hits a tier's number reads as that tier; a tier upgrade
requires exceeding the number.

-}
classify : Int -> XpBudget -> Difficulty
classify encounterXp budget =
    if encounterXp <= 0 then
        Trivial

    else if encounterXp <= budget.low then
        LowDifficulty

    else if encounterXp <= budget.moderate then
        ModerateDifficulty

    else if encounterXp <= budget.high then
        HighDifficulty

    else
        BeyondHigh



-- ── LABEL HELPERS ────────────────────────────────────────────────────────────


difficultyKey : Difficulty -> String
difficultyKey d =
    case d of
        Trivial ->
            "trivial"

        LowDifficulty ->
            "low"

        ModerateDifficulty ->
            "moderate"

        HighDifficulty ->
            "high"

        BeyondHigh ->
            "beyond_high"


difficultyLabel : Difficulty -> String
difficultyLabel d =
    case d of
        Trivial ->
            "Trivial"

        LowDifficulty ->
            "Low"

        ModerateDifficulty ->
            "Moderate"

        HighDifficulty ->
            "High"

        BeyondHigh ->
            "Beyond High"


{-| One-sentence GM-facing summary of the bucket. Surfaces in
the modal's result panel under the headline label so GMs new to
2024's difficulty model have a reference without leaving the app.
-}
difficultyDescription : Difficulty -> String
difficultyDescription d =
    case d of
        Trivial ->
            "Negligible threat. Use sparingly between real encounters or as a tutorial."

        LowDifficulty ->
            "Soft win for the party. Resource cost is light; near-zero risk of a death."

        ModerateDifficulty ->
            "A real fight. The party will spend resources and may take meaningful damage."

        HighDifficulty ->
            "Tough. Expect spell slots burned and a real chance one or more PCs go down."

        BeyondHigh ->
            "Exceeds the 2024 budget ceiling. Likely deadly — split the fight or scale down unless a TPK is desired."



-- ── WIRE FORMAT ──────────────────────────────────────────────────────────────


{-| Encode the full party state for `localStorage.party`. The
auto-increment `next_id` counter is bundled with the member
list so a reload-and-add doesn't accidentally reuse an old id
that's been removed mid-session.
-}
encodePartyState : List PartyMember -> Int -> E.Value
encodePartyState members nextId =
    E.object
        [ ( "members", E.list encodeMember members )
        , ( "next_id", E.int nextId )
        ]


encodeMember : PartyMember -> E.Value
encodeMember m =
    E.object
        [ ( "id", E.int m.id )
        , ( "level", E.int m.level )
        ]


{-| Decode `localStorage.party`. A missing or malformed
`next_id` falls back to `length(members) + 1` so a hand-edited
file still loads — the worst case is a duplicate id on the
next add, which `partyMemberAdd` would catch on subsequent
operations anyway.
-}
decodePartyState : D.Decoder { members : List PartyMember, nextId : Int }
decodePartyState =
    D.map2 (\members nextId -> { members = members, nextId = nextId })
        (D.field "members" (D.list decodeMember))
        (D.oneOf [ D.field "next_id" D.int, D.succeed 0 ])
        |> D.map
            (\state ->
                if state.nextId <= 0 then
                    { state | nextId = List.length state.members + 1 }

                else
                    state
            )


decodeMember : D.Decoder PartyMember
decodeMember =
    D.map2 PartyMember
        (D.field "id" D.int)
        (D.field "level" D.int)
