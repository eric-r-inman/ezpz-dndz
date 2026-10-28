"""The table-side editors a DM drives during a fight."""

import re

from playwright.sync_api import expect

from pages.app import settle

# Elm seeds every single roll from the millisecond clock.  A fixed
# clock therefore fixes the die.  These instants were found by
# replaying elm/random's generator for a plain 1d20 or 1d6.
D20_FACE_AT = {
    20: "2027-01-01T00:00:00.023Z",
    1: "2027-01-01T00:00:00.017Z",
    10: "2027-01-01T00:00:00.015Z",
    9: "2027-01-01T00:00:00.008Z",
}

D6_FACE_AT = {
    6: "2027-01-01T00:00:00.003Z",
    2: "2027-01-01T00:00:00.005Z",
}


def fix_d20(app, face):
    """Makes the next single d20 roll land on `face`."""
    app.page.clock.set_fixed_time(D20_FACE_AT[face])


def fix_d6(app, face):
    """Makes the next single d6 roll land on `face`."""
    app.page.clock.set_fixed_time(D6_FACE_AT[face])


def freeze_clock(app):
    """Stops the clock.  Rolls fired together then share one seed.

    Rolls the app draws from one generator still come out independent.  Rolls
    that each seed themselves come out identical.  That holds however slowly the
    browser runs.
    """
    app.page.clock.set_fixed_time("2027-01-01T00:00:00.000Z")


def select(app, *names):
    for name in names:
        app.card(name).select()


def hp_button(card, which):
    """`which` is Current, Max or Temp."""
    return card.root.get_by_role("button", name=f"{which} HP for {card.name}", exact=True)


def expect_pools(card, hp, max_hp, temp=0):
    expect(hp_button(card, "Current")).to_have_text(str(hp))
    expect(hp_button(card, "Max")).to_have_text(str(max_hp))
    if temp:
        expect(hp_button(card, "Temp")).to_have_text(f"+{temp}")
    else:
        expect(hp_button(card, "Temp")).to_have_count(0)


def clear(field):
    if field.input_value():
        field.fill("")


def lifecycle_badge(card):
    """The DOWN or DEAD pill on the card's top border."""
    return card.root.get_by_role("button", name=re.compile(f"^Mark {re.escape(card.name)} "))


def begin_death_saves(card):
    """Opts a downed creature into death saves and waits for the pips."""
    card.root.get_by_role("button", name="Begin death saving throws").click()
    expect(card.root.get_by_role("group", name="Death saving throws")).to_be_visible()


def advance(app, turns):
    for _ in range(turns):
        app.next_turn()


def fold_toggle(panel, title):
    """A section's fold button.  Its name carries its caret."""
    return panel.root.get_by_role("button", name=re.compile(f"^[▶▼] {re.escape(title)}"))


def unfold(panel, title):
    toggle = fold_toggle(panel, title)
    if toggle.get_attribute("aria-expanded") != "true":
        toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "true")


def log_rows(panel):
    """The panel's log rows as text.  The newest comes first."""
    unfold(panel, "Log")
    # The raw text.  The stylesheet upper-cases the kind label.
    return [
        " ".join(text.split())
        for text in panel.root.locator(".hp-change__log-text").all_text_contents()
    ]


def readout(card, what):
    """A legendary pool's button.

    `what` is Legendary Action or Legendary Resistance.
    """
    return card.root.get_by_role("button", name=re.compile(f"^{what}: "))


def recharge_chip(card, ability):
    """A recharge ability's chip.  Its name says whether it is ready."""
    return card.root.get_by_role("button", name=re.compile(f"^{re.escape(ability)} — Recharge"))


def undo(panel):
    """Presses Undo on the newest row of a panel's log."""
    unfold(panel, "Log")
    panel.root.get_by_role("button", name=re.compile("^Undo ")).click()
    settle(panel.page)


def subtitle(panel):
    return panel.root.get_by_text(re.compile("^Target:"))


class ManageHp:
    def __init__(self, app):
        self.app = app
        self.panel = app.panel("Manage HP")
        self.root = self.panel.root

    def open_for(self, name):
        hp_button(self.app.card(name), "Current").click()
        expect(subtitle(self.panel)).to_have_text(f"Target: {name}")
        return self

    def amount_field(self):
        return self.root.get_by_role("spinbutton", name="HP:")

    def roll_field(self):
        return self.root.get_by_role("textbox", name="or Roll:")

    def verb(self, label):
        return self.root.get_by_role("button", name=label, exact=True)

    def apply(self, label, amount):
        """Types `amount` and clicks the verb.

        A formula goes in the Roll field and a number in the HP field.
        """
        text = str(amount)
        # Each field greys out while the other holds text.
        if "d" in text:
            clear(self.amount_field())
            self.roll_field().fill(text)
        else:
            clear(self.roll_field())
            self.amount_field().fill(text)
        self.verb(label).click()
        settle(self.app.page)
        return self

    def damage(self, amount):
        return self.apply("Damage", amount)

    def heal(self, amount):
        return self.apply("Heal", amount)

    def temp(self, amount):
        return self.apply("+ Temp", amount)

    def raise_max(self, amount):
        return self.apply("+ Max", amount)

    def scope_selected(self, count):
        box = self.root.get_by_role("checkbox", name=f"Selected ({count})")
        box.click()
        expect(box).to_be_checked()

    def fresh_rolls(self):
        box = self.root.get_by_role("checkbox", name="New roll for each creature")
        box.click()
        expect(box).to_be_checked()

    def reset(self):
        self.root.get_by_role("button", name="Reset to Default").click()
        settle(self.app.page)

    def undo(self):
        undo(self.panel)

    def log(self):
        return log_rows(self.panel)

    def open_set(self):
        unfold(self.panel, "Set HP")
        return self

    def set_field(self, label):
        return self.root.get_by_label(label, exact=True)

    def set_pools(self, hp=None, max_hp=None, temp=None):
        self.open_set()
        wanted = {
            "Set HP to:": hp,
            "Set Max HP to:": max_hp,
            "Set Temp HP to:": temp,
        }
        for label, value in wanted.items():
            if value is None:
                clear(self.set_field(label))
        for label, value in wanted.items():
            if value is not None:
                self.set_field(label).fill(str(value))
        self.root.get_by_role("button", name=re.compile("^Target")).click()
        settle(self.app.page)


class ConditionEditor:
    def __init__(self, app):
        self.app = app
        self.panel = app.panel("Condition/Effect")
        self.root = self.panel.root

    def open_for(self, name):
        self.app.card(name).root.get_by_role(
            "button", name=f"Open status and conditions for {name}"
        ).click()
        expect(subtitle(self.panel)).to_have_text(f"Target: {name}")
        return self

    def pick(self, condition):
        self.root.get_by_role("radio", name=re.compile(f"^{re.escape(condition)}")).click()
        expect(self.root.get_by_role("radio", name=re.compile(f"^{re.escape(condition)}"))).to_be_checked()
        # A fill sent before Elm redraws lands in a field that is gone.
        # The browser checks the radio first.  The redraw hides the
        # Custom row and rebuilds the Note field.
        settle(self.app.page)
        return self

    def custom(self, name):
        # The Custom: label is not tied to its field.
        self.root.get_by_placeholder("e.g. Burning").fill(name)
        return self

    def note(self, text):
        # The Note: label is not tied to its field.
        self.root.get_by_placeholder("e.g. from Lyra").fill(text)
        return self

    def duration(self, kind):
        """`kind` is Manual, Next turn, Countdown or 1 Minute."""
        row = self.root.locator(".cond-row").filter(has_text="Duration:")
        row.get_by_role("radio", name=kind, exact=True).click()
        return self

    def phase(self, word):
        """`word` is beginning or end.  It acts on the duration row on show."""
        # The phase radios are display: none.  Only their labels can be
        # reached.  Only a pointer reaches them.
        self.root.locator(".cond-subsection").get_by_text(word, exact=True).click()
        return self

    def turns_of(self, name):
        # The creature picker sits between plain-text labels and has no
        # accessible name.
        self.root.locator(".cond-subsection select.cond-select").select_option(name)
        return self

    def countdown(self, turns):
        self.root.get_by_label("Lasts").fill(str(turns))
        return self

    def save_to_end(self, ability="WIS", dc=10, auto="Manual"):
        box = self.root.get_by_role("checkbox", name="Saving throw to end")
        if not box.is_checked():
            box.click()
        expect(box).to_be_checked()
        self.root.get_by_label("Ability").select_option(ability)
        self.root.get_by_label("DC", exact=True).fill(str(dc))
        self.root.get_by_label("Mod", exact=True).fill("0")
        self.auto_roll(auto)
        return self

    def auto_roll(self, label):
        # Two radio groups here share the name Manual.  Neither has a group
        # label.  The row is found by its text.
        row = self.root.locator(".cond-row").filter(has_text="Auto-roll:")
        row.get_by_role("radio", name=label, exact=True).click()
        return self

    def on_fail(self, damage=None, becomes=None):
        if damage is not None:
            self.root.get_by_label("takes", exact=True).fill(str(damage))
        if becomes is not None:
            self.root.get_by_label("& becomes").fill(becomes)
        return self

    def when_damaged(self, label):
        row = self.root.locator(".cond-row").filter(has_text="When damaged:")
        row.get_by_role("radio", name=label, exact=True).click()
        return self

    def apply(self, scope="Target"):
        self.root.get_by_role("button", name=re.compile(f"^{re.escape(scope)}")).click()
        settle(self.app.page)
        return self

    def log(self):
        return log_rows(self.panel)

    def undo(self):
        undo(self.panel)

    def save_preset(self, name, category):
        """Saves the form as a named preset in a category."""
        self.root.get_by_role("button", name="Save Settings").click()
        modal = self.app.page.get_by_role("dialog")
        modal.get_by_placeholder("Name this preset").fill(name)
        modal.get_by_label("Category:").select_option(category)
        modal.get_by_role("button", name="Save new preset").click()
        expect(modal).to_have_count(0)
        settle(self.app.page)
        return self

    def load_menu(self):
        button = self.root.get_by_role("button", name="Load ▼")
        if button.get_attribute("aria-expanded") != "true":
            button.click()
        expect(button).to_have_attribute("aria-expanded", "true")
        return self.root.get_by_role("listbox")


class SaveChain:
    def __init__(self, app):
        self.app = app
        self.panel = app.panel("Save Chain").open()
        self.root = self.panel.root

    def row(self, label):
        return self.root.locator(".cond-row").filter(has_text=label)

    def preset_picker(self):
        # The preset picker's label is not tied to it.
        return self.root.get_by_role("combobox").first

    def name(self, text):
        self.root.get_by_placeholder("e.g. Hold Person").fill(text)
        return self

    def ability(self, label):
        self.root.get_by_role("radio", name=label, exact=True).click()
        return self

    def dc(self, value):
        # The DC field has no accessible name.
        self.row("DC:").locator("input").fill(str(value))
        return self

    def area(self, label):
        self.row("Area:").get_by_role("radio", name=label, exact=True).click()
        return self

    def side(self, heading):
        """One outcome section.  Its heading finds it."""
        return self.root.locator(".cond-section").filter(
            has=self.app.page.get_by_role("heading", name=heading)
        )

    def hp(self, heading, kind, amount=None):
        side = self.side(heading)
        side.get_by_role("radio", name=kind, exact=True).click()
        if amount is not None:
            side.get_by_placeholder("12 or 2d6+3").fill(str(amount))
        return self

    def add_effect(self, heading, name, save_to_end=False):
        side = self.side(heading)
        side.get_by_role("button", name="+ Add effect").click()
        effect = side.locator(".cond-subsection").last
        effect.get_by_placeholder("condition or effect name").fill(name)
        if save_to_end:
            effect.get_by_role("checkbox", name="Save-to-end").click()
        return effect

    def scope_selected(self, count):
        box = self.root.get_by_role("checkbox", name=f"Apply to all selected creatures ({count})")
        box.click()
        expect(box).to_be_checked()
        return self

    def button(self, label):
        return self.root.get_by_role("button", name=label, exact=True)

    def press(self, label):
        self.button(label).click()
        settle(self.app.page)
        return self

    def log(self):
        """Each row as its side, target, roll note and what landed."""
        unfold(self.panel, "Log")
        rows = self.root.locator(".save-chain__log-entry")
        return [
            tuple(
                " ".join(part.split())
                for part in rows.nth(i).locator(":scope > span").all_text_contents()
            )
            for i in range(rows.count())
        ]


def chip(card, label):
    """A condition chip.  The text its name button shows finds it."""
    return card.root.locator(".condition-chip").filter(
        has=card.page.get_by_role("button", name=label, exact=True)
    )


def chip_names(card):
    # Condition chips have no list role or group label.  A reader cannot
    # step through them as a set.
    return [
        " ".join(text.split())
        for text in card.root.locator(".condition-chip__name").all_inner_texts()
    ]
