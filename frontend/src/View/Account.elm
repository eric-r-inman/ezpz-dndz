module View.Account exposing (view)

{-| Account page (`/me`).

Three sections:

  - **Profile** — read-only email + member-since, editable display
    name.
  - **Security** — current + new + confirm password change.
  - **Actions** — Leave Feedback (mailto link) and Sign Out.

Each form section shows its own inline error / success banner so
profile edits and password changes don't interfere with each
other. Renders a friendly empty-state when the model is in
`AuthLoading` (in practice the loading screen elsewhere catches
this before the user can navigate here, but the branch is here
for safety).

-}

import Auth exposing (AuthState(..), User)
import Html
    exposing
        ( Html
        , a
        , button
        , div
        , h2
        , h3
        , input
        , label
        , p
        , section
        , span
        , text
        )
import Html.Attributes as Attr
    exposing
        ( attribute
        , class
        , disabled
        , for
        , href
        , id
        , maxlength
        , type_
        , value
        )
import Html.Events exposing (onClick, onInput)
import Model exposing (Model)
import Msg exposing (Msg(..))
import Ui.Account as Account exposing (AccountUi, PasswordDraft, ProfileDraft)


view : Model -> Html Msg
view model =
    let
        body =
            case model.auth of
                AuthLoading ->
                    p [ class "empty" ] [ text "Loading account…" ]

                AuthAnonymous ->
                    p [ class "empty" ]
                        [ text "You're not signed in — head to "
                        , a [ href "/login" ] [ text "the sign-in page" ]
                        , text " to sign in or create an account."
                        ]

                AuthAuthenticated user ->
                    accountBody user model.accountUi
    in
    div [ class "workspace workspace--account" ]
        [ section [ class "panel panel--main account-page" ]
            [ div [ class "panel__header" ]
                [ div [ class "panel__title" ] [ text "Account" ] ]
            , div [ class "panel__body account-page__body" ] [ body ]
            ]
        ]


accountBody : User -> AccountUi -> Html Msg
accountBody user ui =
    div [ class "account-page__content" ]
        [ profileSection user ui.profile
        , securitySection ui.password
        , actionsSection
        ]



-- ── PROFILE ──────────────────────────────────────────────────────────────────


profileSection : User -> ProfileDraft -> Html Msg
profileSection user draft =
    section [ class "account-card" ]
        [ h2 [ class "account-card__title" ] [ text "Profile" ]
        , div [ class "account-card__row account-card__row--readonly" ]
            [ span [ class "account-card__label" ] [ text "Email" ]
            , span [ class "account-card__value" ] [ text user.email ]
            ]
        , div [ class "account-card__row account-card__row--readonly" ]
            [ span [ class "account-card__label" ] [ text "Member since" ]
            , span [ class "account-card__value" ]
                [ text (formatCreatedAt user.createdAt) ]
            ]
        , div [ class "account-card__row" ]
            [ label
                [ class "account-card__label", for "account-display-name" ]
                [ text "Display name" ]
            , input
                [ id "account-display-name"
                , class "account-card__input"
                , type_ "text"
                , value draft.displayName
                , maxlength Account.maxDisplayNameLength
                , onInput AccountDisplayNameChanged
                , disabled draft.busy
                ]
                []
            ]
        , profileFeedback draft
        , div [ class "account-card__actions" ]
            [ button
                [ class "action-btn action-btn--green"
                , onClick AccountProfileSubmit
                , disabled (draft.busy || String.trim draft.displayName == user.displayName)
                ]
                [ text
                    (if draft.busy then
                        "Saving…"

                     else
                        "Save profile"
                    )
                ]
            ]
        ]


profileFeedback : ProfileDraft -> Html Msg
profileFeedback draft =
    case ( draft.error, draft.success ) of
        ( Just err, _ ) ->
            p [ class "account-card__error" ] [ text err ]

        ( Nothing, Just ok ) ->
            p [ class "account-card__success" ] [ text ok ]

        _ ->
            text ""



-- ── SECURITY (PASSWORD) ──────────────────────────────────────────────────────


securitySection : PasswordDraft -> Html Msg
securitySection draft =
    section [ class "account-card" ]
        [ h2 [ class "account-card__title" ] [ text "Security" ]
        , h3 [ class "account-card__subtitle" ] [ text "Change password" ]
        , div [ class "account-card__row" ]
            [ label
                [ class "account-card__label", for "account-current-password" ]
                [ text "Current password" ]
            , input
                [ id "account-current-password"
                , class "account-card__input"
                , type_ "password"
                , value draft.current
                , attribute "autocomplete" "current-password"
                , onInput AccountCurrentPasswordChanged
                , disabled draft.busy
                ]
                []
            ]
        , div [ class "account-card__row" ]
            [ label
                [ class "account-card__label", for "account-new-password" ]
                [ text "New password" ]
            , input
                [ id "account-new-password"
                , class "account-card__input"
                , type_ "password"
                , value draft.new
                , attribute "autocomplete" "new-password"
                , Attr.minlength 8
                , onInput AccountNewPasswordChanged
                , disabled draft.busy
                ]
                []
            ]
        , div [ class "account-card__row" ]
            [ label
                [ class "account-card__label", for "account-confirm-password" ]
                [ text "Confirm new password" ]
            , input
                [ id "account-confirm-password"
                , class "account-card__input"
                , type_ "password"
                , value draft.confirm
                , attribute "autocomplete" "new-password"
                , Attr.minlength 8
                , onInput AccountConfirmPasswordChanged
                , disabled draft.busy
                ]
                []
            ]
        , passwordFeedback draft
        , div [ class "account-card__actions" ]
            [ button
                [ class "account-card__text-link"
                , onClick AccountPasswordSubmit
                , disabled draft.busy
                ]
                [ text
                    (if draft.busy then
                        "Updating…"

                     else
                        "Update password"
                    )
                ]
            ]
        ]


passwordFeedback : PasswordDraft -> Html Msg
passwordFeedback draft =
    case ( draft.error, draft.success ) of
        ( Just err, _ ) ->
            p [ class "account-card__error" ] [ text err ]

        ( Nothing, Just ok ) ->
            p [ class "account-card__success" ] [ text ok ]

        _ ->
            text ""



-- ── ACTIONS ──────────────────────────────────────────────────────────────────


actionsSection : Html Msg
actionsSection =
    section [ class "account-card" ]
        [ h2 [ class "account-card__title" ] [ text "Account actions" ]
        , div [ class "account-card__actions account-card__actions--column" ]
            [ a
                [ class "account-card__text-link"
                , href "mailto:feedback@ezpzdndz?subject=ezpz-dndz%20feedback"
                ]
                [ text "Leave feedback" ]
            , button
                [ class "account-card__text-link account-card__text-link--danger"
                , onClick AuthLogout
                ]
                [ text "Sign out" ]
            ]
        , p [ class "account-card__hint" ]
            [ text "Feedback opens your mail client. Replies land at "
            , a [ href "mailto:feedback@ezpzdndz" ] [ text "feedback@ezpzdndz" ]
            , text "."
            ]
        ]



-- ── HELPERS ──────────────────────────────────────────────────────────────────


{-| Pretty-format the unix-seconds `createdAt` from the backend.
We don't pull in a date library for this one display point — a
plain `YYYY-MM-DD` is fine; the backend stores epoch-seconds so
the math is a small integer trick.
-}
formatCreatedAt : Int -> String
formatCreatedAt seconds =
    if seconds <= 0 then
        "Unknown"

    else
        let
            -- Days since Unix epoch.
            totalDays =
                seconds // 86400

            -- Anchor: 1970-01-01 is a Thursday, day 0.  Walk forward
            -- year by year accounting for leap years.
            ( y, m, d ) =
                daysToYmd totalDays
        in
        String.fromInt y
            ++ "-"
            ++ pad2 m
            ++ "-"
            ++ pad2 d


daysToYmd : Int -> ( Int, Int, Int )
daysToYmd days0 =
    let
        ( y, remAfterYear ) =
            walkYear 1970 days0

        ( m, d ) =
            walkMonth y 1 remAfterYear
    in
    ( y, m, d + 1 )


walkYear : Int -> Int -> ( Int, Int )
walkYear year days =
    let
        len =
            yearLength year
    in
    if days < len then
        ( year, days )

    else
        walkYear (year + 1) (days - len)


walkMonth : Int -> Int -> Int -> ( Int, Int )
walkMonth year month days =
    let
        len =
            monthLength year month
    in
    if days < len || month >= 12 then
        ( month, days )

    else
        walkMonth year (month + 1) (days - len)


yearLength : Int -> Int
yearLength year =
    if isLeap year then
        366

    else
        365


monthLength : Int -> Int -> Int
monthLength year month =
    case month of
        1 ->
            31

        2 ->
            if isLeap year then
                29

            else
                28

        3 ->
            31

        4 ->
            30

        5 ->
            31

        6 ->
            30

        7 ->
            31

        8 ->
            31

        9 ->
            30

        10 ->
            31

        11 ->
            30

        12 ->
            31

        _ ->
            30


isLeap : Int -> Bool
isLeap y =
    (modBy 4 y == 0 && modBy 100 y /= 0) || modBy 400 y == 0


pad2 : Int -> String
pad2 n =
    if n < 10 then
        "0" ++ String.fromInt n

    else
        String.fromInt n
