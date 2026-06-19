module Encounter.RandomEncounter.Lore exposing
    ( Role(..), Source(..), Slot, Group
    , bundled
    , materialize
    , groupFits
    , ResolvedMember, resolveMembers
    )

{-| Bundled "lore-accurate" creature associations for the
Random Encounter generator's _Lore-leaning_ toggle.

A `Group` is a small composition of D&D creatures that
naturally appear together — goblins serving a hobgoblin
captain, kobolds worshipping a dragon, a hag and her
familiars. When the toggle is on, the generator preferentially
draws from groups whose members match the active habitat /
type / exclude filters, falling back to the per-slot fill
when no group fits.

This module ships ~45 hand-authored groups covering the
iconic associations across the 2024 SRD bundle. The bundle
references creatures by **name** so the data is independent of
the compendium's uuid scheme; lookups happen at generation
time via `Compendium.findByName`. Members whose names don't
resolve are silently dropped (the bundle stays usable even if
a creature is renamed or removed).

Each member carries a count range; the materialiser rolls
within the range and scales the result down if total XP would
exceed the budget by more than ~20%.

@docs Role, Source, Slot, Group
@docs bundled
@docs materialize
@docs groupFits

-}

import Compendium exposing (Creature, Habitat)
import Random exposing (Generator)


{-| What part the member plays in the group. The role is
informational today (it surfaces in the bundled-group editor
when that ships) but doesn't yet drive the algorithm — the
count range and weight handle composition shape.

  - `Leader` — the boss / commander of the group.
  - `Member` — a regular combatant.
  - `Minion` — a weak supporter (low-CR fill).
  - `Pet` — an animal companion / mount / familiar.

-}
type Role
    = Leader
    | Member
    | Minion
    | Pet


{-| Provenance tag for the group. Bundled groups ship with
the app; eventually the Groups editor will let users author
custom groups whose source is `UserCurated`.
-}
type Source
    = Bundled
    | UserCurated


type alias Slot =
    { name : String
    , role : Role
    , countMin : Int
    , countMax : Int
    }


type alias Group =
    { id : String
    , name : String
    , members : List Slot
    , weight : Int
    , source : Source

    -- Optional free-form paragraph the GM can attach to a
    -- custom grouping — surfaces in the Compendium detail pane
    -- below the members list.  Empty string for bundled groups
    -- (they don't carry authored lore today) and for groups
    -- saved by an older client that didn't know the field.
    , description : String
    }



-- ── HELPERS ──────────────────────────────────────────────────────────────────


member : String -> Role -> Int -> Int -> Slot
member name role lo hi =
    { name = name, role = role, countMin = lo, countMax = hi }


grp : String -> String -> Int -> List Slot -> Group
grp id name weight members_ =
    { id = id
    , name = name
    , members = members_
    , weight = weight
    , source = Bundled
    , description = ""
    }


{-| Attach a lore paragraph to a bundled grouping. Lets each
`grp` entry below stay readable (id, name, weight, members on
familiar lines) while still carrying the GM-facing flavour
text that surfaces in the Compendium detail pane.
-}
withLore : String -> Group -> Group
withLore d g =
    { g | description = d }



-- ── BUNDLED GROUPS ───────────────────────────────────────────────────────────


{-| The full bundled lore-group set. Generator consults this
list when the Lore-leaning toggle is on.
-}
bundled : List Group
bundled =
    -- ── Goblinoids ──────────────────────────────────────────
    [ grp "goblinoid-warband"
        "Goblinoid Warband"
        6
        [ member "Goblin Warrior" Member 3 6
        , member "Hobgoblin Warrior" Leader 1 2
        ]
        |> withLore "Hobgoblin warriors press goblin levies into a respectable warband — the goblins serve as scouts and arrow-fodder for their better-trained elder cousins."
    , grp "goblin-raid"
        "Goblin Raiding Party"
        5
        [ member "Goblin Warrior" Member 3 5
        , member "Bugbear Warrior" Leader 1 2
        ]
        |> withLore "Goblins know to follow a bugbear's nose for plunder; in return, the bugbear gets an obedient bodyguard, and a distraction while it maneuvers for the ambush."
    , grp "goblin-bosss-gang"
        "Goblin Boss's Gang"
        4
        [ member "Goblin Boss" Leader 1 1
        , member "Goblin Warrior" Member 3 6
        , member "Goblin Minion" Minion 2 4
        ]
        |> withLore "Through cunning, bribery, or threats, a goblin boss has climbed the ranks to command jealous warriors and fawning minions to do his bidding."
    , grp "hobgoblin-patrol"
        "Hobgoblin Patrol"
        4
        [ member "Hobgoblin Captain" Leader 1 1
        , member "Hobgoblin Warrior" Member 3 6
        , member "Worg" Pet 2 3
        ]
        |> withLore "A hobgoblin captain marches his warriors towards glory, worgs loping afar to flush out any ambush."
    , grp "bugbear-ambush"
        "Bugbear Ambush"
        3
        [ member "Bugbear Stalker" Leader 2 3
        , member "Goblin Warrior" Member 2 4
        ]
        |> withLore "Goblins distract while the bugbears spring the trap."
    , grp "worg-pack"
        "Worg Pack"
        3
        [ member "Worg" Member 2 4
        , member "Goblin Warrior" Pet 3 5
        ]
        |> withLore "A worg pack lopes through the wild with goblin riders cinched to their backs, on the hunt for meat and spoils."

    -- ── Dragons & Kobolds ───────────────────────────────────
    , grp "kobold-warband"
        "Kobold Warband"
        5
        [ member "Kobold Warrior" Member 6 12
        ]
        |> withLore "Kobolds in packs are dangerous indeed, and a special threat to quarry that underestimates them."
    , grp "wyrmlings-court"
        "Young Dragon's Court"
        2
        [ member "Young Red Dragon" Leader 1 1
        , member "Kobold Warrior" Minion 4 8
        ]
        |> withLore "A young red dragon has attracted the attention of fawning kobold worshippers; annoying, perhaps, but perhaps useful..."
    , grp "adult-dragon-tribute"
        "Adult Dragon's Tribute"
        1
        [ member "Adult Red Dragon" Leader 1 1
        , member "Kobold Warrior" Minion 8 12
        ]
        |> withLore "An adult red dragon's kobold worshippers will defend their lord to the death. Not that their master needs defending, but if their distractions can shorten an inconvenient fight, so much the better."

    -- ── Drider & spiders ────────────────────────────────────
    , grp "drider-webs"
        "Drider's Web"
        3
        [ member "Drider" Leader 1 2
        , member "Giant Spider" Member 2 4
        , member "Giant Wolf Spider" Minion 1 3
        ]
        |> withLore "If you think you've encountered a lone drider, you're wrong."

    -- ── Aquatic aberrations ────────────────────────────────
    , grp "aboleth-throne"
        "Aboleth's Domain"
        2
        [ member "Aboleth" Leader 1 1
        , member "Chuul" Member 1 2
        ]
        |> withLore "The aboleth sends it children forth to project its will, and brings them back to defend their creator."
    , grp "sahuagin-raid"
        "Sahuagin Raid"
        4
        [ member "Sahuagin Warrior" Member 3 5
        , member "Hunter Shark" Pet 1 2
        ]
        |> withLore "The sahuagin with its scouts is a fearsome sea raider indeed."
    , grp "merrow-hunters"
        "Merrow Hunters"
        3
        [ member "Merrow" Member 2 4
        , member "Giant Crocodile" Pet 1 1
        ]
        |> withLore "The ravenous merrow have many traps of ambush, some living..."

    -- ── Gnolls ───────────────────────────────────────────────
    , grp "gnoll-pack"
        "Gnoll Pack"
        4
        [ member "Gnoll Warrior" Member 3 5
        , member "Giant Hyena" Pet 1 2
        , member "Hyena" Pet 2 4
        ]
        |> withLore "A hunting gnoll pack with its loyal hyenas is all gnashing teeth, slashing spears, and ruinous speed."

    -- ── Giants ───────────────────────────────────────────────
    , grp "hill-giant-camp"
        "Hill Giant Camp"
        3
        [ member "Hill Giant" Leader 1 2
        , member "Ogre" Member 1 2
        ]
        |> withLore "One the brains, the other the brawn, and plunder to be had."
    , grp "frost-giant-hunt"
        "Frost Giant Hunt"
        3
        [ member "Frost Giant" Leader 1 2
        , member "Winter Wolf" Pet 2 4
        ]
        |> withLore "In the frozen wastes, the wolves' noses will pick out the prey; their masters will choose the sport."
    , grp "fire-giant-forge"
        "Fire Giant's Forge"
        2
        [ member "Fire Giant" Leader 1 2
        , member "Hell Hound" Pet 2 4
        ]
        |> withLore "Fire giants keep hell hounds as forge-watchers and hunting hounds — the hounds' breath does not melt the slag-piles, but it does keep slaves from creeping out the wrong door."
    , grp "cloud-giant-eyrie"
        "Cloud Giant's Eyrie"
        1
        [ member "Cloud Giant" Leader 1 1
        , member "Griffon" Pet 1 2
        ]
        |> withLore "Cloud giants keep griffons as mounts and messengers — the giants and their griffons share territory by altitude, griffons ranging above the clouds, the giant by the mountain peak."
    , grp "storm-giant-citadel"
        "Storm Giant Citadel"
        1
        [ member "Storm Giant" Leader 1 1
        , member "Wyvern" Pet 1 2
        ]
        |> withLore "A storm giant — the highest of giant-kind — keeps wyverns as guardians of its cloud-skirted citadel, drawn to the giant's lightning and the constant updraft of its court."
    , grp "ogre-marauders"
        "Ogre Marauders"
        3
        [ member "Ogre" Member 2 3
        , member "Bandit" Minion 2 4
        ]
        |> withLore "Ogres and bandits make a profitable pairing — the ogres provide muscle the bandits couldn't muster, the bandits handle the talking and the ransom math."
    , grp "troll-lair"
        "Troll Lair"
        2
        [ member "Troll" Member 1 2
        , member "Ogre Zombie" Minion 0 2
        ]
        |> withLore "Trolls in a wretched lair, with the half-eaten remains of an ogre or two raised as zombies for menial defence — the trolls are too lazy to dispose of the kills, and a moving carcass needs no burial."

    -- ── Undead ───────────────────────────────────────────────
    , grp "mummy-tomb"
        "Mummy Tomb Guard"
        3
        [ member "Mummy" Leader 1 1
        , member "Skeleton" Member 3 6
        , member "Zombie" Member 2 4
        ]
        |> withLore "A mummy stands eternal guard, with skeletons and zombies as its rank-and-file — the dead of the tomb itself, conscripted by ancient curse into perpetual vigil."
    , grp "mummy-lord-court"
        "Mummy Lord's Court"
        1
        [ member "Mummy Lord" Leader 1 1
        , member "Mummy" Member 1 2
        , member "Skeleton" Minion 4 8
        ]
        |> withLore "A mummy lord — pharaoh of the tomb — holds court with lesser mummies as advisors and ranks of skeletons as the standing army of an empire forgotten three thousand years."
    , grp "lich-demesne"
        "Lich's Demesne"
        1
        [ member "Lich" Leader 1 1
        , member "Ghoul" Member 2 4
        , member "Ghast" Member 1 2
        ]
        |> withLore "A lich's demesne is patrolled by its retinue of ghouls and ghasts — feral undead the lich raised in life and treats now as exotic pets, well-fed on intruders."
    , grp "vampire-brood"
        "Vampire's Brood"
        2
        [ member "Vampire" Leader 1 1
        , member "Vampire Spawn" Member 2 4
        , member "Vampire Familiar" Pet 1 2
        ]
        |> withLore "A vampire holds court with its spawn — fledglings still in the first century of unlife, kept on a tight leash — and a familiar (a bat, rat, or wolf) bound by the elder's blood."
    , grp "ghost-haunting"
        "Ghost Haunting"
        3
        [ member "Ghost" Leader 1 1
        , member "Shadow" Member 1 3
        , member "Specter" Member 1 2
        ]
        |> withLore "A ghost lingers where it died, drawing lesser shades and specters into its orbit — the haunting expands until a banishment or a memorial puts it down."
    , grp "skeleton-legion"
        "Skeleton Legion"
        3
        [ member "Skeleton" Member 6 10
        , member "Warhorse Skeleton" Pet 1 3
        , member "Minotaur Skeleton" Leader 0 1
        ]
        |> withLore "A legion of skeletons raised in bulk for some forgotten war — warhorse skeletons as cavalry, with a minotaur skeleton sometimes among them as a champion or relic of the legion's last commander."
    , grp "zombie-horde"
        "Zombie Horde"
        3
        [ member "Zombie" Member 6 12
        , member "Ogre Zombie" Leader 1 2
        ]
        |> withLore "A zombie horde shambles in numbers, with an ogre zombie or two as the centerpiece — the work of a necromancer who valued mass over discrimination."
    , grp "wraith-host"
        "Wraith Host"
        2
        [ member "Wraith" Leader 1 1
        , member "Specter" Member 2 4
        ]
        |> withLore "A wraith — the bound spirit of a powerful evil — gathers lesser specters in its wake, feeding on their lingering despair and binding them as drones to its will."

    -- ── Hags ─────────────────────────────────────────────────
    , grp "hag-coven"
        "Hag Coven"
        1
        [ member "Green Hag" Member 1 1
        , member "Sea Hag" Member 1 1
        , member "Night Hag" Member 1 1
        ]
        |> withLore "A coven of three hags — green, sea, and night — who share secrets and curses across the boundaries of their domains; together they are far more dangerous than any one of them apart."
    , grp "sea-hag-tide"
        "Sea Hag's Tide"
        2
        [ member "Sea Hag" Leader 1 1
        , member "Sahuagin Warrior" Member 2 4
        ]
        |> withLore "A sea hag and her sahuagin acolytes — the hag is a goddess to them, the sahuagin her priesthood and her hunting band, drawn into her cave by the smell of fresh bait."
    , grp "green-hag-grove"
        "Green Hag's Grove"
        2
        [ member "Green Hag" Leader 1 1
        , member "Worg" Pet 1 2
        , member "Goblin Warrior" Minion 2 3
        ]
        |> withLore "A green hag in her shadowed grove keeps worgs as guard-beasts and goblins as servants — the worgs sniff out intruders, the goblins do the chores the hag deems beneath her."
    , grp "night-hag-bargain"
        "Night Hag's Bargain"
        1
        [ member "Night Hag" Leader 1 1
        , member "Imp" Pet 1 2
        ]
        |> withLore "A night hag conducts her soul-bargains in a half-dream, with an imp at her shoulder as scribe and errand-runner — a witness to contracts the buyer thought were spoken in private."

    -- ── Fiends ───────────────────────────────────────────────
    , grp "imp-quasit-servants"
        "Imp & Quasit Servants"
        3
        [ member "Imp" Member 1 2
        , member "Quasit" Member 1 2
        ]
        |> withLore "Imps and quasits — lowest of devils and demons — sometimes paired as servitors to a more powerful master, or just at large in the world running petty errands."
    , grp "devil-patrol"
        "Devil Patrol"
        3
        [ member "Bearded Devil" Member 2 3
        , member "Hell Hound" Pet 1 2
        ]
        |> withLore "Bearded devils on patrol with hell hounds — disciplined infernal infantry that the lower hierarchy of Hell uses to police its outer marches."
    , grp "demon-incursion"
        "Demon Incursion"
        2
        [ member "Vrock" Leader 1 2
        , member "Dretch" Minion 4 6
        ]
        |> withLore "Vrocks lead a swarm of dretches through some torn portal — a demon incursion is mostly a riot, the vrocks barely keeping the dretches pointed in the right direction."
    , grp "pit-fiend-retinue"
        "Pit Fiend's Retinue"
        1
        [ member "Pit Fiend" Leader 1 1
        , member "Bone Devil" Member 1 2
        , member "Barbed Devil" Member 1 2
        ]
        |> withLore "A pit fiend's retinue — a bone devil as advisor, barbed devils as bodyguard — all bound to the pit fiend by infernal contract and centuries of fearful service."
    , grp "marilith-honor-guard"
        "Marilith's Honor Guard"
        1
        [ member "Marilith" Leader 1 1
        , member "Hezrou" Member 1 2
        ]
        |> withLore "A marilith's honor guard of hezrou — the bloated frog-demons enjoy her violence and serve her with a kind of cult devotion no other demon would tolerate."

    -- ── Humanoid bands ──────────────────────────────────────
    , grp "bandit-camp"
        "Bandit Camp"
        5
        [ member "Bandit" Member 4 6
        , member "Bandit Captain" Leader 1 1
        ]
        |> withLore "Bandits in a road-camp with their captain — most of them deserters or runaways, the captain the one who keeps them from murdering each other over the spoils."
    , grp "cultist-cabal"
        "Cultist Cabal"
        4
        [ member "Cultist" Member 3 5
        , member "Cultist Fanatic" Leader 1 2
        ]
        |> withLore "A cabal of cultists with fanatics in the lead — the fanatics handle the rites, the rank-and-file the recruiting and the bookkeeping that pays for incense and ritual blades."
    , grp "knight-retinue"
        "Knight & Retinue"
        2
        [ member "Knight" Leader 1 1
        , member "Guard" Member 3 5
        , member "Scout" Member 0 2
        ]
        |> withLore "A knight on the road with his retinue — guards as muscle, sometimes a scout or two ahead.  Honourable on a good day, mercenary on a bad one."
    , grp "priest-procession"
        "Priest's Procession"
        2
        [ member "Priest" Leader 1 1
        , member "Priest Acolyte" Member 3 5
        ]
        |> withLore "A priest leads acolytes in slow procession — to or from a shrine, a pilgrimage, or a funeral they consider too important to leave to the laity."
    , grp "berserker-warband"
        "Berserker Warband"
        2
        [ member "Berserker" Member 3 5
        ]
        |> withLore "Berserkers without a leader — drunk on grog and fury, they pick fights with anything that crosses their path and stagger off looking for the next when they win or fall."

    -- ── Beasts ───────────────────────────────────────────────
    , grp "wolf-pack"
        "Wolf Pack"
        5
        [ member "Dire Wolf" Leader 1 2
        , member "Wolf" Member 3 5
        ]
        |> withLore "A wolf pack with one or two dire wolves as alpha and the smaller wolves as the hunting line — the pack hunts cooperatively and rarely starts a fight it can't finish."
    , grp "owlbear-den"
        "Owlbear Den"
        3
        [ member "Owlbear" Member 1 3
        ]
        |> withLore "Owlbears around their den — usually a mated pair and sometimes a half-grown cub.  They are not territorial as cousins; they are territorial as a household."
    , grp "bear-family"
        "Bear Family"
        2
        [ member "Brown Bear" Leader 1 1
        , member "Black Bear" Member 1 2
        ]
        |> withLore "A brown bear matriarch and her smaller black-bear cousins — not actually relatives, but cohabiting a forest range and tolerating each other's company near a good salmon run."

    -- ── Underdark / cave ────────────────────────────────────
    , grp "carrion-crawl"
        "Carrion Crawl"
        2
        [ member "Carrion Crawler" Member 1 2
        , member "Zombie" Minion 2 4
        ]
        |> withLore "A carrion crawler trails behind a knot of zombies, drawn by the moving meat — the crawler doesn't mind sharing the kill, since the zombies don't eat what they catch."
    , grp "cloaker-ambush"
        "Cloaker Ambush"
        2
        [ member "Cloaker" Member 1 2
        , member "Darkmantle" Minion 2 4
        ]
        |> withLore "A cloaker drifts on cave-currents above a ceiling crusted with darkmantles — the cloaker chooses its victims, the darkmantles drop on whatever the cloaker has already wounded."
    , grp "stirge-swarm"
        "Stirge Swarm"
        3
        [ member "Stirge" Member 4 8
        , member "Giant Bat" Pet 1 2
        ]
        |> withLore "A stirge swarm in some bat-haunted cave, the stirges feeding on whatever blood the giant bats leave behind — and on each other when nothing else is bleeding."

    -- ── Wilds ────────────────────────────────────────────────
    , grp "treants-grove"
        "Treant's Grove"
        2
        [ member "Treant" Leader 1 1
        , member "Awakened Tree" Member 1 3
        ]
        |> withLore "A treant tends a grove of awakened trees as students and lieutenants — the treant is patient, the awakened trees are not, and intruders are dealt with by whichever is closer."

    -- ── Elementals / fire ──────────────────────────────────
    , grp "salamander-forge"
        "Salamander Forge"
        2
        [ member "Salamander" Member 1 2
        , member "Magma Mephit" Minion 2 4
        ]
        |> withLore "Salamanders work a hidden forge in the heart of an active volcano, with magma mephits as bellows-tenders and errand-runners — a working partnership of fire-creatures with nowhere cooler to be."
    , grp "fire-elemental-cult"
        "Fire Elemental's Court"
        2
        [ member "Fire Elemental" Leader 1 1
        , member "Magma Mephit" Minion 3 5
        ]
        |> withLore "A fire elemental holds court in a chamber of burning rock, with magma mephits as petitioners, jesters, and a kind of impish nobility that flits about its larger cousin."
    ]



-- ── MATCHING + MATERIALISATION ────────────────────────────────────────────────


{-| Test whether a group is eligible for the current generator
params. A group qualifies when:

  - At least one of its members resolves to a real compendium
    creature (the bundle stays robust to compendium edits).
  - If the GM picked a habitat, at least one member lists it.
  - If the GM picked one or more types, at least one member's
    race is in the list.
  - None of the resolved members appear in `excludedIds`.
  - The group's _minimum_ total XP fits within 1.2× the budget
    (affordability — so we don't try a Pit Fiend Retinue on a
    level-1 party).
  - The group's _maximum_ total XP is at least 50% of the
    budget (coverage — so we don't pick Fire Elemental's Court
    for a 14,800 XP budget and watch the roll sum to 2,250).

The affordability + coverage pair bounds the group's natural
XP range to roughly the GM's budget, leaving the top-up pass
to fill the gap when the rolled total lands near the low end
of that range.

The "at least one member matches the filter" rule keeps groups
flexible — a Goblinoid Warband with Forest / Hill / Underdark
worgs and goblins matches a Forest filter without requiring
every member to live in Forest.

-}
groupFits :
    { budget : Int
    , habitat : Maybe Habitat
    , creatureTypes : List String
    , excludedIds : List String
    }
    -> Group
    -> List Creature
    -> Bool
groupFits params group pool =
    let
        resolved =
            resolveMembers group pool

        memberCreatures =
            List.map .creature resolved

        habitatOK =
            case params.habitat of
                Nothing ->
                    True

                Just h ->
                    List.any (\c -> List.member h c.habitats) memberCreatures

        typeOK =
            List.isEmpty params.creatureTypes
                || List.any (\c -> List.member c.race params.creatureTypes) memberCreatures

        notExcluded =
            List.all (\c -> not (List.member c.id params.excludedIds)) memberCreatures

        minTotalXp =
            List.foldl
                (\r acc -> acc + r.creature.xp * r.slot.countMin)
                0
                resolved

        maxTotalXp =
            List.foldl
                (\r acc -> acc + r.creature.xp * r.slot.countMax)
                0
                resolved

        affordable =
            -- Allow the minimum to push the original budget by
            -- up to 20% so a group near the budget ceiling still
            -- qualifies — the materialiser will scale counts
            -- down if needed.
            minTotalXp <= params.budget * 12 // 10

        meaningful =
            -- The group's MAX rolls must hit at least 50% of
            -- the budget so a small-XP group (Wolf Pack at
            -- 650 XP max) doesn't get picked for a level-12
            -- Moderate budget (~14,800).  Slot-queue fill
            -- takes over via `pickLoreFill` falling back to
            -- `pickMainGroups` when no lore group qualifies.
            maxTotalXp * 2 >= params.budget
    in
    not (List.isEmpty resolved)
        && habitatOK
        && typeOK
        && notExcluded
        && affordable
        && meaningful


{-| Roll concrete counts for each member and return the
materialised `(creature, count)` list. Counts roll uniformly
in `[countMin, countMax]`; if the rolled total exceeds the
budget by more than 20% **or** the total creature count
exceeds `maxCount`, every count scales down proportionally to
fit (rounded down, floor of 1 per member so no group entry
vanishes).

The `maxCount` parameter is the Scale knob's promise pushed
into the materialiser — a Few roll caps the total creature
count at 4 even if a Goblinoid Warband would naturally have
5–9 bodies. The result is a shrunken-but-still-thematic
warband (one captain + one warrior + one worg = 3) instead of
violating the Scale.

-}
materialize : Int -> Int -> Group -> List Creature -> Generator (List ( Creature, Int ))
materialize budget maxCount group pool =
    let
        resolved =
            resolveMembers group pool
    in
    rollCounts resolved
        |> Random.map
            (\counts ->
                let
                    pairs =
                        List.map2 (\r n -> ( r.creature, n )) resolved counts

                    total =
                        List.foldl (\( c, n ) acc -> acc + c.xp * n) 0 pairs

                    overTolerance =
                        budget * 12 // 10

                    rolledCount =
                        List.foldl (\( _, n ) acc -> acc + n) 0 pairs

                    -- Pick the tighter of the two ratios so we
                    -- respect whichever ceiling (budget or count)
                    -- bites first.  Default to 1.0 when no scale-
                    -- down is needed.
                    scale =
                        let
                            budgetScale =
                                if total <= overTolerance then
                                    1.0

                                else
                                    toFloat overTolerance / toFloat (max 1 total)

                            countScale =
                                if rolledCount <= maxCount then
                                    1.0

                                else
                                    toFloat maxCount / toFloat (max 1 rolledCount)
                        in
                        Basics.min budgetScale countScale
                in
                if scale >= 1.0 then
                    pairs |> List.filter (\( _, n ) -> n > 0)

                else
                    pairs
                        |> List.map
                            (\( c, n ) ->
                                ( c, max 1 (floor (toFloat n * scale)) )
                            )
                        |> List.filter (\( _, n ) -> n > 0)
            )


rollCounts : List ResolvedMember -> Generator (List Int)
rollCounts members =
    case members of
        [] ->
            Random.constant []

        first :: rest ->
            Random.int first.slot.countMin first.slot.countMax
                |> Random.andThen
                    (\n ->
                        rollCounts rest |> Random.map (\ns -> n :: ns)
                    )


type alias ResolvedMember =
    { slot : Slot
    , creature : Creature
    }


resolveMembers : Group -> List Creature -> List ResolvedMember
resolveMembers group pool =
    List.filterMap
        (\m ->
            Compendium.findByName m.name (Compendium.fromList pool)
                |> Maybe.map (\c -> { slot = m, creature = c })
        )
        group.members
