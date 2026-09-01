module Ui.Status exposing (StatusUi, fromCreature, fresh)

{-| Status editor state — the drawer panel for the posture
toggles (cover, concentrating, hiding, dodging, flying + flight
height). The editor edits this draft; the Apply buttons write it
onto the active creature or the selection.

@docs StatusUi, fromCreature, fresh

-}

import Encounter exposing (Cover(..), Creature)


type alias StatusUi =
    { target : String
    , cover : Cover
    , concentrating : Bool
    , hiding : Bool
    , dodging : Bool
    , flying : Bool
    , flyHeight : Int
    }


{-| Prefill the draft from the creature the editor opened on, so
it reads as "this creature's current status" rather than a blank
form.
-}
fromCreature : Creature -> StatusUi
fromCreature c =
    { target = c.name
    , cover = c.cover
    , concentrating = c.concentrating
    , hiding = c.hiding
    , dodging = c.dodging
    , flying = c.flying
    , flyHeight = c.flyHeight
    }


{-| All-clear defaults, for a target that has left the queue
between click and open.
-}
fresh : String -> StatusUi
fresh target =
    { target = target
    , cover = NoCover
    , concentrating = False
    , hiding = False
    , dodging = False
    , flying = False
    , flyHeight = 0
    }
