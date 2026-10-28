"""Helpers for the session-prep scenarios.  In them a DM builds and saves.

The shared page objects cover the queue.  These cover the editors a DM opens
while preparing a session.  They also cover the Encounter menu in the app bar.
"""

import json
import re
import urllib.request

from playwright.sync_api import expect

from pages.app import settle

# The 2024 XP Budget per Character table.  Each row is Low, Moderate and High.
# The scenarios check the app's figures against this copy.  They never read
# the app's own.
XP_BUDGET = {
    1: (50, 75, 100),
    2: (100, 150, 200),
    3: (150, 225, 400),
    4: (250, 375, 500),
    5: (500, 750, 1100),
    6: (600, 1000, 1400),
    7: (750, 1300, 1700),
    8: (1000, 1700, 2100),
    9: (1300, 2000, 2600),
    10: (1600, 2300, 3100),
    11: (1900, 2900, 4100),
    12: (2200, 3700, 4700),
    13: (2600, 4200, 5400),
    14: (2900, 4900, 6200),
    15: (3300, 5400, 7800),
    16: (3800, 6100, 9800),
    17: (4500, 7200, 11700),
    18: (5000, 8700, 14200),
    19: (5500, 10700, 17200),
    20: (6400, 13200, 22000),
}

TIERS = ("Low", "Moderate", "High")


def party_budget(levels):
    """The party's Low, Moderate and High budgets.

    Each is summed per character.
    """
    return tuple(sum(XP_BUDGET[level][tier] for level in levels) for tier in range(3))


def number(text):
    """The first integer in a label such as 1,250 XP."""
    return int(re.search(r"-?[\d,]+", text).group().replace(",", ""))


def bundled_creatures(server):
    """The compendium an anonymous DM sees.  It is keyed by creature name."""
    with urllib.request.urlopen(server.base_url + "/bundled-creatures.json") as body:
        return {creature["name"]: creature for creature in json.load(body)}


def cr_value(cr):
    """A challenge rating such as 1/4 as a number."""
    whole, _, part = cr.partition("/")
    return int(whole) / int(part) if part else float(whole)


def pick_target(card):
    """Clicks an empty spot on a card.  That aims the editors at it."""
    box = card.root.bounding_box()
    card.root.click(position={"x": box["width"] * 0.6, "y": 10})
    settle(card.page)


def set_party(panel, levels):
    """Sets the party rows in a panel that edits the shared party."""
    rows = panel.root.get_by_role("combobox", name=re.compile("^Level for Player "))
    while rows.count() < len(levels):
        panel.root.get_by_role("button", name="+ Add character").click()
        settle(panel.page)
    while rows.count() > len(levels):
        panel.root.get_by_role("button", name="Remove character").last.click()
        settle(panel.page)
    for index, level in enumerate(levels):
        panel.root.get_by_role(
            "combobox", name=f"Level for Player {index + 1}", exact=True
        ).select_option(str(level))
    settle(panel.page)


# The Encounter menu.


def encounter_menu(page):
    return page.get_by_role("navigation").get_by_role(
        "button", name=re.compile("^Encounter")
    )


def open_encounter_dialog(page, item):
    """Opens Save or Load from the app bar and returns its dialog."""
    encounter_menu(page).click()
    menu = page.get_by_role("menu", name="Encounter")
    menu.get_by_role("menuitem", name=re.compile("^" + item)).click()
    dialog = page.get_by_role("dialog", name=f"{item} Encounter")
    expect(dialog).to_be_visible()
    return dialog


def has_unsaved_mark(page):
    return (
        encounter_menu(page)
        .get_by_role("img", name="Unsaved changes since the last save or load")
        .count()
        > 0
    )


# The Random Encounter panel.


def roll_random(panel):
    """Presses Generate or Reroll and returns the rolled groups and total.

    Each group is a count, a creature name, its XP and whether it is tagged
    a minion.  The result rows carry no list or row semantics.  This reads
    them by class.
    """
    panel.root.get_by_role("button", name=re.compile("^🎲 (Generate|Reroll)$")).click()
    settle(panel.page)
    rows = panel.root.locator(".random-encounter__group-row")
    groups = [
        (
            number(row.locator(".random-encounter__group-count").inner_text()),
            row.locator(".random-encounter__group-name")
            .evaluate("el => el.firstChild.textContent")
            .strip(),
            number(row.locator(".random-encounter__group-xp").inner_text()),
            row.locator(".random-encounter__group-minion-tag").count() > 0,
        )
        for row in rows.all()
    ]
    total = panel.root.locator(".random-encounter__total-value")
    return groups, (number(total.inner_text()) if total.count() else None)


def random_budget(panel):
    return number(panel.root.get_by_text(re.compile(r"^Budget: ")).inner_text())
