module View.EncounterBar exposing (view)

{-| Encounter title bar — the single line above the creature grid.

Left cluster: encounter info ⓘ + round counter + active creature
name + active HP readout + active AC readout + active state
icons (cover, concentrating, hiding, flying) + active conditions
text.

Right cluster: total XP + lair XP variant + the XP scope filter
dropdown.

This is a glanceable summary, not an interactive control surface
— the only click target is the XP filter dropdown.

-}

import Encounter exposing (Cover(..), Creature, Encounter)
import Html exposing (Html, details, div, li, span, summary, text, ul)
import Html.Attributes exposing (attribute, class, tabindex, title)
import Msg exposing (Msg)


view : Encounter -> Maybe String -> Html Msg
view enc savedAs =
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
            [ span [ class "encounter-bar__xp" ] [ text "93,000 XP" ]
            , span [ class "encounter-bar__xp-lair" ] [ text "(115,200 w/Lair)" ]
            , xpFilter
            ]
        ]


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


xpFilter : Html Msg
xpFilter =
    details [ class "xp-filter" ]
        [ summary
            [ class "xp-filter__summary"
            , attribute "aria-label" "Filter XP total"
            , title "Filter XP total"
            ]
            [ text "▾" ]
        , ul [ class "xp-filter__menu" ]
            [ li
                [ class "xp-filter__item"
                , attribute "aria-selected" "true"
                ]
                [ text "Enemies & NPCs" ]
            , li [ class "xp-filter__item" ] [ text "Enemies Only" ]
            , li [ class "xp-filter__item" ] [ text "NPCs Only" ]
            , li [ class "xp-filter__item" ] [ text "Selected Only" ]
            ]
        ]


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
