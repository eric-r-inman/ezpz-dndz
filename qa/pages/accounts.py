"""Accounts, devices and the API as the account scenarios drive them."""

import json
import re
import time
from urllib.parse import quote

import pytest
from playwright.sync_api import expect

from pages.app import PASSWORD, settle, settle_animations
from pages.fight import ConditionEditor, ManageHp
from pages.turns import start_timer, timer_pill
from pages.ui import Dice


# Playwright's request client does not send the Secure session cookie to
# 127.0.0.1.  A fetch inside the page does.
FETCH = """async ([method, path, body, raw, contentType, headers]) => {
  const all = {...headers};
  if (contentType) all['content-type'] = contentType;
  const response = await fetch(path, {
    method,
    headers: all,
    body: raw !== null ? raw : body === null ? undefined : JSON.stringify(body),
  });
  return [response.status, await response.text()];
}"""


class Reply:
    def __init__(self, status, text):
        self.status = status
        self.text = text

    def json(self):
        return json.loads(self.text)

    def __repr__(self):
        return f"Reply({self.status}, {self.text[:200]!r})"


def api(page, method, path, body=None, raw=None, content_type="application/json", headers=None):
    """Calls the server from inside the page.  It carries the page's cookies.

    A raw string goes out as the body unparsed.  Pass content_type=None to
    send a body without declaring it JSON.
    """
    has_body = body is not None or raw is not None
    status, text = page.evaluate(
        FETCH, [method, path, body, raw, content_type if has_body else None, headers or {}]
    )
    return Reply(status, text)


def register(page, email, password=PASSWORD, name="Test DM"):
    reply = api(
        page,
        "POST",
        "/api/auth/register",
        {"email": email, "password": password, "display_name": name},
    )
    assert reply.status == 201, f"Sign-up failed: {reply}"
    return reply.json()


def login(page, email, password=PASSWORD):
    return api(page, "POST", "/api/auth/login", {"email": email, "password": password})


def create_creature(page, name):
    reply = api(
        page,
        "POST",
        "/api/compendium/creatures",
        {
            "name": name,
            "kind": "enemy",
            "size": "medium",
            "armor_class": 15,
            "max_hp": 40,
            "challenge_rating": "3",
        },
    )
    assert reply.status == 201, f"Creating {name} failed: {reply}"
    return reply.json()


def create_group(page, name, creature_id):
    reply = api(
        page,
        "POST",
        "/api/compendium/groups",
        {
            "name": name,
            "initiative_mode": {"type": "each_rolls"},
            "entries": [{"creature_id": creature_id, "count": 3}],
        },
    )
    assert reply.status in (200, 201), f"Creating group {name} failed: {reply}"
    return reply.json()


def group_names(page):
    reply = api(page, "GET", "/api/compendium/groups")
    assert reply.status == 200, reply
    return sorted(group["name"] for group in reply.json())


def own_creature_names(page):
    """Names of the signed-in DM's own creatures.

    The bundled set is left out.
    """
    reply = api(page, "GET", "/api/compendium/creatures")
    assert reply.status == 200, reply
    return sorted(c["name"] for c in reply.json() if not c.get("is_bundled"))


def shot(app, step):
    """Takes the screenshot once fades and slides have finished.

    A modal or a fresh page fades in.  A shot taken mid-fade shows the page
    behind it bleeding through.
    """
    settle_animations(app.page)
    return app.shot(step)


def notifications(page):
    return page.get_by_role("region", name="Notifications")


def success_toast(page, text):
    return notifications(page).get_by_role("status").filter(has_text=text)


def error_toasts(page):
    return notifications(page).get_by_role("alert")


def live_names(page):
    """Creature names in the encounter the server holds for this DM."""
    reply = api(page, "GET", "/api/encounter")
    assert reply.status == 200, reply
    body = reply.json()
    return [] if body is None else [c["name"] for c in body["creatures"]]


def wait_until_saved(page, names, text=""):
    """Waits for the server to hold an encounter of exactly these names.

    Pass text to also wait for the stored encounter to mention it.  The label of
    the last timer set is one example.
    """

    def saved():
        return live_names(page) == names and text in api(page, "GET", "/api/encounter").text

    deadline = time.monotonic() + 5
    while not saved() and time.monotonic() < deadline:
        settle(page)
    assert saved(), f"The server holds {live_names(page)}, not {names} with {text!r}"


def saved_encounters(page):
    """Each named save as its name and the creature names inside it."""
    reply = api(page, "GET", "/api/encounter/saves")
    assert reply.status == 200, reply
    return {
        meta["name"]: [
            c["name"]
            for c in api(page, "GET", "/api/encounter/saves/" + quote(meta["name"]))
            .json()["encounter"]["creatures"]
        ]
        for meta in reply.json()
    }


def settled_network(page):
    """Waits out the burst of requests a signed-in boot sends."""
    page.wait_for_load_state("networkidle")


class LoginPage:
    """The /login form.  It flips in place between sign-in and sign-up."""

    def __init__(self, page, base_url):
        self.page = page
        self.base_url = base_url

    def goto(self):
        self.page.goto(self.base_url + "/login")
        expect(self.email).to_be_visible()
        return self

    @property
    def email(self):
        return self.page.get_by_label("Email")

    @property
    def password(self):
        return self.page.get_by_label("Password", exact=True)

    @property
    def display_name(self):
        return self.page.get_by_label("Display name")

    def to_create_account(self):
        self.page.get_by_role("button", name="Create one").click()
        expect(self.display_name).to_be_visible()
        return self

    def sign_in(self, email, password=PASSWORD):
        self.email.fill(email)
        self.password.fill(password)
        self.page.get_by_role("button", name="Sign in", exact=True).click()
        return self

    def fill_new_account(self, email, password=PASSWORD, name="Test DM"):
        self.email.fill(email)
        self.password.fill(password)
        self.display_name.fill(name)
        return self

    def create_account(self, email, password=PASSWORD, name="Test DM"):
        self.fill_new_account(email, password, name)
        self.page.get_by_role("button", name="Create account", exact=True).click()
        return self

    def error(self):
        """The inline error.  It has no role or label.  This is CSS."""
        return self.page.locator(".auth-login__error")


def wait_signed_in(app, name):
    """Waits for the boot that follows a sign-in to show the DM's name."""
    expect(app.page.get_by_role("link", name=name, exact=True)).to_be_visible()
    app.wait_ready()


def wait_anonymous(app):
    expect(app.page.get_by_text("Sign in to keep changes.")).to_be_visible()


class AccountPage:
    """The /account page with its display name, password change and sign out."""

    def __init__(self, page, base_url):
        self.page = page
        self.base_url = base_url

    def goto(self, name="Test DM"):
        """Opens the page from the AppBar link that names the DM."""
        self.page.goto(self.base_url + "/")
        self.page.get_by_role("link", name=name, exact=True).click()
        expect(self.page.get_by_role("heading", name="Profile")).to_be_visible()
        return self

    @property
    def display_name(self):
        return self.page.get_by_label("Display name")

    def save_display_name(self, name):
        self.display_name.fill(name)
        self.page.get_by_role("button", name="Save profile").click()

    def change_password(self, current, new, confirm=None):
        self.page.get_by_label("Current password").fill(current)
        self.page.get_by_label("New password", exact=True).fill(new)
        self.page.get_by_label("Confirm new password").fill(new if confirm is None else confirm)
        self.page.get_by_role("button", name="Update password").click()

    def error(self):
        """Inline errors carry no role.  This is CSS."""
        return self.page.locator(".account-card__error")

    def success(self):
        return self.page.locator(".account-card__success")

    def sign_out(self):
        self.page.get_by_role("button", name="Sign out").click()


class Devices:
    """Extra browser contexts and tabs beside the scenario's own page.

    A new context is another device.  It has its own cookies and storage.  A new
    tab shares the scenario page's context.  A second tab of the same browser
    does the same.
    """

    def __init__(self, browser, context_args, app):
        self.browser = browser
        self.context_args = context_args
        self.app = app
        self.contexts = []
        self.apps = []

    def _wrap(self, page, label):
        extra = self.app.beside(page, label)
        self.apps.append(extra)
        return extra

    def device(self, label, path="/"):
        context = self.browser.new_context(**self.context_args)
        self.contexts.append(context)
        extra = self._wrap(context.new_page(), label)
        extra.goto(path)
        return extra

    def tab(self, label):
        extra = self._wrap(self.app.page.context.new_page(), label)
        extra.goto("/")
        return extra

    def close(self):
        errors = [error for extra in self.apps for error in extra.page_errors]
        for context in self.contexts:
            context.close()
        assert not errors, "A second page threw:\n" + "\n".join(errors)


@pytest.fixture
def devices(browser, browser_context_args, app):
    """Opens further devices and tabs against the scenario's server."""
    extra = Devices(browser, browser_context_args, app)
    yield extra
    extra.close()


# The per-user stores beyond the encounter and the compendium.

PRESET_PATHS = [
    "/api/condition-presets",
    "/api/save-chain-presets",
    "/api/lore-groups",
    "/api/treasure-table",
    "/api/treasure-profiles",
]

# Small payloads each preset store accepts.  The condition presets
# store is strict.  The scenarios save one through the app instead.
PRESET_SAMPLES = {
    "/api/save-chain-presets": {"Hag's Curse": {"name": "Hag's Curse", "save_ability": "wis"}},
    "/api/lore-groups": [{"id": "hag-coven", "name": "Hag coven"}],
    "/api/treasure-table": {
        "individualBrackets": {},
        "hoardBrackets": {},
        "gems": {"50gp": ["Swamp pearl"]},
        "art": {},
        "magic": {},
    },
    "/api/treasure-profiles": {"Bog hoard": {"gems": 2, "art": 1}},
}


def put_preset_samples(page):
    for path, body in PRESET_SAMPLES.items():
        reply = api(page, "PUT", path, body)
        assert reply.status == 200, f"PUT {path} failed: {reply}"


def save_condition_preset(app, name):
    """Saves the Poisoned condition as a named preset the way a DM does."""
    app.panel("Condition/Effect").open()
    ConditionEditor(app).pick("Poisoned").save_preset(name, "Items")


def roll_d20(app):
    Dice(app).open().button("d20").click()
    settle(app.page)


def wait_for_saved_rolls(page, count):
    """Waits until the server holds this many of the signed-in DM's rolls."""
    deadline = time.monotonic() + 5
    saved = []
    while time.monotonic() < deadline:
        saved = api(page, "GET", "/api/dice/history").json()
        if len(saved) == count:
            return
        page.wait_for_timeout(50)
    pytest.fail(f"The server holds {len(saved)} rolls, not {count}.")


def signed_in_device(devices, label, email, name):
    """A second device that has signed in to an existing account."""
    device = devices.device(label)
    device.sign_in(email)
    wait_signed_in(device, name)
    settled_network(device.page)
    return device


def expect_dice_log(app, count):
    """Waits for the Dice Roller's log heading to count this many rolls."""
    expect(Dice(app).log_toggle()).to_have_text(re.compile(rf"Log \({count}\)"))


# Building and reading a fight in progress.


def build_mid_fight(app):
    """Two goblins and an ogre on the second goblin's turn.  The ogre is hurt.

    The ogre is poisoned and carries a three-turn timer named Web.
    """
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.begin_combat()
    app.next_turn()
    ManageHp(app).open_for("Ogre").damage(10)
    ConditionEditor(app).open_for("Ogre").pick("Poisoned").apply()
    start_timer(app, "Ogre", 3, label="Web")
    return fight_state(app)


def wait_for_cards(app, names):
    """Waits for the queue to hold these cards.

    The page shows its controls before the encounter fetch lands.  A reload is
    not done until the cards are.
    """
    expect(app.card_boxes()).to_have_count(len(names))
    assert app.card_names() == names


def fight_state(app):
    ogre = app.card("Ogre")
    return {
        "names": app.card_names(),
        "round": app.round_number(),
        "active": app.active_name(),
        "ogre_hp": ogre.hp(),
        "ogre_poisoned": ogre.root.get_by_role("button", name="Poisoned", exact=True).count() == 1,
        "ogre_timer": timer_words(app, "Ogre"),
    }


def timer_words(app, name):
    """The turns left and the label on a card's timer.

    One example is 3 Web.  This reads the words before the pill's Cancel button.
    """
    pill = timer_pill(app, name)
    if pill.count() == 0:
        return None
    words = pill.evaluate(
        "pill => Array.from(pill.children).slice(0, -1).map(c => c.textContent)"
    )
    return " ".join(words)


MID_FIGHT = {
    "names": ["Goblin Warrior", "Goblin Warrior 2", "Ogre"],
    "round": 1,
    "active": "Goblin Warrior 2",
    "ogre_hp": 58,
    "ogre_poisoned": True,
    "ogre_timer": "3 Web",
}
