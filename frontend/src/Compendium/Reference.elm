module Compendium.Reference exposing (damageTypes, conditions)

{-| Canonical lookup data from the D&D 2024 rules.

Only the values the compendium edit form needs as multi-select
dropdown options live here — extending these lists is a one-line
change that automatically updates every picker that renders them.

@docs damageTypes, conditions

-}


{-| The 13 damage types from the 2024 Player's Handbook. Listed
in the rules' canonical alphabetical order so the picker is
predictable. Used by the Damage Vulnerabilities / Resistances /
Immunities multi-select pickers in the New / Edit Creature modal.
-}
damageTypes : List String
damageTypes =
    [ "Acid"
    , "Bludgeoning"
    , "Cold"
    , "Fire"
    , "Force"
    , "Lightning"
    , "Necrotic"
    , "Piercing"
    , "Poison"
    , "Psychic"
    , "Radiant"
    , "Slashing"
    , "Thunder"
    ]


{-| The 15 conditions from the 2024 Player's Handbook. Listed in
the rules' canonical alphabetical order. Used by the Condition
Immunities multi-select picker in the New / Edit Creature modal.

`Exhaustion` is included as a single condition; the 2024 rules
ladder its severity over six levels but mid-combat compendium
entries normally just declare immunity to the condition itself.

-}
conditions : List String
conditions =
    [ "Blinded"
    , "Charmed"
    , "Deafened"
    , "Exhaustion"
    , "Frightened"
    , "Grappled"
    , "Incapacitated"
    , "Invisible"
    , "Paralyzed"
    , "Petrified"
    , "Poisoned"
    , "Prone"
    , "Restrained"
    , "Stunned"
    , "Unconscious"
    ]
