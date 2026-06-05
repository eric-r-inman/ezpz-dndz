module View.EncounterBar exposing (Mode(..), view)

{-| Encounter title bar — the single line above the creature grid.

Left cluster: encounter info ⓘ + round counter + active creature
name + active HP readout + active AC readout + active state
icons (cover, concentrating, hiding, flying) + active conditions
text.

Right cluster: total XP for the encounter, summed via the
compendium creatureId lookup and filtered by the GM's chosen
scope (Enemies & NPCs / Enemies Only / NPCs Only / Selected Only).
The scope dropdown is the sole click target here; everything
else is a glanceable summary.

`Mode` toggles the right cluster: `FullBar` is the main
encounter page; `QuickListBar` omits the XP readout, Difficulty
button, and the Quick-List ↗ link — the standalone Quick-List
tab is read-only and shouldn't navigate back into the busy
workspace surfaces.

@docs Mode, view

-}

import Encounter exposing (Cover(..), Creature, Encounter)
import Encounter.Xp as Xp exposing (XpScope(..))
import Html exposing (Html, a, button, div, li, span, text, ul)
import Html.Attributes exposing (attribute, class, href, tabindex, target, title, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (Msg(..))
import Ui.Compendium exposing (CompendiumDb(..))
import View.Tooltips as Tooltips


type Mode
    = FullBar
    | QuickListBar


view : Mode -> Encounter -> Maybe String -> CompendiumDb -> XpScope -> Bool -> Html Msg
view mode enc savedAs db xpScope xpFilterOpen =
    let
        active =
            Encounter.activeCreature enc

        activeName =
            Maybe.map .name active
                |> Maybe.withDefault "—"

        sourceTooltip =
            case savedAs of
                Just name ->
                    Tooltips.sourceFromSaved name

                Nothing ->
                    Tooltips.sourceUnsaved

        rightCluster =
            case mode of
                FullBar ->
                    div [ class "encounter-bar__group encounter-bar__right" ]
                        [ xpReadout enc db xpScope
                        , xpFilter xpScope xpFilterOpen
                        , button
                            [ class "encounter-bar__difficulty"
                            , type_ "button"
                            , onClick CrCalculatorOpen
                            , Tooltips.attr Tooltips.encounterBarDifficulty
                            , attribute "aria-label" Tooltips.encounterBarDifficulty
                            ]
                            [ text "Difficulty" ]
                        , quickListLink
                        ]

                QuickListBar ->
                    text ""
    in
    div [ class "encounter-bar" ]
        [ div [ class "encounter-bar__group" ]
            [ span
                [ class "encounter-bar__info"
                , Tooltips.attr sourceTooltip
                , attribute "aria-label" sourceTooltip
                , tabindex 0
                ]
                [ text "ⓘ" ]
            , span [ class "encounter-bar__round" ]
                [ text ("Round " ++ String.fromInt enc.round) ]
            , span [ class "encounter-bar__sep" ] [ text "|" ]
            , span [ class "encounter-bar__active" ] [ text activeName ]
            , bloodiedMarker active
            , hp active
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , ac active
            , noteSpan active
            , stateIcons active
            , conditionsText active
            ]
        , rightCluster
        ]


{-| ↗ link to the standalone Quick-List page. Same shape and
target as the compendium's "open stat block in new tab" link
so the affordance is recognisable across surfaces.
-}
quickListLink : Html Msg
quickListLink =
    a
        [ class "encounter-bar__quick-list"
        , href "/quick-list"
        , target "_blank"
        , attribute "rel" "noopener"
        , Tooltips.attr Tooltips.quickListOpen
        , attribute "aria-label" "Open quick-list in new tab"
        ]
        [ text "↗ Quick-List" ]


xpReadout : Encounter -> CompendiumDb -> XpScope -> Html Msg
xpReadout enc db scope =
    case db of
        CompendiumDbLoaded loaded ->
            let
                totals =
                    Xp.totalsFor scope enc loaded
            in
            span [ class "encounter-bar__xp-group" ]
                [ span
                    [ class "encounter-bar__xp"
                    , Tooltips.attr (xpScopeTooltip scope)
                    ]
                    [ text (Xp.formatThousands totals.total ++ " XP") ]
                , if totals.lairTotal > totals.total then
                    span
                        [ class "encounter-bar__xp-lair"
                        , Tooltips.attr Tooltips.xpLairTotal
                        ]
                        [ text ("(" ++ Xp.formatThousands totals.lairTotal ++ " w/Lair)") ]

                  else
                    text ""
                ]

        _ ->
            span
                [ class "encounter-bar__xp"
                , Tooltips.attr (xpScopeTooltip scope)
                ]
                [ text "— XP" ]


xpScopeTooltip : XpScope -> String
xpScopeTooltip scope =
    case scope of
        ScopeXpEnemiesAndNpcs ->
            Tooltips.xpScopeEnemiesAndNpcs

        ScopeXpEnemiesOnly ->
            Tooltips.xpScopeEnemiesOnly

        ScopeXpNpcsOnly ->
            Tooltips.xpScopeNpcsOnly

        ScopeXpSelectedOnly ->
            Tooltips.xpScopeSelectedOnly


{-| HP readout for the encounter title bar. Reuses the same
.hp-display\* classes the card row 2 uses so the green/muted/blue
colors line up exactly. Renders an em-dash when no creature is
active (empty queue or activeName drift).
-}
hp : Maybe Creature -> Html Msg
hp active =
    case active of
        Just c ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__current" ]
                    [ text (String.fromInt c.currentHp) ]
                , span [ class "hp-display__sep" ] [ text "/" ]
                , span [ class "hp-display__max" ]
                    [ text (String.fromInt c.maxHp) ]
                , if c.tempHp > 0 then
                    span
                        [ class "hp-display__temp"
                        , Tooltips.attr Tooltips.tempHp
                        ]
                        [ text ("+" ++ String.fromInt c.tempHp) ]

                  else
                    text ""
                ]

        Nothing ->
            span [ class "hp-display" ]
                [ span [ class "hp-display__max" ] [ text "—" ] ]


{-| Active-creature AC readout for the title bar. Mirrors the HP
cluster's "27/59 HP" shape — value on the left, "AC" label on
the right — so the two readouts scan as a pair. Hidden when no
creature is active.
-}
ac : Maybe Creature -> Html Msg
ac active =
    case active of
        Just c ->
            span
                [ class "encounter-bar__ac"
                , Tooltips.attr (Tooltips.armorClass c.armorClass)
                ]
                [ span [ class "encounter-bar__ac-value" ]
                    [ text (String.fromInt c.armorClass) ]
                , span [ class "encounter-bar__ac-label" ] [ text "AC" ]
                ]

        Nothing ->
            text ""


{-| Hand-rolled controlled dropdown. Replaced the native
`<details>/<summary>` pair so we can drive the open state from
the model — the global Esc / click-outside subscriptions in
`Main.subscriptions` need a single source of truth to close
against.

`stopPropagationOn "mousedown"` on the wrapper keeps the global
mousedown subscription from immediately closing the dropdown
when the user clicks the toggle button.

-}
xpFilter : XpScope -> Bool -> Html Msg
xpFilter current isOpen =
    let
        wrapperClass =
            if isOpen then
                "xp-filter xp-filter--open"

            else
                "xp-filter"
    in
    div
        [ class wrapperClass
        , stopPropagationOn "mousedown" (Decode.succeed ( NoOp, True ))
        ]
        [ button
            [ class "xp-filter__summary"
            , type_ "button"
            , attribute "aria-haspopup" "listbox"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            , attribute "aria-label" Tooltips.xpFilter
            , Tooltips.attr Tooltips.xpFilter
            , onClick XpFilterToggle
            ]
            [ text "▾" ]
        , if isOpen then
            ul
                [ class "xp-filter__menu"
                , attribute "role" "listbox"
                ]
                [ xpFilterItem current ScopeXpEnemiesAndNpcs "Enemies & NPCs"
                , xpFilterItem current ScopeXpEnemiesOnly "Enemies Only"
                , xpFilterItem current ScopeXpNpcsOnly "NPCs Only"
                , xpFilterItem current ScopeXpSelectedOnly "Selected Only"
                ]

          else
            text ""
        ]


xpFilterItem : XpScope -> XpScope -> String -> Html Msg
xpFilterItem current scope label =
    li
        [ class "xp-filter__item"
        , attribute "role" "option"
        , attribute "aria-selected"
            (if current == scope then
                "true"

             else
                "false"
            )
        , onClick (XpScopeSet scope)
        ]
        [ text label ]


{-| Active-creature state icons in the encounter title bar.
Renders one icon per actual non-default state (cover, concentrating,
hiding, dodging, flying) — purely indicative, no click handlers.
Hidden when nothing is active.

Cover uses the same ◐ / ◕ / ● glyph vocabulary as the card row 2
toggle so the title bar reads consistently with the card.

-}
stateIcons : Maybe Creature -> Html Msg
stateIcons active =
    case active of
        Just c ->
            div [ class "encounter-bar__states" ]
                (List.filterMap identity
                    [ coverIcon c
                    , stateIconIf c.concentrating "🧠" Tooltips.concentrating
                    , stateIconIf c.hiding "👤" Tooltips.hiding
                    , stateIconIf c.dodging "🤸" Tooltips.dodging
                    , flyingIcon c
                    ]
                )

        Nothing ->
            text ""


{-| Single state icon, shown only when `on` is True. Tooltip
labels it for accessibility. Returned as `Maybe (Html msg)` so
the caller can `filterMap identity` and skip the false ones.
-}
stateIconIf : Bool -> String -> String -> Maybe (Html Msg)
stateIconIf on glyph label =
    if on then
        Just
            (span
                [ class "encounter-bar__state"
                , Tooltips.attr label
                , attribute "aria-label" label
                ]
                [ text glyph ]
            )

    else
        Nothing


coverIcon : Creature -> Maybe (Html Msg)
coverIcon c =
    case c.cover of
        NoCover ->
            Nothing

        HalfCover ->
            Just (stateIcon "◐" Tooltips.halfCover)

        ThreeQuartersCover ->
            Just (stateIcon "◕" Tooltips.threeQuartersCover)

        FullCover ->
            Just (stateIcon "●" Tooltips.fullCover)


{-| Flying icon includes the height inline so the GM can read
"how high" at a glance without opening the card.
-}
flyingIcon : Creature -> Maybe (Html Msg)
flyingIcon c =
    if c.flying then
        Just
            (span
                [ class "encounter-bar__state"
                , Tooltips.attr (Tooltips.flying c.flyHeight)
                , attribute "aria-label" "Flying"
                ]
                [ text ("🪽 " ++ String.fromInt c.flyHeight) ]
            )

    else
        Nothing


stateIcon : String -> String -> Html Msg
stateIcon glyph label =
    span
        [ class "encounter-bar__state"
        , Tooltips.attr label
        , attribute "aria-label" label
        ]
        [ text glyph ]


{-| Bloodied drop next to the active creature's name. Mirrors
the row-2 `.bloodied` marker on the card so the GM can see the
"below half HP" signal in the title bar without finding the
card in the queue. Hidden when nothing is active, or when the
active creature isn't bloodied.
-}
bloodiedMarker : Maybe Creature -> Html Msg
bloodiedMarker active =
    case active of
        Just c ->
            if c.bloodied then
                span
                    [ class "encounter-bar__bloodied"
                    , Tooltips.attr Tooltips.bloodied
                    , attribute "aria-label" "Bloodied"
                    ]
                    [ text "🩸" ]

            else
                text ""

        Nothing ->
            text ""


{-| Active-creature short-note slot in the title bar. Mirrors
the inline note on the card's top row, surfaced here so the GM
can read it without finding the card in the queue. Prefixed
with a flashing red `!` (text, not icon) because the title bar
already implies "active creature" — the marker emphasises that
the note belongs to whoever's acting right now. Hidden when
the note is empty.
-}
noteSpan : Maybe Creature -> Html Msg
noteSpan active =
    case active of
        Just c ->
            if String.isEmpty (String.trim c.note) then
                text ""

            else
                span [ class "encounter-bar__note" ]
                    [ span [ class "encounter-bar__note-bang" ] [ text "!" ]
                    , text c.note
                    ]

        Nothing ->
            text ""


{-| Active-creature conditions slot in the title bar. Plain
purple text separated by " | ", not chips — the GM uses this as
a glanceable summary; the editable chips are on the card itself.
Hidden when there are no conditions.
-}
conditionsText : Maybe Creature -> Html Msg
conditionsText active =
    case active of
        Just c ->
            if List.isEmpty c.conditions then
                text ""

            else
                span [ class "encounter-bar__conditions" ]
                    (List.intersperse
                        (span [ class "encounter-bar__cond-sep" ] [ text "|" ])
                        (List.map
                            (\cond ->
                                span [ class "encounter-bar__cond" ]
                                    [ text cond.name ]
                            )
                            c.conditions
                        )
                    )

        Nothing ->
            text ""
