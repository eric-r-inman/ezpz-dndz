module Encounter.Treasure.MundaneTables exposing
    ( ArmorItem
    , MundaneItem
    , WeaponItem
    , bundledArmor
    , bundledArmorRollByBracket
    , bundledMundane
    , bundledMundaneRollByBracket
    , bundledWeapons
    , bundledWeaponsRollByBracket
    )

{-| Bundled SRD 5.1 data for the three opt-in treasure
categories — Mundane (adventuring gear + artisan's tools),
Weapons, and Armor. Each row is `(name, valueGp)`; the
generator picks uniformly from the user-edited list and reads
the value directly off the picked entry, so there is no tier
abstraction the way gems / art do it.

Per-bracket roll dice live next to the lists so the generator
can scale frequency with encounter strength (CR 17+ encounters
roll more mundane bric-a-brac than CR 0–4 ones). These are
also editable through the Treasure Table modal so the GM can
tune the cadence without touching the item lists.

-}

import Dict exposing (Dict)


type alias MundaneItem =
    { name : String, valueGp : Int }


type alias WeaponItem =
    { name : String, valueGp : Int }


type alias ArmorItem =
    { name : String, valueGp : Int }


{-| Adventuring Gear + Artisan's Tools from SRD 5.1. Values are
the standard list price; copper-priced trinkets that round to
0 gp are recorded at 0 so the GM sees them in the picker but
they don't inflate the gp total. The artisan tool block is
appended after the gear block — both share the same uniform
pick so the GM can dilute one with the other by removing rows.
-}
bundledMundane : List MundaneItem
bundledMundane =
    -- Adventuring Gear (SRD 5.1).
    [ { name = "Abacus", valueGp = 2 }
    , { name = "Acid (vial)", valueGp = 25 }
    , { name = "Alchemist's fire (flask)", valueGp = 50 }
    , { name = "Arrows (20)", valueGp = 1 }
    , { name = "Blowgun needles (50)", valueGp = 1 }
    , { name = "Crossbow bolts (20)", valueGp = 1 }
    , { name = "Sling bullets (20)", valueGp = 0 }
    , { name = "Antitoxin (vial)", valueGp = 50 }
    , { name = "Crystal arcane focus", valueGp = 10 }
    , { name = "Orb arcane focus", valueGp = 20 }
    , { name = "Rod arcane focus", valueGp = 10 }
    , { name = "Staff arcane focus", valueGp = 5 }
    , { name = "Wand arcane focus", valueGp = 10 }
    , { name = "Backpack", valueGp = 2 }
    , { name = "Ball bearings (bag of 1,000)", valueGp = 1 }
    , { name = "Barrel", valueGp = 2 }
    , { name = "Basket", valueGp = 0 }
    , { name = "Bedroll", valueGp = 1 }
    , { name = "Bell", valueGp = 1 }
    , { name = "Blanket", valueGp = 0 }
    , { name = "Block and tackle", valueGp = 1 }
    , { name = "Book", valueGp = 25 }
    , { name = "Bottle, glass", valueGp = 2 }
    , { name = "Bucket", valueGp = 0 }
    , { name = "Caltrops (bag of 20)", valueGp = 1 }
    , { name = "Candle", valueGp = 0 }
    , { name = "Case, crossbow bolt", valueGp = 1 }
    , { name = "Case, map or scroll", valueGp = 1 }
    , { name = "Chain (10 feet)", valueGp = 5 }
    , { name = "Chalk (1 piece)", valueGp = 0 }
    , { name = "Chest", valueGp = 5 }
    , { name = "Climber's kit", valueGp = 25 }
    , { name = "Clothes, common", valueGp = 0 }
    , { name = "Clothes, costume", valueGp = 5 }
    , { name = "Clothes, fine", valueGp = 15 }
    , { name = "Clothes, traveler's", valueGp = 2 }
    , { name = "Component pouch", valueGp = 25 }
    , { name = "Crowbar", valueGp = 2 }
    , { name = "Sprig of mistletoe druidic focus", valueGp = 1 }
    , { name = "Totem druidic focus", valueGp = 1 }
    , { name = "Wooden staff druidic focus", valueGp = 5 }
    , { name = "Yew wand druidic focus", valueGp = 10 }
    , { name = "Fishing tackle", valueGp = 1 }
    , { name = "Flask or tankard", valueGp = 0 }
    , { name = "Grappling hook", valueGp = 2 }
    , { name = "Hammer", valueGp = 1 }
    , { name = "Hammer, sledge", valueGp = 2 }
    , { name = "Healer's kit", valueGp = 5 }
    , { name = "Amulet holy symbol", valueGp = 5 }
    , { name = "Emblem holy symbol", valueGp = 5 }
    , { name = "Reliquary holy symbol", valueGp = 5 }
    , { name = "Holy water (flask)", valueGp = 25 }
    , { name = "Hourglass", valueGp = 25 }
    , { name = "Hunting trap", valueGp = 5 }
    , { name = "Ink (1 ounce bottle)", valueGp = 10 }
    , { name = "Ink pen", valueGp = 0 }
    , { name = "Jug or pitcher", valueGp = 0 }
    , { name = "Climber's kit (rope, harness)", valueGp = 25 }
    , { name = "Disguise kit", valueGp = 25 }
    , { name = "Forgery kit", valueGp = 15 }
    , { name = "Herbalism kit", valueGp = 5 }
    , { name = "Poisoner's kit", valueGp = 50 }
    , { name = "Ladder (10-foot)", valueGp = 0 }
    , { name = "Lamp", valueGp = 0 }
    , { name = "Lantern, bullseye", valueGp = 10 }
    , { name = "Lantern, hooded", valueGp = 5 }
    , { name = "Lock", valueGp = 10 }
    , { name = "Magnifying glass", valueGp = 100 }
    , { name = "Manacles", valueGp = 2 }
    , { name = "Mess kit", valueGp = 0 }
    , { name = "Mirror, steel", valueGp = 5 }
    , { name = "Oil (flask)", valueGp = 0 }
    , { name = "Paper (one sheet)", valueGp = 0 }
    , { name = "Parchment (one sheet)", valueGp = 0 }
    , { name = "Perfume (vial)", valueGp = 5 }
    , { name = "Pick, miner's", valueGp = 2 }
    , { name = "Piton", valueGp = 0 }
    , { name = "Poison, basic (vial)", valueGp = 100 }
    , { name = "Pole (10-foot)", valueGp = 0 }
    , { name = "Pot, iron", valueGp = 2 }
    , { name = "Potion of healing", valueGp = 50 }
    , { name = "Pouch", valueGp = 0 }
    , { name = "Quiver", valueGp = 1 }
    , { name = "Ram, portable", valueGp = 4 }
    , { name = "Rations (1 day)", valueGp = 0 }
    , { name = "Robes", valueGp = 1 }
    , { name = "Rope, hempen (50 feet)", valueGp = 1 }
    , { name = "Rope, silk (50 feet)", valueGp = 10 }
    , { name = "Sack", valueGp = 0 }
    , { name = "Scale, merchant's", valueGp = 5 }
    , { name = "Sealing wax", valueGp = 0 }
    , { name = "Shovel", valueGp = 2 }
    , { name = "Signal whistle", valueGp = 0 }
    , { name = "Signet ring", valueGp = 5 }
    , { name = "Soap", valueGp = 0 }
    , { name = "Spellbook", valueGp = 50 }
    , { name = "Spikes, iron (10)", valueGp = 1 }
    , { name = "Spyglass", valueGp = 1000 }
    , { name = "Tent, two-person", valueGp = 2 }
    , { name = "Tinderbox", valueGp = 0 }
    , { name = "Torch", valueGp = 0 }
    , { name = "Vial", valueGp = 1 }
    , { name = "Waterskin", valueGp = 0 }
    , { name = "Whetstone", valueGp = 0 }

    -- Artisan's Tools (SRD 5.1).
    , { name = "Alchemist's supplies", valueGp = 50 }
    , { name = "Brewer's supplies", valueGp = 20 }
    , { name = "Calligrapher's supplies", valueGp = 10 }
    , { name = "Carpenter's tools", valueGp = 8 }
    , { name = "Cartographer's tools", valueGp = 15 }
    , { name = "Cobbler's tools", valueGp = 5 }
    , { name = "Cook's utensils", valueGp = 1 }
    , { name = "Glassblower's tools", valueGp = 30 }
    , { name = "Jeweler's tools", valueGp = 25 }
    , { name = "Leatherworker's tools", valueGp = 5 }
    , { name = "Mason's tools", valueGp = 10 }
    , { name = "Painter's supplies", valueGp = 10 }
    , { name = "Potter's tools", valueGp = 10 }
    , { name = "Smith's tools", valueGp = 20 }
    , { name = "Tinker's tools", valueGp = 50 }
    , { name = "Weaver's tools", valueGp = 1 }
    , { name = "Woodcarver's tools", valueGp = 1 }
    , { name = "Navigator's tools", valueGp = 25 }
    , { name = "Thieves' tools", valueGp = 25 }

    -- Musical instruments (group with artisan tools per SRD).
    , { name = "Bagpipes", valueGp = 30 }
    , { name = "Drum", valueGp = 6 }
    , { name = "Dulcimer", valueGp = 25 }
    , { name = "Flute", valueGp = 2 }
    , { name = "Lute", valueGp = 35 }
    , { name = "Lyre", valueGp = 30 }
    , { name = "Horn", valueGp = 3 }
    , { name = "Pan flute", valueGp = 12 }
    , { name = "Shawm", valueGp = 2 }
    , { name = "Viol", valueGp = 30 }
    ]


{-| Mundane roll dice per bracket — `(count, faces)`. Cadence
scales with bracket strength: low-CR encounters drop a couple of
trinkets, high-CR encounters drop a fistful. GMs can edit this
in the table editor.
-}
bundledMundaneRollByBracket : Dict String ( Int, Int )
bundledMundaneRollByBracket =
    Dict.fromList
        [ ( "1to4", ( 2, 4 ) )
        , ( "5to10", ( 2, 6 ) )
        , ( "11to16", ( 3, 6 ) )
        , ( "17plus", ( 4, 6 ) )
        ]


{-| Simple + martial weapons from SRD 5.1 with their list price.
-}
bundledWeapons : List WeaponItem
bundledWeapons =
    -- Simple Melee Weapons.
    [ { name = "Club", valueGp = 1 }
    , { name = "Dagger", valueGp = 2 }
    , { name = "Greatclub", valueGp = 2 }
    , { name = "Handaxe", valueGp = 5 }
    , { name = "Javelin", valueGp = 1 }
    , { name = "Light hammer", valueGp = 2 }
    , { name = "Mace", valueGp = 5 }
    , { name = "Quarterstaff", valueGp = 1 }
    , { name = "Sickle", valueGp = 1 }
    , { name = "Spear", valueGp = 1 }

    -- Simple Ranged Weapons.
    , { name = "Light crossbow", valueGp = 25 }
    , { name = "Dart", valueGp = 1 }
    , { name = "Shortbow", valueGp = 25 }
    , { name = "Sling", valueGp = 1 }

    -- Martial Melee Weapons.
    , { name = "Battleaxe", valueGp = 10 }
    , { name = "Flail", valueGp = 10 }
    , { name = "Glaive", valueGp = 20 }
    , { name = "Greataxe", valueGp = 30 }
    , { name = "Greatsword", valueGp = 50 }
    , { name = "Halberd", valueGp = 20 }
    , { name = "Lance", valueGp = 10 }
    , { name = "Longsword", valueGp = 15 }
    , { name = "Maul", valueGp = 10 }
    , { name = "Morningstar", valueGp = 15 }
    , { name = "Pike", valueGp = 5 }
    , { name = "Rapier", valueGp = 25 }
    , { name = "Scimitar", valueGp = 25 }
    , { name = "Shortsword", valueGp = 10 }
    , { name = "Trident", valueGp = 5 }
    , { name = "War pick", valueGp = 5 }
    , { name = "Warhammer", valueGp = 15 }
    , { name = "Whip", valueGp = 2 }

    -- Martial Ranged Weapons.
    , { name = "Blowgun", valueGp = 10 }
    , { name = "Hand crossbow", valueGp = 75 }
    , { name = "Heavy crossbow", valueGp = 50 }
    , { name = "Longbow", valueGp = 50 }
    , { name = "Net", valueGp = 1 }
    ]


{-| Weapons roll dice per bracket. Lower cadence than mundane
gear since weapons land as distinct treasure rather than
flavour clutter.
-}
bundledWeaponsRollByBracket : Dict String ( Int, Int )
bundledWeaponsRollByBracket =
    Dict.fromList
        [ ( "1to4", ( 1, 2 ) )
        , ( "5to10", ( 1, 3 ) )
        , ( "11to16", ( 1, 4 ) )
        , ( "17plus", ( 1, 6 ) )
        ]


{-| Light, Medium, Heavy armor + Shield from SRD 5.1.
-}
bundledArmor : List ArmorItem
bundledArmor =
    -- Light Armor.
    [ { name = "Padded armor", valueGp = 5 }
    , { name = "Leather armor", valueGp = 10 }
    , { name = "Studded leather armor", valueGp = 45 }

    -- Medium Armor.
    , { name = "Hide armor", valueGp = 10 }
    , { name = "Chain shirt", valueGp = 50 }
    , { name = "Scale mail", valueGp = 50 }
    , { name = "Breastplate", valueGp = 400 }
    , { name = "Half plate armor", valueGp = 750 }

    -- Heavy Armor.
    , { name = "Ring mail", valueGp = 30 }
    , { name = "Chain mail", valueGp = 75 }
    , { name = "Splint armor", valueGp = 200 }
    , { name = "Plate armor", valueGp = 1500 }

    -- Shield.
    , { name = "Shield", valueGp = 10 }
    ]


{-| Armor roll dice per bracket. Same cadence as weapons —
armor is more uncommon than gear, and dropping multiple suits
per hoard would tip the encounter's wealth balance.
-}
bundledArmorRollByBracket : Dict String ( Int, Int )
bundledArmorRollByBracket =
    Dict.fromList
        [ ( "1to4", ( 1, 2 ) )
        , ( "5to10", ( 1, 3 ) )
        , ( "11to16", ( 1, 4 ) )
        , ( "17plus", ( 1, 4 ) )
        ]
