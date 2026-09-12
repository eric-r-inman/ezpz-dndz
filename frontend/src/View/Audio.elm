module View.Audio exposing (ringer)

{-| Page-level audio element that plays the ping sound when any
creature has a ringing timer. Mounted only when at least one
timer is ringing — the mount triggers HTML5's `autoplay` so the
sound fires once. When all rings are dismissed the element
unmounts; a future ring remounts it and replays the sound.

Browsers without autoplay permission may block the first play
until the user has interacted with the page; in this app the GM
has already advanced the turn (which is what triggered the ring)
so the user-gesture requirement is satisfied.

-}

import Html exposing (Html, text)
import Html.Attributes exposing (attribute, autoplay, src)
import Model exposing (Model)
import Msg exposing (Msg)


ringer : Model -> Html Msg
ringer model =
    let
        anyRinging =
            List.any
                (\c ->
                    case c.timer of
                        Just t ->
                            t.ringing

                        Nothing ->
                            False
                )
                model.encounter.creatures
    in
    if anyRinging then
        Html.audio
            [ src "/ping.wav"
            , autoplay True
            , attribute "aria-hidden" "true"
            ]
            []

    else
        text ""
