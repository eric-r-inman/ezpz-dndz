"""Session prep: a DM builds the encounter before the players sit down.

These scenarios cover Quick Add, placeholders, the Replace editor, the
difficulty and XP readouts, the random encounter generator and the Clear and
Reset controls.
"""

import re

import pytest
from playwright.sync_api import expect

from pages.app import BEGIN_COMBAT, settle
from pages.building import (
    TIERS,
    bundled_creatures,
    cr_value,
    number,
    party_budget,
    pick_target,
    random_budget,
    roll_random,
    set_party,
)
from pages.fight import ConditionEditor, ManageHp
from pages.turns import set_initiative


def quick_add_rows(app):
    """Creature rows in Quick Add in display order.  Each is a name and a CR."""
    panel = app.panel("Quick Add").open()
    rows = panel.root.get_by_role("list").get_by_role("button", name=re.compile(r" CR "))
    labels = rows.evaluate_all("els => els.map(e => e.textContent)")
    return [tuple(part.strip() for part in label.rsplit("CR ", 1)) for label in labels]


# Quick Add.


def test_quick_add_search_narrows_the_list_and_says_when_nothing_matches(app):
    panel = app.panel("Quick Add").open()
    search = panel.root.get_by_role("searchbox", name="Filter Quick Add by name")

    search.fill("goblin")
    names = [name for name, _ in quick_add_rows(app)]
    assert "Goblin Warrior" in names and "Goblin Boss" in names
    assert all("goblin" in name.lower() for name in names)
    expect(panel.root.get_by_role("button", name="Add placeholder")).to_be_visible()

    search.fill("zzqx")
    expect(panel.root.get_by_text('No matches for "zzqx".')).to_be_visible()
    assert quick_add_rows(app) == []
    expect(panel.root.get_by_role("button", name="Add placeholder")).to_be_visible()
    app.shot("no-matches")


def test_quick_add_sort_toggle_switches_between_name_and_challenge_rating(app):
    panel = app.panel("Quick Add").open()
    toggle = panel.root.get_by_role("button", name=re.compile("^Sort: "))
    expect(toggle).to_have_text("Sort: A → Z")
    names = [name for name, _ in quick_add_rows(app)]
    assert names == sorted(names, key=str.lower)

    toggle.click()
    expect(toggle).to_have_text("Sort: CR ↑")
    ratings = [cr_value(cr) for _, cr in quick_add_rows(app)]
    assert ratings == sorted(ratings)
    assert ratings[0] == 0 and ratings[-1] == 30
    app.shot("by-cr")

    toggle.click()
    expect(toggle).to_have_text("Sort: A → Z")
    assert [name for name, _ in quick_add_rows(app)] == names


def test_quick_add_sorted_by_cr_breaks_ties_alphabetically(app):
    panel = app.panel("Quick Add").open()
    panel.root.get_by_role("button", name=re.compile("^Sort: ")).click()
    rows = quick_add_rows(app)
    for cr in {cr for _, cr in rows}:
        tied = [name for name, rating in rows if rating == cr]
        assert tied == sorted(tied, key=str.lower), f"{cr} ties are out of order."


def test_adding_several_copies_numbers_them_and_keeps_the_panel_open(app):
    app.add("Goblin Warrior", count=3)
    assert app.card_names() == ["Goblin Warrior", "Goblin Warrior 2", "Goblin Warrior 3"]
    assert app.panel("Quick Add").is_open()
    for name in app.card_names():
        assert app.card(name).hp() == 10
        assert app.card(name).ac() == 15
        assert app.card(name).initiative() == 0


def test_a_removed_copy_frees_its_number_for_the_next_add(app):
    app.add("Goblin Warrior", count=3)
    app.card("Goblin Warrior 2").remove()
    app.add("Goblin Warrior")
    assert sorted(app.card_names()) == [
        "Goblin Warrior",
        "Goblin Warrior 2",
        "Goblin Warrior 3",
    ]


def test_placeholders_number_from_one_and_land_at_the_bottom(app):
    app.add("Ogre")
    set_initiative(app, "Ogre", 5)
    app.add_placeholder()
    app.add_placeholder()
    assert app.card_names() == ["Ogre", "Placeholder 1", "Placeholder 2"]
    stub = app.card("Placeholder 2")
    assert (stub.hp(), stub.max_hp(), stub.ac(), stub.initiative()) == (1, 1, 10, 0)

    app.card("Placeholder 1").remove()
    app.add_placeholder()
    assert app.card_names() == ["Ogre", "Placeholder 2", "Placeholder 1"]


# Placeholder rename on the card.


def start_rename(app, name):
    app.card(name).root.get_by_role("button", name=f"Rename {name}").click()
    field = app.page.get_by_role("textbox", name="Rename placeholder")
    expect(field).to_be_visible()
    return field


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-01: the rename field opens without focus, so typing goes nowhere",
)
def test_clicking_a_placeholder_name_puts_the_cursor_in_the_rename_field(app):
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    app.shot("rename-open")
    expect(field).to_be_focused(timeout=2000)


@pytest.mark.cross_browser
def test_enter_commits_a_placeholder_rename(app):
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    field.fill("Captain Vex")
    field.press("Enter")
    expect(app.card("Captain Vex").root).to_be_visible()
    assert app.card_names() == ["Captain Vex"]
    expect(app.page.get_by_role("textbox", name="Rename placeholder")).to_have_count(0)
    app.shot("renamed")


@pytest.mark.cross_browser
def test_clicking_away_commits_a_placeholder_rename(app):
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    field.fill("Lookout")
    app.page.get_by_role("contentinfo").click(position={"x": 5, "y": 5})
    expect(app.card("Lookout").root).to_be_visible()


@pytest.mark.cross_browser
def test_escape_cancels_a_placeholder_rename(app):
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    field.fill("Not this")
    field.press("Escape")
    expect(app.page.get_by_role("textbox", name="Rename placeholder")).to_have_count(0)
    assert app.card_names() == ["Placeholder 1"]


def test_renaming_a_placeholder_to_a_taken_name_numbers_it(app):
    app.add("Ogre")
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    field.fill("Ogre")
    field.press("Enter")
    expect(app.card("Ogre 2").root).to_be_visible()
    assert app.card_names() == ["Ogre", "Ogre 2"]


def test_a_blank_placeholder_rename_keeps_the_old_name(app):
    app.add_placeholder()
    field = start_rename(app, "Placeholder 1")
    field.fill("   ")
    field.press("Enter")
    expect(app.page.get_by_role("textbox", name="Rename placeholder")).to_have_count(0)
    assert app.card_names() == ["Placeholder 1"]


# The Replace editor.


def replace_with(app, creature):
    editor = app.panel("Replace").open()
    editor.root.get_by_role("textbox", name="Search the compendium").fill(creature)
    editor.root.get_by_role("option", name=re.compile("^" + re.escape(creature) + " CR ")).click()
    return editor


def test_replace_swaps_the_target_and_keeps_its_initiative_and_place(app):
    app.add("Ogre")
    app.add("Goblin Warrior", count=2)
    set_initiative(app, "Ogre", 14)
    set_initiative(app, "Goblin Warrior", 9)
    set_initiative(app, "Goblin Warrior 2", 3)
    app.panel("Initiative").fold()
    assert app.card_names() == ["Ogre", "Goblin Warrior", "Goblin Warrior 2"]

    pick_target(app.card("Goblin Warrior"))
    editor = replace_with(app, "Bugbear Warrior")
    expect(editor.root.get_by_text(re.compile("^Target: Goblin Warrior"))).to_be_visible()
    editor.root.get_by_role("button", name="Target", exact=True).click()
    app.settle()

    assert app.card_names() == ["Ogre", "Bugbear Warrior", "Goblin Warrior 2"]
    bugbear = app.card("Bugbear Warrior")
    assert bugbear.initiative() == 9
    assert (bugbear.hp(), bugbear.ac()) == (33, 14)
    expect(editor.root.get_by_role("button", name="▼ Log (1)")).to_be_visible()
    expect(editor.root.get_by_text("→ Bugbear Warrior")).to_be_visible()
    app.shot("replaced")


def test_replace_selected_swaps_every_ticked_creature_with_unique_names(app):
    app.add("Goblin Warrior", count=3)
    set_initiative(app, "Goblin Warrior", 12)
    set_initiative(app, "Goblin Warrior 3", 4)
    app.panel("Initiative").fold()
    order = app.card_names()
    app.card("Goblin Warrior").select()
    app.card("Goblin Warrior 3").select()

    editor = replace_with(app, "Kobold Warrior")
    editor.root.get_by_role("button", name="Selected (2)").click()
    app.settle()

    names = app.card_names()
    assert names[order.index("Goblin Warrior 2")] == "Goblin Warrior 2"
    swapped = [names[order.index("Goblin Warrior")], names[order.index("Goblin Warrior 3")]]
    assert swapped == ["Kobold Warrior", "Kobold Warrior 2"]
    assert app.card("Kobold Warrior").initiative() == 12
    assert app.card("Kobold Warrior 2").initiative() == 4


def test_replacing_the_creature_whose_turn_it_is_keeps_the_turn(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    set_initiative(app, "Ogre", 20)
    app.panel("Initiative").fold()
    app.begin_combat()
    app.next_turn()
    assert app.active_name() == "Goblin Warrior"
    editor = replace_with(app, "Goblin Boss")
    expect(editor.root.get_by_text(re.compile("^Target: Goblin Warrior"))).to_be_visible()
    editor.root.get_by_role("button", name="Target", exact=True).click()
    app.settle()
    assert app.active_name() == "Goblin Boss"
    assert app.round_number() == 1
    app.next_turn()
    assert (app.active_name(), app.round_number()) == ("Ogre", 2)


def test_replace_needs_a_pick_before_it_can_apply(app):
    app.add("Ogre")
    editor = app.panel("Replace").open()
    expect(editor.root.get_by_role("button", name="Target", exact=True)).to_be_disabled()
    editor.root.get_by_role("textbox", name="Search the compendium").fill("Owlbear")
    option = editor.root.get_by_role("option", name="Owlbear CR 3")
    option.click()
    expect(option).to_have_attribute("aria-selected", "true")
    expect(editor.root.get_by_role("button", name="Target", exact=True)).to_be_enabled()
    option.click()
    expect(option).to_have_attribute("aria-selected", "false")
    expect(editor.root.get_by_role("button", name="Target", exact=True)).to_be_disabled()


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-02: Quick Add rows take focus but Enter does nothing",
)
def test_a_keyboard_dm_adds_a_creature_from_quick_add_with_enter(app):
    panel = app.panel("Quick Add").open()
    panel.root.get_by_role("searchbox", name="Filter Quick Add by name").fill("Ogre")
    row = panel.root.get_by_role("button", name="Ogre CR 2")
    row.focus()
    expect(row).to_be_focused()
    app.page.keyboard.press("Enter")
    expect(app.card("Ogre").root).to_be_visible(timeout=2000)


# Clear and Reset.


def confirm_dialog(app, title):
    dialog = app.page.get_by_role("dialog", name=title)
    expect(dialog).to_be_visible()
    return dialog


@pytest.mark.cross_browser
def test_clear_asks_first_and_cancel_or_escape_keeps_the_encounter(app):
    app.add("Ogre")
    app.add("Goblin Warrior", count=2)
    clear = app.page.get_by_role("button", name="Clear encounter")

    clear.click()
    dialog = confirm_dialog(app, "Clear Encounter")
    expect(dialog.get_by_text("Remove every creature and reset round to 1?")).to_be_visible()
    app.shot("clear-confirm")
    dialog.get_by_role("button", name="Cancel").click()
    expect(dialog).to_be_hidden()
    assert len(app.card_names()) == 3

    clear.click()
    confirm_dialog(app, "Clear Encounter")
    app.page.keyboard.press("Escape")
    expect(app.page.get_by_role("dialog", name="Clear Encounter")).to_be_hidden()
    assert len(app.card_names()) == 3


def test_clear_removes_every_creature_and_goes_back_to_round_one(app):
    app.add("Ogre")
    app.add("Goblin Warrior", count=2)
    app.begin_combat()
    app.next_turn()
    app.next_turn()
    app.next_turn()
    assert app.round_number() == 2

    app.page.get_by_role("button", name="Clear encounter").click()
    confirm_dialog(app, "Clear Encounter").get_by_role("button", name="Clear").click()
    expect(app.page.get_by_role("article")).to_have_count(0)
    assert app.round_number() == 1
    expect(app.page.get_by_role("button", name=BEGIN_COMBAT)).to_be_visible()
    app.shot("cleared")

    app.reload()
    expect(app.page.get_by_role("article")).to_have_count(0)


def wound_and_burden(app, name):
    """Damages a creature and piles per-fight state onto it."""
    pick_target(app.card(name))
    app.panel("Manage HP").open()
    ManageHp(app).damage(20).temp(5)
    status = app.panel("Status").open()
    status.root.get_by_role("button", name="dodging").click()
    status.root.get_by_role("button", name="concentrating").click()
    status.root.get_by_role("button", name="Target", exact=True).click()
    status.fold()
    app.panel("Condition/Effect").open()
    ConditionEditor(app).pick("Prone").apply()
    app.panel("Condition/Effect").fold()
    card = app.card(name).root
    card.get_by_role("button", name="Ready an Action").click()
    card.get_by_role("button", name=re.compile("^Reaction available")).click()
    app.settle()


def test_reset_restores_full_hp_and_clears_conditions_and_status(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    app.begin_combat()
    app.next_turn()
    app.next_turn()
    wound_and_burden(app, "Ogre")
    ogre = app.card("Ogre")
    assert (ogre.hp(), app.round_number()) == (48, 2)
    expect(ogre.root.get_by_role("button", name="Temp HP for Ogre")).to_be_visible()
    expect(ogre.root.get_by_role("button", name="Prone")).to_be_visible()
    expect(ogre.root.get_by_role("button", name="Clear dodging for Ogre")).to_be_visible()
    expect(ogre.root.get_by_role("button", name="Action Readied")).to_be_visible()
    expect(ogre.root.get_by_role("button", name=re.compile("^Reaction spent"))).to_be_visible()
    app.shot("before-reset")

    app.page.get_by_role("button", name=re.compile("^Reset every creature")).click()
    dialog = confirm_dialog(app, "Reset Encounter")
    dialog.get_by_role("button", name="Reset", exact=True).click()
    expect(dialog).to_be_hidden()

    assert (ogre.hp(), ogre.max_hp()) == (68, 68)
    assert app.card_names() == ["Goblin Warrior", "Ogre"]
    expect(ogre.root.get_by_role("button", name="Temp HP for Ogre")).to_have_count(0)
    expect(ogre.root.get_by_role("button", name="Prone")).to_have_count(0)
    expect(ogre.root.get_by_role("button", name=re.compile("^Clear "))).to_have_count(0)
    expect(ogre.root.get_by_role("button", name="Ready an Action")).to_be_visible()
    expect(ogre.root.get_by_role("button", name=re.compile("^Reaction available"))).to_be_visible()
    assert app.round_number() == 1
    assert app.active_name() is None
    app.shot("after-reset")


def test_cancelling_reset_leaves_the_wounds_in_place(app):
    app.add("Ogre")
    wound_and_burden(app, "Ogre")
    app.page.get_by_role("button", name=re.compile("^Reset every creature")).click()
    confirm_dialog(app, "Reset Encounter").get_by_role("button", name="Cancel").click()
    assert app.card("Ogre").hp() == 48
    expect(app.card("Ogre").root.get_by_role("button", name="Prone")).to_be_visible()


# Encounter Difficulty.


def difficulty_readout(panel):
    """The Result section as numbers.  It has no table or list semantics."""
    root = panel.root
    amounts = root.locator(".cr-calc__budget-amount").all_inner_texts()
    label = root.locator(".cr-calc__difficulty-label")
    return {
        "xp": number(root.locator(".cr-calc__result-value").inner_text()),
        "budget": tuple(number(text) for text in amounts),
        "band": label.inner_text() if label.count() else None,
    }


@pytest.mark.parametrize(
    "levels",
    [[1, 1, 1, 1], [3, 3, 3, 3], [5, 5, 5, 5], [2, 7, 11], [20], [13, 14, 15, 16, 17, 18]],
    ids=lambda levels: "-".join(map(str, levels)),
)
def test_difficulty_budgets_match_the_2024_xp_budget_per_character(app, levels):
    panel = app.panel("Encounter Difficulty").open()
    set_party(panel, levels)
    assert difficulty_readout(panel)["budget"] == party_budget(levels)


def test_adding_and_removing_characters_changes_the_party_budget(app):
    panel = app.panel("Encounter Difficulty").open()
    assert difficulty_readout(panel)["budget"] == party_budget([1, 1, 1, 1])

    panel.root.get_by_role("button", name="+ Add character").click()
    expect(panel.root.get_by_role("combobox", name="Level for Player 5")).to_be_visible()
    assert difficulty_readout(panel)["budget"] == party_budget([1] * 5)

    for _ in range(5):
        panel.root.get_by_role("button", name="Remove character").first.click()
    expect(
        panel.root.get_by_text("No characters yet. Add one to start the calculation.")
    ).to_be_visible()
    expect(
        panel.root.get_by_text("Add at least one character to see a difficulty rating.")
    ).to_be_visible()
    assert difficulty_readout(panel)["budget"] == (0, 0, 0)
    app.shot("no-party")


@pytest.mark.parametrize(
    "goblins, band",
    [
        (0, "Trivial"),
        (1, "Low"),
        (4, "Low"),
        (5, "Moderate"),
        (6, "Moderate"),
        (8, "High"),
        (9, "Beyond High"),
    ],
)
def test_difficulty_band_follows_the_encounter_xp(app, goblins, band):
    if goblins:
        app.add("Goblin Warrior", count=goblins)
    panel = app.panel("Encounter Difficulty").open()
    readout = difficulty_readout(panel)
    assert readout["xp"] == 50 * goblins
    assert readout["band"] == band


def test_difficulty_scope_selected_only_counts_ticked_creatures(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.add_placeholder()
    panel = app.panel("Encounter Difficulty").open()
    assert difficulty_readout(panel)["xp"] == 550

    app.card("Ogre").select()
    app.card("Placeholder 1").select()
    panel.root.get_by_role("button", name="Selected only").click()
    expect(panel.root.get_by_role("button", name="Selected only")).to_have_attribute(
        "aria-pressed", "true"
    )
    assert difficulty_readout(panel)["xp"] == 450
    assert difficulty_readout(panel)["band"] == "Beyond High"

    panel.root.get_by_role("button", name="NPCs only").click()
    expect(panel.root.locator(".cr-calc__result-value")).to_have_text("0 XP")
    panel.root.get_by_role("button", name="Enemies & NPCs").click()
    expect(panel.root.locator(".cr-calc__result-value")).to_have_text("550 XP")


def test_the_party_is_shared_with_random_encounter_and_survives_a_reload(app):
    difficulty = app.panel("Encounter Difficulty").open()
    set_party(difficulty, [5, 5, 6])
    app.reload()
    difficulty = app.panel("Encounter Difficulty").open()
    assert difficulty_readout(difficulty)["budget"] == party_budget([5, 5, 6])
    random = app.panel("Random Encounter").open()
    assert random_budget(random) == party_budget([5, 5, 6])[1]


# Encounter XP.


def xp_headline(panel):
    return number(panel.root.locator(".xp-panel__total").inner_text())


def test_encounter_xp_scope_and_calculations_tally(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.add_placeholder()
    panel = app.panel("Encounter XP").open()
    assert xp_headline(panel) == 550

    panel.root.get_by_role("button", name="▶ Show calculations").click()
    rows = panel.root.locator(".xp-calc__row")
    expect(rows).to_have_count(3)
    assert rows.all_inner_texts()[2].split()[:2] == ["Ogre", "450"]
    tally = panel.root.locator(".xp-calc__total")
    expect(tally).to_have_text("550 XP")

    panel.root.get_by_role("button", name="Exclude Ogre from the tally").click()
    expect(tally).to_have_text("100 XP")
    assert xp_headline(panel) == 550
    app.shot("ogre-excluded")
    panel.root.get_by_role("button", name="Include Ogre in the tally").click()
    expect(tally).to_have_text("550 XP")

    app.card("Goblin Warrior 2").select()
    panel.root.get_by_role("option", name="Selected Only").click()
    expect(panel.root.get_by_role("option", name="Selected Only")).to_have_attribute(
        "aria-selected", "true"
    )
    expect(rows).to_have_count(1)
    assert xp_headline(panel) == 50
    panel.root.get_by_role("option", name="NPCs Only").click()
    expect(panel.root.get_by_text("Nothing in scope.")).to_be_visible()
    assert xp_headline(panel) == 0


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-03: the Encounter XP scope options cannot be reached by keyboard",
)
def test_a_keyboard_dm_can_reach_the_encounter_xp_scope(app):
    panel = app.panel("Encounter XP").open()
    panel.fold_button().focus()
    reached = []
    for _ in range(6):
        app.page.keyboard.press("Tab")
        reached.append(
            app.page.evaluate(
                "() => (document.activeElement.getAttribute('role') || '') + ':'"
                " + document.activeElement.textContent.trim()"
            )
        )
    assert any(item.startswith("option:") for item in reached), reached


# Random Encounter.


def random_panel(app, levels=None):
    app.panel("Quick Add").fold()
    panel = app.panel("Random Encounter").open()
    if levels:
        set_party(panel, levels)
    return panel


def choose(panel, *, difficulty=None, scale=None, habitat=None, minions=None, lore=None):
    root = panel.root
    if difficulty:
        root.get_by_role("button", name=difficulty, exact=True).click()
    if scale:
        root.get_by_role("button", name=scale, exact=True).click()
    if habitat:
        root.get_by_role("combobox", name="Habitat:").select_option(label=habitat)
    for name, wanted in (("Include minions", minions), ("Lore-leaning", lore)):
        box = root.get_by_role("checkbox", name=name)
        if wanted is not None and box.is_checked() != wanted:
            box.click()
            expect(box).to_be_checked(checked=wanted)
    settle(panel.page)


def pin(panel, creature, count=1):
    root = panel.root
    if root.get_by_role("searchbox", name="Search creatures to pin").count() == 0:
        root.get_by_role("button", name="➕ Pin a creature").click()
    root.get_by_role("searchbox", name="Search creatures to pin").fill(creature)
    root.get_by_role("button", name=re.compile("^" + re.escape(creature) + " CR ")).click()
    for _ in range(count - 1):
        root.get_by_role("button", name=f"One more {creature}").click()


def exclude(panel, creature):
    root = panel.root
    if root.get_by_role("searchbox", name="Search creatures to exclude").count() == 0:
        root.get_by_role("button", name="🚫 Exclude a creature").click()
    root.get_by_role("searchbox", name="Search creatures to exclude").fill(creature)
    root.get_by_role("button", name=re.compile("^" + re.escape(creature) + " CR ")).click()


def creature_count(groups):
    return sum(count for count, _, _, _ in groups)


def test_random_rolls_honor_the_habitat_and_every_chosen_type(app):
    db = bundled_creatures(app.server)
    panel = random_panel(app, [5, 5, 5, 5])
    choose(panel, habitat="Arctic")
    for _ in range(5):
        groups, _ = roll_random(panel)
        assert groups
        for _, name, _, _ in groups:
            assert "arctic" in db[name]["habitats"], name

    types = panel.root.get_by_role("combobox", name=re.compile("^Creature type filter "))
    types.nth(0).select_option("Beast")
    expect(types).to_have_count(2)
    types.nth(1).select_option("Dragon")
    expect(types).to_have_count(3)
    for _ in range(6):
        groups, _ = roll_random(panel)
        races = {db[name]["race"] for _, name, _, _ in groups}
        assert races == {"Beast", "Dragon"}, groups
        assert all("arctic" in db[name]["habitats"] for _, name, _, _ in groups)
    app.shot("arctic-beasts-and-dragons")

    types.nth(0).select_option("")
    expect(types).to_have_count(2)
    assert types.nth(0).input_value() == "Dragon"


def test_pinned_creatures_are_in_every_roll_and_come_off_the_budget(app):
    db = bundled_creatures(app.server)
    panel = random_panel(app, [5, 5, 5, 5])
    choose(panel, habitat="Underwater")
    pin(panel, "Ogre", count=3)
    panel.root.get_by_role("button", name="One fewer Ogre").click()
    expect(
        panel.root.get_by_text(
            "Pinned: 900 XP of 3,000 budget · 2,100 XP remaining for random fill."
        )
    ).to_be_visible()
    for _ in range(5):
        groups, _ = roll_random(panel)
        assert groups[0][:3] == (2, "Ogre", 900)
        assert len(groups) > 1
        assert all("underwater" in db[name]["habitats"] for _, name, _, _ in groups[1:])
    expect(panel.root.get_by_role("button", name="Exclude Ogre")).to_have_count(0)
    app.shot("pinned-ogres")

    panel.root.get_by_role("button", name="Remove Ogre").click()
    expect(panel.root.get_by_text(re.compile("^Pinned: "))).to_have_count(0)


def test_pins_over_the_budget_skip_the_random_fill(app):
    panel = random_panel(app, [1, 1, 1, 1])
    pin(panel, "Tarrasque")
    expect(
        panel.root.get_by_text(
            "Pinned: 155,000 XP · 154,700 XP over the 300 XP budget"
            " — random fill will be skipped."
        )
    ).to_be_visible()
    groups, total = roll_random(panel)
    assert [group[:3] for group in groups] == [(1, "Tarrasque", 155000)]
    assert total == 155000


def test_excluded_creatures_never_appear_and_an_emptied_pool_says_so(app):
    panel = random_panel(app, [5, 5, 5, 5])
    choose(panel, scale="One", habitat="Elemental Plane of Earth")
    exclude(panel, "Xorn")
    expect(panel.root.get_by_role("button", name="Stop excluding Xorn")).to_be_visible()
    for _ in range(6):
        groups, _ = roll_random(panel)
        assert [group[:2] for group in groups] == [(1, "Earth Elemental")]

    panel.root.get_by_role("button", name="Exclude Earth Elemental").click()
    expect(panel.root.get_by_text("Hit Generate to roll.")).to_be_visible()
    groups, total = roll_random(panel)
    assert (groups, total) == ([], None)
    expect(panel.root.get_by_text(re.compile("^No creatures match"))).to_be_visible()
    expect(panel.root.get_by_role("button", name="Add to Encounter")).to_be_disabled()
    app.shot("pool-emptied")

    panel.root.get_by_role("button", name="Stop excluding Xorn").click()
    groups, _ = roll_random(panel)
    assert [group[:2] for group in groups] == [(1, "Xorn")]


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-15: a two-word creature name wraps under its CR in the roll result",
)
def test_roll_result_rows_keep_the_name_clear_of_the_cr(app):
    panel = random_panel(app, [5, 5, 5, 5])
    choose(panel, scale="One", habitat="Elemental Plane of Earth")
    exclude(panel, "Xorn")
    roll_random(panel)
    row = panel.root.locator(".random-encounter__group-row").first
    row.scroll_into_view_if_needed()
    app.shot("result-row")
    # The name's box stays in its column while the text spills out of it.
    # This measures the text itself.
    text_right = row.locator(".random-encounter__group-name").evaluate(
        "el => { const range = document.createRange(); range.selectNodeContents(el);"
        " return Math.max(...[...range.getClientRects()].map(r => r.right)); }"
    )
    cr_left = row.locator(".random-encounter__group-cr").bounding_box()["x"]
    assert text_right <= cr_left, (text_right, cr_left)


def test_a_habitat_with_no_creatures_reports_an_empty_pool(app):
    panel = random_panel(app)
    choose(panel, habitat="Limbo")
    groups, _ = roll_random(panel)
    assert groups == []
    expect(panel.root.get_by_text(re.compile("^No creatures match"))).to_be_visible()
    expect(panel.root.get_by_role("button", name="Add to Encounter")).to_be_disabled()


def test_add_to_encounter_queues_the_roll_with_unique_names(app):
    app.add("Goblin Warrior")
    panel = random_panel(app, [3, 3, 3, 3])
    pin(panel, "Goblin Warrior", count=2)
    groups, total = roll_random(panel)
    panel.root.get_by_role("button", name="Add to Encounter").click()
    added = creature_count(groups)
    expect(app.page.get_by_text(f"Rolled an encounter: {added} creatures added")).to_be_visible()
    names = app.card_names()
    assert len(names) == 1 + added
    assert len(set(names)) == len(names)
    assert {"Goblin Warrior", "Goblin Warrior 2", "Goblin Warrior 3"} <= set(names)

    difficulty = app.panel("Encounter Difficulty").open()
    assert difficulty_readout(difficulty)["xp"] == total + 50
    app.shot("roll-added")


def test_include_minions_adds_a_small_group_tagged_as_minions(app):
    db = bundled_creatures(app.server)
    panel = random_panel(app)
    choose(panel, scale="Many (4+)", minions=True)
    for _ in range(5):
        groups, _ = roll_random(panel)
        minions = [group for group in groups if group[3]]
        assert len(minions) == 1, groups
        count, name, _, _ = minions[0]
        assert 2 <= count <= 6
        assert db[name]["xp"] <= 100


@pytest.mark.parametrize("scale", ["One", "Few (2-4)"])
@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-04: Include minions adds none to One or Few rolls yet holds back budget",
)
def test_include_minions_adds_minions_or_is_unavailable(app, scale):
    panel = random_panel(app, [12, 12, 12, 12])
    choose(panel, scale=scale, minions=True)
    box = panel.root.get_by_role("checkbox", name="Include minions")
    minion_rolls = [any(group[3] for group in roll_random(panel)[0]) for _ in range(5)]
    assert box.is_disabled() or all(minion_rolls)


@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-05: Few and Many rolls often come back with fewer creatures than promised",
)
def test_scale_few_and_many_keep_their_promised_creature_counts(app):
    panel = random_panel(app)
    choose(panel, difficulty="Low", scale="Few (2-4)")
    few = [creature_count(roll_random(panel)[0]) for _ in range(12)]
    choose(panel, difficulty="Moderate", scale="Many (4+)")
    many = [creature_count(roll_random(panel)[0]) for _ in range(12)]
    assert all(2 <= count <= 4 for count in few), few
    assert all(count >= 4 for count in many), many


@pytest.mark.parametrize("tier", TIERS)
def test_a_large_roll_lands_roughly_on_the_budget(app, tier):
    panel = random_panel(app, [5, 5, 5, 5])
    choose(panel, difficulty=tier, scale="Many (4+)")
    budget = party_budget([5, 5, 5, 5])[TIERS.index(tier)]
    assert random_budget(panel) == budget
    totals = [roll_random(panel)[1] for _ in range(5)]
    assert all(0.5 * budget <= total <= 1.25 * budget for total in totals), totals


@pytest.mark.xfail(
    strict=True,
    reason="QA-BUILD-06: about one default Moderate roll in seven lands in the Low band",
)
def test_the_default_roll_lands_in_the_moderate_band(app):
    panel = random_panel(app)
    low, _, high = party_budget([1, 1, 1, 1])
    # About one roll in seven undershoots.  Sixty rolls almost surely catch
    # one.
    totals = [roll_random(panel)[1] for _ in range(60)]
    assert all(low < total <= high for total in totals), sorted(totals)


def test_lore_leaning_rolls_still_honor_the_filters(app):
    db = bundled_creatures(app.server)
    panel = random_panel(app, [3, 3, 3, 3])
    choose(panel, habitat="Hill", lore=True)
    for _ in range(6):
        groups, _ = roll_random(panel)
        assert groups
        assert all("hill" in db[name]["habitats"] for _, name, _, _ in groups), groups
