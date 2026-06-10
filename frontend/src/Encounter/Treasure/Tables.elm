module Encounter.Treasure.Tables exposing
    ( ArtTier(..), GemTier(..), HoardEntry, IndividualEntry, MagicTable(..), Rarity(..)
    , artObjects, artTierValue, gemTierValue, gems
    , hoardEntries, individualEntries, magicItems
    , magicTableRarity, rarityLabel
    , magicTableLabel
    )

{-| Bundled SRD 5.1 treasure-table data.

The tables here are the random-treasure scaffolding from the
2014 SRD (CC-BY-4.0). Frontend-only — the server doesn't
re-model treasure; the encounter carries its rolled treasure as
opaque JSON and the GM rerolls / marks-distributed from the
modal.

The treasure flow has five concrete tables:

  - **Individual treasure** by CR bracket — what a creature
    carries on its body. Almost always coins.
  - **Treasure hoard** by CR bracket — what a lair or stash
    contains. Coins plus optional gems / art / magic items.
  - **Gems** by value tier (10 / 50 / 100 / 500 / 1000 / 5000 gp).
  - **Art objects** by value tier (25 / 250 / 750 / 2500 / 7500 gp).
  - **Magic items** by rarity-tier table (A–I).

Each hoard entry references which gem tier + count, which art
tier + count, and which magic-item table + count to roll. The
generator (in `Encounter.Treasure`) walks those references and
materialises a concrete list.

For magic items the SRD's d100 → exact-item mapping is collapsed
to "uniform random from the rarity tier". The output is the
item name + rarity tag — the GM looks up the full description in
whatever reference they prefer. Inlining 900 d100 rows here
would be both bulky and brittle (small differences between
printings would cause noise); a flat list is faithful to the
spirit of the random-treasure feel without the data load.

@docs ArtTier, GemTier, HoardEntry, IndividualEntry, MagicTable, Rarity
@docs artObjects, artTierValue, gemTierValue, gems
@docs hoardEntries, individualEntries, magicItems
@docs magicTableRarity, rarityLabel

-}

-- ── ENUMS ────────────────────────────────────────────────────────────────────


{-| Gem-pile value tiers — each integer is gp per stone.
-}
type GemTier
    = Gem10gp
    | Gem50gp
    | Gem100gp
    | Gem500gp
    | Gem1000gp
    | Gem5000gp


gemTierValue : GemTier -> Int
gemTierValue tier =
    case tier of
        Gem10gp ->
            10

        Gem50gp ->
            50

        Gem100gp ->
            100

        Gem500gp ->
            500

        Gem1000gp ->
            1000

        Gem5000gp ->
            5000


{-| Art-object value tiers — gp per object.
-}
type ArtTier
    = Art25gp
    | Art250gp
    | Art750gp
    | Art2500gp
    | Art7500gp


artTierValue : ArtTier -> Int
artTierValue tier =
    case tier of
        Art25gp ->
            25

        Art250gp ->
            250

        Art750gp ->
            750

        Art2500gp ->
            2500

        Art7500gp ->
            7500


{-| Magic-item tables from the SRD. A is the lowest tier
(potions, scrolls, common consumables); I is the rarest
(legendary one-shots). The mapping to rarity is fixed by the
SRD and reproduced in [`magicTableRarity`](#magicTableRarity).
-}
type MagicTable
    = TableA
    | TableB
    | TableC
    | TableD
    | TableE
    | TableF
    | TableG
    | TableH
    | TableI


magicTableLabel : MagicTable -> String
magicTableLabel t =
    case t of
        TableA ->
            "A"

        TableB ->
            "B"

        TableC ->
            "C"

        TableD ->
            "D"

        TableE ->
            "E"

        TableF ->
            "F"

        TableG ->
            "G"

        TableH ->
            "H"

        TableI ->
            "I"


magicTableRarity : MagicTable -> Rarity
magicTableRarity t =
    case t of
        TableA ->
            Common

        TableB ->
            Uncommon

        TableC ->
            Rare

        TableD ->
            VeryRare

        TableE ->
            Legendary

        TableF ->
            Uncommon

        TableG ->
            Rare

        TableH ->
            VeryRare

        TableI ->
            Legendary


type Rarity
    = Common
    | Uncommon
    | Rare
    | VeryRare
    | Legendary


rarityLabel : Rarity -> String
rarityLabel r =
    case r of
        Common ->
            "Common"

        Uncommon ->
            "Uncommon"

        Rare ->
            "Rare"

        VeryRare ->
            "Very Rare"

        Legendary ->
            "Legendary"



-- ── INDIVIDUAL TREASURE ──────────────────────────────────────────────────────


{-| One row of an individual-treasure table. Coin formulas are
expressed as `(diceCount, diceFaces, multiplier)` — e.g.,
`(5, 6, 1)` means 5d6 × 1; `(4, 6, 100)` is 4d6 × 100.

`weight` is the d100 range width: it's the raw number of d100
faces this row covers. The generator picks a row by weighted
roll, then rolls each coin formula.

-}
type alias IndividualEntry =
    { weight : Int
    , copper : Maybe ( Int, Int, Int )
    , silver : Maybe ( Int, Int, Int )
    , electrum : Maybe ( Int, Int, Int )
    , gold : Maybe ( Int, Int, Int )
    , platinum : Maybe ( Int, Int, Int )
    }


emptyIndividual : IndividualEntry
emptyIndividual =
    { weight = 0
    , copper = Nothing
    , silver = Nothing
    , electrum = Nothing
    , gold = Nothing
    , platinum = Nothing
    }


{-| SRD individual-treasure tables keyed by CR bracket index
(0..3 = brackets 0–4, 5–10, 11–16, 17+).
-}
individualEntries : Int -> List IndividualEntry
individualEntries bracketIndex =
    case bracketIndex of
        0 ->
            individualBracketOne

        1 ->
            individualBracketTwo

        2 ->
            individualBracketThree

        _ ->
            individualBracketFour


individualBracketOne : List IndividualEntry
individualBracketOne =
    -- Challenge 0-4.
    [ { emptyIndividual | weight = 30, copper = Just ( 5, 6, 1 ) }
    , { emptyIndividual | weight = 30, silver = Just ( 4, 6, 1 ) }
    , { emptyIndividual | weight = 10, electrum = Just ( 3, 6, 1 ) }
    , { emptyIndividual | weight = 25, gold = Just ( 3, 6, 1 ) }
    , { emptyIndividual | weight = 5, platinum = Just ( 1, 6, 1 ) }
    ]


individualBracketTwo : List IndividualEntry
individualBracketTwo =
    -- Challenge 5-10.
    [ { emptyIndividual
        | weight = 30
        , copper = Just ( 4, 6, 100 )
        , electrum = Just ( 1, 6, 10 )
      }
    , { emptyIndividual
        | weight = 30
        , silver = Just ( 6, 6, 10 )
        , gold = Just ( 2, 6, 10 )
      }
    , { emptyIndividual
        | weight = 10
        , electrum = Just ( 3, 6, 10 )
        , gold = Just ( 2, 6, 10 )
      }
    , { emptyIndividual | weight = 25, gold = Just ( 4, 6, 10 ) }
    , { emptyIndividual | weight = 5, platinum = Just ( 2, 6, 10 ) }
    ]


individualBracketThree : List IndividualEntry
individualBracketThree =
    -- Challenge 11-16.
    [ { emptyIndividual
        | weight = 20
        , silver = Just ( 4, 6, 100 )
        , gold = Just ( 1, 6, 100 )
      }
    , { emptyIndividual
        | weight = 15
        , electrum = Just ( 1, 6, 100 )
        , gold = Just ( 1, 6, 100 )
      }
    , { emptyIndividual | weight = 40, gold = Just ( 2, 6, 100 ) }
    , { emptyIndividual | weight = 25, platinum = Just ( 2, 6, 10 ) }
    ]


individualBracketFour : List IndividualEntry
individualBracketFour =
    -- Challenge 17+.
    [ { emptyIndividual
        | weight = 15
        , electrum = Just ( 2, 6, 1000 )
        , gold = Just ( 8, 6, 100 )
      }
    , { emptyIndividual
        | weight = 40
        , gold = Just ( 1, 6, 1000 )
        , platinum = Just ( 1, 6, 100 )
      }
    , { emptyIndividual | weight = 45, platinum = Just ( 2, 6, 100 ) }
    ]



-- ── HOARD TREASURE ───────────────────────────────────────────────────────────


{-| One row of a treasure-hoard table. Same weighted d100
structure as `IndividualEntry`; coins are scaled-up (1000s of
each denomination at the high end) and the row optionally
indicates gem / art / magic-item rolls.
-}
type alias HoardEntry =
    { weight : Int
    , copper : Maybe ( Int, Int, Int )
    , silver : Maybe ( Int, Int, Int )
    , electrum : Maybe ( Int, Int, Int )
    , gold : Maybe ( Int, Int, Int )
    , platinum : Maybe ( Int, Int, Int )
    , gems : Maybe ( Int, Int, GemTier )
    , art : Maybe ( Int, Int, ArtTier )
    , magic : Maybe ( Int, Int, MagicTable )
    }


emptyHoard : HoardEntry
emptyHoard =
    { weight = 0
    , copper = Nothing
    , silver = Nothing
    , electrum = Nothing
    , gold = Nothing
    , platinum = Nothing
    , gems = Nothing
    , art = Nothing
    , magic = Nothing
    }


hoardEntries : Int -> List HoardEntry
hoardEntries bracketIndex =
    case bracketIndex of
        0 ->
            hoardBracketOne

        1 ->
            hoardBracketTwo

        2 ->
            hoardBracketThree

        _ ->
            hoardBracketFour


hoardBracketOne : List HoardEntry
hoardBracketOne =
    -- Challenge 0-4.  Coin base for the whole bracket:
    -- 6d6 cp, 3d6 sp, 2d6 gp (and rarely 1d6 pp).
    let
        coinBase =
            { emptyHoard
                | copper = Just ( 6, 6, 1 )
                , silver = Just ( 3, 6, 1 )
                , gold = Just ( 2, 6, 1 )
            }

        bigCoinBase =
            { coinBase | platinum = Just ( 1, 6, 1 ) }
    in
    [ { coinBase | weight = 6 }
    , { coinBase | weight = 10, gems = Just ( 2, 6, Gem10gp ) }
    , { coinBase | weight = 10, art = Just ( 2, 4, Art25gp ) }
    , { coinBase | weight = 10, gems = Just ( 2, 6, Gem50gp ) }
    , { coinBase | weight = 6, magic = Just ( 1, 6, TableA ) }
    , { coinBase
        | weight = 8
        , gems = Just ( 2, 6, Gem10gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 8
        , art = Just ( 2, 4, Art25gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 6
        , gems = Just ( 2, 6, Gem50gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 4
        , gems = Just ( 2, 6, Gem10gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { coinBase
        | weight = 4
        , art = Just ( 2, 4, Art25gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { coinBase
        | weight = 4
        , gems = Just ( 2, 6, Gem50gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { bigCoinBase | weight = 4, magic = Just ( 1, 4, TableC ) }
    , { coinBase
        | weight = 10
        , gems = Just ( 2, 6, Gem50gp )
        , magic = Just ( 1, 4, TableC )
      }
    , { bigCoinBase | weight = 5, magic = Just ( 1, 4, TableF ) }
    , { bigCoinBase | weight = 5, magic = Just ( 1, 4, TableG ) }
    ]


hoardBracketTwo : List HoardEntry
hoardBracketTwo =
    -- Challenge 5-10.
    let
        coinBase =
            { emptyHoard
                | copper = Just ( 2, 6, 100 )
                , silver = Just ( 2, 6, 1000 )
                , gold = Just ( 6, 6, 100 )
                , platinum = Just ( 3, 6, 10 )
            }
    in
    [ { coinBase | weight = 4 }
    , { coinBase | weight = 6, art = Just ( 2, 4, Art25gp ) }
    , { coinBase | weight = 6, gems = Just ( 3, 6, Gem50gp ) }
    , { coinBase | weight = 6, gems = Just ( 3, 6, Gem100gp ) }
    , { coinBase
        | weight = 8
        , art = Just ( 2, 4, Art25gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 8
        , gems = Just ( 3, 6, Gem50gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 8
        , gems = Just ( 3, 6, Gem100gp )
        , magic = Just ( 1, 6, TableA )
      }
    , { coinBase
        | weight = 6
        , art = Just ( 2, 4, Art25gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { coinBase
        | weight = 6
        , gems = Just ( 3, 6, Gem50gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { coinBase
        | weight = 6
        , gems = Just ( 3, 6, Gem100gp )
        , magic = Just ( 1, 4, TableB )
      }
    , { coinBase
        | weight = 4
        , art = Just ( 2, 4, Art25gp )
        , magic = Just ( 1, 4, TableC )
      }
    , { coinBase
        | weight = 4
        , gems = Just ( 3, 6, Gem50gp )
        , magic = Just ( 1, 4, TableC )
      }
    , { coinBase
        | weight = 4
        , gems = Just ( 3, 6, Gem100gp )
        , magic = Just ( 1, 4, TableC )
      }
    , { coinBase | weight = 4, magic = Just ( 1, 4, TableF ) }
    , { coinBase
        | weight = 4
        , gems = Just ( 1, 4, Gem100gp )
        , magic = Just ( 1, 4, TableG )
      }
    , { coinBase | weight = 4, magic = Just ( 1, 4, TableH ) }
    , { coinBase | weight = 12, gems = Just ( 1, 4, Gem500gp ) }
    ]


hoardBracketThree : List HoardEntry
hoardBracketThree =
    -- Challenge 11-16.
    let
        coinBase =
            { emptyHoard
                | gold = Just ( 4, 6, 1000 )
                , platinum = Just ( 5, 6, 100 )
            }
    in
    [ { coinBase | weight = 3, art = Just ( 2, 4, Art250gp ) }
    , { coinBase | weight = 3, art = Just ( 2, 4, Art750gp ) }
    , { coinBase | weight = 3, gems = Just ( 3, 6, Gem500gp ) }
    , { coinBase | weight = 3, gems = Just ( 3, 6, Gem1000gp ) }
    , { coinBase
        | weight = 11
        , art = Just ( 2, 4, Art250gp )
        , magic = Just ( 1, 4, TableA )
      }
    , { coinBase
        | weight = 12
        , art = Just ( 2, 4, Art750gp )
        , magic = Just ( 1, 4, TableA )
      }
    , { coinBase
        | weight = 11
        , gems = Just ( 3, 6, Gem500gp )
        , magic = Just ( 1, 4, TableA )
      }
    , { coinBase
        | weight = 11
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 4, TableA )
      }
    , { coinBase
        | weight = 6
        , art = Just ( 2, 4, Art250gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 7
        , art = Just ( 2, 4, Art750gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 6
        , gems = Just ( 3, 6, Gem500gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 7
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 2
        , art = Just ( 2, 4, Art250gp )
        , magic = Just ( 1, 4, TableE )
      }
    , { coinBase
        | weight = 2
        , art = Just ( 2, 4, Art750gp )
        , magic = Just ( 1, 4, TableE )
      }
    , { coinBase
        | weight = 5
        , gems = Just ( 3, 6, Gem500gp )
        , magic = Just ( 1, 4, TableE )
      }
    , { coinBase
        | weight = 8
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 4, TableE )
      }
    ]


hoardBracketFour : List HoardEntry
hoardBracketFour =
    -- Challenge 17+.
    let
        coinBase =
            { emptyHoard
                | gold = Just ( 12, 6, 1000 )
                , platinum = Just ( 8, 6, 1000 )
            }
    in
    [ { coinBase | weight = 2, gems = Just ( 3, 6, Gem1000gp ) }
    , { coinBase | weight = 5, art = Just ( 1, 10, Art2500gp ) }
    , { coinBase | weight = 8, art = Just ( 1, 4, Art7500gp ) }
    , { coinBase | weight = 3, gems = Just ( 1, 8, Gem5000gp ) }
    , { coinBase
        | weight = 15
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 8, TableC )
      }
    , { coinBase
        | weight = 15
        , art = Just ( 1, 10, Art2500gp )
        , magic = Just ( 1, 8, TableC )
      }
    , { coinBase
        | weight = 12
        , art = Just ( 1, 4, Art7500gp )
        , magic = Just ( 1, 8, TableC )
      }
    , { coinBase
        | weight = 8
        , gems = Just ( 1, 8, Gem5000gp )
        , magic = Just ( 1, 8, TableC )
      }
    , { coinBase
        | weight = 6
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 6
        , art = Just ( 1, 10, Art2500gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 5
        , art = Just ( 1, 4, Art7500gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 5
        , gems = Just ( 1, 8, Gem5000gp )
        , magic = Just ( 1, 6, TableD )
      }
    , { coinBase
        | weight = 4
        , gems = Just ( 3, 6, Gem1000gp )
        , magic = Just ( 1, 6, TableE )
      }
    , { coinBase
        | weight = 4
        , art = Just ( 1, 10, Art2500gp )
        , magic = Just ( 1, 6, TableE )
      }
    , { coinBase
        | weight = 4
        , art = Just ( 1, 4, Art7500gp )
        , magic = Just ( 1, 6, TableE )
      }
    , { coinBase
        | weight = 3
        , gems = Just ( 1, 8, Gem5000gp )
        , magic = Just ( 1, 6, TableE )
      }
    ]



-- ── GEMS + ART OBJECTS ───────────────────────────────────────────────────────


{-| Specific gem names by value tier. SRD 5.1 Treasure section.
-}
gems : GemTier -> List String
gems tier =
    case tier of
        Gem10gp ->
            [ "Azurite (opaque mottled deep blue)"
            , "Banded agate (translucent striped brown/blue/white/red)"
            , "Blue quartz (transparent pale blue)"
            , "Eye agate (translucent circles of grey, white, brown)"
            , "Hematite (opaque grey-black)"
            , "Lapis lazuli (opaque light/dark blue with yellow flecks)"
            , "Malachite (opaque striated light/dark green)"
            , "Moss agate (translucent pink/yellow-white with mossy grey/green markings)"
            , "Obsidian (opaque black)"
            , "Rhodochrosite (opaque light pink)"
            , "Tiger eye (translucent brown with golden centre)"
            , "Turquoise (opaque light blue-green)"
            ]

        Gem50gp ->
            [ "Bloodstone (opaque dark grey with red flecks)"
            , "Carnelian (opaque orange to red-brown)"
            , "Chalcedony (opaque white)"
            , "Chrysoprase (translucent green)"
            , "Citrine (transparent pale yellow-brown)"
            , "Jasper (opaque blue, black, or brown)"
            , "Moonstone (translucent white with pale blue glow)"
            , "Onyx (opaque bands of black and white, or pure black or white)"
            , "Quartz (transparent white, smoky grey, or yellow)"
            , "Sardonyx (opaque bands of red and white)"
            , "Star rose quartz (translucent rosy stone with white star-shaped centre)"
            , "Zircon (transparent pale blue-green)"
            ]

        Gem100gp ->
            [ "Amber (transparent watery gold to rich gold)"
            , "Amethyst (transparent deep purple)"
            , "Chrysoberyl (transparent yellow-green to pale green)"
            , "Coral (opaque crimson)"
            , "Garnet (transparent red, brown-green, or violet)"
            , "Jade (translucent light green, deep green, or white)"
            , "Jet (opaque deep black)"
            , "Pearl (opaque lustrous white, yellow, or pink)"
            , "Spinel (transparent red, red-brown, or deep green)"
            , "Tourmaline (transparent pale green, blue, brown, or red)"
            ]

        Gem500gp ->
            [ "Alexandrite (transparent dark green)"
            , "Aquamarine (transparent pale blue-green)"
            , "Black pearl (opaque pure black)"
            , "Blue spinel (transparent deep blue)"
            , "Peridot (transparent rich olive green)"
            , "Topaz (transparent golden yellow)"
            ]

        Gem1000gp ->
            [ "Black opal (translucent dark green with black mottling and golden flecks)"
            , "Blue sapphire (transparent blue-white to medium blue)"
            , "Emerald (transparent deep bright green)"
            , "Fire opal (translucent fiery red)"
            , "Opal (translucent pale blue with green and golden mottling)"
            , "Star ruby (translucent ruby with white star-shaped centre)"
            , "Star sapphire (translucent blue sapphire with white star-shaped centre)"
            , "Yellow sapphire (transparent fiery yellow or yellow-green)"
            ]

        Gem5000gp ->
            [ "Black sapphire (translucent lustrous black with glowing highlights)"
            , "Diamond (transparent blue-white, canary, pink, brown, or blue)"
            , "Jacinth (transparent fiery orange)"
            , "Ruby (transparent clear red to deep crimson)"
            ]


{-| Specific art-object descriptions by value tier.
-}
artObjects : ArtTier -> List String
artObjects tier =
    case tier of
        Art25gp ->
            [ "Silver ewer"
            , "Carved bone statuette"
            , "Small gold bracelet"
            , "Cloth-of-gold vestments"
            , "Black velvet mask stitched with silver thread"
            , "Copper chalice with silver filigree"
            , "Pair of engraved bone dice"
            , "Small mirror set in a painted wooden frame"
            , "Embroidered silk handkerchief"
            , "Gold locket with a painted portrait inside"
            ]

        Art250gp ->
            [ "Gold ring set with bloodstones"
            , "Carved ivory statuette"
            , "Large gold bracelet"
            , "Silver necklace with a gemstone pendant"
            , "Bronze crown"
            , "Silk robe with gold embroidery"
            , "Large well-made tapestry"
            , "Brass mug with jade inlay"
            , "Box of turquoise animal figurines"
            , "Gold bird cage with electrum filigree"
            ]

        Art750gp ->
            [ "Silver chalice set with moonstones"
            , "Silver-plated steel longsword with jet set in hilt"
            , "Carved harp of exotic wood with ivory inlay and zircon gems"
            , "Small gold idol"
            , "Gold dragon comb set with red garnets as eyes"
            , "Bottle stopper cork embossed with gold leaf and set with amethysts"
            , "Ceremonial electrum dagger with black pearl in the pommel"
            , "Silver and gold brooch"
            , "Obsidian statuette with gold fittings and inlay"
            , "Painted gold war mask"
            ]

        Art2500gp ->
            [ "Fine gold chain set with a fire opal"
            , "Old masterpiece painting"
            , "Embroidered silk and velvet mantle set with numerous moonstones"
            , "Platinum bracelet set with a sapphire"
            , "Embroidered glove set with jewel chips"
            , "Jeweled anklet"
            , "Gold music box"
            , "Gold circlet set with four aquamarines"
            , "Eye patch with a mock eye set in blue sapphire and moonstone"
            , "A necklace string of small pink pearls"
            ]

        Art7500gp ->
            [ "Jeweled gold crown"
            , "Jeweled platinum ring"
            , "Small gold statuette set with rubies"
            , "Gold cup set with emeralds"
            , "Gold jewelry box with platinum filigree"
            , "Painted gold child's sarcophagus"
            , "Jade game board with solid gold playing pieces"
            , "Bejeweled ivory drinking horn with gold filigree"
            ]



-- ── MAGIC ITEMS ──────────────────────────────────────────────────────────────


{-| Representative magic items per SRD table. Names only —
descriptions live in whatever rulebook the GM is using. These
lists deliberately bias toward commonly-rolled items rather than
reproducing the SRD's d100 mapping verbatim; the spirit of
"random magic item from this rarity tier" survives the
simplification.
-}
magicItems : MagicTable -> List String
magicItems table =
    case table of
        TableA ->
            -- Common consumables.
            [ "Potion of Healing"
            , "Spell scroll (cantrip)"
            , "Potion of Climbing"
            , "Spell scroll (1st level)"
            , "Spell scroll (2nd level)"
            , "Potion of Greater Healing"
            , "Bag of Holding"
            , "Driftglobe"
            ]

        TableB ->
            -- Uncommon, mostly consumables.
            [ "Potion of Greater Healing"
            , "Potion of Fire Breath"
            , "Potion of Resistance"
            , "Ammunition, +1"
            , "Potion of Animal Friendship"
            , "Potion of Hill Giant Strength"
            , "Potion of Growth"
            , "Potion of Water Breathing"
            , "Spell scroll (2nd level)"
            , "Spell scroll (3rd level)"
            , "Bag of Holding"
            , "Keoghtom's Ointment"
            , "Oil of Slipperiness"
            , "Dust of Disappearance"
            , "Dust of Dryness"
            , "Dust of Sneezing and Choking"
            , "Elemental gem"
            , "Philter of Love"
            , "Alchemy jug"
            , "Cap of Water Breathing"
            , "Cloak of the Manta Ray"
            , "Driftglobe"
            , "Goggles of Night"
            , "Helm of Comprehending Languages"
            , "Immovable Rod"
            , "Lantern of Revealing"
            , "Mariner's Armor"
            , "Mithral Armor"
            , "Potion of Poison"
            , "Ring of Swimming"
            , "Rope of Climbing"
            , "Saddle of the Cavalier"
            , "Wand of Magic Detection"
            , "Wand of Secrets"
            ]

        TableC ->
            -- Rare consumables / minor utility.
            [ "Potion of Superior Healing"
            , "Spell scroll (4th level)"
            , "Ammunition, +2"
            , "Potion of Clairvoyance"
            , "Potion of Diminution"
            , "Potion of Gaseous Form"
            , "Potion of Frost Giant Strength"
            , "Potion of Stone Giant Strength"
            , "Potion of Heroism"
            , "Potion of Invulnerability"
            , "Potion of Mind Reading"
            , "Spell scroll (5th level)"
            , "Elixir of Health"
            , "Oil of Etherealness"
            , "Potion of Fire Giant Strength"
            , "Quaal's Feather Token"
            , "Scroll of Protection"
            , "Bag of Beans"
            , "Bead of Force"
            , "Chime of Opening"
            , "Decanter of Endless Water"
            , "Eyes of Minute Seeing"
            , "Folding Boat"
            , "Heward's Handy Haversack"
            , "Horseshoes of Speed"
            , "Necklace of Fireballs"
            , "Periapt of Health"
            , "Sending Stones"
            , "Stone of Good Luck (Luckstone)"
            , "Wind Fan"
            , "Winged Boots"
            ]

        TableD ->
            -- Very rare consumables.
            [ "Potion of Supreme Healing"
            , "Potion of Invisibility"
            , "Potion of Speed"
            , "Spell scroll (6th level)"
            , "Spell scroll (7th level)"
            , "Ammunition, +3"
            , "Oil of Sharpness"
            , "Potion of Flying"
            , "Potion of Cloud Giant Strength"
            , "Potion of Longevity"
            , "Potion of Vitality"
            , "Spell scroll (8th level)"
            , "Horseshoes of a Zephyr"
            , "Nolzur's Marvelous Pigments"
            , "Bag of Devouring"
            , "Portable Hole"
            ]

        TableE ->
            -- Legendary consumables.
            [ "Spell scroll (9th level)"
            , "Potion of Storm Giant Strength"
            , "Sovereign Glue"
            , "Universal Solvent"
            , "Talisman of Pure Good"
            , "Talisman of the Sphere"
            , "Talisman of Ultimate Evil"
            , "Tome of Clear Thought"
            , "Tome of Leadership and Influence"
            , "Tome of Understanding"
            ]

        TableF ->
            -- Uncommon permanent items.
            [ "Weapon, +1"
            , "Shield, +1"
            , "Sentinel Shield"
            , "Amulet of Proof against Detection and Location"
            , "Boots of Elvenkind"
            , "Boots of Striding and Springing"
            , "Bracers of Archery"
            , "Brooch of Shielding"
            , "Broom of Flying"
            , "Cloak of Elvenkind"
            , "Cloak of Protection"
            , "Gauntlets of Ogre Power"
            , "Hat of Disguise"
            , "Javelin of Lightning"
            , "Pearl of Power"
            , "Rod of the Pact Keeper, +1"
            , "Slippers of Spider Climbing"
            , "Staff of the Adder"
            , "Staff of the Python"
            , "Sword of Vengeance"
            , "Trident of Fish Command"
            , "Wand of Magic Missiles"
            , "Wand of the War Mage, +1"
            , "Wand of Web"
            , "Weapon of Warning"
            , "Adamantine Armor"
            , "Bag of Tricks"
            , "Boots of the Winterlands"
            , "Eyes of Charming"
            , "Eyes of the Eagle"
            , "Figurine of Wondrous Power"
            , "Gloves of Missile Snaring"
            , "Gloves of Swimming and Climbing"
            , "Gloves of Thievery"
            , "Headband of Intellect"
            , "Helm of Telepathy"
            , "Instrument of the Bards (Doss lute, Fochlucan bandore, Mac-Fuirmidh cittern)"
            , "Medallion of Thoughts"
            , "Necklace of Adaptation"
            , "Periapt of Wound Closure"
            , "Pipes of Haunting"
            , "Pipes of the Sewers"
            , "Quiver of Ehlonna"
            , "Stone of Good Luck (Luckstone)"
            , "Wind Fan"
            , "Winged Boots"
            ]

        TableG ->
            -- Rare permanent items.
            [ "Weapon, +2"
            , "Adamantine Armor"
            , "Figurine of Wondrous Power (Bronze Griffon, Ebony Fly, Golden Lions, Marble Elephant, Onyx Dog, Serpentine Owl)"
            , "Amulet of Health"
            , "Armor of Resistance"
            , "Berserker Axe"
            , "Boots of Levitation"
            , "Boots of Speed"
            , "Bracers of Defense"
            , "Brazier of Commanding Fire Elementals"
            , "Cape of the Mountebank"
            , "Carpet of Flying"
            , "Censer of Controlling Air Elementals"
            , "Chime of Opening"
            , "Cloak of Displacement"
            , "Cloak of the Bat"
            , "Cube of Force"
            , "Daern's Instant Fortress"
            , "Dagger of Venom"
            , "Dimensional Shackles"
            , "Dragon Slayer"
            , "Elven Chain"
            , "Flame Tongue"
            , "Folding Boat"
            , "Giant Slayer"
            , "Helm of Teleportation"
            , "Horn of Blasting"
            , "Iron Bands of Bilarro"
            , "Mantle of Spell Resistance"
            , "Necklace of Prayer Beads"
            , "Periapt of Proof against Poison"
            , "Quaal's Feather Token (anchor, bird, fan, swan boat, tree, whip)"
            , "Ring of Animal Influence"
            , "Ring of Evasion"
            , "Ring of Feather Falling"
            , "Ring of Free Action"
            , "Ring of Protection"
            , "Ring of Resistance"
            , "Ring of Spell Storing"
            , "Ring of the Ram"
            , "Robe of Useful Items"
            , "Rod of Rulership"
            , "Rod of the Pact Keeper, +2"
            , "Stone of Controlling Earth Elementals"
            , "Sun Blade"
            , "Sword of Life Stealing"
            , "Sword of Wounding"
            , "Wand of Binding"
            , "Wand of Enemy Detection"
            , "Wand of Fear"
            , "Wand of Fireballs"
            , "Wand of Lightning Bolts"
            , "Wand of Paralysis"
            , "Wand of the War Mage, +2"
            , "Wand of Wonder"
            , "Wings of Flying"
            ]

        TableH ->
            -- Very rare permanent items.
            [ "Weapon, +3"
            , "Amulet of the Planes"
            , "Animated Shield"
            , "Belt of Giant Strength (Fire, Frost, or Stone)"
            , "Armor of Invulnerability"
            , "Arrow-Catching Shield"
            , "Bag of Devouring"
            , "Belt of Hill Giant Strength"
            , "Berserker Axe"
            , "Cloak of Arachnida"
            , "Dancing Sword"
            , "Demon Armor"
            , "Dragon Scale Mail"
            , "Dwarven Plate"
            , "Dwarven Thrower"
            , "Elemental Gem"
            , "Frost Brand"
            , "Helm of Brilliance"
            , "Horn of Valhalla (silver or brass)"
            , "Instrument of the Bards (Anstruth harp, Canaith mandolin, Cli lyre)"
            , "Ioun Stone (awareness, protection, reserve, regeneration, sustenance)"
            , "Manual of Bodily Health"
            , "Manual of Gainful Exercise"
            , "Manual of Golems"
            , "Manual of Quickness of Action"
            , "Mirror of Life Trapping"
            , "Nine Lives Stealer"
            , "Oathbow"
            , "Plate Armor of Etherealness"
            , "Ring of Regeneration"
            , "Ring of Shooting Stars"
            , "Ring of Telekinesis"
            , "Robe of Scintillating Colors"
            , "Robe of Stars"
            , "Rod of Absorption"
            , "Rod of Alertness"
            , "Rod of Security"
            , "Rod of the Pact Keeper, +3"
            , "Scimitar of Speed"
            , "Shield of Missile Attraction"
            , "Staff of Fire"
            , "Staff of Frost"
            , "Staff of Power"
            , "Staff of Striking"
            , "Staff of Thunder and Lightning"
            , "Sword of Sharpness"
            , "Tome of Clear Thought"
            , "Tome of Leadership and Influence"
            , "Tome of Understanding"
            , "Vorpal Sword"
            , "Wand of Polymorph"
            , "Wand of the War Mage, +3"
            ]

        TableI ->
            -- Legendary permanent items.
            [ "Defender"
            , "Hammer of Thunderbolts"
            , "Luck Blade"
            , "Sword of Answering"
            , "Holy Avenger"
            , "Ring of Djinni Summoning"
            , "Ring of Invisibility"
            , "Ring of Spell Turning"
            , "Rod of Lordly Might"
            , "Staff of the Magi"
            , "Vorpal Sword"
            , "Belt of Giant Strength (Cloud or Storm)"
            , "Armor of Invulnerability"
            , "Belt of Cloud Giant Strength"
            , "Cubic Gate"
            , "Deck of Many Things"
            , "Efreeti Bottle"
            , "Iron Flask"
            , "Plate Armor of Etherealness"
            , "Sphere of Annihilation"
            , "Talisman of Pure Good"
            , "Talisman of the Sphere"
            , "Tome of the Stilled Tongue"
            ]
