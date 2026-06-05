module View.Page.QuickList exposing (view)

{-| Standalone read-only "quick list" view of the combat queue.

Lives at `/quick-list` and is opened by the ↗ button in the
encounter title bar. The GM parks it on a second monitor so
they can scan key combat stats (AC, HP, conditions) at a
glance without scrolling the main encounter grid.

Cross-tab updates land via `Ports.incomingEncounter`, decoded
in `Main.encounterFromOtherTab`. This view itself never
mutates state — every chip, badge, and label is display-only.

Card layout, per spec:

  - **Line 1** — name, optional creature note, AC, HP / HP-max,
    conditions / effects, bloodied marker.
  - **Line 2** — only rendered when at least one of the
    following is set: cover, concentrating, hiding, dodging,
    flying (+height), readied, memo, timer. Each appears as a
    small read-only chip.

The active creature gets the same accent class the main view
uses so it's instantly recognisable as "whose turn it is."

-}

import Encounter exposing (Cover(..), Creature, Encounter, Timer)
import Encounter.Xp as Xp
import Html exposing (Html, div, section, span, text)
import Html.Attributes exposing (attribute, class, classList)
import Msg exposing (Msg)
import Ui.Compendium exposing (CompendiumDb(..))
import View.EncounterBar
import View.Tooltips as Tooltips


view : Encounter -> Maybe String -> CompendiumDb -> Html Msg
view enc savedAs db =
    div [ class "workspace workspace--quick-list" ]
        [ section [ class "panel panel--quick-list" ]
            [ div [ class "panel__header panel__header--encounter" ]
                [ -- XpScope / xpFilterOpen values are ignored by the
                  -- bar in QuickListBar mode but the function still
                  -- takes them.  Pass safe defaults.
                  View.EncounterBar.view
                    View.EncounterBar.QuickListBar
                    enc
                    savedAs
                    db
                    Xp.ScopeXpEnemiesAndNpcs
                    False
                ]
            , div [ class "panel__body quick-list__body" ]
                (if List.isEmpty enc.creatures then
                    [ div [ class "quick-list__empty" ]
                        [ text "No creatures in the queue." ]
                    ]

                 else
                    List.map (creatureCard enc.activeName) enc.creatures
                )
            ]
        ]


creatureCard : String -> Creature -> Html Msg
creatureCard activeName creature =
    let
        isActive =
            creature.name == activeName
    in
    div
        [ classList
            [ ( "quick-list-card", True )
            , ( "quick-list-card--active", isActive )
            , ( "quick-list-card--inactive", creature.inactive )
            , ( "quick-list-card--bloodied", creature.bloodied )
            , ( "quick-list-card--down", creature.currentHp == 0 )
            ]
        , attribute "aria-current"
            (if isActive then
                "true"

             else
                "false"
            )
        ]
        [ lineOne creature
        , lineTwo creature
        ]


lineOne : Creature -> Html Msg
lineOne creature =
    div [ class "quick-list-card__line quick-list-card__line--primary" ]
        [ span [ class "quick-list-card__name" ] [ text creature.name ]
        , creatureNoteSpan creature
        , span [ class "quick-list-card__stats" ]
            [ span [ class "quick-list-card__ac" ]
                [ span [ class "quick-list-card__stat-label" ] [ text "AC " ]
                , text (String.fromInt creature.armorClass)
                ]
            , hpDisplay creature
            ]
        , bloodiedChip creature
        , conditionsRow creature
        ]


creatureNoteSpan : Creature -> Html Msg
creatureNoteSpan creature =
    if String.isEmpty creature.note then
        text ""

    else
        span [ class "quick-list-card__note" ]
            [ text ("(" ++ creature.note ++ ")") ]


{-| Mirror of the encounter title bar's HP block: same DOM
shape, same `.hp-display*` class names so the per-theme color
rules (green current / muted "/" / muted max / temp HP accent)
cascade for free, including under the Accessible theme.
-}
hpDisplay : Creature -> Html Msg
hpDisplay creature =
    span [ class "hp-display" ]
        [ span [ class "quick-list-card__stat-label" ] [ text "HP " ]
        , span [ class "hp-display__current" ]
            [ text (String.fromInt creature.currentHp) ]
        , span [ class "hp-display__sep" ] [ text "/" ]
        , span [ class "hp-display__max" ]
            [ text (String.fromInt creature.maxHp) ]
        , if creature.tempHp > 0 then
            span
                [ class "hp-display__temp"
                , Tooltips.attr Tooltips.tempHp
                ]
                [ text ("+" ++ String.fromInt creature.tempHp) ]

          else
            text ""
        ]


bloodiedChip : Creature -> Html Msg
bloodiedChip creature =
    if creature.bloodied then
        span
            [ class "quick-list-card__chip quick-list-card__chip--bloodied"
            , Tooltips.attr Tooltips.bloodied
            ]
            [ text "🩸 Bloodied" ]

    else
        text ""


conditionsRow : Creature -> Html Msg
conditionsRow creature =
    if List.isEmpty creature.conditions then
        text ""

    else
        span [ class "quick-list-card__conditions" ]
            (List.map conditionChip creature.conditions)


conditionChip : Encounter.Condition -> Html Msg
conditionChip cond =
    let
        body =
            if String.isEmpty cond.note then
                cond.name

            else
                cond.name ++ " · " ++ cond.note
    in
    span [ class "quick-list-card__chip quick-list-card__chip--condition" ]
        [ text body ]


{-| Optional second line. Only rendered when at least one
toggle / status is set so a totally idle creature collapses to a
single line.
-}
lineTwo : Creature -> Html Msg
lineTwo creature =
    let
        coverChip =
            case creature.cover of
                NoCover ->
                    Nothing

                HalfCover ->
                    Just "◻ Half cover"

                ThreeQuartersCover ->
                    Just "◭ 3/4 cover"

                FullCover ->
                    Just "⬛ Total cover"

        chip cls maybeLabel =
            case maybeLabel of
                Just label ->
                    [ span [ class ("quick-list-card__chip " ++ cls) ]
                        [ text label ]
                    ]

                Nothing ->
                    []

        boolChip cls predicate label =
            if predicate then
                [ span [ class ("quick-list-card__chip " ++ cls) ]
                    [ text label ]
                ]

            else
                []

        flyingChip =
            if creature.flying then
                let
                    body =
                        if creature.flyHeight > 0 then
                            "⬆ Flying " ++ String.fromInt creature.flyHeight ++ "ft"

                        else
                            "⬆ Flying"
                in
                [ span [ class "quick-list-card__chip quick-list-card__chip--flying" ]
                    [ text body ]
                ]

            else
                []

        memoChip =
            if String.isEmpty creature.memo then
                []

            else
                [ span [ class "quick-list-card__chip quick-list-card__chip--memo" ]
                    [ text ("✎ " ++ creature.memo) ]
                ]

        timerChip =
            case creature.timer of
                Just t ->
                    [ span [ class "quick-list-card__chip quick-list-card__chip--timer" ]
                        [ text
                            ("⏱ "
                                ++ String.fromInt t.remaining
                                ++ (if String.isEmpty t.note then
                                        ""

                                    else
                                        " (" ++ t.note ++ ")"
                                   )
                            )
                        ]
                    ]

                Nothing ->
                    []

        chips =
            chip "quick-list-card__chip--cover" coverChip
                ++ boolChip "quick-list-card__chip--concentrating" creature.concentrating "✨ Concentrating"
                ++ boolChip "quick-list-card__chip--hiding" creature.hiding "👁\u{200D}🗨 Hiding"
                ++ boolChip "quick-list-card__chip--dodging" creature.dodging "🛡 Dodging"
                ++ flyingChip
                ++ boolChip "quick-list-card__chip--readied" creature.readied "✋ Ready"
                ++ memoChip
                ++ timerChip
    in
    if List.isEmpty chips then
        text ""

    else
        div [ class "quick-list-card__line quick-list-card__line--secondary" ]
            chips
