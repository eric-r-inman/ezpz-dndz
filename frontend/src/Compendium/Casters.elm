module Compendium.Casters exposing (CasterSummary, resolve, spellcastingFor)

{-| Which creatures in an encounter can cast, and what they cast.

Lives beside the compendium rather than inside it because the
fallback parse routes through `Compendium.SpellcastingText`,
which imports `Compendium` itself. Keeping the predicate here
means the spell-list surface and the queue's reminder strip
agree on who counts as a caster.

@docs CasterSummary, resolve, spellcastingFor

-}

import Compendium exposing (Spellcasting)
import Compendium.SpellcastingText
import Encounter


{-| An encounter creature paired with the spellcasting block its
compendium source carries.
-}
type alias CasterSummary =
    { creature : Encounter.Creature
    , spellcasting : Spellcasting
    }


{-| Look the creature's source up by id, falling back to its
name for instances that predate compendium ids, and keep it only
when that source can cast.
-}
resolve : Compendium.Db -> Encounter.Creature -> Maybe CasterSummary
resolve db c =
    let
        lookup =
            case c.creatureId of
                Just id ->
                    case Compendium.find id db of
                        Just hit ->
                            Just hit

                        Nothing ->
                            Compendium.findByName c.name db

                Nothing ->
                    Compendium.findByName c.name db
    in
    lookup
        |> Maybe.andThen spellcastingFor
        |> Maybe.map (\sc -> { creature = c, spellcasting = sc })


{-| Prefer the structured field; fall back to parsing any
Spellcasting-named feature on the fly for older bundled data
that predates the parser's extraction pass.
-}
spellcastingFor : Compendium.Creature -> Maybe Spellcasting
spellcastingFor c =
    case c.spellcasting of
        Just sc ->
            Just sc

        Nothing ->
            spellcastingFeatureDescription c
                |> Maybe.andThen Compendium.SpellcastingText.parse


spellcastingFeatureDescription : Compendium.Creature -> Maybe String
spellcastingFeatureDescription c =
    (c.actions ++ c.bonusActions ++ c.traits)
        |> List.filter (\f -> nameLooksLikeSpellcasting f.name)
        |> List.head
        |> Maybe.map .description


nameLooksLikeSpellcasting : String -> Bool
nameLooksLikeSpellcasting name =
    String.contains "spellcasting" (String.toLower name)
