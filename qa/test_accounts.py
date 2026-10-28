"""A DM's account: signing up, in and out, the account page, and the edges.

Each scenario owns a fresh server.  Every email here is new to it.
"""

import re
import time

import pytest
from playwright.sync_api import expect

from pages.accounts import (
    PRESET_PATHS,
    AccountPage,
    LoginPage,
    api,
    create_creature,
    create_group,
    devices,  # noqa: F401  The fixture is used by name.
    error_toasts,
    group_names,
    live_names,
    login,
    own_creature_names,
    put_preset_samples,
    register,
    roll_d20,
    save_condition_preset,
    saved_encounters,
    settled_network,
    shot,
    success_toast,
    wait_anonymous,
    wait_for_cards,
    wait_signed_in,
    wait_until_saved,
)
from pages.app import DM, PASSWORD
from pages.building import open_encounter_dialog
from pages.compendium import duplicate



def signed_out(app, email=DM, name="Test DM"):
    """Registers an account through the API.  It then drops the session."""
    register(app.page, email, name=name)
    api(app.page, "POST", "/api/auth/logout")


# Signing up, in and out.


@pytest.mark.cross_browser
def test_a_new_dm_creates_an_account_and_lands_signed_in(app):
    wait_anonymous(app)
    app.page.get_by_role("link", name="Sign in", exact=True).click()
    form = LoginPage(app.page, app.server.base_url)
    expect(form.email).to_be_visible()
    form.to_create_account().fill_new_account(DM, name="Dee Em")
    shot(app, "filled-in")
    app.page.get_by_role("button", name="Create account", exact=True).click()
    wait_signed_in(app, "Dee Em")
    expect(app.page).to_have_url(app.server.base_url + "/")
    expect(app.page.get_by_text("Sign in to keep changes.")).to_have_count(0)
    shot(app, "signed-in")


@pytest.mark.cross_browser
def test_a_dm_signs_out_and_back_in_through_the_form(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    wait_signed_in(app, "Dee Em")
    app.page.get_by_role("link", name="Dee Em", exact=True).click()
    account = AccountPage(app.page, app.server.base_url)
    expect(account.display_name).to_have_value("Dee Em")
    account.sign_out()
    wait_anonymous(app)
    expect(app.page).to_have_url(app.server.base_url + "/")
    assert api(app.page, "GET", "/api/auth/me").status == 401

    LoginPage(app.page, app.server.base_url).goto().sign_in(DM)
    wait_signed_in(app, "Dee Em")
    shot(app, "back-in")


@pytest.mark.cross_browser
def test_a_wrong_password_and_an_unknown_email_get_the_same_refusal(app):
    signed_out(app)
    form = LoginPage(app.page, app.server.base_url).goto()
    form.sign_in(DM, "not the password")
    expect(form.error()).to_have_text("Invalid email or password.")
    wrong_password = form.error().inner_text()
    shot(app, "wrong-password")

    with app.page.expect_response("**/api/auth/login") as unknown:
        form.sign_in("stranger@example.test", "not the password")
    assert unknown.value.status == 401
    app.settle()
    assert form.error().inner_text() == wrong_password
    expect(app.page).to_have_url(app.server.base_url + "/login")
    assert api(app.page, "GET", "/api/auth/me").status == 401


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-07: the sign-in error is not announced to screen readers",
)
def test_a_sign_in_error_is_announced_to_screen_readers(app):
    signed_out(app)
    form = LoginPage(app.page, app.server.base_url).goto()
    form.sign_in(DM, "not the password")
    expect(form.error()).to_be_visible()
    expect(app.page.get_by_role("alert")).to_contain_text(
        "Invalid email or password", timeout=1000
    )


def test_an_email_already_registered_is_refused_whatever_its_case(app):
    signed_out(app)
    form = LoginPage(app.page, app.server.base_url).goto().to_create_account()
    form.create_account("DM@Example.TEST", "another long password", "Impostor")
    expect(form.error()).to_have_text("That email is already registered.")
    shot(app, "taken")
    assert login(app.page, DM, "another long password").status == 401
    assert login(app.page, DM).status == 200


def test_a_short_password_never_creates_an_account(app):
    form = LoginPage(app.page, app.server.base_url).goto().to_create_account()
    form.create_account(DM, "short", "Dee Em")
    app.settle()
    assert form.password.evaluate("e => e.validity.tooShort")
    assert "8" in form.password.evaluate("e => e.validationMessage")
    shot(app, "short-password")
    expect(app.page).to_have_url(app.server.base_url + "/login")
    assert login(app.page, DM, "short").status == 401


def test_empty_fields_keep_the_sign_in_form_from_sending(app):
    sent = []
    app.page.on(
        "request",
        lambda request: re.search("/api/auth/(login|register)", request.url)
        and sent.append(request.url),
    )
    form = LoginPage(app.page, app.server.base_url).goto()
    app.page.get_by_role("button", name="Sign in", exact=True).click()
    app.settle()
    assert form.email.evaluate("e => e.validity.valueMissing")
    assert form.email.evaluate("e => e.validationMessage")
    assert sent == []


def test_a_blank_display_name_is_refused(app):
    form = LoginPage(app.page, app.server.base_url).goto().to_create_account()
    form.create_account(DM, PASSWORD, "   ")
    expect(form.error()).to_contain_text("display name")
    shot(app, "blank-name")
    assert login(app.page, DM).status == 401


@pytest.mark.cross_browser
def test_cancel_and_escape_both_leave_the_sign_in_page(app):
    form = LoginPage(app.page, app.server.base_url).goto()
    app.page.get_by_role("link", name="Cancel sign-in and return to the encounter page").click()
    app.wait_ready()
    expect(app.page).to_have_url(app.server.base_url + "/")

    form.goto()
    form.email.fill("half typed")
    app.page.keyboard.press("Escape")
    app.wait_ready()
    expect(app.page).to_have_url(app.server.base_url + "/")


# Throttling repeated sign-ins.


def bad_logins(page, count):
    return [login(page, DM, f"guess number {n}").status for n in range(count)]


def test_a_burst_of_bad_sign_ins_is_throttled_until_the_window_passes(app):
    signed_out(app)
    # The sign-up above spent one attempt of the ten a window allows.
    assert bad_logins(app.page, 9) == [401] * 9
    throttled = login(app.page, DM, "guess number 10")
    assert throttled.status == 429
    assert "Too many authentication attempts" in throttled.json()["error"]
    wait = throttled.json()["retry_after_secs"]
    assert 0 < wait <= 60
    assert login(app.page, DM).status == 429

    time.sleep(wait + 1)
    assert login(app.page, DM).status == 200


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-08: a throttled sign-in says only 'Something went wrong'",
)
def test_a_throttled_dm_is_told_to_wait(app):
    signed_out(app)
    bad_logins(app.page, 10)
    form = LoginPage(app.page, app.server.base_url).goto()
    form.sign_in(DM)
    expect(form.error()).to_be_visible()
    shot(app, "throttled")
    expect(form.error()).to_contain_text(re.compile("too many|wait", re.IGNORECASE))


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-09: a made-up X-Forwarded-For header resets the sign-in throttle",
)
def test_a_forged_forwarded_for_header_does_not_dodge_the_throttle(app):
    signed_out(app)
    bad_logins(app.page, 10)
    assert login(app.page, DM, "one more guess").status == 429
    forged = api(
        app.page,
        "POST",
        "/api/auth/login",
        {"email": DM, "password": "yet another guess"},
        headers={"X-Forwarded-For": "203.0.113.7"},
    )
    assert forged.status == 429


# The account page.


def test_a_dm_renames_themselves_and_the_new_name_sticks(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    account = AccountPage(app.page, app.server.base_url).goto("Dee Em")
    account.save_display_name("  Dungeon Mistress  ")
    expect(account.success()).to_have_text("Display name saved.")
    expect(app.page.get_by_role("link", name="Dungeon Mistress", exact=True)).to_be_visible()
    shot(app, "renamed")
    account.goto("Dungeon Mistress")
    expect(account.display_name).to_have_value("Dungeon Mistress")
    assert api(app.page, "GET", "/api/auth/me").json()["display_name"] == "Dungeon Mistress"


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-04: loading /me directly shows the server's JSON, not the account page",
)
def test_reloading_the_account_page_keeps_the_dm_on_it(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    AccountPage(app.page, app.server.base_url).goto("Dee Em")
    app.page.reload()
    shot(app, "reloaded")
    expect(app.page.get_by_role("heading", name="Profile")).to_be_visible(timeout=3000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-18: Leave feedback mails feedback@ezpzdndz, which has no domain",
)
def test_leave_feedback_mails_an_address_that_can_receive_it(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    AccountPage(app.page, app.server.base_url).goto("Dee Em")
    href = app.page.get_by_role("link", name="Leave feedback").get_attribute("href")
    address = re.match(r"mailto:([^?]+)", href).group(1)
    assert re.fullmatch(r"[^@]+@[^@]+\.[a-z]{2,}", address), address


def test_a_blank_display_name_is_refused_on_the_account_page(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    account = AccountPage(app.page, app.server.base_url).goto("Dee Em")
    account.save_display_name("   ")
    expect(account.error()).to_have_text("Display name must not be empty.")
    assert api(app.page, "GET", "/api/auth/me").json()["display_name"] == "Dee Em"


def test_a_mismatched_confirmation_is_caught_before_anything_is_sent(app):
    app.sign_up(DM)
    sent = []
    app.page.on("request", lambda r: "/api/auth/password" in r.url and sent.append(r.url))
    account = AccountPage(app.page, app.server.base_url).goto()
    account.change_password(PASSWORD, "a brand new password", "a brand new passw0rd")
    expect(account.error()).to_have_text("New password and confirmation don't match.")
    account.change_password(PASSWORD, "short")
    expect(account.error()).to_have_text("New password must be at least 8 characters.")
    shot(app, "refused")
    assert sent == []


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-10: a wrong current password reads 'Server returned 401.'",
)
def test_a_wrong_current_password_is_refused_with_a_reason(app, devices):
    app.sign_up(DM)
    account = AccountPage(app.page, app.server.base_url).goto()
    account.change_password("not my password", "a brand new password")
    expect(account.error()).to_be_visible()
    shot(app, "wrong-current")
    other = devices.device("other")
    assert login(other.page, DM).status == 200
    expect(account.error()).to_contain_text(re.compile("current password", re.IGNORECASE))


def test_a_new_password_replaces_the_old_one(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    account = AccountPage(app.page, app.server.base_url).goto("Dee Em")
    account.change_password(PASSWORD, "a brand new password")
    expect(account.success()).to_have_text("Password updated.")
    expect(app.page.get_by_label("Current password")).to_have_value("")
    shot(app, "updated")
    account.sign_out()
    wait_anonymous(app)

    form = LoginPage(app.page, app.server.base_url).goto()
    form.sign_in(DM, PASSWORD)
    expect(form.error()).to_have_text("Invalid email or password.")
    form.sign_in(DM, "a brand new password")
    wait_signed_in(app, "Dee Em")


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-11: changing the password leaves other devices signed in",
)
def test_changing_the_password_signs_out_other_devices(app, devices):
    app.sign_up(DM, PASSWORD, "Dee Em")
    laptop = devices.device("laptop", "/login")
    LoginPage(laptop.page, app.server.base_url).sign_in(DM)
    wait_signed_in(laptop, "Dee Em")

    account = AccountPage(app.page, app.server.base_url).goto("Dee Em")
    account.change_password(PASSWORD, "a brand new password")
    expect(account.success()).to_be_visible()
    assert api(laptop.page, "GET", "/api/auth/me").status == 401


# What an anonymous DM is told.


def test_an_anonymous_dm_is_pointed_at_sign_in_wherever_an_account_is_needed(app):
    wait_anonymous(app)
    expect(app.page.get_by_role("link", name="Sign in", exact=True)).to_have_attribute(
        "href", "/login"
    )
    dialog = open_encounter_dialog(app.page, "Save")
    dialog.get_by_text("This server", exact=True).click()
    expect(dialog).to_contain_text("Saving to the server keeps an encounter with your account")
    shot(app, "save-nudge")
    dialog.get_by_role("link", name="Sign in").click()
    expect(LoginPage(app.page, app.server.base_url).email).to_be_visible()
    expect(app.page).to_have_url(app.server.base_url + "/login")

    app.goto("/")
    expect(open_encounter_dialog(app.page, "Load")).to_contain_text(
        "Sign in to keep encounters on the server"
    )
    shot(app, "load-nudge")


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-17: the compendium page says to sign in but offers no way to",
)
def test_the_compendium_page_offers_a_way_to_sign_in_for_server_saves(app):
    app.goto("/compendium")
    app.page.get_by_role("button", name=re.compile("Import$")).click()
    dialog = app.page.get_by_role("dialog")
    dialog.get_by_label("Server").check()
    expect(dialog).to_contain_text("Sign in to load your compendium from the eZpZ-dndZ server.")
    shot(app, "compendium-nudge")
    expect(app.page.get_by_role("link", name=re.compile("sign in", re.IGNORECASE))).to_be_visible(
        timeout=1000
    )


# Bringing anonymous work into an account.

PARTY = ["Goblin Warrior", "Goblin Warrior 2", "Ogre"]


def test_anonymous_work_moves_into_a_new_account(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    duplicate(app, "Ogre", "Swamp Ogre")
    assert app.card_names() == PARTY
    shot(app, "anonymous-work")

    LoginPage(app.page, app.server.base_url).goto().to_create_account().create_account(
        DM, name="Dee Em"
    )
    wait_signed_in(app, "Dee Em")
    expect(success_toast(app.page, "Saved your pre-sign-in encounter as “Local — ")).to_be_visible()
    expect(success_toast(app.page, "Imported 1 creature from your pre-sign-in session.")).to_be_visible()
    shot(app, "moved-in")
    settled_network(app.page)
    assert app.card_names() == PARTY
    assert live_names(app.page) == PARTY
    saves = saved_encounters(app.page)
    assert list(saves.values()) == [PARTY]
    assert next(iter(saves)).startswith("Local — ")
    assert own_creature_names(app.page) == ["Swamp Ogre"]

    app.reload()
    wait_for_cards(app, PARTY)
    left_behind = app.page.evaluate("() => Object.keys(localStorage)")
    assert "encounter" not in left_behind and "compendium" not in left_behind


def test_signing_in_keeps_the_accounts_own_creatures_and_groups(app, devices):
    register(app.page, DM)
    hag = create_creature(app.page, "Bramble Hag")
    create_group(app.page, "Hag coven", hag["id"])
    laptop = devices.device("laptop", "/login")
    LoginPage(laptop.page, app.server.base_url).sign_in(DM)
    wait_signed_in(laptop, "Test DM")
    settled_network(laptop.page)
    shot(laptop, "signed-in")
    kept = (own_creature_names(laptop.page), group_names(laptop.page))
    assert kept == (["Bramble Hag"], ["Hag coven"])


def test_signing_out_and_back_in_keeps_the_dms_creatures(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    create_creature(app.page, "Bramble Hag")
    AccountPage(app.page, app.server.base_url).goto("Dee Em").sign_out()
    wait_anonymous(app)
    LoginPage(app.page, app.server.base_url).goto().sign_in(DM)
    wait_signed_in(app, "Dee Em")
    settled_network(app.page)
    assert own_creature_names(app.page) == ["Bramble Hag"]


def test_signing_in_with_anonymous_creatures_adds_them_beside_the_accounts_own(app, devices):
    register(app.page, DM)
    create_creature(app.page, "Bramble Hag")
    laptop = devices.device("laptop")
    duplicate(laptop, "Ogre", "Swamp Ogre")
    LoginPage(laptop.page, app.server.base_url).goto().sign_in(DM)
    wait_signed_in(laptop, "Test DM")
    settled_network(laptop.page)
    assert own_creature_names(laptop.page) == ["Bramble Hag", "Swamp Ogre"]


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-02: signing in with an anonymous encounter discards the account's live fight",
)
def test_signing_in_with_an_anonymous_encounter_keeps_the_accounts_live_fight(app, devices):
    app.sign_up(DM)
    app.add("Ogre")
    app.begin_combat()
    wait_until_saved(app.page, ["Ogre"])

    laptop = devices.device("laptop")
    laptop.add("Goblin Warrior")
    LoginPage(laptop.page, app.server.base_url).goto().sign_in(DM)
    wait_signed_in(laptop, "Test DM")
    settled_network(laptop.page)
    shot(laptop, "signed-in")
    assert laptop.card_names() == ["Goblin Warrior"]
    kept = [live_names(laptop.page), *saved_encounters(laptop.page).values()]
    assert ["Ogre"] in kept, f"The ogre fight is gone.  The account holds {kept}."


def test_a_new_account_boots_without_an_error_toast(app):
    app.sign_up(DM)
    settled_network(app.page)
    app.settle()
    shot(app, "booted")
    # Toasts fade on their own.  A retrying expect would wait one out.
    assert error_toasts(app.page).all_inner_texts() == []



# Keeping two DMs apart.


def alice_prepares_a_table(app):
    """Alice signs up and leaves something in every store she has."""
    app.sign_up("alice@example.test", PASSWORD, "Alice")
    app.add("Ogre")
    wait_until_saved(app.page, ["Ogre"])
    live = api(app.page, "GET", "/api/encounter").json()
    assert api(app.page, "PUT", "/api/encounter/saves/Ogre%20ambush", live).status == 200
    hag = create_creature(app.page, "Bramble Hag")
    coven = create_group(app.page, "Hag coven", hag["id"])
    roll_d20(app)
    save_condition_preset(app, "Hag poison")
    put_preset_samples(app.page)
    return hag, coven


def test_two_dms_never_see_each_others_table(app, devices):
    alice_prepares_a_table(app)
    assert len(api(app.page, "GET", "/api/dice/history").json()) == 1
    assert "Hag poison" in api(app.page, "GET", "/api/condition-presets").json()

    bob = devices.device("bob")
    register(bob.page, "bob@example.test", name="Bob")
    bob.reload()
    wait_signed_in(bob, "Bob")
    settled_network(bob.page)
    shot(bob, "bobs-table")
    assert bob.card_names() == []
    assert live_names(bob.page) == []
    assert saved_encounters(bob.page) == {}
    assert own_creature_names(bob.page) == []
    assert group_names(bob.page) == []
    assert api(bob.page, "GET", "/api/dice/history").json() == []
    for path in PRESET_PATHS:
        assert api(bob.page, "GET", path).json() is None, f"Bob can read Alice's {path}"

    app.reload()
    wait_for_cards(app, ["Ogre"])


def test_one_dm_cannot_reach_anothers_records_by_id(app, devices):
    hag, coven = alice_prepares_a_table(app)
    bob = devices.device("bob")
    register(bob.page, "bob@example.test", name="Bob")
    creature = "/api/compendium/creatures/" + hag["id"]
    group = "/api/compendium/groups/" + coven["id"]
    save = "/api/encounter/saves/Ogre%20ambush"
    attempts = {
        ("GET", creature): api(bob.page, "GET", creature),
        ("PUT", creature): api(bob.page, "PUT", creature, {**hag, "name": "Bob's Hag"}),
        ("POST", creature + "/duplicate"): api(bob.page, "POST", creature + "/duplicate"),
        ("DELETE", creature): api(bob.page, "DELETE", creature),
        ("GET", group): api(bob.page, "GET", group),
        ("PUT", group): api(bob.page, "PUT", group, {**coven, "name": "Bob's coven"}),
        ("DELETE", group): api(bob.page, "DELETE", group),
        ("GET", save): api(bob.page, "GET", save),
        ("DELETE", save): api(bob.page, "DELETE", save),
    }
    assert {key: reply.status for key, reply in attempts.items()} == {
        key: 404 for key in attempts
    }
    assert own_creature_names(bob.page) == []
    assert own_creature_names(app.page) == ["Bramble Hag"]
    assert group_names(app.page) == ["Hag coven"]
    assert saved_encounters(app.page) == {"Ogre ambush": ["Ogre"]}


# The API's edges.

PROTECTED = [
    ("GET", "/api/encounter", None),
    ("PUT", "/api/encounter", {"creatures": []}),
    ("GET", "/api/encounter/saves", None),
    ("GET", "/api/compendium/creatures", None),
    ("POST", "/api/compendium/creatures", {"name": "x"}),
    ("GET", "/api/compendium/export", None),
    ("POST", "/api/compendium/import", []),
    ("POST", "/api/compendium/reset", None),
    ("GET", "/api/compendium/saves", None),
    ("GET", "/api/compendium/groups", None),
    ("GET", "/api/dice/history", None),
    ("DELETE", "/api/dice/history", None),
    *[("GET", path, None) for path in PRESET_PATHS],
    ("PUT", "/api/lore-groups", []),
    ("GET", "/api/auth/me", None),
    ("PUT", "/api/auth/me", {"display_name": "x"}),
    ("POST", "/api/auth/password", {"current_password": "x", "new_password": "y"}),
]


def anonymous_replies(app):
    return {
        (method, path): api(app.page, method, path, body)
        for method, path, body in PROTECTED
    }


def test_protected_endpoints_refuse_an_anonymous_caller(app):
    replies = anonymous_replies(app)
    assert {key: reply.status for key, reply in replies.items()} == {
        key: 401 for key in replies
    }
    assert all(reply.json().get("error") for reply in replies.values())


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-12: a request without a session is told 'Invalid email or password'",
)
def test_a_caller_without_a_session_is_not_told_their_password_is_wrong(app):
    messages = {key: reply.json()["error"] for key, reply in anonymous_replies(app).items()}
    blamed = [key for key, message in messages.items() if "password" in message.lower()]
    assert blamed == [], f"These blame a password nobody typed: {blamed}"


WRITES = [
    ("PUT", "/api/encounter"),
    ("POST", "/api/encounter/saves/Junk/rename"),
    ("POST", "/api/compendium/creatures"),
    ("POST", "/api/compendium/import"),
    ("POST", "/api/compendium/groups"),
    ("POST", "/api/dice/history"),
    *[("PUT", path) for path in PRESET_PATHS],
    ("PUT", "/api/auth/me"),
    ("POST", "/api/auth/password"),
    ("POST", "/api/auth/login"),
    ("POST", "/api/auth/register"),
]


def test_malformed_bodies_are_refused_with_a_client_error(app):
    app.sign_up(DM)
    statuses = {}
    for method, path in WRITES:
        statuses[(method, path, "not json")] = api(app.page, method, path, raw="{not json").status
        statuses[(method, path, "no type")] = api(
            app.page, method, path, raw='{"a": 1}', content_type=None
        ).status
        statuses[(method, path, "wrong shape")] = api(app.page, method, path, {"zzz": 1}).status
    malformed = {key: s for key, s in statuses.items() if key[2] != "wrong shape"}
    assert {key: s for key, s in malformed.items() if not 400 <= s < 500} == {}
    # A body of the wrong shape must not break the server.  Some stores
    # accept one anyway.  QA-ACCT-13 covers those.
    assert {key: s for key, s in statuses.items() if s >= 500} == {}
    assert api(app.page, "GET", "/api/auth/me").json()["display_name"] == "Test DM"


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-13: named saves and treasure profiles accept JSON of any shape",
)
def test_stores_refuse_a_body_of_the_wrong_shape(app):
    app.sign_up(DM)
    statuses = {
        path: api(app.page, "PUT", path, {"zzz": 1}).status
        for path in [
            "/api/encounter/saves/Junk",
            "/api/compendium/saves/Junk",
            "/api/treasure-profiles",
        ]
    }
    assert statuses == {path: 400 for path in statuses}


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-05: over plain HTTP on a LAN name the session cookie is refused",
)
def test_signing_in_over_plain_http_on_a_home_network_works(
    server, browser_type, browser_name, browser_context_args
):
    if browser_name != "chromium":
        pytest.skip("Only Chromium can map a made-up hostname to the loopback address.")
    browser = browser_type.launch(args=["--host-resolver-rules=MAP dm-laptop.test 127.0.0.1"])
    try:
        page = browser.new_context(**browser_context_args).new_page()
        page.goto(f"http://dm-laptop.test:{server.port}/")
        expect(page.get_by_role("button", name="Quick Add", exact=True)).to_be_visible()
        register(page, DM, name="Dee Em")
        page.reload()
        expect(page.get_by_role("button", name="Quick Add", exact=True)).to_be_visible()
        expect(page.get_by_role("link", name="Dee Em", exact=True)).to_be_visible(timeout=3000)
    finally:
        browser.close()
