module Update.Treasure exposing
    ( open, close
    , kindSet
    , roll, rolled
    , categoryRolled, rerollCategory
    , armorRemove, artRemove, coinRemove, contributionsToggle, gemRemove, magicRemove, mundaneRemove, profileDelete, profileLoad, profileNameChanged, profileSave, settingsCountSet, settingsNoneSet, settingsPresetApply, settingsReset, settingsScrollChanceSet, settingsToggle, settingsValueSet, weaponsRemove
    )

{-| Msg handlers for the Treasure modal.

The modal owns:

  - The dropdown selections (Kind + Bracket), which live on
    `Ui.Treasure.TreasureUi`.
  - A pure handler that fires the random `Generator` and lands
    the result into `model.encounter.treasure`.

The treasure result persists with the encounter (it's a field on
`Encounter`), so the standard `persistEncounterCmd` hook in the
update wrapper round-trips it to the server or localStorage
without anything extra from this module.

@docs open, close
@docs kindSet, bracketSet
@docs roll, rolled
@docs categoryRolled, rerollCategory

-}

import Compendium
import Dict
import Encounter
import Encounter.Treasure as Treasure exposing (Bracket, EnemyInfo, RollContext)
import Model exposing (Model)
import Msg exposing (Msg(..), TreasurePreset(..))
import Random
import Ui.Compendium
import Ui.Toast exposing (ToastKind(..))
import Ui.Treasure
import Update.Toast


{-| Open the modal. UI state is now bracket-free; the bracket
each enemy uses falls out of their own CR at roll time, so the
modal opens straight into the Kind picker.
-}
open : Model -> ( Model, Cmd Msg )
open model =
    ( { model | modal = Just (Model.ModalTreasure Ui.Treasure.fresh) }
    , Cmd.none
    )


close : Model -> ( Model, Cmd Msg )
close model =
    ( { model | modal = Nothing }, Cmd.none )


contributionsToggle : Model -> ( Model, Cmd Msg )
contributionsToggle model =
    ( Model.mapModal Model.treasureLens
        (\ui -> { ui | contributionsExpanded = not ui.contributionsExpanded })
        model
    , Cmd.none
    )


settingsToggle : Model -> ( Model, Cmd Msg )
settingsToggle model =
    ( Model.mapModal Model.treasureLens
        (\ui -> { ui | settingsExpanded = not ui.settingsExpanded })
        model
    , Cmd.none
    )


loadedDb : Model -> Compendium.Db
loadedDb model =
    case model.compendium.db of
        Ui.Compendium.CompendiumDbLoaded db ->
            db

        _ ->
            Compendium.fromList []


{-| Update the Kind dropdown ("individual" / "hoard"). Unknown
strings collapse to Hoard, the safer default for a typo.
-}
kindSet : String -> Model -> ( Model, Cmd Msg )
kindSet wire model =
    let
        kind =
            case wire of
                "individual" ->
                    Treasure.Individual

                _ ->
                    Treasure.Hoard
    in
    ( Model.mapModal Model.treasureLens (\ui -> { ui | kind = kind }) model
    , Cmd.none
    )


{-| Fire the random Generator with the current Kind + Bracket.
The runtime feeds the result into `TreasureRolled` via the
standard `Random.generate` glue.
-}
roll : Model -> ( Model, Cmd Msg )
roll model =
    case model.modal of
        Just (Model.ModalTreasure ui) ->
            ( model
            , Random.generate TreasureRolled
                (Treasure.generate
                    model.encounter.treasureSettings
                    ui.kind
                    (activeTable model)
                    (rollContext model)
                )
            )

        _ ->
            ( model, Cmd.none )


{-| Resolve the table to roll against — the user's edited copy
when they have one, otherwise the bundled default. Centralised
here so all the per-category / re-roll handlers stay in sync.
-}
activeTable : Model -> Treasure.TreasureTable
activeTable model =
    Maybe.withDefault Treasure.bundledTable model.userTreasureTable


{-| Build the per-roll context from the encounter:

  - One `EnemyInfo` per non-placeholder, `creatureKind ==
    "enemy"` creature, paired with the bracket derived from
    its CR (compendium lookup; defaults to `B1to4` for
    manual-entry creatures with no link).
  - `hoardBracket` = the toughest enemy's bracket, used by
    Hoard rolls. Defaults to `B1to4` when there are no enemies.

The CR Bracket dropdown is gone; this context replaces the
GM's manual pick with what the encounter already knows.

-}
rollContext : Model -> RollContext
rollContext model =
    let
        enemies =
            enemyInfos model
    in
    { enemies = enemies
    , hoardBracket = highestBracketOrDefault (List.map .bracket enemies)
    }


enemyInfos : Model -> List EnemyInfo
enemyInfos model =
    let
        db =
            loadedDb model
    in
    model.encounter.creatures
        |> List.filter (\c -> c.creatureKind == "enemy" && not c.isPlaceholder)
        |> List.map
            (\c ->
                { name = c.name
                , bracket = creatureBracket db c
                , loot = creatureLoot db c
                }
            )


creatureBracket : Compendium.Db -> Encounter.Creature -> Bracket
creatureBracket db c =
    c.creatureId
        |> Maybe.andThen (\id -> Compendium.find id db)
        |> Maybe.map (.challengeRating >> Compendium.crToFloat >> Treasure.bracketFor)
        |> Maybe.withDefault Treasure.B1to4


{-| Resolve the creature's compendium loot list — empty when
the encounter creature has no compendium link (a manually-typed
placeholder won't have authored loot).
-}
creatureLoot : Compendium.Db -> Encounter.Creature -> List String
creatureLoot db c =
    c.creatureId
        |> Maybe.andThen (\id -> Compendium.find id db)
        |> Maybe.map .loot
        |> Maybe.withDefault []


highestBracketOrDefault : List Bracket -> Bracket
highestBracketOrDefault brackets =
    case brackets of
        [] ->
            Treasure.B1to4

        head :: rest ->
            List.foldl
                (\b acc ->
                    if bracketRank b > bracketRank acc then
                        b

                    else
                        acc
                )
                head
                rest


bracketRank : Bracket -> Int
bracketRank b =
    case b of
        Treasure.B1to4 ->
            0

        Treasure.B5to10 ->
            1

        Treasure.B11to16 ->
            2

        Treasure.B17plus ->
            3


{-| Materialised roll landed — save it onto the encounter and
collapse the By-Creature accordion. Every fresh roll resets the
accordion to collapsed regardless of whether the GM had
expanded it for a prior roll; lets the rolled-loot list use the
full vertical space by default.
-}
rolled : Treasure.TreasureRoll -> Model -> ( Model, Cmd Msg )
rolled treasureRoll model =
    let
        encounter =
            model.encounter

        withRoll =
            { model | encounter = { encounter | treasure = Just treasureRoll } }
    in
    ( Model.mapModal Model.treasureLens
        (\ui -> { ui | contributionsExpanded = False })
        withRoll
    , Cmd.none
    )


{-| Fire a fresh random Generator targeting the chosen category.
Re-uses the originating row's spec (stored on `roll.source`) so
the gem tier / dice count stay consistent with the original
roll — only the specific stone / object / item names change.

Pre-source rolls (legacy saved encounters) fall through to a
fresh full-row regen, since there's no spec to re-use.

The runtime lands the result in `TreasureCategoryRolled`, which
[`categoryRolled`](#categoryRolled) below merges into the
existing roll.

-}
rerollCategory : Treasure.Category -> Model -> ( Model, Cmd Msg )
rerollCategory category model =
    case model.encounter.treasure of
        Just currentRoll ->
            ( model
            , Random.generate (TreasureCategoryRolled category)
                (Treasure.generateRerollCategory
                    model.encounter.treasureSettings
                    (activeTable model)
                    (rollContext model)
                    currentRoll
                    category
                )
            )

        Nothing ->
            ( model, Cmd.none )


{-| Per-class roll-knob update. Caller picks which axis of
which class via wire-friendly strings: `class` is one of
"coins", "gems", "art", "magic"; `axis` is "count" or "value"
(coins only support "count"); `value` is the wire token for
the adjust enum ("fewer" / "normal" / "more" or "lower" /
"normal" / "higher").

A no-op when an unknown combination comes in — the modal
never emits invalid ones, but defensive against custom
serializations.

-}
settingsCountSet : String -> String -> Model -> ( Model, Cmd Msg )
settingsCountSet itemClass valueWire model =
    let
        value =
            Treasure.countAdjustFromWire valueWire

        settings =
            model.encounter.treasureSettings

        next =
            case itemClass of
                "coins" ->
                    { settings | coinsCount = value }

                "gems" ->
                    { settings | gemsCount = value }

                "art" ->
                    { settings | artCount = value }

                "magic" ->
                    { settings | magicCount = value }

                "mundane" ->
                    { settings | mundaneCount = value }

                "weapons" ->
                    { settings | weaponsCount = value }

                "armor" ->
                    { settings | armorCount = value }

                _ ->
                    settings
    in
    ( updateEncounterSettings next model, Cmd.none )


{-| Toggle the per-category "None" switch. When on, the
category is skipped at roll time regardless of its Count knob.
Toggle state is per-Kind: writing to Hoard doesn't affect
Individual. Mundane / Weapons / Armor default to None=on
(opt-in); the four classic categories default to None=off for
Hoard and None=on for Individual.
-}
settingsNoneSet :
    Treasure.Kind
    -> String
    -> Bool
    -> Model
    -> ( Model, Cmd Msg )
settingsNoneSet kind itemClass none model =
    let
        settings =
            model.encounter.treasureSettings

        toggles =
            Treasure.togglesFor kind settings

        nextToggles =
            case itemClass of
                "coins" ->
                    { toggles | coinsNone = none }

                "gems" ->
                    { toggles | gemsNone = none }

                "art" ->
                    { toggles | artNone = none }

                "magic" ->
                    { toggles | magicNone = none }

                "mundane" ->
                    { toggles | mundaneNone = none }

                "weapons" ->
                    { toggles | weaponsNone = none }

                "armor" ->
                    { toggles | armorNone = none }

                _ ->
                    toggles

        next =
            case kind of
                Treasure.Hoard ->
                    { settings | hoardToggles = nextToggles }

                Treasure.Individual ->
                    { settings | individualToggles = nextToggles }
    in
    ( updateEncounterSettings next model, Cmd.none )


settingsValueSet : String -> String -> Model -> ( Model, Cmd Msg )
settingsValueSet itemClass valueWire model =
    let
        value =
            Treasure.valueAdjustFromWire valueWire

        settings =
            model.encounter.treasureSettings

        next =
            case itemClass of
                "gems" ->
                    { settings | gemsValue = value }

                "art" ->
                    { settings | artValue = value }

                "magic" ->
                    { settings | magicValue = value }

                _ ->
                    settings
    in
    ( updateEncounterSettings next model, Cmd.none )


{-| Set the spell-scroll post-process chance from a percent
input string. Clamps to 0..100 and treats empty / non-numeric
input as 0 so a half-typed field never leaves an undefined-state
percentage.
-}
settingsScrollChanceSet : String -> Model -> ( Model, Cmd Msg )
settingsScrollChanceSet raw model =
    let
        clamped =
            String.toInt (String.trim raw)
                |> Maybe.withDefault 0
                |> max 0
                |> min 100

        settings =
            model.encounter.treasureSettings
    in
    ( updateEncounterSettings { settings | magicScrollChance = clamped } model
    , Cmd.none
    )


settingsReset : Model -> ( Model, Cmd Msg )
settingsReset model =
    ( updateEncounterSettings Treasure.defaultSettings model, Cmd.none )


{-| Apply a one-click preset. Each preset overrides the current
Kind's toggle bucket + the magicScrollChance knob; the other
Kind's bucket stays untouched so flipping between Hoard and
Individual still works the way the GM left it.
-}
settingsPresetApply : Msg.TreasurePreset -> Model -> ( Model, Cmd Msg )
settingsPresetApply preset model =
    case model.modal of
        Just (Model.ModalTreasure ui) ->
            let
                settings =
                    model.encounter.treasureSettings

                ( newToggles, newScrollChance ) =
                    presetFor preset

                next =
                    case ui.kind of
                        Treasure.Hoard ->
                            { settings
                                | hoardToggles = newToggles
                                , magicScrollChance = newScrollChance
                            }

                        Treasure.Individual ->
                            { settings
                                | individualToggles = newToggles
                                , magicScrollChance = newScrollChance
                            }
            in
            ( updateEncounterSettings next model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| The canned toggle + scroll-chance configurations. Counts
and Value adjusts always reset to Normal — presets are about
"what categories roll", not "how aggressive the dice are."
-}
presetFor : Msg.TreasurePreset -> ( Treasure.CategoryToggles, Int )
presetFor preset =
    let
        none =
            { coinsNone = True
            , gemsNone = True
            , artNone = True
            , magicNone = True
            , mundaneNone = True
            , weaponsNone = True
            , armorNone = True
            }
    in
    case preset of
        Msg.PresetCoinsOnly ->
            ( { none | coinsNone = False }, 0 )

        Msg.PresetCoinsGems ->
            ( { none | coinsNone = False, gemsNone = False }, 0 )

        Msg.PresetSrdDefault ->
            ( { none
                | coinsNone = False
                , gemsNone = False
                , artNone = False
                , magicNone = False
              }
            , 15
            )

        Msg.PresetWizardLair ->
            ( { none | coinsNone = False, magicNone = False }, 75 )

        Msg.PresetBanditCamp ->
            ( { none
                | coinsNone = False
                , weaponsNone = False
                , armorNone = False
              }
            , 0
            )



-- ── NAMED PROFILES ─────────────────────────────────────────────────────────


profileNameChanged : String -> Model -> ( Model, Cmd Msg )
profileNameChanged raw model =
    ( { model | userTreasureProfileNameDraft = raw }, Cmd.none )


{-| Save the current encounter's TreasureSettings as a named
profile. Trims whitespace; refuses empty names with a toast.
Overwrites any existing profile by the same name silently —
that's the GM editing a saved set, not a destructive surprise.
-}
profileSave : Model -> ( Model, Cmd Msg )
profileSave model =
    let
        name =
            String.trim model.userTreasureProfileNameDraft
    in
    if String.isEmpty name then
        Update.Toast.push ToastError "Give the profile a name first." model

    else
        let
            next =
                Dict.insert name
                    model.encounter.treasureSettings
                    model.userTreasureProfiles
        in
        ( { model
            | userTreasureProfiles = next
            , userTreasureProfileNameDraft = ""
          }
        , Cmd.none
        )


profileLoad : String -> Model -> ( Model, Cmd Msg )
profileLoad name model =
    case Dict.get name model.userTreasureProfiles of
        Just settings ->
            ( updateEncounterSettings settings model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


profileDelete : String -> Model -> ( Model, Cmd Msg )
profileDelete name model =
    ( { model | userTreasureProfiles = Dict.remove name model.userTreasureProfiles }
    , Cmd.none
    )


updateEncounterSettings : Treasure.TreasureSettings -> Model -> Model
updateEncounterSettings settings model =
    let
        enc =
            model.encounter
    in
    { model | encounter = { enc | treasureSettings = settings } }


{-| Per-row delete: zero out one coin denomination from the
encounter's current roll.
-}
coinRemove : String -> Model -> ( Model, Cmd Msg )
coinRemove denomination =
    mutateRoll (Treasure.clearCoin denomination)


gemRemove : Int -> Model -> ( Model, Cmd Msg )
gemRemove index =
    mutateRoll (Treasure.removeGem index)


artRemove : Int -> Model -> ( Model, Cmd Msg )
artRemove index =
    mutateRoll (Treasure.removeArt index)


magicRemove : Int -> Model -> ( Model, Cmd Msg )
magicRemove index =
    mutateRoll (Treasure.removeMagic index)


mundaneRemove : Int -> Model -> ( Model, Cmd Msg )
mundaneRemove index =
    mutateRoll (Treasure.removeMundaneItem index)


weaponsRemove : Int -> Model -> ( Model, Cmd Msg )
weaponsRemove index =
    mutateRoll (Treasure.removeWeaponItem index)


armorRemove : Int -> Model -> ( Model, Cmd Msg )
armorRemove index =
    mutateRoll (Treasure.removeArmorItem index)


mutateRoll : (Treasure.TreasureRoll -> Treasure.TreasureRoll) -> Model -> ( Model, Cmd Msg )
mutateRoll fn model =
    case model.encounter.treasure of
        Just current ->
            let
                encounter =
                    model.encounter
            in
            ( { model | encounter = { encounter | treasure = Just (fn current) } }
            , Cmd.none
            )

        Nothing ->
            ( model, Cmd.none )


{-| Materialised single-category re-roll landed. Replace only
the chosen category's data on the existing `TreasureRoll`,
leaving the other categories untouched.
-}
categoryRolled :
    Treasure.Category
    -> Treasure.TreasureRoll
    -> Model
    -> ( Model, Cmd Msg )
categoryRolled category fresh model =
    case model.encounter.treasure of
        Nothing ->
            ( model, Cmd.none )

        Just existing ->
            let
                nextRoll =
                    case category of
                        Treasure.CoinsCategory ->
                            { existing | coins = fresh.coins }

                        Treasure.GemsCategory ->
                            { existing | gems = fresh.gems }

                        Treasure.ArtCategory ->
                            { existing | art = fresh.art }

                        Treasure.MagicCategory ->
                            { existing | magic = fresh.magic }

                        Treasure.MundaneCategory ->
                            { existing | mundane = fresh.mundane }

                        Treasure.WeaponsCategory ->
                            { existing | weapons = fresh.weapons }

                        Treasure.ArmorCategory ->
                            { existing | armor = fresh.armor }

                encounter =
                    model.encounter
            in
            ( { model | encounter = { encounter | treasure = Just nextRoll } }
            , Cmd.none
            )
