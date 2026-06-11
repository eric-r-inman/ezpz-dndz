module Encounter.Treasure.ScrollSpells exposing
    ( ScrollLevel(..)
    , bundledScrollSpells
    , scrollLevelAll
    , scrollLevelLabel
    , scrollLevelValueGp
    , scrollLevelWire
    )

{-| SRD 5.1 spell names bundled by spell level, plus the
metadata the scroll post-process needs (level enum, wire slug,
display label, market gp value).

The post-process in the treasure generator may swap a rolled
magic-item entry for "Spell Scroll (Nth level): <picked spell>"
at a probability the GM sets in Tune-your-rolls. The picked
spell is drawn uniformly from the user-editable list at the
appropriate level; bundled defaults below are a curated subset
of the open-licensed spells in the SRD per level so a first-boot
user has something to roll on without authoring a single entry.

Values follow the DMG-derived rarity-tier midpoints (cantrip 30
gp through 9th-level 17,000 gp) — used by the modal to display
a gp tag on the rolled scroll.

-}


type ScrollLevel
    = ScrollCantrip
    | Scroll1st
    | Scroll2nd
    | Scroll3rd
    | Scroll4th
    | Scroll5th
    | Scroll6th
    | Scroll7th
    | Scroll8th
    | Scroll9th


scrollLevelAll : List ScrollLevel
scrollLevelAll =
    [ ScrollCantrip
    , Scroll1st
    , Scroll2nd
    , Scroll3rd
    , Scroll4th
    , Scroll5th
    , Scroll6th
    , Scroll7th
    , Scroll8th
    , Scroll9th
    ]


{-| Stable URL-style slug used as the key in `TreasureTable.scrollSpells`
and in the wire codec. Don't rename without bumping a wire-codec
backward-compat path.
-}
scrollLevelWire : ScrollLevel -> String
scrollLevelWire l =
    case l of
        ScrollCantrip ->
            "cantrip"

        Scroll1st ->
            "1st"

        Scroll2nd ->
            "2nd"

        Scroll3rd ->
            "3rd"

        Scroll4th ->
            "4th"

        Scroll5th ->
            "5th"

        Scroll6th ->
            "6th"

        Scroll7th ->
            "7th"

        Scroll8th ->
            "8th"

        Scroll9th ->
            "9th"


{-| Human-readable label used in the modal results and the
editor section headers. "Cantrip" for cantrips; "Nth level"
for the rest.
-}
scrollLevelLabel : ScrollLevel -> String
scrollLevelLabel l =
    case l of
        ScrollCantrip ->
            "Cantrip"

        Scroll1st ->
            "1st level"

        Scroll2nd ->
            "2nd level"

        Scroll3rd ->
            "3rd level"

        Scroll4th ->
            "4th level"

        Scroll5th ->
            "5th level"

        Scroll6th ->
            "6th level"

        Scroll7th ->
            "7th level"

        Scroll8th ->
            "8th level"

        Scroll9th ->
            "9th level"


{-| DMG-derived market values per scroll level. Surface in the
modal as a flavour suffix so the GM can ballpark party wealth
without a separate lookup; not used in roll math.
-}
scrollLevelValueGp : ScrollLevel -> Int
scrollLevelValueGp l =
    case l of
        ScrollCantrip ->
            30

        Scroll1st ->
            75

        Scroll2nd ->
            150

        Scroll3rd ->
            300

        Scroll4th ->
            1000

        Scroll5th ->
            1500

        Scroll6th ->
            3000

        Scroll7th ->
            5500

        Scroll8th ->
            8000

        Scroll9th ->
            17000


{-| Bundled spell names per level, sourced from SRD 5.1 (open
content under the OGL / CC-BY-4.0). Curated subset — the GM can
add, remove, or rename through the Treasure Table editor.
-}
bundledScrollSpells : ScrollLevel -> List String
bundledScrollSpells l =
    case l of
        ScrollCantrip ->
            [ "Acid Splash"
            , "Chill Touch"
            , "Dancing Lights"
            , "Druidcraft"
            , "Eldritch Blast"
            , "Fire Bolt"
            , "Guidance"
            , "Light"
            , "Mage Hand"
            , "Mending"
            , "Message"
            , "Minor Illusion"
            , "Poison Spray"
            , "Prestidigitation"
            , "Produce Flame"
            , "Ray of Frost"
            , "Resistance"
            , "Sacred Flame"
            , "Shillelagh"
            , "Shocking Grasp"
            , "Spare the Dying"
            , "Thaumaturgy"
            , "True Strike"
            , "Vicious Mockery"
            ]

        Scroll1st ->
            [ "Bless"
            , "Burning Hands"
            , "Charm Person"
            , "Color Spray"
            , "Comprehend Languages"
            , "Create or Destroy Water"
            , "Cure Wounds"
            , "Detect Evil and Good"
            , "Detect Magic"
            , "Detect Poison and Disease"
            , "Disguise Self"
            , "Expeditious Retreat"
            , "Faerie Fire"
            , "False Life"
            , "Feather Fall"
            , "Find Familiar"
            , "Fog Cloud"
            , "Goodberry"
            , "Grease"
            , "Healing Word"
            , "Hellish Rebuke"
            , "Heroism"
            , "Identify"
            , "Inflict Wounds"
            , "Jump"
            , "Mage Armor"
            , "Magic Missile"
            , "Protection from Evil and Good"
            , "Purify Food and Drink"
            , "Sanctuary"
            , "Shield"
            , "Shield of Faith"
            , "Silent Image"
            , "Sleep"
            , "Speak with Animals"
            , "Tasha's Hideous Laughter"
            , "Thunderwave"
            , "Witch Bolt"
            ]

        Scroll2nd ->
            [ "Acid Arrow"
            , "Aid"
            , "Alter Self"
            , "Animal Messenger"
            , "Arcane Lock"
            , "Augury"
            , "Barkskin"
            , "Blindness/Deafness"
            , "Blur"
            , "Branding Smite"
            , "Calm Emotions"
            , "Continual Flame"
            , "Darkness"
            , "Darkvision"
            , "Detect Thoughts"
            , "Enhance Ability"
            , "Enlarge/Reduce"
            , "Find Traps"
            , "Flaming Sphere"
            , "Gentle Repose"
            , "Gust of Wind"
            , "Heat Metal"
            , "Hold Person"
            , "Invisibility"
            , "Knock"
            , "Lesser Restoration"
            , "Levitate"
            , "Magic Mouth"
            , "Magic Weapon"
            , "Mirror Image"
            , "Misty Step"
            , "Pass without Trace"
            , "Prayer of Healing"
            , "Protection from Poison"
            , "Scorching Ray"
            , "See Invisibility"
            , "Shatter"
            , "Silence"
            , "Spider Climb"
            , "Spiritual Weapon"
            , "Suggestion"
            , "Web"
            , "Zone of Truth"
            ]

        Scroll3rd ->
            [ "Animate Dead"
            , "Beacon of Hope"
            , "Bestow Curse"
            , "Blink"
            , "Call Lightning"
            , "Clairvoyance"
            , "Counterspell"
            , "Create Food and Water"
            , "Daylight"
            , "Dispel Magic"
            , "Fear"
            , "Feign Death"
            , "Fireball"
            , "Fly"
            , "Gaseous Form"
            , "Glyph of Warding"
            , "Haste"
            , "Hypnotic Pattern"
            , "Lightning Bolt"
            , "Magic Circle"
            , "Major Image"
            , "Mass Healing Word"
            , "Meld into Stone"
            , "Nondetection"
            , "Phantom Steed"
            , "Plant Growth"
            , "Protection from Energy"
            , "Remove Curse"
            , "Revivify"
            , "Sending"
            , "Sleet Storm"
            , "Slow"
            , "Speak with Dead"
            , "Spirit Guardians"
            , "Stinking Cloud"
            , "Tongues"
            , "Vampiric Touch"
            , "Water Breathing"
            , "Water Walk"
            ]

        Scroll4th ->
            [ "Arcane Eye"
            , "Banishment"
            , "Blight"
            , "Compulsion"
            , "Confusion"
            , "Conjure Minor Elementals"
            , "Control Water"
            , "Death Ward"
            , "Dimension Door"
            , "Divination"
            , "Dominate Beast"
            , "Fabricate"
            , "Fire Shield"
            , "Freedom of Movement"
            , "Greater Invisibility"
            , "Guardian of Faith"
            , "Hallucinatory Terrain"
            , "Ice Storm"
            , "Locate Creature"
            , "Phantasmal Killer"
            , "Polymorph"
            , "Resilient Sphere"
            , "Stone Shape"
            , "Stoneskin"
            , "Wall of Fire"
            ]

        Scroll5th ->
            [ "Animate Objects"
            , "Bigby's Hand"
            , "Cloudkill"
            , "Commune"
            , "Cone of Cold"
            , "Conjure Elemental"
            , "Contact Other Plane"
            , "Contagion"
            , "Creation"
            , "Dispel Evil and Good"
            , "Dominate Person"
            , "Dream"
            , "Flame Strike"
            , "Geas"
            , "Greater Restoration"
            , "Hallow"
            , "Hold Monster"
            , "Insect Plague"
            , "Legend Lore"
            , "Mass Cure Wounds"
            , "Mislead"
            , "Modify Memory"
            , "Passwall"
            , "Planar Binding"
            , "Raise Dead"
            , "Reincarnate"
            , "Scrying"
            , "Seeming"
            , "Telekinesis"
            , "Teleportation Circle"
            , "Tree Stride"
            , "Wall of Force"
            , "Wall of Stone"
            ]

        Scroll6th ->
            [ "Blade Barrier"
            , "Chain Lightning"
            , "Circle of Death"
            , "Conjure Fey"
            , "Contingency"
            , "Create Undead"
            , "Disintegrate"
            , "Drawmij's Instant Summons"
            , "Eyebite"
            , "Find the Path"
            , "Flesh to Stone"
            , "Forbiddance"
            , "Globe of Invulnerability"
            , "Guards and Wards"
            , "Harm"
            , "Heal"
            , "Heroes' Feast"
            , "Magic Jar"
            , "Mass Suggestion"
            , "Move Earth"
            , "Otiluke's Freezing Sphere"
            , "Otto's Irresistible Dance"
            , "Planar Ally"
            , "Programmed Illusion"
            , "Sunbeam"
            , "True Seeing"
            , "Wall of Ice"
            , "Wind Walk"
            , "Word of Recall"
            ]

        Scroll7th ->
            [ "Conjure Celestial"
            , "Delayed Blast Fireball"
            , "Divine Word"
            , "Etherealness"
            , "Finger of Death"
            , "Fire Storm"
            , "Forcecage"
            , "Mirage Arcane"
            , "Mordenkainen's Magnificent Mansion"
            , "Mordenkainen's Sword"
            , "Plane Shift"
            , "Prismatic Spray"
            , "Project Image"
            , "Regenerate"
            , "Resurrection"
            , "Reverse Gravity"
            , "Sequester"
            , "Simulacrum"
            , "Symbol"
            , "Teleport"
            ]

        Scroll8th ->
            [ "Animal Shapes"
            , "Antimagic Field"
            , "Antipathy/Sympathy"
            , "Clone"
            , "Control Weather"
            , "Demiplane"
            , "Dominate Monster"
            , "Earthquake"
            , "Feeblemind"
            , "Glibness"
            , "Holy Aura"
            , "Incendiary Cloud"
            , "Maze"
            , "Mind Blank"
            , "Power Word Stun"
            , "Sunburst"
            , "Telepathy"
            , "Tsunami"
            ]

        Scroll9th ->
            [ "Astral Projection"
            , "Foresight"
            , "Gate"
            , "Imprisonment"
            , "Mass Heal"
            , "Meteor Swarm"
            , "Power Word Kill"
            , "Prismatic Wall"
            , "Shapechange"
            , "Storm of Vengeance"
            , "Time Stop"
            , "True Polymorph"
            , "True Resurrection"
            , "Weird"
            , "Wish"
            ]
