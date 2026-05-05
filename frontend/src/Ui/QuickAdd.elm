module Ui.QuickAdd exposing (QuickAddSort(..), QuickAddUi, fresh, toggleSort)

{-| Quick Add modal state — a one-click "drop a creature into the
encounter" picker that lists every compendium creature with its
challenge rating and exposes a single sort toggle.

The modal intentionally has no search box, no kind filter, and no
add-count: it's the lightweight sister to the full Compendium
browser, optimised for the common case of "I want to add one
goblin right now."

@docs QuickAddSort, QuickAddUi, fresh, toggleSort

-}


{-| Which key the list is sorted by. Initial value is
`SortAlpha`; the toggle button flips between the two.
-}
type QuickAddSort
    = SortAlpha
    | SortByCr


type alias QuickAddUi =
    { sort : QuickAddSort
    }


fresh : QuickAddUi
fresh =
    { sort = SortAlpha }


toggleSort : QuickAddUi -> QuickAddUi
toggleSort ui =
    case ui.sort of
        SortAlpha ->
            { ui | sort = SortByCr }

        SortByCr ->
            { ui | sort = SortAlpha }
