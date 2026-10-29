"""Initiative and turn-flow controls as a DM drives them at the table."""

import re

from playwright.sync_api import expect

from pages.app import ACTIVE_MARKER, settle
from pages.fight import ManageHp, hp_button, subtitle
from pages.ui import Dice

ROLL_ROW = "Roll & sort:"
APPLY_ROW = "Apply to:"


class Initiative:
    """The Initiative editor in the drawer column."""

    def __init__(self, app):
        self.app = app
        self.panel = app.panel("Initiative")
        self.root = self.panel.root

    def open(self):
        self.panel.open()
        return self

    def target(self):
        label = self.root.get_by_text(re.compile("^Target:")).inner_text()
        return label.removeprefix("Target:").strip()

    def mode(self, name):
        return self.root.get_by_role("radio", name=name, exact=True)

    def pick_mode(self, name):
        self.mode(name).click()
        settle(self.app.page)

    def row(self, lead):
        # The roll and apply rows repeat the same button names.  Each row is
        # a group named for its lead text.
        return self.root.get_by_role("group", name=lead.replace(":", ""), exact=True)

    def scope_button(self, lead, scope):
        name = re.compile("^Selected ") if scope == "Selected" else scope
        return self.row(lead).get_by_role("button", name=name, exact=scope != "Selected")

    def roll(self, scope="Target"):
        self.scope_button(ROLL_ROW, scope).click()
        settle(self.app.page)

    def field(self):
        return self.root.get_by_role("textbox", name="or Set:")

    def type_value(self, value):
        self.field().fill(str(value))

    def apply(self, value, scope="Target"):
        self.type_value(value)
        self.scope_button(APPLY_ROW, scope).click()
        settle(self.app.page)

    def quick_sort(self):
        self.root.get_by_role("button", name=re.compile("Quick Sort Encounter")).click()
        settle(self.app.page)


INITIATIVE_ROLL = re.compile(
    r"^(?:▶ )?Initiative → (?P<name>.+?) (?:(?P<mode>Adv|Dis): )?1d20(?P<bonus>[+-]\d+)?: "
    r"\((?P<dice>[^)]*)\)\S* = (?P<total>-?\d+)"
)


def initiative_rolls(app):
    """The initiative rolls in the dice log.  The newest comes first.

    Each is a dict of the creature, the mode, the bonus, the faces and the
    total.  A dropped die is the one in brackets.
    """
    roller = Dice(app).open()
    lines = [" ".join(t.split()) for t in roller.root.get_by_role("listitem").all_inner_texts()]
    matches = [INITIATIVE_ROLL.match(line) for line in lines]
    return [
        {
            "name": m["name"],
            "mode": m["mode"],
            "bonus": int(m["bonus"] or 0),
            "faces": [int(f.strip("[]")) for f in m["dice"].split(",")],
            "total": int(m["total"]),
        }
        for m in matches
        if m
    ]


def round_dialog(app):
    return app.page.get_by_role("dialog", name="Set Round")


def open_round_setter(app):
    app.page.get_by_role("button", name="Set the round number").click()
    expect(round_dialog(app)).to_be_visible()
    return round_dialog(app)


def manage_hp_target(app):
    return subtitle(app.panel("Manage HP"))


def press_manage_hp(app, verb, amount):
    """Presses a Manage HP verb on whatever the editor is aimed at."""
    ManageHp(app).apply(verb, amount)


def timer_pill(app, name):
    return app.card(name).root.locator(".timer-pill")


def open_timer(app, name):
    app.card(name).root.get_by_role("button", name="Set timer").click()
    form = app.card(name).root
    expect(form.get_by_role("spinbutton", name="Timer lasts")).to_be_visible()
    return form


def fill_timer(form, turns, phase, label):
    """Fills a timer form.  Without a phase it keeps the default."""
    form.get_by_role("spinbutton", name="Timer lasts").fill(str(turns))
    if phase:
        # The radio is hidden from sight.  A pointer clicks its label.
        form.locator(".cond-phase").filter(has_text=phase).click()
    form.get_by_role("textbox", name="Label").fill(label)


def start_timer(app, name, turns, phase=None, label=""):
    """Starts a timer on a card."""
    form = open_timer(app, name)
    fill_timer(form, turns, phase, label)
    form.get_by_role("button", name="Start Timer").click()
    expect(timer_pill(app, name)).to_be_visible()


def initiative_badge(app, name):
    return app.card(name).root.get_by_role("button", name=re.compile("^Initiative "))


def open_initiative_for(app, name):
    initiative_badge(app, name).click()
    settle(app.page)
    editor = Initiative(app)
    expect(editor.root.get_by_text(f"Target: {name}", exact=True)).to_be_visible()
    return editor


def set_initiative(app, name, value):
    open_initiative_for(app, name).apply(value)
    expect(initiative_badge(app, name)).to_have_text(f"({value})")


def set_initiatives(app, values):
    for name, value in values.items():
        set_initiative(app, name, value)


def initiatives(app):
    """Each creature's name and initiative.  The order is the queue's."""
    return dict(zip(app.card_names(), [app.card(n).initiative() for n in app.card_names()]))


def turn_arrow(app, name):
    return app.card(name).root.get_by_role(
        "button",
        name=re.compile(
            f"^(Make {re.escape(name)} the active creature|It is {re.escape(name)}'s turn)$"
        ),
    )


def make_active(app, name):
    turn_arrow(app, name).click()
    settle(app.page)


def inactive_toggle(app, name):
    return app.card(name).root.get_by_role("button", name="Toggle inactive")


def toggle_inactive(app, name):
    inactive_toggle(app, name).click()
    settle(app.page)


def change_hp(app, name, verb, amount):
    """Damages or heals a creature through Manage HP.  Its card aims it."""
    ManageHp(app).open_for(name).apply(verb, amount)


def knock_down(app, name):
    change_hp(app, name, "Damage", 999)
    expect(hp_button(app.card(name), "Current")).to_have_text("0")


def heal(app, name, amount):
    change_hp(app, name, "Heal", amount)


def mark_dead(app, name):
    knock_down(app, name)
    app.card(name).root.get_by_role("button", name=f"Mark {name} dead").click()
    settle(app.page)


def reaction(app, name):
    return app.card(name).root.get_by_role("button", name=re.compile("^Reaction "))


def readied(app, name):
    return app.card(name).root.get_by_role(
        "button", name=re.compile("^(Ready an Action|Action Readied)$")
    )


def turn_order(app, turns):
    """Advances the given number of turns.

    It returns the round and the active creature after each.
    """
    seen = []
    for _ in range(turns):
        app.next_turn()
        seen.append((app.round_number(), app.active_name()))
    return seen


def drag_card(app, moving, onto, half):
    """Drops one card on the upper or lower half of another."""
    target = app.card(onto).root
    box = target.bounding_box()
    y = box["height"] * (0.2 if half == "upper" else 0.8)
    app.card(moving).root.drag_to(target, target_position={"x": box["width"] / 2, "y": y})
    settle(app.page)


def strip(app, label):
    """One of the reminder strips above the queue.  Its label finds it."""
    return app.page.get_by_role("note").filter(has_text=re.compile("^" + re.escape(label) + ":"))


def quick_view(app):
    return app.page.get_by_role("region", name="Quick view")


def encounter_body(app):
    return app.page.locator("#encounter-panel-body")


CARD_IN_VIEW = """([id, slack]) => {
    const body = document.getElementById('encounter-panel-body').getBoundingClientRect();
    const card = document.getElementById(id).getBoundingClientRect();
    return card.top >= body.top - 1 && card.bottom <= body.bottom + 1
        && card.top - body.top <= slack;
}"""


def card_is_in_view(app, name):
    """Whether the card sits wholly inside the scrolling queue."""
    card_id = app.card(name).root.evaluate("el => el.id")
    return app.page.evaluate(f"({CARD_IN_VIEW})", [card_id, 100000])


def wait_until_card_in_view(app, name, near_top=False):
    """Waits for the queue to scroll the card into view.

    With near_top the card must also sit within 40 pixels of the top of
    the queue.  The app leaves a 16 pixel margin there.
    """
    card_id = app.card(name).root.evaluate("el => el.id")
    app.page.wait_for_function(
        f"({CARD_IN_VIEW})", arg=[card_id, 40 if near_top else 100000], timeout=5000
    )


def scroll_queue_to_top(app):
    encounter_body(app).evaluate("el => { el.scrollTop = 0 }")
    settle(app.page)
