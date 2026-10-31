module Util.Text exposing (andList)

{-| Helpers for the sentences the app shows.

@docs andList

-}


{-| Names joined for a sentence: "Ogre", "Ogre and Wolf", or
"Ogre, Wolf and Bat".
-}
andList : List String -> String
andList names =
    case List.reverse names of
        last :: ((_ :: _) as rest) ->
            String.join ", " (List.reverse rest) ++ " and " ++ last

        _ ->
            String.concat names
