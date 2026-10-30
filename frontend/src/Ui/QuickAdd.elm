module Ui.QuickAdd exposing
    ( QuickAddSort(..), QuickAddUi
    , fresh, setSearchText, toggleSort
    )

{-| Quick Add modal state — a one-click "drop a creature into the
encounter" picker that lists every compendium creature with its
challenge rating, plus a sort toggle and a name-search input.

The modal stays lightweight compared to the full Compendium
browser: no kind filter, no add-count, no edit affordances —
just "I want to add one goblin right now," with a search box so
the GM can narrow the list at speed.

@docs QuickAddSort, QuickAddUi
@docs fresh, setSearchText, toggleSort

-}


{-| Which key the list is sorted by. Initial value is
`SortAlpha`; the toggle button flips between the two.
-}
type QuickAddSort
    = SortAlpha
    | SortByCr


type alias QuickAddUi =
    { sort : QuickAddSort
    , searchText : String
    }


fresh : QuickAddUi
fresh =
    { sort = SortAlpha
    , searchText = ""
    }


toggleSort : QuickAddUi -> QuickAddUi
toggleSort ui =
    case ui.sort of
        SortAlpha ->
            { ui | sort = SortByCr }

        SortByCr ->
            { ui | sort = SortAlpha }


setSearchText : String -> QuickAddUi -> QuickAddUi
setSearchText text ui =
    { ui | searchText = text }
