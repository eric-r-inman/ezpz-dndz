module Ui.Status exposing (StatusLogEntry, StatusTargetSnapshot, StatusUi, fresh, maxStatusLogEntries)

{-| Status editor state — the drawer panel for the posture
toggles. The editor edits this draft; the Apply buttons add it to
the target creature or the selection.

@docs StatusLogEntry, StatusTargetSnapshot, StatusUi, fresh, maxStatusLogEntries

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


{-| One row of the status editor's log. `summary` names what the
apply put on, and `seq` is the row's identity, handed out by
`Model.nextStatusLogSeq`.
-}
type alias StatusLogEntry =
    { seq : Int
    , summary : String
    , targets : List StatusTargetSnapshot
    }


{-| A creature's posture as it stood before an apply touched it.
An apply only ever adds, so undoing one cannot switch the applied
flags back off without stripping a status the creature already
carried; it puts these values back instead.
-}
type alias StatusTargetSnapshot =
    { name : String
    , cover : Cover
    , concentrating : Bool
    , concentrationNote : String
    , hiding : Bool
    , dodging : Bool
    , flying : Bool
    , flyHeight : Int
    }


{-| Cap on the status log, matching the condition log's depth.
-}
maxStatusLogEntries : Int
maxStatusLogEntries =
    30


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
