"""What a DM meets with a keyboard, a screen reader or the Accessible theme."""

import re

import pytest
from playwright.sync_api import expect

from pages.app import BEGIN_COMBAT, NEXT_TURN, settle_animations
from pages.ui import (
    Dice,
    axe_summary,
    axe_violations,
    choose_theme,
    focused,
    heading,
    six_creature_fight,
)



def busy_fight(app):
    """A fight in progress with the editors a DM keeps open."""
    six_creature_fight(app)
    app.next_turn()
    app.next_turn()
    Dice(app).open().roll("2d6+3")
    app.panel("Status").open()
    app.panel("Condition/Effect").open()
    app.card("Ogre").root.get_by_role("button", name="Show stat block").click()
    expect(app.page.locator(".card-statblock__body")).to_be_visible()
    # axe passes over text that a running scroll still hides.
    settle_animations(app.page)
    app.settle()


def show(app, where):
    if where == "empty encounter":
        app.goto("/")
    elif where == "busy encounter":
        app.goto("/")
        busy_fight(app)
    else:
        app.goto("/" + where)
    app.page.wait_for_load_state("networkidle")
    app.settle()


PAGES = ["empty encounter", "busy encounter", "login", "about", "compendium"]
THEMES = ["Modern", "Dark", "Accessible"]

MUTED = "QA-UI-05: muted grey text on panel headings and the footer is below 4.5:1"
NESTED = "QA-UI-05: every compendium row is a focusable control wrapping more controls"

# What axe found when this suite was written.  Each key is a page and a theme.
KNOWN = {
    ("empty encounter", "Modern"): MUTED,
    ("empty encounter", "Accessible"): "QA-UI-05: the + Max label is 2.48:1 even in the Accessible theme",
    ("busy encounter", "Modern"): MUTED + ", and the dice buttons and + Max too",
    ("busy encounter", "Dark"): "QA-UI-05: dice buttons, idle status toggles and stat block titles are below 4.5:1",
    ("busy encounter", "Accessible"): "QA-UI-05: + Max, dice buttons and stat block titles are below 4.5:1",
    ("login", "Modern"): MUTED,
    ("login", "Dark"): "QA-UI-05: the Sign in button's label is 3.08:1 on violet",
    ("about", "Modern"): MUTED,
    ("compendium", "Modern"): NESTED,
    ("compendium", "Dark"): NESTED,
    ("compendium", "Accessible"): NESTED,
}


def axe_case(where, theme):
    reason = KNOWN.get((where, theme))
    marks = [pytest.mark.xfail(strict=True, reason=reason)] if reason else []
    return pytest.param(where, theme, marks=marks, id=f"{where}-{theme}")


@pytest.mark.parametrize(
    "where,theme", [axe_case(where, theme) for where in PAGES for theme in THEMES]
)
def test_axe_finds_nothing_serious_or_critical(app, where, theme):
    choose_theme(app, theme)
    show(app, where)
    app.shot(f"{where}-{theme}")
    violations = axe_violations(app.page)
    print(f"\n{where} / {theme}:\n{axe_summary(violations)}")
    serious = [v for v in violations if v["impact"] in ("serious", "critical")]
    assert not serious, axe_summary(serious)


# Keyboard.


def tab_walk(app, steps):
    """Tabs on from the skip link and records each stop's name and ring."""
    # Manage HP takes focus on load.  See QA-UI-04.
    app.page.get_by_role("link", name="Skip to main content").focus()
    stops = []
    for _ in range(steps):
        app.page.keyboard.press("Tab")
        stops.append(focused(app.page) or {"tag": "BODY", "name": "", "ring": False})
    return stops


@pytest.mark.cross_browser
def test_tab_walks_the_app_bar_then_the_column_then_the_cards_in_order(app):
    app.add("Goblin Warrior", count=2)
    app.panel("Quick Add").fold()
    names = [stop["name"] for stop in tab_walk(app, 90)]

    def first(name):
        assert name in names, f"{name!r} was never reached:\n{names}"
        return names.index(name)

    assert (
        first("Go to the Encounter page")
        < first("Open settings")
        < first("Compendium (new tab)")
        < first("Begin combat \u2014 highest-initiative creature acts")
        < first("Fold this panel away, or open it back up")
        < first("Set the round number")
        < first("Select Goblin Warrior")
        < first("Current HP for Goblin Warrior")
        < first("Select Goblin Warrior 2")
    )


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-15: the app bar's title link shows no focus ring",
)
@pytest.mark.cross_browser
def test_every_tab_stop_shows_where_the_focus_is(app):
    app.add("Goblin Warrior")
    app.panel("Quick Add").fold()
    unringed = [stop["name"] for stop in tab_walk(app, 45) if not stop["ring"]]
    assert unringed == []


@pytest.mark.cross_browser
def test_a_dm_runs_turns_and_deals_damage_with_the_keyboard_alone(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.panel("Quick Add").fold()
    page = app.page
    page.get_by_role("link", name="Skip to main content").focus()
    for _ in range(25):
        page.keyboard.press("Tab")
        stop = focused(page)
        if stop and BEGIN_COMBAT.match(stop["name"]):
            break
    page.keyboard.press("Enter")
    app.settle()
    first = app.active_name()
    assert first is not None
    assert focused(page)["name"] == NEXT_TURN

    page.keyboard.press("Enter")
    app.settle()
    target = app.active_name()
    assert target not in (None, first)
    assert focused(page)["name"] == NEXT_TURN

    before = app.card(target).hp()
    for _ in range(3):
        page.keyboard.press("Tab")
    expect(page.get_by_label("HP:", exact=True)).to_be_focused()
    page.keyboard.type("3")
    page.keyboard.press("Enter")
    app.settle()
    assert app.card(target).hp() == before - 3
    app.shot("after-keyboard-damage")


@pytest.mark.cross_browser
def test_a_modal_takes_focus_and_keeps_tab_inside_it(app):
    trigger = app.page.get_by_role("button", name="Set the round number")
    trigger.focus()
    app.page.keyboard.press("Enter")
    dialog = app.page.get_by_role("dialog", name="Set Round")
    expect(dialog).to_be_visible()
    expect(dialog.get_by_role("button", name="Close")).to_be_focused()
    for _ in range(8):
        app.page.keyboard.press("Tab")
        assert dialog.evaluate("d => d.contains(document.activeElement)")
    app.page.keyboard.press("Escape")
    expect(dialog).to_have_count(0)


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-16: closing a modal drops focus to the page, not to the control that opened it",
)
@pytest.mark.cross_browser
def test_closing_a_modal_returns_focus_to_what_opened_it(app):
    trigger = app.page.get_by_role("button", name="Set the round number")
    trigger.focus()
    app.page.keyboard.press("Enter")
    expect(app.page.get_by_role("dialog", name="Set Round")).to_be_visible()
    app.page.keyboard.press("Escape")
    expect(trigger).to_be_focused(timeout=2000)


@pytest.mark.cross_browser
def test_the_settings_popover_works_from_the_keyboard(app):
    trigger = app.page.get_by_role("button", name="Open settings")
    trigger.focus()
    app.page.keyboard.press("Enter")
    expect(trigger).to_have_attribute("aria-expanded", "true")
    app.page.keyboard.press("Tab")
    expect(app.page.get_by_role("radio", name="Modern")).to_be_focused()
    app.page.keyboard.press("ArrowDown")
    expect(app.page.get_by_role("radio", name="Dark")).to_be_checked()
    expect(app.page.locator(".app-shell")).to_have_attribute("data-theme", "dark")
    app.page.keyboard.press("Tab")
    expect(app.page.get_by_role("radio", name="Beta")).to_be_focused()


# Accessible names.

NAMES_JS = "els => els.map(e => (e.getAttribute('aria-label') || e.textContent || '').trim())"


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-14: most card buttons, such as Remove, never say which creature they act on",
)
def test_every_card_button_names_its_creature(app):
    app.add("Goblin Warrior", count=2)
    names = app.card("Goblin Warrior 2").root.get_by_role("button").evaluate_all(NAMES_JS)
    vague = [name for name in names if "Goblin Warrior 2" not in name]
    assert vague == [], f"Card buttons that do not name their creature: {vague}"


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-14: every panel's fold and pin buttons share one name that omits the panel",
)
def test_every_panel_heading_button_names_its_panel(app):
    for title in ["Manage HP", "Dice Roller", "Quick Add"]:
        names = heading(app.panel(title)).get_by_role("button").evaluate_all(NAMES_JS)
        vague = [name for name in names if title.lower() not in name.lower()]
        assert vague == [], f"{title} heading buttons: {vague}"


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-14: the dice log's re-roll button is named only by its glyph",
)
def test_the_reroll_button_says_what_it_rerolls(app):
    dice = Dice(app).open()
    dice.roll("2d6+5")
    dice.wait_for_rows(1)
    names = dice.rows().nth(0).get_by_role("button").evaluate_all(NAMES_JS)
    assert all(re.search("roll", name, re.IGNORECASE) for name in names), names
