"""The encounter page as a DM drives it.

Scenarios speak in a DM's verbs, such as add a creature or start the fight.
The locators here find controls by their accessible names, so a control a
screen reader cannot name is also one these helpers cannot find.
"""

import re

from playwright.sync_api import expect

NEXT_TURN = "Advance to next creature in initiative order"
ACTIVE_MARKER = "It is this creature's turn"
DM = "dm@example.test"
PASSWORD = "correct horse battery staple"
BEGIN_COMBAT = re.compile("^Begin combat")


def settle(page):
    """Waits until Elm has drawn the view an action produced.

    Elm renders on the animation frame after a message.  Two frames cover a
    message that a first render's effect sends.
    """
    page.evaluate(
        "() => new Promise(done => requestAnimationFrame("
        "() => requestAnimationFrame(done)))"
    )


def settle_animations(page):
    """Waits for fades, slides and the page's other finite animations."""
    page.evaluate(
        "() => Promise.all(document.getAnimations()"
        ".filter(a => a.effect && a.effect.getTiming().iterations !== Infinity)"
        ".map(a => a.finished.catch(() => null)))"
    )


class App:
    def __init__(self, page, server, shots_dir):
        self.page = page
        self.server = server
        self.shots_dir = shots_dir
        self.shot_count = 0
        self.page_errors = []
        page.on("pageerror", lambda error: self.page_errors.append(str(error)))

    def goto(self, path="/"):
        self.page.goto(self.server.base_url + path)
        if path == "/":
            self.wait_ready()

    def wait_ready(self):
        expect(self.page.get_by_role("button", name="Quick Add", exact=True)).to_be_visible()

    def reload(self):
        self.page.reload()
        self.wait_ready()

    def settle(self):
        settle(self.page)

    def sign_up(self, email=DM, password=PASSWORD, name="Test DM"):
        """Registers an account and reloads the page signed in.

        It goes through the API, which shares the page's cookies.  The
        account scenarios drive the sign-up form itself.
        """
        response = self.page.request.post(
            self.server.base_url + "/api/auth/register",
            data={"email": email, "password": password, "display_name": name},
        )
        assert response.ok, f"Sign-up failed: {response.status} {response.text()}"
        self.reload()

    def sign_in(self, email=DM, password=PASSWORD):
        """Signs in to an existing account and reloads the page signed in."""
        response = self.page.request.post(
            self.server.base_url + "/api/auth/login",
            data={"email": email, "password": password},
        )
        assert response.ok, f"Sign-in failed: {response.status} {response.text()}"
        self.reload()

    def beside(self, page, label):
        """Another page on the same server.  Its screenshots go beside these."""
        shots = self.shots_dir.parent / f"{self.shots_dir.name}--{label}"
        return App(page, self.server, shots)

    def shot(self, step):
        """Saves a full-page screenshot for the human pass over the run."""
        self.shot_count += 1
        self.shots_dir.mkdir(parents=True, exist_ok=True)
        path = self.shots_dir / f"{self.shot_count:02d}-{step}.png"
        self.page.screenshot(path=str(path), full_page=True)
        return path

    # The editor column.

    def panel(self, title):
        return Panel(self.page, title)

    # Building the encounter.

    def add(self, name, count=1):
        """Adds count copies of a compendium creature through Quick Add."""
        quick_add = self.panel("Quick Add").open()
        search = quick_add.root.get_by_role("searchbox", name="Filter Quick Add by name")
        search.fill(name)
        row = quick_add.root.get_by_role(
            "button", name=re.compile("^" + re.escape(name) + " CR ")
        )
        for _ in range(count):
            row.click()
        search.fill("")
        self.settle()

    def add_placeholder(self):
        quick_add = self.panel("Quick Add").open()
        quick_add.root.get_by_role("button", name="Add placeholder").click()
        self.settle()

    def card(self, name):
        return Card(self.page, name)

    def card_boxes(self):
        """Each card's select box in queue order."""
        return self.page.get_by_role("article").get_by_role(
            "checkbox", name=re.compile("^Select ")
        )

    def card_names(self):
        """Creature names in queue order."""
        return [
            label.removeprefix("Select ")
            for label in self.card_boxes().evaluate_all(
                "els => els.map(e => e.getAttribute('aria-label'))"
            )
        ]

    # Running the fight.

    def begin_combat(self):
        self.page.get_by_role("button", name=BEGIN_COMBAT).click()
        self.settle()

    def next_turn(self):
        self.page.get_by_role("button", name=NEXT_TURN).click()
        self.settle()

    def round_number(self):
        label = self.page.get_by_role("button", name="Set the round number").inner_text()
        return int(re.search(r"\d+", label).group())

    def active_name(self):
        """The creature whose turn it is, or None before the fight starts."""
        marker = self.page.get_by_role("button", name=ACTIVE_MARKER)
        if marker.count() == 0:
            return None
        card = self.page.get_by_role("article").filter(has=marker)
        label = card.get_by_role("checkbox", name=re.compile("^Select ")).get_attribute(
            "aria-label"
        )
        return label.removeprefix("Select ")


class Panel:
    """One editor in the drawer column, found by its title."""

    def __init__(self, page, title):
        self.page = page
        self.title = title
        self.root = page.locator("section.panel--drawer").filter(
            has=page.locator(
                ".panel__title--drawer", has_text=re.compile("^" + re.escape(title))
            )
        )

    def fold_button(self):
        return self.root.get_by_role(
            "button", name="Fold this panel away, or open it back up"
        )

    def is_open(self):
        return self.fold_button().get_attribute("aria-expanded") == "true"

    def open(self):
        if not self.is_open():
            self.fold_button().click()
        expect(self.fold_button()).to_have_attribute("aria-expanded", "true")
        return self

    def fold(self):
        if self.is_open():
            self.fold_button().click()
        expect(self.fold_button()).to_have_attribute("aria-expanded", "false")
        return self

    def pin_button(self):
        return self.root.get_by_role("button", name=re.compile("^(Pin to|Unpin from) the top"))

    def is_pinned(self):
        return self.pin_button().get_attribute("aria-pressed") == "true"

    def toggle_pin(self):
        self.pin_button().click()
        settle(self.page)
        return self


class Card:
    """One creature's card in the initiative queue."""

    def __init__(self, page, name):
        self.page = page
        self.name = name
        self.root = page.get_by_role("article").filter(
            has=page.get_by_role("checkbox", name=f"Select {name}", exact=True)
        )

    def hp(self):
        return int(
            self.root.get_by_role("button", name=f"Current HP for {self.name}").inner_text()
        )

    def max_hp(self):
        return int(
            self.root.get_by_role("button", name=f"Max HP for {self.name}").inner_text()
        )

    def ac(self):
        return int(
            self.root.get_by_role(
                "button", name=re.compile(f"^Armor Class \\d+ for {re.escape(self.name)},")
            ).inner_text()
        )

    def initiative(self):
        label = self.root.get_by_role("button", name=re.compile("^Initiative ")).inner_text()
        return int(re.search(r"-?\d+", label).group())

    def checkbox(self):
        return self.root.get_by_role("checkbox", name=f"Select {self.name}", exact=True)

    def select(self, shift=False):
        """Clicks the card's checkbox.  With shift it selects or clears all."""
        box = self.checkbox()
        was = box.is_checked()
        # The app cancels the native toggle and draws the box itself a frame
        # later.  Playwright's check() reads that as a failed click.
        box.click(modifiers=["Shift"] if shift else None)
        settle(self.page)
        if not shift:
            expect(box).to_be_checked(checked=not was)

    def remove(self):
        self.root.get_by_role("button", name="Remove", exact=True).click()
        settle(self.page)
