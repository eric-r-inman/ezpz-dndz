module View.EncounterBar exposing (view)

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

-}

import Compendium
import Encounter exposing (Cover(..), Creature, Encounter)
import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (attribute, class, tabindex, title, type_)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as Decode
import Msg exposing (Msg(..), XpScope(..))
import Ui.Compendium exposing (CompendiumDb(..))


view : Encounter -> Maybe String -> CompendiumDb -> XpScope -> Bool -> Html Msg
view enc savedAs db xpScope xpFilterOpen =
    let
        active =
            Encounter.activeCreature enc

        activeName =
            Maybe.map .name active
                |> Maybe.withDefault "—"

        sourceTooltip =
            case savedAs of
                Just name ->
                    "from: " ++ name

                Nothing ->
                    "from: (unsaved)"
    in
    div [ class "encounter-bar" ]
        [ div [ class "encounter-bar__group" ]
            [ span
                [ class "encounter-bar__info"
                , title sourceTooltip
                , attribute "aria-label" sourceTooltip
                , tabindex 0
                ]
                [ text "ⓘ" ]
            , span [ class "encounter-bar__round" ]
                [ text ("Round " ++ String.fromInt enc.round) ]
            , span [ class "encounter-bar__sep" ] [ text "|" ]
            , span [ class "encounter-bar__active" ] [ text activeName ]
            , hp active
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , ac active
            , stateIcons active
            , conditionsText active
            ]
        , div [ class "encounter-bar__group encounter-bar__right" ]
            [ xpReadout enc db xpScope
            , xpFilter xpScope xpFilterOpen
            ]
        ]


{-| Pair of XP totals across the encounter, filtered by `scope`.

  - `total` — sum of every in-scope creature's base `xp`.
  - `lairTotal` — sum of `xpInLair` if non-zero, otherwise `xp`,
    so a mixed party (some with lair XP, some without) sums
    correctly. Equal to `total` when nothing in scope has a
    lair-XP variant; the view uses that equality to decide
    whether to render the secondary `(N w/Lair)` chip.

Resolved through each creature's `creatureId` against the
compendium so the source-of-truth XP comes from the compendium
entry, not duplicated onto the live-encounter creature.

-}
type alias XpTotals =
    { total : Int
    , lairTotal : Int
    }


totalXp : XpScope -> Encounter -> CompendiumDb -> XpTotals
totalXp scope enc db =
    case db of
        CompendiumDbLoaded loaded ->
            enc.creatures
                |> List.filterMap (xpForCreature scope loaded)
                |> List.foldl
                    (\( base, lair ) acc ->
                        { total = acc.total + base
                        , lairTotal = acc.lairTotal + lair
                        }
                    )
                    { total = 0, lairTotal = 0 }

        _ ->
            { total = 0, lairTotal = 0 }


xpForCreature : XpScope -> Compendium.Db -> Creature -> Maybe ( Int, Int )
xpForCreature scope db ec =
    ec.creatureId
        |> Maybe.andThen (\id -> Compendium.find id db)
        |> Maybe.andThen
            (\source ->
                if source.kind == Compendium.Player then
                    Nothing

                else if matchesScope scope source.kind ec then
                    let
                        lair =
                            if source.xpInLair > 0 then
                                source.xpInLair

                            else
                                source.xp
                    in
                    Just ( source.xp, lair )

                else
                    Nothing
            )


matchesScope : XpScope -> Compendium.CreatureKind -> Creature -> Bool
matchesScope scope kind ec =
    case scope of
        ScopeXpEnemiesAndNpcs ->
            kind == Compendium.Enemy || kind == Compendium.Npc

        ScopeXpEnemiesOnly ->
            kind == Compendium.Enemy

        ScopeXpNpcsOnly ->
            kind == Compendium.Npc

        ScopeXpSelectedOnly ->
            ec.selected


xpReadout : Encounter -> CompendiumDb -> XpScope -> Html Msg
xpReadout enc db scope =
    case db of
        CompendiumDbLoaded _ ->
            let
                totals =
                    totalXp scope enc db
            in
            span [ class "encounter-bar__xp-group" ]
                [ span
                    [ class "encounter-bar__xp"
                    , title (xpScopeTooltip scope)
                    ]
                    [ text (formatThousands totals.total ++ " XP") ]
                , if totals.lairTotal > totals.total then
                    span
                        [ class "encounter-bar__xp-lair"
                        , title "Total XP if these creatures are fought in their lair"
                        ]
                        [ text ("(" ++ formatThousands totals.lairTotal ++ " w/Lair)") ]

                  else
                    text ""
                ]

        _ ->
            span
                [ class "encounter-bar__xp"
                , title (xpScopeTooltip scope)
                ]
                [ text "— XP" ]


xpScopeTooltip : XpScope -> String
xpScopeTooltip scope =
    case scope of
        ScopeXpEnemiesAndNpcs ->
            "Total XP for enemies and NPCs"

        ScopeXpEnemiesOnly ->
            "Total XP for enemies only"

        ScopeXpNpcsOnly ->
            "Total XP for NPCs only"

        ScopeXpSelectedOnly ->
            "Total XP for selected creatures only"


{-| Pretty-print an integer with thousand separators, matching
the source-side D&D Beyond convention (e.g. `15,000 XP`).
Negative values keep their sign on the left.
-}
formatThousands : Int -> String
formatThousands n =
    let
        digits =
            String.fromInt (Basics.abs n)

        head =
            modBy 3 (String.length digits)

        firstChunk =
            String.left head digits

        rest =
            String.dropLeft head digits

        chunks =
            chunk3 rest

        joined =
            if String.isEmpty firstChunk then
                String.join "," chunks

            else
                String.join "," (firstChunk :: chunks)
    in
    if n < 0 then
        "-" ++ joined

    else
        joined


chunk3 : String -> List String
chunk3 s =
    if String.isEmpty s then
        []

    else if String.length s <= 3 then
        [ s ]

    else
        String.left 3 s :: chunk3 (String.dropLeft 3 s)


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
                        , title "Temporary hit points"
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
                , title ("Armor Class " ++ String.fromInt c.armorClass)
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
            , attribute "aria-label" "Filter XP total"
            , title "Filter XP total"
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
                    , stateIconIf c.concentrating "🧠" "Concentrating"
                    , stateIconIf c.hiding "👤" "Hiding"
                    , stateIconIf c.dodging "🤸" "Dodging"
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
                , title label
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
            Just (stateIcon "◐" "Half cover")

        ThreeQuartersCover ->
            Just (stateIcon "◕" "Three-quarters cover")

        FullCover ->
            Just (stateIcon "●" "Full cover")


{-| Flying icon includes the height inline so the GM can read
"how high" at a glance without opening the card.
-}
flyingIcon : Creature -> Maybe (Html Msg)
flyingIcon c =
    if c.flying then
        Just
            (span
                [ class "encounter-bar__state"
                , title ("Flying — " ++ String.fromInt c.flyHeight ++ " ft")
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
        , title label
        , attribute "aria-label" label
        ]
        [ text glyph ]


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
