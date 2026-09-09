module View.Panel.Dice exposing (recentBadges, view)

{-| Dice roller panel; the chrome comes from `View.Panel`.
Rendered only while `SurfaceDice` sits in the drawer stack.

Its log carries the HP changes as well as the rolls: the two are
one record of what happened at the table, and a manual HP change
rolls nothing, so the roller is the only place it would show.

-}

import Dice
import Html exposing (Html, button, div, input, label, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, class, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Msg exposing (Msg(..))
import Set exposing (Set)
import Ui.Dice exposing (DiceUi)
import Ui.HpChange exposing (HpChangeEntry)
import Util.Keyboard
import View.HpLog
import View.Inline.Field as Field
import View.LogRow
import View.Panel
import View.Tooltips as Tooltips


{-| What the log needs from the model beyond the roller's own
state.
-}
type alias Log =
    { hpChangeLog : List HpChangeEntry
    , expanded : Set String
    , flashedRollSeq : Int
    }


{-| The most recent roll totals, rendered beside the rail's 🎲
icon so a roll reads without opening the panel. The newest is
emphasized in yellow; older advantage and disadvantage rolls keep
their green and red. While a triple-roll is the newest thing
rolled (`override`, set by `Update.Dice.tripleRollLanded`), its
three results — the newest three entries — are coloured by roll
mode instead, standard in plain text, so they read as the set the
popups showed; the next single roll clears that.

Keyed by each roll's ordinal rather than its list position: a
landing roll gets a fresh key and mounts (playing its flash),
while an older one that merely shifted down a slot keeps its
existing node and does not replay.

-}
recentBadges : Dice.History -> Maybe (List Dice.Roll) -> Html Msg
recentBadges rollHistory override =
    let
        tripleSize =
            override
                |> Maybe.map List.length
                |> Maybe.withDefault 0
    in
    Html.Keyed.node "span"
        [ class "recent-rolls" ]
        (Dice.historyEntries rollHistory
            |> List.take recentBadgeCount
            |> List.indexedMap (recentBadge rollHistory.pushed tripleSize)
        )


recentBadgeCount : Int
recentBadgeCount =
    4


recentBadge : Int -> Int -> Int -> Dice.Roll -> ( String, Html Msg )
recentBadge pushed tripleSize i roll =
    ( "roll-badge-" ++ String.fromInt (pushed - i)
    , span [ class (recentBadgeClass tripleSize i roll.kind) ]
        [ text (String.fromInt roll.total) ]
    )


recentBadgeClass : Int -> Int -> Dice.RollKind -> String
recentBadgeClass tripleSize i kind =
    if i < tripleSize then
        "recent-roll " ++ tripleBadgeClass kind

    else if i == 0 then
        "recent-roll recent-roll--latest"

    else
        case kind of
            Dice.Advantage ->
                "recent-roll recent-roll--advantage"

            Dice.Disadvantage ->
                "recent-roll recent-roll--disadvantage"

            _ ->
                "recent-roll"


tripleBadgeClass : Dice.RollKind -> String
tripleBadgeClass kind =
    case kind of
        Dice.Advantage ->
            "recent-roll--advantage"

        Dice.Disadvantage ->
            "recent-roll--disadvantage"

        _ ->
            "recent-roll--standard"


view : View.Panel.Header -> Log -> DiceUi -> Html Msg
view header log ui =
    View.Panel.view
        { close = Nothing
        , title = "Dice Roller"
        , titleTrail = View.Panel.titleMarkIf ui.unread
        , subtitle = Nothing
        , header = header
        , extraClass = "panel-drawer--dice"
        , body =
            [ form ui
            , faceButtons
            , specialButtons
            , history log ui
            ]
        }


form : DiceUi -> Html Msg
form ui =
    div [ class "dice-form" ]
        [ div [ class "cond-row" ]
            [ label [ for "dice-input", class "cond-label" ] [ text "Expression:" ]
            , input
                [ id "dice-input"
                , class "cond-input cond-input--grow"
                , type_ "text"
                , placeholder "e.g. 2d6+3"
                , value ui.input
                , onInput DiceInputChanged
                , Html.Events.on "keydown" (Util.Keyboard.enterKey DiceRollFromInput)
                ]
                []
            , button
                [ class "action-btn action-btn--green"
                , onClick DiceRollFromInput
                ]
                [ text "Roll" ]
            ]
        , case ui.inputError of
            Just (Dice.ParseError raw) ->
                div [ class "cond-section__caption cond-section__caption--danger" ]
                    [ text ("Couldn't parse: " ++ raw) ]

            Nothing ->
                text ""
        , div [ class "cond-divider" ] []

        -- Two characters cover every count and modifier the game
        -- asks for; text inputs because a number input ignores
        -- `maxlength`.
        , div [ class "cond-row" ]
            [ label
                [ for "dice-count", class "cond-label" ]
                [ text "Count:" ]
            , span [ class "cond-spin-wrap" ]
                [ input
                    [ id "dice-count"
                    , class "cond-input cond-input--2ch"
                    , type_ "text"
                    , Attr.maxlength 2
                    , attribute "inputmode" "numeric"
                    , value (String.fromInt ui.count)
                    , onInput DiceCountChanged
                    ]
                    []
                , Field.spin
                    { up = DiceCountAdjust 1
                    , down = DiceCountAdjust -1
                    , what = "count"
                    }
                ]
            , label
                [ for "dice-modifier"
                , class "cond-label"
                ]
                [ text "Modifier:" ]
            , span [ class "cond-spin-wrap" ]
                [ input
                    [ id "dice-modifier"
                    , class "cond-input cond-input--2ch"
                    , type_ "text"
                    , Attr.maxlength 2
                    , attribute "inputmode" "numeric"
                    , value ui.modifierText
                    , onInput DiceModifierChanged
                    ]
                    []
                , Field.spin
                    { up = DiceModifierAdjust 1
                    , down = DiceModifierAdjust -1
                    , what = "modifier"
                    }
                ]
            , button
                [ class "dice-form__reset"
                , onClick DiceResetSliders
                , Tooltips.attr Tooltips.diceReset
                , attribute "aria-label" "Reset count and modifier"
                ]
                [ text "❌" ]
            ]
        ]


faceButtons : Html Msg
faceButtons =
    div [ class "die-btn-grid" ]
        [ faceButton 4 "die-btn--d4"
        , faceButton 6 "die-btn--d6"
        , faceButton 8 "die-btn--d8"
        , faceButton 10 "die-btn--d10"
        , faceButton 12 "die-btn--d12"
        , faceButton 20 "die-btn--d20"
        , faceButton 100 "die-btn--d100"
        , button
            [ class "die-btn die-btn--coin"
            , onClick DiceFlipCoin
            , Tooltips.attr Tooltips.diceCoinFlip
            , attribute "aria-label" "Flip a coin"
            ]
            [ text "🪙" ]
        ]


faceButton : Int -> String -> Html Msg
faceButton faces colorClass =
    button
        [ class ("die-btn " ++ colorClass)
        , onClick (DiceRollFaces faces)
        , Tooltips.attr (Tooltips.diceFaceRoll faces)
        ]
        [ text ("d" ++ String.fromInt faces) ]


specialButtons : Html Msg
specialButtons =
    div [ class "dice-special-row" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick DiceRollAdvantage
            , Tooltips.attr Tooltips.diceAdvantage
            ]
            [ text "Advantage (d20)" ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick DiceRollDisadvantage
            , Tooltips.attr Tooltips.diceDisadvantage
            ]
            [ text "Disadvantage (d20)" ]
        ]


{-| Rolls and HP changes read as one record of what happened, so
they share a list. Neither carries a clock the other can be
compared against, so the order comes from the roll count each HP
entry was stamped with: an entry logged after the nth roll sorts
between the nth and the (n+1)th, and ahead of the nth on the tie,
because the roll that produced it came first. Manual changes
between two rolls all carry the same stamp, and hold the order
they arrive in — the sort is stable and the log is newest-first.
-}
history : Log -> DiceUi -> Html Msg
history log ui =
    let
        rolls =
            Dice.historyEntries ui.history

        rollRows =
            List.indexedMap
                (\i roll ->
                    let
                        ordinal =
                            ui.history.pushed - i

                        key =
                            "roll-" ++ String.fromInt ordinal
                    in
                    ( ( ordinal, 0 )
                    , ( "r" ++ String.fromInt ordinal
                      , historyEntry ui
                            i
                            { key = key
                            , flash = ordinal > log.flashedRollSeq
                            , expanded = Set.member key log.expanded
                            }
                            roll
                      )
                    )
                )
                rolls

        -- Only the changes a roll produced belong beside the rolls;
        -- a typed number is the Manage HP editor's own record.
        -- Undo always reverts the newest change of any kind, so
        -- only that one offers it here.
        newestSeq =
            List.head log.hpChangeLog |> Maybe.map .seq

        hpRows =
            List.map
                (\e ->
                    ( ( e.rollsBefore, 1 )
                    , ( "h" ++ String.fromInt e.seq
                      , View.HpLog.entry
                            { undoable = Just e.seq == newestSeq
                            , flash = False
                            , expanded = Set.member (View.HpLog.rowKey e) log.expanded
                            }
                            e
                      )
                    )
                )
                (List.filter .rolled log.hpChangeLog)

        entries =
            List.sortBy (\( ( ordinal, tie ), _ ) -> ( -ordinal, -tie ))
                (rollRows ++ hpRows)
    in
    div [ class "dice-history" ]
        (div [ class "log-head" ]
            [ button
                [ class "log-fold"
                , type_ "button"
                , onClick DiceHistoryToggle
                , Tooltips.attr Tooltips.logToggle
                , attribute "aria-expanded"
                    (if ui.historyOpen then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ class "log-fold__caret" ]
                    [ text
                        (if ui.historyOpen then
                            "▼"

                         else
                            "▶"
                        )
                    ]
                , span [ class "log-fold__title" ]
                    [ text ("Log (" ++ String.fromInt (List.length entries) ++ ")") ]
                ]
            , if List.isEmpty entries then
                text ""

              else
                button
                    [ class "dice-history__rerun"
                    , onClick DiceClearHistory
                    , Tooltips.attr Tooltips.diceClearHistory
                    ]
                    [ text "Clear" ]
            ]
            :: (if not ui.historyOpen then
                    []

                else if List.isEmpty entries then
                    [ div [ class "log-empty" ]
                        [ text "No rolls yet." ]
                    ]

                else
                    -- Keyed so a landing roll mounts a fresh row and
                    -- its flash runs, rather than patching the row
                    -- that held the previous newest.
                    [ Html.Keyed.ul [ class "log-list" ]
                        (List.map Tuple.second entries)
                    ]
               )
        )


{-| One roll row. `key` is its identity for the fold; `flash`
marks a roll that landed while the panel was showing.

Folded, the source chip sits inline with the formula so the
whole thing ellipses as one line. Unfolded, the source chip
moves up beside the caret instead — it is the row's headline —
and everything else flows on the row beneath, wrapping as a long
formula or a long creature name needs.

-}
historyEntry : DiceUi -> Int -> { key : String, flash : Bool, expanded : Bool } -> Dice.Roll -> Html Msg
historyEntry ui idx opts roll =
    let
        isMenuOpen =
            ui.rerunMenuOpenFor == Just idx

        rowClass =
            String.join " "
                (List.filterMap identity
                    [ Just "dice-history__entry"
                    , if opts.flash then
                        Just "dice-history__entry--flash"

                      else
                        Nothing
                    , if opts.expanded then
                        Just "dice-history__entry--open"

                      else
                        Nothing
                    ]
                )

        -- The colon rides on the formula text: as its own flex
        -- item the faces span would sit a gap away from it.
        rolledAndType =
            [ span [ class "dice-history__rolled" ]
                [ text (rolledString roll) ]
            , case roll.expression.damageType of
                Just damage ->
                    span [ class "dice-history__damage-type" ] [ text (" " ++ String.toLower damage) ]

                Nothing ->
                    text ""
            , text " = "
            ]
    in
    if opts.expanded then
        li [ class rowClass ]
            [ div [ class "dice-history__entry-top" ]
                [ View.LogRow.foldToggle opts.key opts.expanded
                , rollSource roll.source
                ]
            , div [ class "dice-history__entry-detail" ]
                (text (tightFormula roll ++ ":")
                    :: rolledAndType
                    ++ [ div [ class "dice-history__total" ] [ text (String.fromInt roll.total) ]
                       , rerunControl idx isMenuOpen roll
                       ]
                )
            ]

    else
        li [ class rowClass ]
            [ View.LogRow.foldToggle opts.key opts.expanded
            , div [ class "dice-history__formula" ]
                (rollSource roll.source :: text (tightFormula roll ++ ":") :: rolledAndType)
            , div [ class "dice-history__total" ] [ text (String.fromInt roll.total) ]
            , rerunControl idx isMenuOpen roll
            ]


{-| Re-roll trigger + dropdown for one history entry. The
trigger button toggles the menu; the menu has two items:
"Reroll" (existing behaviour, fires `DiceRerun`) and
"Reroll, no modifier" (strips the expression's flat constant
before rolling, fires `DiceRerunNoModifier`).
-}
rerunControl : Int -> Bool -> Dice.Roll -> Html Msg
rerunControl idx isOpen roll =
    div
        [ class
            (if isOpen then
                "dice-history__rerun-wrap dice-history__rerun-wrap--open"

             else
                "dice-history__rerun-wrap"
            )
        ]
        [ button
            [ class "dice-history__rerun"
            , onClick (DiceRerunMenuToggle idx)
            , Tooltips.attr Tooltips.diceRollAgain
            , attribute "aria-haspopup" "menu"
            , attribute "aria-expanded"
                (if isOpen then
                    "true"

                 else
                    "false"
                )
            ]
            [ text "↻" ]
        , if isOpen then
            div
                [ class "dice-history__rerun-menu"
                , attribute "role" "menu"
                ]
                [ button
                    [ class "dice-history__rerun-menu-item"
                    , type_ "button"
                    , onClick (DiceRerun roll)
                    , attribute "role" "menuitem"
                    ]
                    [ text "Reroll" ]
                , button
                    [ class "dice-history__rerun-menu-item"
                    , type_ "button"
                    , onClick (DiceRerunNoModifier roll)
                    , attribute "role" "menuitem"
                    ]
                    [ text "Reroll, no modifier" ]
                ]

          else
            text ""
        ]


{-| Render the source chip on a history entry: "Damage → Brakka,
Ogre Brute" / "Stat block → Goblin Boss" / etc. Hides the chip
for the default `Manual` source since the dice panel's own buttons
already make the context obvious.
-}
rollSource : Dice.Source -> Html Msg
rollSource source =
    if source.feature == "Manual" then
        text ""

    else
        let
            label_ =
                case source.target of
                    Just t ->
                        source.feature ++ " → " ++ t

                    Nothing ->
                        source.feature
        in
        span [ class "dice-history__source", Tooltips.attr label_ ]
            [ text label_ ]


{-| The formula as typed, minus the damage type its tail carries,
so the type can be shown once — after the faces, where it reads
as what the total is. `Dice.Roll.formula` keeps the type because
it is the wire form and the reroll label; only the row drops it.
-}
formulaWithoutType : Dice.Roll -> String
formulaWithoutType roll =
    case roll.expression.damageType of
        Just damage ->
            let
                suffix =
                    " " ++ damage
            in
            if String.endsWith suffix roll.formula then
                String.dropRight (String.length suffix) roll.formula

            else
                roll.formula

        Nothing ->
            roll.formula


{-| The formula minus its damage type, with every "+"/"-" operator
tightened (no surrounding spaces) for the log's compact one-line
display: "2d8+8" rather than "2d8 + 8".
-}
tightFormula : Dice.Roll -> String
tightFormula roll =
    formulaWithoutType roll
        |> String.replace " + " "+"
        |> String.replace " - " "-"


{-| Format the individual face values for a Roll, with kept faces
inline and dropped (advantage/disadvantage loser) ones bracketed,
parenthesized: "(14,3)" or "(17,[8])" etc.
-}
rolledString : Dice.Roll -> String
rolledString roll =
    let
        faces =
            roll.groups
                |> List.concatMap .rolled
                |> List.map
                    (\d ->
                        if d.kept then
                            String.fromInt d.face

                        else
                            "[" ++ String.fromInt d.face ++ "]"
                    )
                |> String.join ","

        modifierText =
            if roll.expression.constant > 0 then
                "+" ++ String.fromInt roll.expression.constant

            else if roll.expression.constant < 0 then
                "−" ++ String.fromInt (abs roll.expression.constant)

            else
                ""
    in
    "(" ++ faces ++ ")" ++ modifierText
