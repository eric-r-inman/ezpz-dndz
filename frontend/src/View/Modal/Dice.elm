module View.Modal.Dice exposing (view)

{-| Dice roller modal. Renders nothing while closed, the full
overlay while open. Modal chrome (backdrop, header, ✕ button,
click-out / Esc to close) is delegated to `View.Modal.view`.
-}

import Dice
import Html exposing (Html, button, div, input, label, li, span, text, ul)
import Html.Attributes as Attr exposing (attribute, class, for, id, placeholder, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Msg exposing (Msg(..))
import Ui.Dice exposing (DiceUi)
import Util.Keyboard
import View.Modal


view : DiceUi -> Html Msg
view ui =
    if ui.open then
        View.Modal.view
            { close = CloseDice
            , noOp = NoOp
            , title = "🎲 Dice Roller"
            , extraClass = "modal--dice"
            , body =
                [ form ui
                , faceButtons
                , specialButtons
                , history ui.history
                ]
            }

    else
        text ""


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
        , div [ class "dice-form__row" ]
            [ label [ for "dice-count" ] [ text "Count" ]
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
            , label [ for "dice-modifier", class "dice-form__row-spacer" ] [ text "Modifier" ]
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
                , title "Reset count to 1 and modifier to 0"
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
        ]


faceButton : Int -> String -> Html Msg
faceButton faces colorClass =
    button
        [ class ("die-btn " ++ colorClass)
        , onClick (DiceRollFaces faces)
        , title ("Roll d" ++ String.fromInt faces)
        ]
        [ text ("d" ++ String.fromInt faces) ]


specialButtons : Html Msg
specialButtons =
    div [ class "dice-special-row" ]
        [ button
            [ class "action-btn action-btn--green"
            , onClick DiceRollAdvantage
            , title "Roll 2d20, keep highest"
            ]
            [ text "Advantage" ]
        , button
            [ class "action-btn action-btn--orange"
            , onClick DiceRollDisadvantage
            , title "Roll 2d20, keep lowest"
            ]
            [ text "Disadvantage" ]
        , button
            [ class "action-btn"
            , onClick DiceFlipCoin
            , title "50/50 coin flip"
            ]
            [ text "🪙 Coin Flip" ]
        ]


history : Dice.History -> Html Msg
history h =
    let
        entries =
            Dice.historyEntries h
    in
    div [ class "dice-history" ]
        [ div [ class "dice-history__head" ]
            [ div [ class "dice-history__title" ]
                [ text ("Recent rolls (" ++ String.fromInt (List.length entries) ++ ")") ]
            , if List.isEmpty entries then
                text ""

              else
                button
                    [ class "dice-history__rerun"
                    , onClick DiceClearHistory
                    , title "Clear roll history"
                    ]
                    [ text "Clear" ]
            ]
        , if List.isEmpty entries then
            div [ class "dice-history__empty" ]
                [ text "No rolls yet. Click a die above or type an expression." ]

          else
            ul [ class "dice-history__list" ]
                (List.map historyEntry entries)
        ]


historyEntry : Dice.Roll -> Html Msg
historyEntry roll =
    li [ class "dice-history__entry" ]
        [ div [ class "dice-history__formula" ]
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
        , button
            [ class "dice-history__rerun"
            , onClick (DiceRerun roll)
            , title "Roll this again"
            ]
            [ text "↻" ]
        ]


{-| Render the source chip on a history entry: "Damage → Brakka,
Ogre Brute" / "Stat block → Goblin Boss" / etc. Hides the chip
for the default `Manual` source since the dice modal's own buttons
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
        span [ class "dice-history__source", title label_ ]
            [ text label_ ]


{-| Format the individual face values for a Roll, with kept faces
inline and dropped (advantage/disadvantage loser) ones bracketed.
"rolled 14, +3" or "rolled 17 (8 dropped)" etc.
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
    "rolled " ++ faces ++ modifierText
