module Preferences exposing (Preferences, CardDensity(..), default)

{-| User-tunable preferences blob.

The struct lives on `Model.preferences` and is read by every
feature that has a configurable behavior — currently
`Update.Encounter.nextTurn` reads `autoScrollActiveCard` to
decide whether to scroll the freshly-active card into view, and
the AppBar settings popover writes `theme` via
`Update.Preferences.themeSet`.

The plan is for `/api/me/preferences` (Phase 11) to load and
persist this struct per-user. Until that endpoint lands, every
session uses [`default`](#default) and any in-session changes
live only in memory.

@docs Preferences, CardDensity, default

-}

import Dict exposing (Dict)
import Msg exposing (CompendiumSort(..), Theme(..))



-- `Theme` is re-exported from `Msg` (where the type is defined
-- to avoid an import cycle with the `PreferencesThemeSet Theme`
-- Msg constructor).  `Auto` follows the OS / browser preference
-- (`prefers-color-scheme`); `Modern` and `Dark` pin a specific
-- mode.


{-| Layout density on the creature cards. `Compact` shrinks the
row gaps + font size for high-creature-count encounters;
`Normal` is the current rendering.
-}
type CardDensity
    = Compact
    | Normal


type alias Preferences =
    { theme : Theme
    , cardDensity : CardDensity
    , soundEnabled : Bool
    , autoScrollActiveCard : Bool
    , autoRollInitiativeOnAdd : Bool
    , defaultCompendiumSort : CompendiumSort
    , keyboardShortcuts : Dict String String
    }


{-| Sane defaults for a fresh session. These match the existing
hard-coded behavior so adopting this struct is a no-op until the
GM tweaks something.

  - Theme `Auto` because the CSS already handles
    `prefers-color-scheme`.
  - Density `Normal` because that's the only thing the CSS
    currently renders.
  - Sound on.
  - Auto-scroll the active card into view at the top of every
    turn — a strong default for long queues.
  - Auto-roll initiative when a new creature lands in the queue
    — matches the current `Compendium.AddToQueue` flow.
  - Default sort matches what `Ui.Compendium.emptyCompendium`
    initializes the browser to (`SortName`).
  - Keyboard shortcuts: empty by default. The future feature
    will let users override individual shortcuts via this Dict.

-}
default : Preferences
default =
    { theme = Auto
    , cardDensity = Normal
    , soundEnabled = True
    , autoScrollActiveCard = True
    , autoRollInitiativeOnAdd = True
    , defaultCompendiumSort = SortName
    , keyboardShortcuts = Dict.empty
    }
