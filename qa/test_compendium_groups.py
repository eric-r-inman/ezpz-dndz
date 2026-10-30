"""Session prep with compendium groups and Lore groupings.

A group bundles creatures that join the encounter together.  It holds counts,
minion hit points and one initiative rule.  A Lore grouping rolls its member
counts when the DM adds it.
"""

import re

import pytest
from playwright.sync_api import expect

from pages import compendium as library
from pages.compendium import create_group, group_row


# Groups.


def test_group_lists_its_total_count_initiative_rule_and_entries(app, tab):
    create_group(
        tab,
        "Goblin Patrol",
        [("Goblin Warrior", 3, "Minion (1 HP)"), ("Ogre", 1)],
        initiative="Shared rolled",
    )
    row = group_row(tab, "Goblin Patrol")
    expect(row).to_contain_text("4 creatures · Shared rolled")

    row.get_by_role("button", name="Toggle group entries").click()
    expect(row.get_by_role("button", name="Toggle group entries")).to_have_attribute(
        "aria-expanded", "true"
    )
    expect(tab.page.get_by_text("3 × Goblin Warrior", exact=True)).to_be_visible()

    row.click()
    detail = tab.page.locator(".compendium__detail")
    expect(detail).to_contain_text("Initiative: Shared rolled")
    expect(detail).to_contain_text("3 × Goblin Warrior · Minion (1 HP)")
    expect(detail).to_contain_text("1 × Ogre")
    tab.shot("group-detail")

    groups_chip = tab.kind_chip("Groups")
    groups_chip.click()
    expect(groups_chip).to_have_attribute("aria-pressed", "false")
    expect(row).to_have_count(0)
    groups_chip.click()
    expect(row).to_be_visible()


def test_adding_a_group_spawns_every_member_with_minion_hp_and_one_initiative(app, tab):
    create_group(
        tab,
        "Goblin Patrol",
        [("Goblin Warrior", 3, "Minion (1 HP)"), ("Ogre", 1, "Minion (½ HP)")],
        initiative="Shared rolled",
    )
    group_row(tab, "Goblin Patrol").click()
    tab.button("➕ Add Group to Encounter").click()
    expect(tab.toast("Added group: 4 creatures")).to_be_visible()

    expect(app.card_boxes()).to_have_count(4)
    assert sorted(app.card_names()) == [
        "Goblin Warrior",
        "Goblin Warrior 2",
        "Goblin Warrior 3",
        "Ogre",
    ]
    assert [app.card(f).max_hp() for f in ["Goblin Warrior", "Goblin Warrior 2"]] == [1, 1]
    assert app.card("Ogre").max_hp() == 34
    initiatives = {app.card(name).initiative() for name in app.card_names()}
    assert len(initiatives) == 1
    app.shot("group-in-encounter")


def test_shared_manual_initiative_puts_every_member_on_that_count(app, tab):
    create_group(
        tab, "Ogre Pair", [("Ogre", 2)], initiative="Shared manual", manual=15
    )
    group_row(tab, "Ogre Pair").click()
    expect(tab.page.locator(".compendium__detail")).to_contain_text(
        "Initiative: Shared manual (15)"
    )
    tab.button("➕ Add Group to Encounter").click()
    expect(app.card_boxes()).to_have_count(2)
    assert [app.card(name).initiative() for name in ["Ogre", "Ogre 2"]] == [15, 15]


def test_each_rolls_initiative_adds_each_creatures_initiative_bonus(app, tab):
    create_group(tab, "Goblin Patrol", [("Goblin Warrior", 3)], initiative="Each rolls")
    group_row(tab, "Goblin Patrol").click()
    tab.button("➕ Add Group to Encounter").click()
    expect(app.card_boxes()).to_have_count(3)
    rolls = (tab.local("diceHistory") or [])[:3]
    assert len(rolls) == 3
    for roll in rolls:
        face = roll["groups"][0]["rolled"][0]["face"]
        assert roll["total"] == face + 2


def test_group_from_selected_starts_with_the_checked_creatures(tab):
    tab.check("Goblin Warrior")
    tab.check("Ogre")
    tab.button("👥 Create Group w/Selected (2)").click()
    pane = tab.editor()
    pickers = pane.get_by_role("combobox", name="Creature")
    expect(pickers).to_have_count(2)
    chosen = sorted(
        picker.evaluate("el => el.options[el.selectedIndex].text")
        for picker in pickers.all()
    )
    assert chosen == ["Goblin Warrior", "Ogre"]
    pane.get_by_label("Name").fill("Odd Couple")
    pane.get_by_role("button", name="Create Group", exact=True).click()
    expect(group_row(tab, "Odd Couple")).to_contain_text("2 creatures")


def test_editing_a_group_changes_its_entries(tab):
    create_group(tab, "Goblin Patrol", [("Goblin Warrior", 3), ("Ogre", 1)])
    group_row(tab, "Goblin Patrol").click()
    tab.button("✏️ Edit").click()
    pane = tab.editor()
    expect(pane.get_by_role("heading", name="👥 Edit Group")).to_be_visible()
    counts = pane.get_by_role("spinbutton", name="Instance count")
    expect(counts).to_have_count(2)
    counts.first.fill("5")
    expect(counts.first).to_have_value("5")
    pane.get_by_role("button", name="Remove entry").last.click()
    expect(counts).to_have_count(1)
    pane.get_by_role("button", name="Save Group", exact=True).click()
    expect(pane).to_be_hidden()
    expect(group_row(tab, "Goblin Patrol")).to_contain_text("5 creatures · Each rolls")


def test_group_editor_names_what_is_missing(tab):
    tab.button("👥 Create Group").click()
    pane = tab.editor()
    create = pane.get_by_role("button", name="Create Group", exact=True)
    create.click()
    expect(pane.get_by_text("Name is required.")).to_be_visible()

    pane.get_by_label("Name").fill("Empty Patrol")
    create.click()
    expect(pane.get_by_text("Add at least one creature to the group.")).to_be_visible()

    pane.get_by_role("button", name="+ Add Entry").click()
    create.click()
    expect(pane.get_by_text("Pick a creature for every row.")).to_be_visible()

    pane.get_by_role("combobox", name="Creature").select_option(label="Ogre")
    pane.get_by_role("spinbutton", name="Instance count").fill("0")
    create.click()
    expect(pane.get_by_text("Each entry must have at least 1 instance.")).to_be_visible()
    expect(group_row(tab, "Empty Patrol")).to_have_count(0)


def test_deleting_a_group_removes_it(tab):
    create_group(tab, "Goblin Patrol", [("Goblin Warrior", 2)])
    group_row(tab, "Goblin Patrol").click()
    tab.page.get_by_role("button", name="Delete group").click()
    tab.button("Delete").click()
    expect(tab.toast('Deleted group "Goblin Patrol".')).to_be_visible()
    expect(group_row(tab, "Goblin Patrol")).to_have_count(0)


def test_deleting_a_group_asks_first(tab):
    create_group(tab, "Goblin Patrol", [("Goblin Warrior", 2)])
    group_row(tab, "Goblin Patrol").click()
    tab.page.get_by_role("button", name="Delete group").click()
    tab.settle()
    expect(group_row(tab, "Goblin Patrol")).to_be_visible(timeout=1000)


def test_signed_in_group_lives_on_the_server(app, signed_in_tab):
    tab = signed_in_tab
    create_group(tab, "Goblin Patrol", [("Goblin Warrior", 3)])
    assert [group["name"] for group in library.server_groups(app.page)] == ["Goblin Patrol"]

    tab.page.reload()
    tab.wait_ready()
    expect(group_row(tab, "Goblin Patrol")).to_contain_text("3 creatures")

    group_row(tab, "Goblin Patrol").click()
    tab.page.get_by_role("button", name="Delete group").click()
    tab.button("Delete").click()
    expect(tab.toast('Deleted group "Goblin Patrol".')).to_be_visible()
    assert library.server_groups(app.page) == []


# Lore groupings.


def lore_row(tab, name):
    return tab.page.locator(".compendium__row--lore").filter(
        has=tab.page.get_by_role("button", name=re.compile("^(?:📖|🔒) " + re.escape(name) + " "))
    )


def lore_section(tab):
    toggle = tab.page.get_by_role("button", name="Toggle Lore groupings", exact=True)
    if toggle.get_attribute("aria-expanded") != "true":
        toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "true")


def lore_member(dialog, creature, low, high):
    search = dialog.get_by_placeholder("🔍 Search a creature to add…")
    search.fill(creature)
    dialog.get_by_role("button", name=re.compile("^" + re.escape(creature) + " CR ")).click()
    dialog.get_by_role("spinbutton", name="Minimum count").last.fill(str(low))
    dialog.get_by_role("spinbutton", name="Maximum count").last.fill(str(high))


def lore_save(dialog):
    return dialog.get_by_role("button", name="Save Lore Grouping")


def create_lore(tab, name, members, weight=None):
    tab.page.get_by_role("button", name="Create a new Lore grouping", exact=True).click()
    dialog = tab.dialog("📖 Create Lore Grouping")
    expect(dialog).to_be_visible()
    dialog.get_by_placeholder("e.g. Kobold Skirmishers").fill(name)
    if weight is not None:
        dialog.get_by_role("slider", name="Weight").fill(str(weight))
    for member in members:
        lore_member(dialog, *member)
    return dialog


def test_new_lore_grouping_tests_saves_and_lists_its_members(app, tab):
    dialog = create_lore(
        tab, "Goblin Raiders", [("Goblin Warrior", 2, 4), ("Ogre", 1, 1)], weight=7
    )
    expect(dialog.get_by_text("Weight (7)")).to_be_visible()
    dialog.get_by_role("button", name="Test", exact=True).click()
    expect(dialog.get_by_text("Settings most likely to roll this Lore grouping:")).to_be_visible()
    tab.shot("lore-test-panel")
    lore_save(dialog).click()
    expect(dialog).to_be_hidden()

    lore_section(tab)
    row = lore_row(tab, "Goblin Raiders")
    expect(row).to_contain_text("2 members · weight 7")
    row.click()
    detail = tab.page.locator(".compendium__detail")
    expect(detail).to_contain_text("Weight 7 · User-curated")
    expect(detail).to_contain_text("2–4× Goblin Warrior")
    expect(tab.button("Edit Lore Grouping")).to_be_enabled()

    tab.page.reload()
    tab.wait_ready()
    lore_section(tab)
    expect(lore_row(tab, "Goblin Raiders")).to_be_visible()


def test_adding_a_lore_grouping_rolls_counts_inside_each_range(app, tab):
    dialog = create_lore(tab, "Goblin Raiders", [("Goblin Warrior", 2, 4), ("Ogre", 1, 1)])
    lore_save(dialog).click()
    lore_section(tab)
    lore_row(tab, "Goblin Raiders").click()
    tab.button("➕ Add Grouping to Encounter").click()
    expect(tab.toast(re.compile("Added Goblin Raiders: \\d creatures"))).to_be_visible()

    expect(app.card_boxes().first).to_be_visible()
    names = app.card_names()
    goblins = [name for name in names if name.startswith("Goblin Warrior")]
    assert 2 <= len(goblins) <= 4
    assert [name for name in names if name.startswith("Ogre")] == ["Ogre"]


def test_editing_and_deleting_a_lore_grouping(tab):
    dialog = create_lore(tab, "Goblin Raiders", [("Goblin Warrior", 2, 4)])
    lore_save(dialog).click()
    lore_section(tab)
    lore_row(tab, "Goblin Raiders").click()
    tab.page.get_by_role("button", name="Edit Lore Grouping").click()
    dialog = tab.dialog("📖 Edit Lore Grouping")
    dialog.get_by_role("spinbutton", name="Maximum count").fill("6")
    lore_save(dialog).click()
    expect(dialog).to_be_hidden()
    expect(tab.page.locator(".compendium__detail")).to_contain_text("2–6× Goblin Warrior")

    tab.page.get_by_role("button", name="Delete this Lore grouping").click()
    expect(lore_row(tab, "Goblin Raiders")).to_be_visible()
    tab.button("Delete").click()
    expect(tab.toast('Deleted lore grouping "Goblin Raiders".')).to_be_visible()
    expect(lore_row(tab, "Goblin Raiders")).to_have_count(0)
    expect(tab.page.get_by_text("Select a creature or group on the left.")).to_be_visible()


def test_lore_editor_names_what_is_missing(tab):
    dialog = create_lore(tab, "", [])
    save = lore_save(dialog)
    save.click()
    expect(dialog.get_by_text("Lore grouping needs a name.")).to_be_visible()
    dialog.get_by_placeholder("e.g. Kobold Skirmishers").fill("Nobody Home")
    save.click()
    expect(
        dialog.locator(".group-edit__error").get_by_text(
            "Add at least one creature to the Lore grouping."
        )
    ).to_be_visible()
    lore_member(dialog, "Ogre", 5, 2)
    save.click()
    expect(dialog.get_by_text(re.compile("invalid count range"))).to_be_visible()


def test_two_lore_groupings_with_one_name_both_survive(tab):
    lore_save(create_lore(tab, "Raiders", [("Goblin Warrior", 2, 4)])).click()
    lore_save(create_lore(tab, "Raiders", [("Ogre", 1, 2)])).click()
    lore_section(tab)
    expect(lore_row(tab, "Raiders")).to_have_count(2, timeout=2000)


def test_bundled_lore_grouping_is_read_only_but_adds(app, tab):
    lore_section(tab)
    bundled = tab.page.get_by_role("button", name=re.compile("^🔒 ")).first
    bundled.click()
    expect(tab.page.locator(".compendium__detail")).to_contain_text("Bundled")
    expect(
        tab.page.get_by_role("button", name=re.compile("^Bundled Lore groupings can't be edited"))
    ).to_be_disabled()
    expect(
        tab.page.get_by_role("button", name="Bundled Lore groupings can't be deleted.")
    ).to_be_disabled()
    tab.button("➕ Add Grouping to Encounter").click()
    expect(app.card_boxes().first).to_be_visible()


def test_lore_groupings_stay_listed_when_no_creature_matches(tab):
    tab.search("xyzzy")
    expect(tab.page.get_by_text("No creatures match the current filters.")).to_be_visible()
    expect(
        tab.page.get_by_role("button", name="Create a new Lore grouping", exact=True)
    ).to_be_visible(timeout=2000)
