module Update.TreasureTable exposing
    ( open, close
    , toggleSection
    , gemAdd, gemEdit, gemRemove
    , artAdd, artEdit, artRemove
    , magicAdd, magicEdit, magicRemove
    , resetToBundled
    , coinAdd, coinRemove, coinSet, flatAdd, flatNameSet, flatRemove, flatValueSet, rowAdd, rowRemove, save, scrollAdd, scrollEdit, scrollRemove, subAdd, subCountSet, subFacesSet, subRemove, subTierSet, weightSet
    )

{-| Msg handlers for the singular per-user Treasure Table
editor.

There's exactly one editable treasure table per user — initialised
from `Encounter.Treasure.bundledTable` and mutated through this
modal. The editor exposes per-section name-list editing for the
gem / art / magic tiers (the parts a GM most commonly customises:
add a homebrew item to Table B, rename gems for setting flavor).
Individual + hoard rows render read-only for now; a later phase
will add a row-editor for weights and coin formulas.

Saves are persisted by the standard `userTreasureTableCmd` hook
in `Main.update` — server PUT for authed sessions, localStorage
for anonymous.

@docs open, close
@docs toggleSection
@docs gemAdd, gemEdit, gemRemove
@docs artAdd, artEdit, artRemove
@docs magicAdd, magicEdit, magicRemove
@docs resetToBundled

-}

import Dict
import Encounter.Treasure as Treasure exposing (TreasureTable)
import Encounter.Treasure.Tables as Tables
    exposing
        ( ArtTier(..)
        , GemTier(..)
        , HoardEntry
        , IndividualEntry
        , MagicTable(..)
        )
import Model exposing (Model)
import Msg
    exposing
        ( CoinField(..)
        , CoinKind(..)
        , Msg(..)
        , RowKind(..)
        , SubKind(..)
        )
import Ui.TreasureTable as Ui
import Update.Treasure


open : Model -> ( Model, Cmd Msg )
open model =
    let
        snapshot =
            Maybe.withDefault Treasure.bundledTable model.userTreasureTable
    in
    ( { model | modal = Just (Model.ModalTreasureTable (Ui.fresh snapshot)) }
    , Cmd.none
    )


{-| Close the modal without committing. The draft inside the UI
state is discarded along with the modal itself; the live
`model.userTreasureTable` is untouched, so nothing persists.
The Treasure roller modal opens immediately after — the GM
almost always edits the table because they're about to roll
from it, so chaining the two saves a click and keeps focus on
the task.
-}
close : Model -> ( Model, Cmd Msg )
close model =
    Update.Treasure.open model


{-| Commit the in-flight draft to `model.userTreasureTable` and
hand off to the Treasure roller modal. The standard
`userTreasureTableCmd` hook in `Main.update` sees
`model.userTreasureTable` change and fires the right persistence
Cmd (server PUT for authed, localStorage for anonymous); the
roller then opens against the freshly-saved table.
-}
save : Model -> ( Model, Cmd Msg )
save model =
    case model.modal of
        Just (Model.ModalTreasureTable ui) ->
            Update.Treasure.open
                { model | userTreasureTable = Just ui.draft }

        _ ->
            ( model, Cmd.none )


toggleSection : String -> String -> Model -> ( Model, Cmd Msg )
toggleSection kind key model =
    let
        section =
            case kind of
                "individual" ->
                    Ui.IndividualSection key

                "hoard" ->
                    Ui.HoardSection key

                "gem" ->
                    Ui.GemSection key

                "art" ->
                    Ui.ArtSection key

                "magic" ->
                    Ui.MagicSection key

                _ ->
                    Ui.FlatSection kind key
    in
    ( Model.mapModal Model.treasureTableLens
        (Ui.toggleSection section)
        model
    , Cmd.none
    )



-- ── NAME-LIST EDITS ─────────────────────────────────────────────────────────


{-| Apply `fn` to the editor's in-flight draft. The live
`model.userTreasureTable` is /not/ touched here — only the
draft inside the open modal's UI state. `Update.TreasureTable.save`
is the only path that copies the draft back into the model
proper, which is what triggers the persistence hook.
-}
mutateTable : (TreasureTable -> TreasureTable) -> Model -> ( Model, Cmd Msg )
mutateTable fn model =
    ( Model.mapModal Model.treasureTableLens (Ui.withDraft fn) model
    , Cmd.none
    )


gemAdd : String -> Model -> ( Model, Cmd Msg )
gemAdd tierKey =
    mutateTable
        (\table ->
            { table
                | gems = updateDictList tierKey (\names -> names ++ [ "" ]) table.gems
            }
        )


gemEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
gemEdit tierKey idx value =
    mutateTable
        (\table ->
            { table
                | gems =
                    updateDictList tierKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.gems
            }
        )


gemRemove : String -> Int -> Model -> ( Model, Cmd Msg )
gemRemove tierKey idx =
    mutateTable
        (\table ->
            { table | gems = updateDictList tierKey (dropIndex idx) table.gems }
        )


artAdd : String -> Model -> ( Model, Cmd Msg )
artAdd tierKey =
    mutateTable
        (\table ->
            { table | art = updateDictList tierKey (\names -> names ++ [ "" ]) table.art }
        )


artEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
artEdit tierKey idx value =
    mutateTable
        (\table ->
            { table
                | art =
                    updateDictList tierKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.art
            }
        )


artRemove : String -> Int -> Model -> ( Model, Cmd Msg )
artRemove tierKey idx =
    mutateTable
        (\table ->
            { table | art = updateDictList tierKey (dropIndex idx) table.art }
        )


magicAdd : String -> Model -> ( Model, Cmd Msg )
magicAdd tableKey =
    mutateTable
        (\table ->
            { table | magic = updateDictList tableKey (\names -> names ++ [ "" ]) table.magic }
        )


magicEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
magicEdit tableKey idx value =
    mutateTable
        (\table ->
            { table
                | magic =
                    updateDictList tableKey
                        (List.indexedMap
                            (\i name ->
                                if i == idx then
                                    value

                                else
                                    name
                            )
                        )
                        table.magic
            }
        )


magicRemove : String -> Int -> Model -> ( Model, Cmd Msg )
magicRemove tableKey idx =
    mutateTable
        (\table ->
            { table | magic = updateDictList tableKey (dropIndex idx) table.magic }
        )



-- ── ROW-LEVEL EDITS (Individual + Hoard) ────────────────────────────────────


{-| Add a fresh blank row at the end of the bracket. Blank rows
have weight 0 so the generator's weighted-pick won't roll them
until the GM gives them a non-zero weight — that way an
unfinished new row never throws off the brackets that ARE
populated.
-}
rowAdd : RowKind -> String -> Model -> ( Model, Cmd Msg )
rowAdd kind bracketKey =
    mutateRows kind bracketKey (\rows -> rows ++ [ freshRow kind ])


rowRemove : RowKind -> String -> Int -> Model -> ( Model, Cmd Msg )
rowRemove kind bracketKey idx =
    mutateRows kind bracketKey (dropIndex idx)


weightSet : RowKind -> String -> Int -> String -> Model -> ( Model, Cmd Msg )
weightSet kind bracketKey idx raw =
    mutateRows kind bracketKey (mapIndex idx (setWeight (parseClampNonNeg raw)))


coinAdd : RowKind -> String -> Int -> CoinKind -> Model -> ( Model, Cmd Msg )
coinAdd kind bracketKey idx coin =
    mutateRows kind bracketKey (mapIndex idx (setCoin coin (Just defaultCoinFormula)))


coinRemove :
    RowKind
    -> String
    -> Int
    -> CoinKind
    -> Model
    -> ( Model, Cmd Msg )
coinRemove kind bracketKey idx coin =
    mutateRows kind bracketKey (mapIndex idx (setCoin coin Nothing))


coinSet :
    RowKind
    -> String
    -> Int
    -> CoinKind
    -> CoinField
    -> String
    -> Model
    -> ( Model, Cmd Msg )
coinSet kind bracketKey idx coin field raw =
    mutateRows kind
        bracketKey
        (mapIndex idx (updateCoinField coin field (parseClampPositive raw)))



-- ── HOARD SUBROLLS (gems / art / magic) ─────────────────────────────────────


subAdd : String -> Int -> SubKind -> Model -> ( Model, Cmd Msg )
subAdd bracketKey idx sub =
    mutateHoard bracketKey (mapIndex idx (addSub sub))


subRemove : String -> Int -> SubKind -> Model -> ( Model, Cmd Msg )
subRemove bracketKey idx sub =
    mutateHoard bracketKey (mapIndex idx (removeSub sub))


subCountSet :
    String
    -> Int
    -> SubKind
    -> String
    -> Model
    -> ( Model, Cmd Msg )
subCountSet bracketKey idx sub raw =
    mutateHoard bracketKey
        (mapIndex idx (updateSubCount sub (parseClampPositive raw)))


subFacesSet :
    String
    -> Int
    -> SubKind
    -> String
    -> Model
    -> ( Model, Cmd Msg )
subFacesSet bracketKey idx sub raw =
    mutateHoard bracketKey
        (mapIndex idx (updateSubFaces sub (parseClampPositive raw)))


subTierSet :
    String
    -> Int
    -> SubKind
    -> String
    -> Model
    -> ( Model, Cmd Msg )
subTierSet bracketKey idx sub raw =
    mutateHoard bracketKey
        (mapIndex idx (updateSubTier sub raw))


{-| Reset the in-flight draft to the bundled SRD defaults. The
GM still has to click Save for the change to commit; closing the
modal without saving leaves their current saved table intact.
-}
resetToBundled : Model -> ( Model, Cmd Msg )
resetToBundled =
    mutateTable (\_ -> Treasure.bundledTable)



-- ── FLAT-CATEGORY NAME+VALUE EDITS (Mundane / Weapons / Armor) ─────────────


flatAdd : Msg.FlatCategory -> Model -> ( Model, Cmd Msg )
flatAdd cat =
    mutateFlat cat (\items -> items ++ [ { name = "", valueGp = 0 } ])


flatRemove : Msg.FlatCategory -> Int -> Model -> ( Model, Cmd Msg )
flatRemove cat idx =
    mutateFlat cat (dropIndex idx)


flatNameSet : Msg.FlatCategory -> Int -> String -> Model -> ( Model, Cmd Msg )
flatNameSet cat idx name =
    mutateFlat cat (mapIndex idx (\item -> { item | name = name }))


flatValueSet : Msg.FlatCategory -> Int -> String -> Model -> ( Model, Cmd Msg )
flatValueSet cat idx raw =
    mutateFlat cat
        (mapIndex idx (\item -> { item | valueGp = parseClampNonNeg raw }))


{-| Apply a transformation to the right flat-category list inside
the draft. Operates on the structurally-identical record type
the three categories share so one helper covers all three.
-}
mutateFlat :
    Msg.FlatCategory
    -> (List { name : String, valueGp : Int } -> List { name : String, valueGp : Int })
    -> Model
    -> ( Model, Cmd Msg )
mutateFlat cat fn =
    mutateTable
        (\table ->
            case cat of
                Msg.FlatMundane ->
                    { table | mundane = fn table.mundane }

                Msg.FlatWeapons ->
                    { table | weapons = fn table.weapons }

                Msg.FlatArmor ->
                    { table | armor = fn table.armor }
        )



-- ── SCROLL-SPELL NAME EDITS (per level) ────────────────────────────────────


scrollAdd : String -> Model -> ( Model, Cmd Msg )
scrollAdd levelKey =
    mutateScroll levelKey (\names -> names ++ [ "" ])


scrollEdit : String -> Int -> String -> Model -> ( Model, Cmd Msg )
scrollEdit levelKey idx name =
    mutateScroll levelKey
        (List.indexedMap
            (\i existing ->
                if i == idx then
                    name

                else
                    existing
            )
        )


scrollRemove : String -> Int -> Model -> ( Model, Cmd Msg )
scrollRemove levelKey idx =
    mutateScroll levelKey (dropIndex idx)


mutateScroll : String -> (List String -> List String) -> Model -> ( Model, Cmd Msg )
mutateScroll levelKey fn =
    mutateTable
        (\table ->
            { table
                | scrollSpells =
                    updateDictList levelKey fn table.scrollSpells
            }
        )



-- ── HELPERS ────────────────────────────────────────────────────────────────


updateDictList :
    String
    -> (List String -> List String)
    -> Dict.Dict String (List String)
    -> Dict.Dict String (List String)
updateDictList key fn dict =
    Dict.update key
        (\existing ->
            Just (fn (Maybe.withDefault [] existing))
        )
        dict


dropIndex : Int -> List a -> List a
dropIndex idx xs =
    xs
        |> List.indexedMap Tuple.pair
        |> List.filter (\( i, _ ) -> i /= idx)
        |> List.map Tuple.second


mapIndex : Int -> (a -> a) -> List a -> List a
mapIndex idx fn xs =
    List.indexedMap
        (\i x ->
            if i == idx then
                fn x

            else
                x
        )
        xs



-- ── ROW MUTATION PLUMBING ──────────────────────────────────────────────────


{-| Rewrite a single bracket's row list and persist. The
`RowKind` distinguishes individual vs hoard rows so callers don't
have to handle two separate Dict layers; the right table dict
gets patched and the other stays untouched.
-}
mutateRows :
    RowKind
    -> String
    -> (List IndividualEntry -> List IndividualEntry)
    -> Model
    -> ( Model, Cmd Msg )
mutateRows kind bracketKey fn model =
    case Treasure.bracketFromWire bracketKey of
        Nothing ->
            -- Unknown bracket slug — caller bug; just no-op.
            ( model, Cmd.none )

        Just bracket ->
            case kind of
                IndividualRow ->
                    mutateTable
                        (\table ->
                            Treasure.setIndividualRows bracket
                                (fn (Treasure.individualRowsFor bracket table))
                                table
                        )
                        model

                HoardRow ->
                    -- IndividualEntry and HoardEntry share the
                    -- coin-formula columns the editor touches, but
                    -- the persisted shape is different, so we
                    -- convert in/out at the seam.  The fn passed
                    -- in only ever rewrites coin + weight fields.
                    mutateTable
                        (\table ->
                            Treasure.setHoardRows bracket
                                (Treasure.hoardRowsFor bracket table
                                    |> List.map hoardToIndividualView
                                    |> fn
                                    |> applyToHoard (Treasure.hoardRowsFor bracket table)
                                )
                                table
                        )
                        model


{-| Rewrite a single hoard bracket's rows (used by subroll edits
that only apply to hoard, not individual).
-}
mutateHoard :
    String
    -> (List HoardEntry -> List HoardEntry)
    -> Model
    -> ( Model, Cmd Msg )
mutateHoard bracketKey fn model =
    case Treasure.bracketFromWire bracketKey of
        Nothing ->
            ( model, Cmd.none )

        Just bracket ->
            mutateTable
                (\table ->
                    Treasure.setHoardRows bracket
                        (fn (Treasure.hoardRowsFor bracket table))
                        table
                )
                model


{-| Shared seam: the coin/weight edit functions are written
against `IndividualEntry` because that's all they touch. Hoard
rows project down to a same-shaped record for the function and
then merge the coin/weight result back into the original hoard
row, preserving its subroll fields.
-}
hoardToIndividualView : HoardEntry -> IndividualEntry
hoardToIndividualView h =
    { weight = h.weight
    , copper = h.copper
    , silver = h.silver
    , electrum = h.electrum
    , gold = h.gold
    , platinum = h.platinum
    }


applyToHoard : List HoardEntry -> List IndividualEntry -> List HoardEntry
applyToHoard originals updates =
    let
        zipped =
            List.map2 Tuple.pair originals updates

        mergedExisting =
            List.map mergeBack zipped

        extras =
            List.drop (List.length originals) updates
                |> List.map individualToHoard
    in
    -- An "add row" widens `updates` past `originals`; the extra
    -- updates get materialised as fresh hoard rows.  A "remove
    -- row" shortens `updates`; the dropped originals are simply
    -- not in `zipped`.  Either way the resulting list has length
    -- equal to `updates`.
    mergedExisting ++ extras


mergeBack : ( HoardEntry, IndividualEntry ) -> HoardEntry
mergeBack ( h, u ) =
    { h
        | weight = u.weight
        , copper = u.copper
        , silver = u.silver
        , electrum = u.electrum
        , gold = u.gold
        , platinum = u.platinum
    }


individualToHoard : IndividualEntry -> HoardEntry
individualToHoard u =
    { weight = u.weight
    , copper = u.copper
    , silver = u.silver
    , electrum = u.electrum
    , gold = u.gold
    , platinum = u.platinum
    , gems = Nothing
    , art = Nothing
    , magic = Nothing
    }



-- ── ROW FIELD HELPERS (operate on IndividualEntry-shaped records) ──────────


setWeight : Int -> IndividualEntry -> IndividualEntry
setWeight n row =
    { row | weight = n }


defaultCoinFormula : ( Int, Int, Int )
defaultCoinFormula =
    ( 1, 6, 1 )


setCoin : CoinKind -> Maybe ( Int, Int, Int ) -> IndividualEntry -> IndividualEntry
setCoin kind value row =
    case kind of
        CKCopper ->
            { row | copper = value }

        CKSilver ->
            { row | silver = value }

        CKElectrum ->
            { row | electrum = value }

        CKGold ->
            { row | gold = value }

        CKPlatinum ->
            { row | platinum = value }


getCoin : CoinKind -> IndividualEntry -> Maybe ( Int, Int, Int )
getCoin kind row =
    case kind of
        CKCopper ->
            row.copper

        CKSilver ->
            row.silver

        CKElectrum ->
            row.electrum

        CKGold ->
            row.gold

        CKPlatinum ->
            row.platinum


updateCoinField :
    CoinKind
    -> CoinField
    -> Int
    -> IndividualEntry
    -> IndividualEntry
updateCoinField coin field n row =
    case getCoin coin row of
        Nothing ->
            -- Editing a coin column whose formula is absent — no
            -- silent insert; the caller should have hit coinAdd
            -- first.  Keep the row unchanged.
            row

        Just ( c, f, m ) ->
            let
                next =
                    case field of
                        CFCount ->
                            ( n, f, m )

                        CFFaces ->
                            ( c, n, m )

                        CFMult ->
                            ( c, f, n )
            in
            setCoin coin (Just next) row



-- ── HOARD SUBROLL HELPERS ──────────────────────────────────────────────────


addSub : SubKind -> HoardEntry -> HoardEntry
addSub sub row =
    case sub of
        SKGems ->
            { row | gems = Just defaultGems }

        SKArt ->
            { row | art = Just defaultArt }

        SKMagic ->
            { row | magic = Just defaultMagic }


removeSub : SubKind -> HoardEntry -> HoardEntry
removeSub sub row =
    case sub of
        SKGems ->
            { row | gems = Nothing }

        SKArt ->
            { row | art = Nothing }

        SKMagic ->
            { row | magic = Nothing }


defaultGems : ( Int, Int, GemTier )
defaultGems =
    ( 1, 6, Gem10gp )


defaultArt : ( Int, Int, ArtTier )
defaultArt =
    ( 1, 6, Art25gp )


defaultMagic : ( Int, Int, MagicTable )
defaultMagic =
    ( 1, 6, TableA )


updateSubCount : SubKind -> Int -> HoardEntry -> HoardEntry
updateSubCount sub n row =
    case sub of
        SKGems ->
            { row | gems = Maybe.map (\( _, f, t ) -> ( n, f, t )) row.gems }

        SKArt ->
            { row | art = Maybe.map (\( _, f, t ) -> ( n, f, t )) row.art }

        SKMagic ->
            { row | magic = Maybe.map (\( _, f, t ) -> ( n, f, t )) row.magic }


updateSubFaces : SubKind -> Int -> HoardEntry -> HoardEntry
updateSubFaces sub n row =
    case sub of
        SKGems ->
            { row | gems = Maybe.map (\( c, _, t ) -> ( c, n, t )) row.gems }

        SKArt ->
            { row | art = Maybe.map (\( c, _, t ) -> ( c, n, t )) row.art }

        SKMagic ->
            { row | magic = Maybe.map (\( c, _, t ) -> ( c, n, t )) row.magic }


updateSubTier : SubKind -> String -> HoardEntry -> HoardEntry
updateSubTier sub raw row =
    case sub of
        SKGems ->
            case gemTierFromString raw of
                Just t ->
                    { row | gems = Maybe.map (\( c, f, _ ) -> ( c, f, t )) row.gems }

                Nothing ->
                    row

        SKArt ->
            case artTierFromString raw of
                Just t ->
                    { row | art = Maybe.map (\( c, f, _ ) -> ( c, f, t )) row.art }

                Nothing ->
                    row

        SKMagic ->
            case magicTableFromString raw of
                Just t ->
                    { row | magic = Maybe.map (\( c, f, _ ) -> ( c, f, t )) row.magic }

                Nothing ->
                    row


gemTierFromString : String -> Maybe GemTier
gemTierFromString s =
    case s of
        "10gp" ->
            Just Gem10gp

        "50gp" ->
            Just Gem50gp

        "100gp" ->
            Just Gem100gp

        "500gp" ->
            Just Gem500gp

        "1000gp" ->
            Just Gem1000gp

        "5000gp" ->
            Just Gem5000gp

        _ ->
            Nothing


artTierFromString : String -> Maybe ArtTier
artTierFromString s =
    case s of
        "25gp" ->
            Just Art25gp

        "250gp" ->
            Just Art250gp

        "750gp" ->
            Just Art750gp

        "2500gp" ->
            Just Art2500gp

        "7500gp" ->
            Just Art7500gp

        _ ->
            Nothing


magicTableFromString : String -> Maybe MagicTable
magicTableFromString s =
    case s of
        "A" ->
            Just TableA

        "B" ->
            Just TableB

        "C" ->
            Just TableC

        "D" ->
            Just TableD

        "E" ->
            Just TableE

        "F" ->
            Just TableF

        "G" ->
            Just TableG

        "H" ->
            Just TableH

        "I" ->
            Just TableI

        _ ->
            Nothing



-- ── FRESH-ROW CONSTRUCTORS ─────────────────────────────────────────────────


freshRow : RowKind -> IndividualEntry
freshRow _ =
    -- Both rows share this projection during edit; the hoard
    -- merge path will widen with empty subroll defaults.
    { weight = 0
    , copper = Nothing
    , silver = Nothing
    , electrum = Nothing
    , gold = Nothing
    , platinum = Nothing
    }



-- ── INPUT PARSING ──────────────────────────────────────────────────────────


{-| Parse a weight input. Negative values clamp to 0 (a row with
weight 0 simply never rolls — the editor surfaces a warning).
Empty / non-numeric also clamps to 0 so a half-typed input never
crashes the persistence layer.
-}
parseClampNonNeg : String -> Int
parseClampNonNeg raw =
    String.toInt (String.trim raw)
        |> Maybe.withDefault 0
        |> max 0


{-| Parse a dice-formula component (count / faces / multiplier).
Anything below 1 clamps to 1 — a 0-count or 0-face roll has no
sensible interpretation in the generator, and a 0 multiplier
zeroes the whole coin column without removing it, which is
confusing for the user.
-}
parseClampPositive : String -> Int
parseClampPositive raw =
    String.toInt (String.trim raw)
        |> Maybe.withDefault 1
        |> max 1
