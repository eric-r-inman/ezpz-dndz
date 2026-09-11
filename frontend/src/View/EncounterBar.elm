module View.EncounterBar exposing (Mode(..), view)

{-| Encounter title bar — the single line above the creature grid.

Left cluster: encounter info ⓘ + round counter + active creature
name + active HP readout + active AC readout + active state
icons (cover, concentrating, hiding, flying) + active conditions
text.

Right cluster: the ↗ link to the standalone Quick-List page.

`Mode` toggles the right cluster: `FullBar` is the main
encounter page; `QuickListBar` omits it entirely, since the
link would point at the page the reader is already on.

@docs Mode, view

-}

import Encounter exposing (Cover(..), Creature, Encounter)
import Html exposing (Html, a, button, div, span, text)
import Html.Attributes exposing (attribute, class, href, tabindex, target, type_)
import Html.Events exposing (onClick)
import Msg exposing (Msg(..))
import View.Tooltips as Tooltips


type Mode
    = FullBar
    | QuickListBar


view : Mode -> Encounter -> Maybe String -> Html Msg
view mode enc savedAs =
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
                        [ quickListLink ]

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
            , button
                [ class "encounter-bar__round"
                , type_ "button"
                , onClick RoundSetOpen
                , Tooltips.attr Tooltips.roundSet
                , attribute "aria-label" Tooltips.roundSet
                ]
                [ text ("Round " ++ String.fromInt enc.round) ]
            , sectionSep
            , activeNameLink active activeName
            , noteSpan active
            , sectionSep
            , hp active
            , span [ class "encounter-bar__hp-label" ] [ text "HP" ]
            , sectionSep
            , ac active
            , sectionSepBefore (hasStates active)
            , stateIcons active
            , sectionSepBefore (hasConditions active)
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

        -- No `rel="noopener"` here on purpose: the QuickList
        -- tab needs `window.opener` intact so it can call
        -- `window.opener.focus()` to bring the main tab back
        -- to front when the GM clicks a creature row.
        , Tooltips.attr Tooltips.quickListOpen
        , attribute "aria-label" "Open quick-list in new tab"
        ]
        [ text "↗" ]


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
                [ span
                    [ class
                        (if c.bloodied then
                            "hp-display__current hp-display__current--bloodied"

                         else
                            "hp-display__current"
                        )
                    , Tooltips.attr
                        (if c.bloodied then
                            Tooltips.bloodied

                         else
                            ""
                        )
                    ]
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


{-| Active-creature state icons in the encounter title bar.
Renders one icon per actual non-default state (cover, concentrating,
hiding, dodging, flying) — purely indicative, no click handlers.
Renders nothing when there is no icon to show.

Cover reads as ◐ / ◕ / ● so the bar says how much of it there is,
where the Status editor's toggle only says that there is some.

-}
stateIcons : Maybe Creature -> Html Msg
stateIcons active =
    let
        icons =
            case active of
                Just c ->
                    List.filterMap identity
                        [ coverIcon c
                        , stateIconIf c.concentrating "🧠" Tooltips.concentrating
                        , stateIconIf c.hiding "👤" Tooltips.hiding
                        , stateIconIf c.dodging "🤸" Tooltips.dodging
                        , flyingIcon c
                        ]

                Nothing ->
                    []
    in
    -- An empty container would still take a gap on each side of
    -- itself, pushing the sections around it apart.
    if List.isEmpty icons then
        text ""

    else
        div [ class "encounter-bar__states" ] icons


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
                [ text ("🪽; " ++ String.fromInt c.flyHeight) ]
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


{-| Active creature's name, rendered as a scroll-to-card
button when there IS an active creature and a plain "—"
span otherwise. Fires `ScrollCardIntoView` on click; the
handler in `Main` delegates to `Effects.scrollActiveIntoView`
so the workspace panel scrolls the card into view without
touching the encounter model. Lets the GM jump to the
active card from the title bar even when the queue is long
enough to push it out of the viewport.
-}
activeNameLink : Maybe Creature -> String -> Html Msg
activeNameLink active activeName =
    case active of
        Just c ->
            button
                [ class "encounter-bar__active encounter-bar__active--clickable"
                , type_ "button"
                , onClick (ScrollCardIntoView c.name)
                , Tooltips.attr "Scroll to this creature's card"
                , attribute "aria-label" ("Scroll to " ++ c.name)
                ]
                [ text c.name ]

        Nothing ->
            span [ class "encounter-bar__active" ] [ text activeName ]


{-| The gray pipe that divides the bar's readouts. The two that
precede optional sections render only when their section does,
so the row never ends on a dangling divider.
-}
sectionSep : Html Msg
sectionSep =
    span [ class "encounter-bar__sep" ] [ text "|" ]


sectionSepBefore : Bool -> Html Msg
sectionSepBefore present =
    if present then
        sectionSep

    else
        text ""


hasStates : Maybe Creature -> Bool
hasStates active =
    case active of
        Just c ->
            c.cover /= NoCover || c.concentrating || c.hiding || c.dodging || c.flying

        Nothing ->
            False


hasConditions : Maybe Creature -> Bool
hasConditions active =
    case active of
        Just c ->
            not (List.isEmpty c.conditions)

        Nothing ->
            False


{-| Active-creature short-note slot in the title bar, sitting
right of the name in the same parenthesised italics the card
uses. Hidden when the note is empty.
-}
noteSpan : Maybe Creature -> Html Msg
noteSpan active =
    case active of
        Just c ->
            if String.isEmpty (String.trim c.note) then
                text ""

            else
                span [ class "encounter-bar__note" ]
                    [ text ("(" ++ String.trim c.note ++ ")") ]

        Nothing ->
            text ""


{-| Active-creature conditions slot in the title bar: a
comma-separated list rather than chips, since the GM reads this
as a glanceable summary and edits on the card itself. Hidden
when there are no conditions.
-}
conditionsText : Maybe Creature -> Html Msg
conditionsText active =
    case active of
        Just c ->
            if List.isEmpty c.conditions then
                text ""

            else
                span [ class "encounter-bar__conditions" ]
                    [ text (String.join ", " (List.map .name c.conditions)) ]

        Nothing ->
            text ""
