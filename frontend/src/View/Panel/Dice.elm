module View.Panel.Dice exposing (view)

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
        [ div [ class "dice-form__row" ]
            [ label [ for "dice-input" ] [ text "Expression" ]
            , input
                [ id "dice-input"
                , class "dice-form__input"
                , type_ "text"
                , placeholder "e.g. 2d6+3 fire damage"
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
                div [ class "dice-form__error" ]
                    [ text ("Couldn't parse: " ++ raw) ]

            Nothing ->
                text ""
        , div [ class "dice-form__pair-row" ]
            [ label
                [ for "dice-count", class "dice-form__pair-label" ]
                [ text "Count" ]
            , input
                [ id "dice-count"
                , class "dice-form__input dice-form__numeric"
                , type_ "number"
                , Attr.min "1"
                , Attr.max "99"
                , value (String.fromInt ui.count)
                , onInput DiceCountChanged
                ]
                []
            , label
                [ for "dice-modifier"
                , class "dice-form__pair-label dice-form__pair-label--split"
                ]
                [ text "Modifier" ]
            , input
                [ id "dice-modifier"
                , class "dice-form__input dice-form__numeric"
                , type_ "number"
                , Attr.min "-999"
                , Attr.max "999"
                , value ui.modifierText
                , onInput DiceModifierChanged
                ]
                []
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

        hpRows =
            List.indexedMap
                (\i e ->
                    ( ( e.rollsBefore, 1 )
                    , ( "h" ++ String.fromInt e.seq
                      , View.HpLog.entry
                            { undoable = i == 0
                            , flash = False
                            , expanded = Set.member (View.HpLog.rowKey e) log.expanded
                            }
                            e
                      )
                    )
                )
                log.hpChangeLog

        entries =
            List.sortBy (\( ( ordinal, tie ), _ ) -> ( -ordinal, -tie ))
                (rollRows ++ hpRows)
    in
    div [ class "dice-history" ]
        (div [ class "dice-history__head" ]
            [ button
                [ class "dice-history__fold"
                , type_ "button"
                , onClick DiceHistoryToggle
                , Tooltips.attr Tooltips.diceHistoryToggle
                , attribute "aria-expanded"
                    (if ui.historyOpen then
                        "true"

                     else
                        "false"
                    )
                ]
                [ span [ class "dice-history__caret" ]
                    [ text
                        (if ui.historyOpen then
                            "▼"

                         else
                            "▶"
                        )
                    ]
                , span [ class "dice-history__title" ]
                    [ text ("Rolls and HP changes (" ++ String.fromInt (List.length entries) ++ ")") ]
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
                    [ div [ class "dice-history__empty" ]
                        [ text "Nothing yet. Click a die above or type an expression." ]
                    ]

                else
                    -- Keyed so a landing roll mounts a fresh row and
                    -- its flash runs, rather than patching the row
                    -- that held the previous newest.
                    [ Html.Keyed.ul [ class "dice-history__list" ]
                        (List.map Tuple.second entries)
                    ]
               )
        )


{-| One roll row. `key` is its identity for the fold; `flash`
marks a roll that landed while the panel was showing.
-}
historyEntry : DiceUi -> Int -> { key : String, flash : Bool, expanded : Bool } -> Dice.Roll -> Html Msg
historyEntry ui idx opts roll =
    let
        isMenuOpen =
            ui.rerunMenuOpenFor == Just idx

        rowClass =
            if opts.flash then
                "dice-history__entry dice-history__entry--flash"

            else
                "dice-history__entry"
    in
    li [ class rowClass ]
        [ View.LogRow.foldToggle opts.key opts.expanded
        , div [ class (View.LogRow.openable "dice-history__formula" opts.expanded) ]
            [ rollSource roll.source
            , text roll.formula
            , span [ class "dice-history__rolled" ]
                [ text (" — " ++ rolledString roll) ]
            , case roll.expression.damageType of
                Just damage ->
                    span [ class "dice-history__damage" ] [ text damage ]

                Nothing ->
                    text ""
            ]
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


{-| Format the individual face values for a Roll, with kept faces
inline and dropped (advantage/disadvantage loser) ones bracketed.
"rolled: 14, +3" or "rolled: 17 [8]" etc.
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
                |> String.join ", "

        modifierText =
            if roll.expression.constant > 0 then
                " + " ++ String.fromInt roll.expression.constant

            else if roll.expression.constant < 0 then
                " − " ++ String.fromInt (abs roll.expression.constant)

            else
                ""
    in
    "rolled: " ++ faces ++ modifierText
