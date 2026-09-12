module Ui.Status exposing (StatusUi, fresh)

{-| Status editor state — the drawer panel for the posture
toggles. The editor edits this draft; the Apply buttons add it to
the target creature or the selection.

@docs StatusUi, fresh

-}

import Encounter exposing (Cover(..))


type alias StatusUi =
    { target : String
    , cover : Cover
    , concentrating : Bool
    , concentrationNote : String
    , hiding : Bool
    , dodging : Bool
    , flying : Bool
    , flyHeight : Int
    }


{-| A draft with nothing set, aimed at the named creature.
-}
fresh : String -> StatusUi
fresh target =
    { target = target
    , cover = NoCover
    , concentrating = False
    , concentrationNote = ""
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    }
