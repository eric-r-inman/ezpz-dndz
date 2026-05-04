module Update.DeathSave exposing
    ( roll
    , rollLanded
    , toggleFailure
    , toggleSuccess
    )

{-| Update branches for the death-save tracker on creature cards
(the success / failure pip strips and the d20 roll button).

The toggle branches are pure visual (star-rating semantics on the
3-pip strip). The roll path fires a 1d20 through the same dice
machinery used elsewhere; the result lands in `rollLanded`, which
applies the 5e rules and threads the roll into the dice history.

-}

import Dice
import Effects
import Encounter exposing (Creature)
import Model exposing (Model)
import Msg exposing (Msg(..))


withEncounter : (Encounter.Encounter -> Encounter.Encounter) -> Model -> Model
withEncounter fn model =
    { model | encounter = fn model.encounter }


{-| Click on success pip `idx` (0..2). Star-rating semantics:
clicking a filled pip clears it and every later one (so unchecking
pip 0 wipes pips 1 and 2); clicking an empty pip fills up to and
including it. Pure visual toggle — no roll fired here.
-}
toggleSuccess : String -> Int -> Model -> ( Model, Cmd Msg )
toggleSuccess name idx model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c
                    | deathSaves =
                        let
                            ds =
                                c.deathSaves
                        in
                        { ds | successes = pipStripTarget idx ds.successes }
                }
            )
        )
        model
    , Cmd.none
    )


toggleFailure : String -> Int -> Model -> ( Model, Cmd Msg )
toggleFailure name idx model =
    ( withEncounter
        (Encounter.mapCreature name
            (\c ->
                { c
                    | deathSaves =
                        let
                            ds =
                                c.deathSaves
                        in
                        { ds | failures = pipStripTarget idx ds.failures }
                }
            )
        )
        model
    , Cmd.none
    )


{-| Fire a 1d20 roll tagged so the dice history reads
"Death save → <name>". The result lands in `rollLanded` which
interprets it per 5e.
-}
roll : String -> Model -> ( Model, Cmd Msg )
roll name model =
    ( model
    , Dice.rollCmd (DeathSaveRollLanded name)
        (source name)
        expression
    )


{-| 5e death-save rules:

  - nat 1 → +2 failures
  - 2..9 → +1 failure
  - 10..19 → +1 success
  - nat 20 → revive at 1 HP, clear tracker, conscious

The roll itself is a plain 1d20 with no modifier so `roll.total` is
the d20 face. Apply the rule, push the roll into the dice
history, and persist.

-}
rollLanded : String -> Dice.Roll -> Model -> ( Model, Cmd Msg )
rollLanded name d20Roll model =
    let
        applyRule c =
            applyResult d20Roll.total c
    in
    ( { model
        | encounter = Encounter.mapCreature name applyRule model.encounter
      }
        |> Effects.pushDiceRoll d20Roll
    , Effects.persistDiceRoll d20Roll
    )



-- ── HELPERS ────────────────────────────────────────────────────────────


{-| Source label for death-save rolls — "Death save → <creature>"
in the dice history.
-}
source : String -> Dice.Source
source name =
    { feature = "Death save", target = Just name }


{-| Plain 1d20, no modifier. Built once and re-used so every
death-save roll has the same expression shape (and the dice
history's "1d20" label stays stable for searching/filtering).
-}
expression : Dice.Expression
expression =
    { dice = [ { count = 1, faces = 20, sign = Dice.Positive } ]
    , constant = 0
    , damageType = Nothing
    }


{-| Compute the new pip-strip count when pip `idx` (0..2) is
clicked given the current count. Star-rating semantics — clicking
a filled pip clears it and every later pip; clicking an empty pip
fills up to and including it.
-}
pipStripTarget : Int -> Int -> Int
pipStripTarget idx current =
    if idx < current then
        idx

    else
        idx + 1


{-| Resolve a 5e death-save d20 face against the creature.

  - 20 → revive at 1 HP, conscious, tracker cleared.
  - 1 → +2 failures.
  - 10..19 → +1 success.
  - 2..9 → +1 failure.

The helper checks for the pre-existing dead/stable state and is a
no-op there so a stray click on the Roll button after death
doesn't change anything.

-}
applyResult : Int -> Creature -> Creature
applyResult d20 c =
    if Encounter.isDeathSaveDead c.deathSaves || Encounter.isDeathSaveStable c.deathSaves then
        c

    else if d20 == 20 then
        { c
            | currentHp = Basics.max 1 c.currentHp
            , deathSaves = Encounter.emptyDeathSaves
        }

    else if d20 == 1 then
        { c | deathSaves = Encounter.addDeathSaveFailures 2 c.deathSaves }

    else if d20 >= 10 then
        { c | deathSaves = Encounter.addDeathSaveSuccesses 1 c.deathSaves }

    else
        { c | deathSaves = Encounter.addDeathSaveFailures 1 c.deathSaves }
