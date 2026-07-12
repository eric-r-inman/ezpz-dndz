module View.Chip exposing (view)

{-| Shared chip / pill primitive.

The card row 1 condition chip, the green "Saved: X" notice
chip, the row 3 memo pill, and the row 3 timer pill all share
the same shape: colored capsule with optional label, optional
trailing icon row, and an optional × dismiss button. This
helper extracts that shape so per-callsite views only declare
the variant + content, and the CSS gets a single base `.pill`
class with modifier classes per use case.

@docs view

-}

import Html exposing (Html, button, span, text)
import Html.Attributes exposing (attribute, class)
import Html.Events exposing (onClick)
import View.Tooltips as Tooltips


{-| Render a chip / pill.

  - `class_` — extra classes appended to `.pill`, used for color
    (~"pill--condition"~, ~"pill--saved"~, ~"pill--memo"~,
    ~"pill--timer"~, ~"pill--timer-ringing"~).
  - `title_` — optional tooltip on the wrapper.
  - `label` — primary text content (the condition name, the
    memo text, the timer count).
  - `onLabelClick` — optional click handler on the label
    itself. If `Just`, the label is rendered as a `<button>`
    (so it picks up cursor / focus styles); otherwise as a
    `<span>`.
  - `extras` — inline trailing content (e.g., 🎲 save button,
    `⏳3` duration glyph, `(note)` annotation).
  - `dismiss` — optional × button. When `Just`, dispatches the
    given Msg.

-}
view :
    { class_ : String
    , title_ : Maybe String
    , label : String
    , onLabelClick : Maybe msg
    , extras : List (Html msg)
    , dismiss : Maybe msg
    }
    -> Html msg
view config =
    let
        wrapperAttrs =
            [ class ("pill " ++ config.class_) ]
                ++ (case config.title_ of
                        Just t ->
                            [ Tooltips.attr t ]

                        Nothing ->
                            []
                   )

        labelNode =
            case config.onLabelClick of
                Just msg ->
                    button
                        [ class "pill__label pill__label--clickable"
                        , onClick msg
                        , Tooltips.attr Tooltips.chipClickToEdit
                        ]
                        [ text config.label ]

                Nothing ->
                    span [ class "pill__label" ] [ text config.label ]

        dismissNode =
            case config.dismiss of
                Just msg ->
                    button
                        [ class "pill__dismiss"
                        , onClick msg
                        , Tooltips.attr Tooltips.chipDismiss
                        , attribute "aria-label" "Dismiss"
                        ]
                        [ text "×" ]

                Nothing ->
                    text ""
    in
    span wrapperAttrs (labelNode :: config.extras ++ [ dismissNode ])
