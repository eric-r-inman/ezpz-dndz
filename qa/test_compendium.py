"""Session prep in the full-page compendium.  The DM browses, rolls and adds.

The compendium opens in its own tab from the editor column.  A DM parks it on a
second monitor, picks monsters and sends them to the encounter tab.  The two
tabs talk over a BroadcastChannel.
"""

import json
import re

import pytest
from playwright.sync_api import expect

from pages import compendium as library
from pages.accounts import api, error_toasts, success_toast, wait_for_cards
from pages.compendium import add_row
from pages.building import bundled_creatures, cr_value


@pytest.fixture
def bundled(app):
    return bundled_creatures(app.server)


def rules_modifier(score):
    return (score - 10) // 2


def signed(number):
    return f"+{number}" if number >= 0 else str(number)


def wait_for_rolls(tab, count, feature):
    tab.page.wait_for_function(
        "([count, feature]) => {"
        " const h = JSON.parse(localStorage.getItem('diceHistory') || '[]');"
        " return h.length >= count && h.slice(0, count)"
        "   .every(r => r.source && r.source.feature === feature); }",
        arg=[count, feature],
    )
    return (tab.local("diceHistory") or [])[:count]


def assert_triple_roll(rolls, bonus):
    """Straight, advantage and disadvantage.  Each is a d20 plus the bonus."""
    assert [roll["kind"] for roll in rolls] == ["standard", "advantage", "disadvantage"]
    for roll in rolls:
        assert roll["expression"]["constant"] == bonus
    faces = [[die["face"] for die in roll["groups"][0]["rolled"]] for roll in rolls]
    assert len(faces[0]) == 1
    assert len(faces[1]) == 2 and len(faces[2]) == 2
    assert rolls[0]["total"] == faces[0][0] + bonus
    assert rolls[1]["total"] == max(faces[1]) + bonus
    assert rolls[2]["total"] == min(faces[2]) + bonus


def popup_totals(tab):
    layer = tab.page.get_by_role("status", name="Dice roll results")
    expect(layer.get_by_text(re.compile(r"^-?\d+$"))).to_have_count(3)
    return [int(text) for text in layer.get_by_text(re.compile(r"^-?\d+$")).all_inner_texts()]


# Opening the library.


@pytest.mark.cross_browser
def test_books_button_opens_the_library_in_one_reusable_tab(app, tab):
    assert tab.page.url == app.server.base_url + "/compendium"
    expect(tab.page.get_by_text("Select a creature or group on the left.")).to_be_visible()
    expect(tab.page.get_by_role("button", name="Quick Add", exact=True)).to_have_count(0)
    tab.shot("library-opened")

    app.page.bring_to_front()
    app.page.get_by_role("button", name="Compendium (new tab)").click()
    app.settle()
    assert len(app.page.context.pages) == 2


def test_card_stat_block_hands_off_to_the_library_on_that_creature(app, bundled):
    app.add("Ogre")
    app.card("Ogre").root.get_by_role("button", name="Show stat block").click()
    with app.page.context.expect_page() as opened:
        app.page.get_by_role(
            "button", name="Show this creature in the Compendium tab"
        ).click()
    tab = library.tab_for(app, opened.value)
    expect(tab.detail_name()).to_have_text("Ogre")
    assert tab.page.url.endswith("/compendium?creature=" + bundled["Ogre"]["id"])
    expect(tab.row("Ogre")).to_have_attribute("aria-pressed", "true")
    tab.shot("handed-off-to-ogre")
    tab.assert_quiet()


@pytest.mark.xfail(
    strict=True, reason="QA-COMP-02: a deep link never scrolls its row into view"
)
def test_deep_link_scrolls_the_chosen_row_into_view(app, bundled):
    tab = library.open_at(app, "/compendium?creature=" + bundled["Ogre"]["id"])
    expect(tab.detail_name()).to_have_text("Ogre")
    expect(tab.row("Ogre")).to_be_in_viewport()


def test_creature_page_shows_one_stat_block_and_names_a_missing_one(app, bundled):
    tab = library.open_at(app, "/compendium/creatures/" + bundled["Ogre"]["id"])
    expect(tab.page.locator(".statblock__name")).to_have_text("Ogre")
    expect(tab.page.get_by_text("68 (8d10 + 24)")).to_be_visible()
    tab.shot("creature-page")

    tab.page.goto(app.server.base_url + "/compendium/creatures/no-such-creature")
    expect(tab.page.get_by_text("Creature not found in the compendium.")).to_be_visible()
    tab.assert_quiet()


# Finding creatures.


def test_search_matches_name_and_type_and_says_when_nothing_matches(tab, bundled):
    tab.search("ogre")
    assert tab.row_names() == ["Ogre", "Ogre Zombie"]

    tab.search("giant")
    names = tab.row_names()
    assert "Ogre" in names
    assert "Giant Spider" in names
    assert "Goblin Warrior" not in names

    tab.search("xyzzy")
    expect(tab.rows()).to_have_count(0)
    expect(tab.page.get_by_text("No creatures match the current filters.")).to_be_visible()
    expect(
        tab.page.get_by_text(f"{len(bundled)} creatures hidden", exact=False)
    ).to_be_visible()

    tab.search("")
    expect(tab.rows()).to_have_count(len(bundled))


def test_sorting_by_cr_runs_from_weakest_to_strongest(tab):
    names = tab.row_names()
    assert names == sorted(names, key=str.lower)

    tab.sort_by("By CR")
    ratings = [
        re.search(r"CR\xa0(\S+)$", meta).group(1) for meta in tab.row_metas()
    ]
    values = [cr_value(cr) for cr in ratings]
    assert values == sorted(values)
    assert values[0] == 0
    assert values[-1] >= 20


def test_habitat_filter_keeps_only_creatures_of_that_habitat(tab, bundled):
    tab.tag_filter().select_option(label="Hill")
    tab.settle()
    hill = sorted(name for name, c in bundled.items() if "hill" in c["habitats"])
    assert sorted(tab.row_names()) == hill
    assert "Ogre" in hill

    tab.page.get_by_role("button", name="Clear tag filter").click()
    expect(tab.rows()).to_have_count(len(bundled))
    expect(tab.tag_filter()).to_have_value("")


# Reading a stat block.


def test_picking_a_bundled_creature_shows_its_stat_block_read_only(app, tab):
    tab.select("Ogre")
    block = tab.statblock()
    expect(block).to_contain_text("Large Giant, chaotic evil")
    expect(block).to_contain_text("Armor Class: 11 (natural armor)")
    expect(block).to_contain_text("Hit Points: 68 (8d10 + 24)")
    expect(block).to_contain_text("Challenge: 2 (450 XP)")
    expect(tab.row("Ogre")).to_have_attribute("aria-pressed", "true")
    expect(tab.button("✏️ Edit")).to_be_disabled()
    expect(tab.button("📋 Duplicate")).to_be_enabled()
    expect(tab.page.get_by_role("button", name="Delete creature")).to_have_count(0)
    expect(tab.badge()).to_have_text("0 in Encounter")
    tab.shot("ogre-stat-block")


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-01: odd ability scores below 10 show a modifier one too high",
)
def test_ability_cells_show_the_rules_modifier_for_every_score(tab, bundled):
    tab.select("Ogre")
    for short, key in [
        ("STR", "str"),
        ("DEX", "dex"),
        ("CON", "con"),
        ("INT", "int"),
        ("WIS", "wis"),
        ("CHA", "cha"),
    ]:
        score = bundled["Ogre"]["abilities"][key]
        expect(
            tab.button(f"{short} {score} ({signed(rules_modifier(score))})")
        ).to_be_visible(timeout=1000)


# Rolling from a stat block.


@pytest.mark.cross_browser
def test_ability_check_rolls_straight_advantage_and_disadvantage(app, tab):
    tab.select("Ogre")
    tab.button("STR 19 (+4)").click()
    rolls = wait_for_rolls(tab, 3, "STR check")
    assert_triple_roll(rolls, 4)
    assert all(roll["source"]["target"] == "Ogre" for roll in rolls)
    assert sorted(popup_totals(tab)) == sorted(roll["total"] for roll in rolls)
    tab.shot("triple-roll-popups")


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-01: an INT 5 check rolls with -2 instead of -3",
)
def test_low_ability_check_rolls_with_the_rules_modifier(tab):
    tab.select("Ogre")
    tab.button(re.compile(r"^INT 5 ")).click()
    assert_triple_roll(wait_for_rolls(tab, 3, "INT check"), -3)


def test_saving_throw_rolls_with_the_listed_save_bonus(tab):
    tab.select("Ogre")
    tab.button("INT -3").click()
    rolls = wait_for_rolls(tab, 3, "INT saving throw")
    assert_triple_roll(rolls, -3)


def test_attack_link_rolls_to_hit_three_ways(tab):
    tab.select("Ogre")
    tab.page.get_by_role("button", name="Melee Attack Roll: +6").click()
    rolls = wait_for_rolls(tab, 3, "Attack")
    assert_triple_roll(rolls, 6)


def test_damage_link_rolls_its_dice_once(tab):
    tab.select("Ogre")
    tab.page.get_by_role("button", name="13 (2d8 + 4) Bludgeoning damage").click()
    tab.page.wait_for_function(
        "() => (JSON.parse(localStorage.getItem('diceHistory') || '[]')).length > 0"
    )
    roll = tab.local("diceHistory")[0]
    faces = [die["face"] for die in roll["groups"][0]["rolled"]]
    assert len(faces) == 2
    assert roll["total"] == sum(faces) + 4
    assert 6 <= roll["total"] <= 20


# Sending creatures to the encounter tab.


@pytest.mark.cross_browser
def test_add_to_encounter_reaches_the_encounter_tab_live(app, tab):
    tab.select("Goblin Warrior")
    tab.add_to_encounter()
    tab.add_to_encounter()
    expect(tab.badge()).to_have_text("2 in Encounter")
    expect(tab.row("Goblin Warrior")).to_be_visible()
    tab.shot("two-goblins-added")

    wait_for_cards(app, ["Goblin Warrior", "Goblin Warrior 2"])
    assert app.card("Goblin Warrior 2").max_hp() == 10
    app.shot("encounter-tab-received-them")

    app.reload()
    assert app.card_names() == ["Goblin Warrior", "Goblin Warrior 2"]


def test_badge_follows_creatures_added_and_removed_in_the_encounter_tab(app, tab):
    tab.select("Ogre")
    expect(tab.badge()).to_have_text("0 in Encounter")

    app.add("Ogre", count=2)
    expect(tab.badge()).to_have_text("2 in Encounter")
    expect(tab.row("Ogre").get_by_label("in encounter")).to_be_visible()

    app.card("Ogre 2").remove()
    expect(tab.badge()).to_have_text("1 in Encounter")


def test_add_selected_sends_every_checked_creature(app, tab):
    tab.check("Goblin Warrior")
    tab.check("Ogre")
    tab.select("Ogre")
    tab.button("➕ Add Selected (2)").click()
    expect(tab.toast("Added 2 creatures to encounter")).to_be_visible()
    expect(app.card_boxes()).to_have_count(2)
    assert sorted(app.card_names()) == ["Goblin Warrior", "Ogre"]


@pytest.mark.xfail(
    strict=True, reason="QA-COMP-03: adding one checked creature toasts 'Added 1 creatures'"
)
def test_add_selected_with_one_creature_reads_as_singular(tab):
    tab.check("Ogre")
    tab.select("Ogre")
    tab.button("➕ Add Selected (1)").click()
    expect(tab.toast("Added 1 creature to encounter")).to_be_visible(timeout=2000)


def test_added_filter_narrows_the_list_to_the_encounter(app, tab, bundled):
    app.add("Ogre")
    app.add("Goblin Warrior")
    added = tab.page.get_by_role("button", name="Added", exact=True)
    expect(added).to_have_attribute("aria-pressed", "false")
    added.click()
    expect(added).to_have_attribute("aria-pressed", "true")
    expect(tab.rows()).to_have_count(2)
    assert tab.row_names() == ["Goblin Warrior", "Ogre"]
    tab.shot("added-filter-on")

    added.click()
    expect(tab.rows()).to_have_count(len(bundled))


def test_kind_chips_show_only_the_chosen_kind(tab, bundled):
    tab.new_creature()
    tab.field("Name").fill("Lia the Bard")
    tab.editor().get_by_role("radio", name="Player").check()
    tab.submit("Lia the Bard", "Create")

    tab.kind_chip("Player").click()
    expect(tab.rows()).to_have_count(1)
    assert tab.row_names() == ["Lia the Bard"]
    expect(tab.kind_chip("Player")).to_have_attribute("aria-pressed", "true")
    expect(tab.kind_chip("Enemy")).to_have_attribute("aria-pressed", "false")

    tab.kind_chip("Enemy").click()
    expect(tab.rows()).to_have_count(len(bundled) + 1)

    tab.kind_chip("Player").click()
    expect(tab.rows()).to_have_count(len(bundled))
    assert "Lia the Bard" not in tab.row_names()


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-04: a creature made while signed out sorts last under Newest first",
)
def test_newest_first_puts_a_creature_made_while_signed_out_on_top(tab):
    tab.create("Bog Hag")
    tab.sort_by("Newest first")
    assert tab.row_names()[0] == "Bog Hag"


def test_newest_first_puts_a_creature_made_while_signed_in_on_top(app, signed_in_tab):
    tab = signed_in_tab
    tab.create("Bog Hag")
    tab.sort_by("Newest first")
    assert tab.row_names()[0] == "Bog Hag"


# The keyboard.


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True, reason="QA-COMP-05: the hidden Manage HP panel swallows the page's slash key"
)
def test_slash_jumps_to_the_search_box(tab):
    tab.select("Ogre")
    tab.page.keyboard.press("/")
    expect(tab.search_box()).to_be_focused(timeout=2000)


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True, reason="QA-COMP-05: the hidden Manage HP panel swallows the page's Esc key"
)
def test_escape_backs_out_of_the_reset_dialog(tab):
    tab.button("↺ Reset").click()
    expect(tab.dialog("Reset Compendium")).to_be_visible()
    tab.page.keyboard.press("Escape")
    expect(tab.dialog("Reset Compendium")).to_be_hidden(timeout=2000)


@pytest.mark.cross_browser
def test_escape_closes_the_creature_editor(tab):
    tab.new_creature()
    tab.field("Name").fill("Half-typed")
    tab.page.keyboard.press("Escape")
    expect(tab.editor()).to_be_hidden()
    expect(tab.rows().filter(has_text="Half-typed")).to_have_count(0)


@pytest.mark.cross_browser
def test_clicking_outside_the_clear_dialog_cancels_it(tab, bundled):
    tab.button("🗑 Clear").click()
    dialog = tab.dialog("Clear Compendium")
    expect(dialog).to_be_visible()
    tab.page.mouse.click(5, 5)
    expect(dialog).to_be_hidden()
    expect(tab.rows()).to_have_count(len(bundled))


# Custom creatures.


def add_feature(tab, legend, name, description):
    section = tab.section(legend)
    names = section.get_by_placeholder("Name (e.g. Multiattack)")
    add_row(section, "+ Add Entry", names)
    names.last.fill(name)
    section.get_by_placeholder(re.compile("^Description")).last.fill(description)
    return section


def picker_chip(tab, picker, option):
    """One chip of a multi-select picker.

    The three damage pickers repeat the same chip names with nothing to tell
    them apart.  The picker is found by its label text.
    """
    return (
        tab.editor()
        .locator(".edit-field--picker")
        .filter(has_text=picker)
        .get_by_role("button", name=option, exact=True)
    )


def fill_marsh_troll(tab):
    """A home-brew troll that touches the core of the editor."""
    tab.new_creature()
    tab.field("Name").fill("Marsh Troll")
    tab.editor().get_by_role("combobox", name="Size").select_option(label="Large")
    tab.field("Race").fill("Giant")
    tab.field("Alignment").fill("chaotic evil")
    tab.field("AC").fill("15")
    tab.field("AC Note").fill("natural armor")
    tab.field("Max HP").fill("84")
    tab.field("HP Formula").fill("8d10 + 40")
    tab.field("Init Bonus").fill("1")
    tab.field("Swim").fill("20")
    for short, score in [("STR", 18), ("DEX", 13), ("CON", 20), ("WIS", 9), ("CHA", 7)]:
        tab.ability_field(short).fill(str(score))
    expect(tab.ability_field("CON")).to_have_accessible_name("CON (+5)")

    saves = tab.section("Saving Throws")
    saves.get_by_role("button", name="+ Add Save").click()
    saves.get_by_role("combobox").select_option(label="CON")
    saves.get_by_role("spinbutton", name="Bonus").fill("8")

    skills = tab.section("Skills")
    skills.get_by_role("button", name="+ Add Skill").click()
    skills.get_by_placeholder("Skill name (e.g. Perception)").fill("Perception")
    skills.get_by_role("spinbutton", name="Bonus").fill("2")

    picker_chip(tab, "Damage Resistances", "Fire").click()
    picker_chip(tab, "Condition Immunities", "Frightened").click()
    expect(picker_chip(tab, "Damage Resistances", "Fire")).to_have_attribute(
        "aria-pressed", "true"
    )
    expect(picker_chip(tab, "Damage Immunities", "Fire")).to_have_attribute(
        "aria-pressed", "false"
    )
    tab.field("Challenge Rating").fill("5")
    tab.field("XP").fill("1800")
    tab.field("Languages").fill("Giant")
    tab.field("Darkvision").fill("60")
    tab.field("Passive Perception").fill("12")

    add_feature(tab, "Traits", "Regeneration", "It regains 10 Hit Points at the start of each of its turns.")
    add_feature(
        tab,
        "Actions",
        "Claw",
        "Melee Attack Roll: +7, reach 5 ft. Hit: 9 (1d10 + 4) Slashing damage.",
    )
    breath = add_feature(tab, "Actions", "Fetid Breath", "Each creature in a 15-foot cone makes a DC 15 Constitution save.")
    breath.get_by_label("Usage").last.select_option(label="Recharge")
    breath.get_by_label("Low").fill("5")
    breath.get_by_label("High").fill("6")


def test_new_creature_saves_and_shows_its_stat_block(app, tab):
    fill_marsh_troll(tab)
    tab.shot("marsh-troll-form")
    tab.submit("Marsh Troll", "Create")

    expect(tab.detail_name()).to_have_text("Marsh Troll")
    block = tab.statblock()
    expect(block).to_contain_text("Large Giant, chaotic evil")
    expect(block).to_contain_text("Armor Class: 15 (natural armor)")
    expect(block).to_contain_text("Hit Points: 84 (8d10 + 40)")
    expect(block).to_contain_text("Initiative: +1 (11)")
    expect(block).to_contain_text("Speed: 30 ft., swim 20 ft.")
    expect(block).to_contain_text("Skills: Perception +2")
    expect(block).to_contain_text("Damage Resistances: Fire")
    expect(block).to_contain_text("Condition Immunities: Frightened")
    expect(block).to_contain_text("Senses: darkvision 60 ft., passive Perception 12")
    expect(block).to_contain_text("Challenge: 5 (1,800 XP)")
    expect(block).to_contain_text("Fetid Breath (Recharge 5–6).")
    expect(tab.button("CON 20 (+5)")).to_be_visible()
    expect(tab.button("CON +8")).to_be_visible()
    expect(tab.page.get_by_role("button", name="Melee Attack Roll: +7")).to_be_visible()
    expect(tab.button("✏️ Edit")).to_be_enabled()
    expect(tab.page.get_by_role("button", name="Delete creature")).to_be_visible()
    expect(tab.row("Marsh Troll")).to_be_visible()
    tab.shot("marsh-troll-stat-block")

    saved = tab.local("compendium")
    assert "Marsh Troll" in [creature["name"] for creature in saved["creatures"]]
    tab.page.reload()
    tab.wait_ready()
    expect(tab.row("Marsh Troll")).to_be_visible()


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-06: the encounter tab's Quick Add misses new creatures until reload",
)
def test_new_creature_shows_up_in_quick_add_without_a_reload(app, tab):
    tab.create("Bog Hag", ac="17", hp="82")
    app.page.bring_to_front()
    quick_add = app.panel("Quick Add").open()
    quick_add.root.get_by_role("searchbox", name="Filter Quick Add by name").fill("Bog Hag")
    expect(
        quick_add.root.get_by_role("button", name=re.compile("^Bog Hag CR "))
    ).to_be_visible(timeout=2000)


def test_new_creature_lands_on_a_card_with_its_numbers(app, tab):
    fill_marsh_troll(tab)
    tab.submit("Marsh Troll", "Create")

    app.reload()
    app.add("Marsh Troll")
    troll = app.card("Marsh Troll")
    assert troll.hp() == 84
    assert troll.max_hp() == 84
    assert troll.ac() == 15
    troll.root.get_by_role("button", name="Show stat block").click()
    expect(app.page.get_by_text("Fetid Breath (Recharge 5–6).")).to_be_visible()
    app.shot("marsh-troll-card")


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-06: a card sent from the library has no stat block until reload",
)
def test_new_creature_sent_from_the_library_shows_its_stat_block_on_the_card(app, tab):
    fill_marsh_troll(tab)
    tab.submit("Marsh Troll", "Create")
    tab.add_to_encounter()

    app.page.bring_to_front()
    expect(app.card_boxes()).to_have_count(1)
    app.card("Marsh Troll").root.get_by_role("button", name="Show stat block").click(
        timeout=2000
    )
    app.shot("card-stat-block-opened")
    expect(app.page.get_by_text("Fetid Breath (Recharge 5–6).")).to_be_visible(timeout=2000)


def test_library_and_editor_read_in_the_dark_theme(app):
    app.page.evaluate("() => localStorage.setItem('theme', 'dark')")
    tab = library.open_from(app)
    expect(tab.page.locator("html")).to_have_attribute("data-theme", "dark")
    tab.select("Ogre")
    tab.shot("dark-stat-block")
    tab.new_creature()
    tab.field("Name").fill("Bog Hag")
    tab.shot("dark-editor")
    tab.button("↺ Reset").click()
    expect(tab.dialog("Reset Compendium")).to_be_visible()
    tab.shot("dark-reset-dialog")
    tab.assert_quiet()


def test_editing_a_custom_creature_updates_its_block_and_tags(app, tab):
    tab.create("Bog Hag", ac="17", hp="82")
    tab.button("✏️ Edit").click()
    expect(tab.editor().get_by_role("heading", name="📚 Edit Creature")).to_be_visible()
    expect(tab.field("Max HP")).to_have_value("82")
    tab.field("AC").fill("18")
    tags = tab.section("Tags")
    tags.get_by_role("button", name="+ Add Tag").click()
    tags.get_by_placeholder("tag_name").fill("swamp_lurker")
    loot = tab.section("Loot")
    loot.get_by_role("button", name="+ Add Loot Item").click()
    loot.get_by_placeholder(re.compile("^e.g. Bone necklace")).fill("Rotting toad charm")
    tab.section("Habitats").get_by_role("button", name="Swamp", exact=True).click()
    treasure = tab.section("Treasure").get_by_role("button", name="Relics", exact=True)
    treasure.click()
    expect(treasure).to_have_attribute("aria-pressed", "true")
    tab.submit("Bog Hag")

    block = tab.statblock()
    expect(block).to_contain_text("Armor Class: 18")
    expect(block).to_contain_text("swamp_lurker")
    expect(block).to_contain_text("Rotting toad charm")
    expect(block).to_contain_text("Habitat: Swamp")
    expect(block).to_contain_text("Treasure: Relics")
    assert "AC\xa018" in tab.row_metas()[tab.row_names().index("Bog Hag")]

    tab.tag_filter().select_option(label="swamp_lurker")
    tab.settle()
    assert tab.row_names() == ["Bog Hag"]
    tab.tag_filter().select_option(label="Swamp")
    tab.settle()
    assert "Bog Hag" in tab.row_names()
    tab.shot("edited-bog-hag")


def test_duplicating_a_bundled_creature_makes_an_editable_copy(tab):
    tab.select("Ogre")
    tab.button("📋 Duplicate").click()
    expect(tab.field("Name")).to_have_value("Ogre (copy)")
    expect(tab.field("Max HP")).to_have_value("68")
    tab.field("Name").fill("Ogre Brute")
    tab.field("Max HP").fill("90")
    tab.submit("Ogre Brute", "Create")

    expect(tab.detail_name()).to_have_text("Ogre Brute")
    expect(tab.statblock()).to_contain_text("Hit Points: 90")
    expect(tab.statblock()).to_contain_text("Greatclub.")
    expect(tab.button("✏️ Edit")).to_be_enabled()
    tab.select("Ogre")
    expect(tab.statblock()).to_contain_text("Hit Points: 68")
    expect(tab.button("✏️ Edit")).to_be_disabled()


def test_deleting_from_the_list_asks_before_it_removes(tab):
    tab.create("Bog Hag")
    tab.page.get_by_role("button", name="Delete creature").click()
    expect(
        tab.page.get_by_text('Delete "Bog Hag" from the compendium? This cannot be undone.')
    ).to_be_visible()
    tab.button("Cancel").click()
    expect(tab.row("Bog Hag")).to_be_visible()

    tab.delete_shown()
    expect(tab.toast("Creature deleted")).to_be_visible()
    expect(tab.row("Bog Hag")).to_have_count(0)
    expect(tab.page.get_by_text("Select a creature or group on the left.")).to_be_visible()


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-09: the editor's Delete removes the creature with no confirmation",
)
def test_deleting_from_the_editor_asks_before_it_removes(tab):
    tab.create("Bog Hag")
    tab.button("✏️ Edit").click()
    tab.editor().get_by_role("button", name="🗑 Delete").click()
    tab.settle()
    expect(tab.row("Bog Hag")).to_be_visible(timeout=1000)
    expect(tab.page.get_by_text(re.compile("cannot be undone"))).to_be_visible(timeout=1000)


def test_signed_in_custom_creature_lives_on_the_server(app, signed_in_tab):
    tab = signed_in_tab
    tab.create("Bog Hag", ac="17", hp="82", Challenge_Rating="5")
    assert library.server_creatures(app.page)["Bog Hag"]["armor_class"] == 17
    assert tab.local("compendium") is None

    tab.button("✏️ Edit").click()
    tab.field("AC").fill("19")
    tab.submit("Bog Hag")
    assert library.server_creatures(app.page)["Bog Hag"]["armor_class"] == 19

    tab.page.reload()
    tab.wait_ready()
    tab.select("Bog Hag")
    expect(tab.statblock()).to_contain_text("Armor Class: 19")

    app.reload()
    app.add("Bog Hag")
    assert app.card("Bog Hag").ac() == 19

    tab.page.bring_to_front()
    tab.delete_shown()
    expect(tab.toast("Creature deleted")).to_be_visible()
    assert "Bog Hag" not in library.server_creatures(app.page)


def test_signed_out_creature_follows_the_dm_into_a_new_account(app, tab, bundled):
    tab.create("Bog Hag", ac="17", hp="82", Challenge_Rating="5")
    tab.page.close()
    app.sign_up()
    expect(
        success_toast(app.page, re.compile("Imported 1 creatures? from your pre-sign-in session"))
    ).to_be_visible()
    assert library.server_creatures(app.page)["Bog Hag"]["armor_class"] == 17

    signed_in = library.open_from(app)
    expect(signed_in.row("Bog Hag")).to_be_visible()
    expect(signed_in.rows()).to_have_count(len(bundled) + 1)
    assert signed_in.local("compendium") is None
    signed_in.assert_quiet()


def test_signing_out_and_back_in_keeps_the_accounts_creatures_and_groups(
    app, signed_in_tab
):
    tab = signed_in_tab
    tab.create("Bog Hag", ac="17", hp="82", Challenge_Rating="5")
    library.create_group(tab, "Hag Coven", [("Bog Hag", 1)])
    expect(tab.editor()).to_be_hidden()
    assert [group["name"] for group in library.server_groups(app.page)] == ["Hag Coven"]
    tab.page.close()

    # The app's own sign-out and sign-in both end in a full page load.
    assert api(app.page, "POST", "/api/auth/logout").status == 204
    app.reload()
    app.sign_in()
    app.shot("signed-back-in")

    kept = (
        "Bog Hag" in library.server_creatures(app.page),
        [group["name"] for group in library.server_groups(app.page)],
    )
    assert kept == (True, ["Hag Coven"])


# The editor's validation.


def submit_new(tab):
    tab.editor().get_by_role("button", name="Create", exact=True).click()
    tab.settle()


def test_editor_rejects_a_missing_name_and_non_whole_numbers(tab):
    tab.new_creature()
    submit_new(tab)
    expect(tab.editor().get_by_text("Name is required.")).to_be_visible()

    tab.field("Name").fill("Bog Hag")
    tab.field("AC").fill("15.5")
    submit_new(tab)
    expect(tab.editor().get_by_text("Armor Class must be a whole number.")).to_be_visible()

    tab.field("AC").fill("15")
    tab.field("Max HP").fill("")
    submit_new(tab)
    expect(tab.editor().get_by_text("Max HP must be a whole number.")).to_be_visible()
    expect(tab.row("Bog Hag")).to_have_count(0)


@pytest.mark.xfail(
    strict=True, reason="QA-COMP-07: the editor saves a creature with 0 max HP"
)
def test_editor_rejects_a_creature_with_no_hit_points(tab):
    tab.new_creature()
    tab.field("Name").fill("Hollow Shade")
    tab.field("Max HP").fill("0")
    submit_new(tab)
    expect(tab.editor()).to_be_visible(timeout=1000)
    expect(tab.row("Hollow Shade")).to_have_count(0)


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-08: the editor silently drops a tag with a space and a nameless action",
)
def test_editor_warns_before_dropping_entries_it_cannot_save(tab):
    tab.new_creature()
    tab.field("Name").fill("Bog Hag")
    tags = tab.section("Tags")
    tags.get_by_role("button", name="+ Add Tag").click()
    tags.get_by_placeholder("tag_name").fill("swamp witch")
    actions = tab.section("Actions")
    actions.get_by_role("button", name="+ Add Entry").click()
    actions.get_by_placeholder(re.compile("^Description")).fill("Hit: 7 (2d6) Poison damage.")
    submit_new(tab)
    expect(tab.editor()).to_be_visible(timeout=1000)


def test_advanced_sections_reach_the_stat_block_and_the_card(app, tab):
    tab.new_creature()
    tab.field("Name").fill("Fen Wyrm")
    tab.field("AC").fill("18")
    tab.field("Max HP").fill("150")
    tab.field("Challenge Rating").fill("12")

    legendary = tab.section("Legendary Actions")
    legendary.get_by_role("button", name="+ Add Legendary Actions").click()
    legendary.get_by_label("Uses", exact=True).fill("3")
    legendary.get_by_label("Uses (in lair)").fill("4")
    add_row(legendary, "+ Add Option", legendary.get_by_label("Name"))
    legendary.get_by_label("Name").fill("Tail Swipe")
    legendary.get_by_label("Description").last.fill("Melee Attack Roll: +9. Hit: 13 (2d8 + 4) Bludgeoning damage.")

    lair = tab.section("Lair Actions")
    lair.get_by_role("button", name="+ Add Lair Actions").click()
    lair.get_by_label("Initiative").fill("20")
    lair.get_by_label("Description").first.fill("On initiative count 20 the fen stirs.")
    add_row(lair, "+ Add Option", lair.get_by_label("Name"))
    lair.get_by_label("Name").fill("Sucking Mud")
    lair.get_by_label("Description").last.fill("The ground in a 20-foot square turns to mud.")

    regional = tab.section("Regional Effects")
    regional.get_by_role("button", name="+ Add Regional Effects").click()
    regional.get_by_label("Description").first.fill("The marsh around the lair warps.")
    regional.get_by_label("Fade After").fill("The effects fade over 1d10 days.")
    add_row(regional, "+ Add Effect", regional.get_by_label("Name"))
    regional.get_by_label("Name").fill("Fog Banks")
    regional.get_by_label("Description").last.fill("Thick fog lies within 1 mile.")

    spells = tab.section("Spellcasting")
    spells.get_by_role("button", name="+ Add Spellcasting").click()
    spells.get_by_label("Description").fill("The wyrm casts spells.")
    spells.get_by_role("radio", name="WIS").check()
    spells.get_by_label("Save DC").fill("16")
    spells.get_by_label("Attack Bonus").fill("8")
    spells.get_by_role("textbox", name="At will spells, comma-separated").fill(
        "Light, Thaumaturgy"
    )
    add_row(spells, "+ Add Slot Level", spells.get_by_label("Level"))
    spells.get_by_label("Level").fill("1")
    spells.get_by_label("Slots").fill("2")
    spells.get_by_label("Spells (comma-separated)").first.fill("Bless")
    add_row(spells, "+ Add Innate Group", spells.get_by_label("Uses"))
    spells.get_by_label("Uses").fill("1")
    spells.get_by_label("Spells (comma-separated)").last.fill("Fog Cloud")

    custom = tab.section("Custom Sections")
    add_row(custom, "+ Add Section", custom.get_by_placeholder("Section heading"))
    custom.get_by_placeholder("Section heading").fill("Tactics")
    custom.get_by_role("textbox").last.fill("Fights from deep water.")
    tab.shot("advanced-sections-form")

    tab.submit("Fen Wyrm", "Create")
    block = tab.statblock()
    expect(block).to_contain_text("Legendary Action Uses: 3 (4 in Lair).")
    expect(block).to_contain_text("Tail Swipe.")
    expect(block.get_by_role("button", name="Melee Attack Roll: +9")).to_be_visible()
    expect(block).to_contain_text("Lair Actions")
    expect(block).to_contain_text("Sucking Mud.")
    expect(block).to_contain_text("Regional Effects")
    expect(block).to_contain_text("Fog Banks.")
    expect(block).to_contain_text("The effects fade over 1d10 days.")
    expect(block).to_contain_text(
        "Spellcasting ability: WIS (spell save DC 16, +8 to hit with spell attacks)"
    )
    expect(block).to_contain_text("1st level (2 slots): Bless")
    expect(block).to_contain_text("1/day each: Fog Cloud")
    expect(block).to_contain_text("At will: Light, Thaumaturgy")
    expect(block).to_contain_text("Fights from deep water.")
    tab.shot("advanced-sections-stat-block")

    app.page.bring_to_front()
    app.reload()
    app.add("Fen Wyrm")
    expect(
        app.card("Fen Wyrm").root.get_by_role(
            "button", name=re.compile(r"^Legendary Action: \d of \d remaining")
        )
    ).to_be_visible()
    app.shot("fen-wyrm-card")


# Pasting a stat block.

HOME_BREW_BLOCK = """Mire Stalker
Medium monstrosity, neutral evil
Armor Class 14 (natural armor)
Hit Points 45 (6d8 + 18)
Speed 30 ft., swim 30 ft.
STR 16 (+3) DEX 14 (+2) CON 16 (+3) INT 6 (-2) WIS 12 (+1) CHA 7 (-2)
Senses darkvision 60 ft., passive Perception 11
Languages --
Challenge 3 (700 XP)"""


def test_pasted_stat_block_previews_and_fills_the_editor(app, tab):
    tab.button("📋 Paste Stat Block").click()
    paste = tab.editor()
    apply = paste.get_by_role("button", name="Apply to Form")
    expect(paste.get_by_text("Paste a stat block to see the live preview.")).to_be_visible()
    expect(apply).to_be_disabled()

    box = paste.get_by_role("textbox")
    box.fill("Mire Stalker")
    expect(paste.get_by_text(re.compile("^Need at least two lines"))).to_be_visible()
    expect(apply).to_be_disabled()

    box.fill(HOME_BREW_BLOCK)
    preview = paste.locator(".statblock")
    expect(preview).to_contain_text("Medium Monstrosity")
    expect(preview).to_contain_text("Armor Class: 14 (natural armor)")
    expect(preview).to_contain_text("Hit Points: 45 (6d8 + 18)")
    expect(preview).to_contain_text("Challenge: 3 (700 XP)")
    tab.shot("paste-preview")

    apply.click()
    expect(tab.editor().get_by_role("heading", name="📚 New Creature")).to_be_visible()
    expect(tab.field("Name")).to_have_value("Mire Stalker")
    expect(tab.field("AC")).to_have_value("14")
    expect(tab.field("Max HP")).to_have_value("45")
    expect(tab.field("Swim")).to_have_value("30")
    expect(tab.ability_field("STR")).to_have_value("16")
    tab.submit("Mire Stalker", "Create")
    expect(tab.row("Mire Stalker")).to_be_visible()


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-16: a pasted block with no Initiative line gets +0, not its DEX modifier",
)
def test_pasted_block_without_an_initiative_line_rolls_initiative_off_dex(tab):
    tab.button("📋 Paste Stat Block").click()
    tab.editor().get_by_role("textbox").fill(HOME_BREW_BLOCK)
    tab.editor().get_by_role("button", name="Apply to Form").click()
    expect(tab.field("Init Bonus")).to_have_value("2", timeout=2000)


# Export, import and the destructive bulk actions.


def export_to_file(tab, tmp_path, filename):
    tab.button("📤 Export").click()
    dialog = tab.dialog("Save Compendium")
    expect(dialog.get_by_role("radio", name="Device")).to_be_checked()
    dialog.get_by_label("Filename").fill(filename)
    with tab.page.expect_download() as download_info:
        dialog.get_by_role("button", name="Save", exact=True).click()
    download = download_info.value
    path = tmp_path / download.suggested_filename
    download.save_as(path)
    return download, path


def import_from_file(tab, path):
    tab.button("📥 Import").click()
    dialog = tab.dialog("Load Compendium")
    dialog.get_by_role("radio", name="Device").check()
    with tab.page.expect_file_chooser() as chooser_info:
        dialog.get_by_role("button", name="📁 Choose file…").click()
    chooser_info.value.set_files(str(path))
    return dialog


def close_dialog(dialog):
    """Presses the dialog's own Close button.

    The corner cross is a different button.
    """
    dialog.get_by_role("button", name="Close").filter(has_text="Close").click()
    expect(dialog).to_be_hidden()


def exported_bog_hag(tab, tmp_path, bundled):
    tab.create("Bog Hag", ac="17", hp="82")
    download, path = export_to_file(tab, tmp_path, "Swamp Bestiary")
    assert download.suggested_filename == "Swamp Bestiary.json"
    saved = json.loads(path.read_text())
    assert len(saved["creatures"]) == len(bundled) + 1
    assert "Bog Hag" in [creature["name"] for creature in saved["creatures"]]
    tab.delete_shown()
    expect(tab.row("Bog Hag")).to_have_count(0)
    return path


@pytest.mark.cross_browser
def test_export_then_import_round_trips_the_library(app, tab, tmp_path, bundled):
    path = exported_bog_hag(tab, tmp_path, bundled)
    dialog = import_from_file(tab, path)
    expect(
        tab.page.get_by_text(
            f"Import {len(bundled) + 1} creatures? This REPLACES the entire current library."
        )
    ).to_be_visible()
    tab.shot("import-confirm-behind-dialog")
    close_dialog(dialog)
    tab.button("Replace library").click()
    expect(tab.toast(f"Imported {len(bundled) + 1} creatures")).to_be_visible()
    expect(tab.row("Bog Hag")).to_be_visible()
    expect(tab.rows()).to_have_count(len(bundled) + 1)


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-11: the import confirmation sits behind the Load Compendium dialog",
)
def test_import_confirmation_is_reachable_from_the_load_dialog(tab, tmp_path, bundled):
    path = exported_bog_hag(tab, tmp_path, bundled)
    import_from_file(tab, path)
    tab.button("Replace library").click(trial=True, timeout=2000)


@pytest.mark.cross_browser
def test_importing_a_file_that_is_not_a_compendium_changes_nothing(app, tab, tmp_path, bundled):
    tab.create("Bog Hag")
    junk = tmp_path / "shopping-list.json"
    junk.write_text('{"eggs": 12}')
    dialog = import_from_file(tab, junk)
    expect(tab.page.get_by_text(re.compile("compatibility issues"))).to_be_visible()
    tab.shot("import-junk")
    close_dialog(dialog)
    tab.button("OK").click()
    expect(tab.rows()).to_have_count(len(bundled) + 1)
    expect(tab.row("Bog Hag")).to_be_visible()


def test_reset_asks_first_then_returns_to_the_bundled_library(app, tab, bundled):
    tab.create("Bog Hag")
    tab.button("↺ Reset").click()
    dialog = tab.dialog("Reset Compendium")
    expect(dialog).to_contain_text("Every custom creature will be discarded")
    tab.shot("reset-confirm")
    dialog.get_by_role("button", name="Cancel").click()
    expect(dialog).to_be_hidden()
    expect(tab.row("Bog Hag")).to_be_visible()

    tab.button("↺ Reset").click()
    dialog.get_by_role("button", name="Reset", exact=True).click()
    expect(tab.row("Bog Hag")).to_have_count(0)
    expect(tab.rows()).to_have_count(len(bundled))


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-10: the Reset dialog promises 'the original 5 creatures' of 330",
)
def test_reset_dialog_counts_the_bundled_creatures_it_restores(tab, bundled):
    tab.button("↺ Reset").click()
    expect(tab.dialog("Reset Compendium")).to_contain_text(
        f"original {len(bundled)} creatures", timeout=1000
    )


def test_clear_selected_and_clear_all_empty_the_library(app, tab, bundled):
    tab.check("Aboleth")
    tab.check("Ogre")
    tab.button("🗑 Clear").click()
    dialog = tab.dialog("Clear Compendium")
    expect(dialog).to_contain_text("Bundled creatures go too")
    dialog.get_by_role("button", name="Clear Selected (2)").click()
    expect(dialog).to_be_hidden()
    expect(tab.rows()).to_have_count(len(bundled) - 2)
    expect(tab.row("Ogre")).to_have_count(0)

    tab.button("🗑 Clear").click()
    expect(dialog.get_by_role("button", name=re.compile("^Clear Selected"))).to_have_count(0)
    dialog.get_by_role("button", name="Clear All").click()
    expect(tab.page.get_by_text("Your compendium is empty.")).to_be_visible()
    expect(tab.button("creating one")).to_be_visible()
    tab.shot("library-cleared")

    tab.button("↺ Reset").click()
    tab.dialog("Reset Compendium").get_by_role("button", name="Reset", exact=True).click()
    expect(tab.rows()).to_have_count(len(bundled))


def clear_all(tab):
    tab.button("🗑 Clear").click()
    tab.dialog("Clear Compendium").get_by_role("button", name="Clear All").click()
    expect(tab.page.get_by_text("Your compendium is empty.")).to_be_visible()


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-12: a signed-out Clear All is undone by a reload",
)
def test_cleared_library_stays_empty_after_a_reload(tab):
    clear_all(tab)
    tab.page.reload()
    expect(tab.page.get_by_text("Your compendium is empty.")).to_be_visible()
    expect(tab.rows()).to_have_count(0, timeout=2000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-12: a signed-in Clear All toasts 0 creatures and keeps all 330",
)
def test_signed_in_clear_all_empties_the_library(app, signed_in_tab):
    tab = signed_in_tab
    tab.button("🗑 Clear").click()
    tab.dialog("Clear Compendium").get_by_role("button", name="Clear All").click()
    expect(tab.toast("Library now has 0 creatures")).to_be_visible()
    expect(tab.rows()).to_have_count(0, timeout=2000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-COMP-13: every fresh sign-in toasts a Save Chain decode error",
)
def test_signed_in_library_opens_without_an_error_toast(app, signed_in_tab):
    tab = signed_in_tab
    tab.select("Ogre")
    expect(error_toasts(tab.page)).to_have_count(0, timeout=2000)


def test_delete_selected_removes_every_checked_custom_creature(tab, bundled):
    tab.create("Bog Hag")
    tab.create("Mire Stalker")
    tab.create("Fen Wyrm")
    tab.check("Bog Hag")
    tab.check("Mire Stalker")
    tab.select("Bog Hag")
    tab.page.get_by_role("button", name="Delete creature").click()
    tab.button("Delete Selected (2)").click()
    expect(tab.row("Bog Hag")).to_have_count(0)
    expect(tab.row("Mire Stalker")).to_have_count(0)
    expect(tab.row("Fen Wyrm")).to_be_visible()
    expect(tab.rows()).to_have_count(len(bundled) + 1)


# Named snapshots on the server.


# A server snapshot save took 2 seconds on an idle machine and 26 under
# load from other suites.  The figure is a guess with room above that.
SNAPSHOT_MS = 60_000


def save_snapshot(tab, name):
    tab.button("📤 Export").click()
    dialog = tab.dialog("Save Compendium")
    dialog.get_by_role("radio", name="Server").check()
    dialog.get_by_label("Save name").fill(name)
    dialog.get_by_role("button", name="Save", exact=True).click()
    return dialog


def test_server_snapshot_saves_and_loads_back(app, signed_in_tab):
    tab = signed_in_tab
    tab.create("Bog Hag")
    save_snapshot(tab, "Swamp Bestiary")
    expect(tab.toast('Saved compendium "Swamp Bestiary".')).to_be_visible(timeout=SNAPSHOT_MS)

    tab.create("Mire Stalker")
    tab.delete_shown()
    tab.select("Bog Hag")
    tab.delete_shown()
    expect(tab.row("Bog Hag")).to_have_count(0)
    tab.create("Fen Wyrm")

    tab.button("📥 Import").click()
    dialog = tab.dialog("Load Compendium")
    dialog.get_by_role("radio", name="Server").check()
    dialog.get_by_role("button", name="Swamp Bestiary").click()
    expect(dialog).to_contain_text('Load "Swamp Bestiary"? This replaces the current compendium.')
    tab.shot("load-snapshot-confirm")
    dialog.get_by_role("button", name="Load", exact=True).click()
    expect(tab.toast('Loaded compendium "Swamp Bestiary".')).to_be_visible(timeout=SNAPSHOT_MS)
    expect(tab.row("Bog Hag")).to_be_visible()
    expect(tab.row("Fen Wyrm")).to_have_count(0)
    tab.page.reload()
    tab.wait_ready()
    expect(tab.row("Bog Hag")).to_be_visible()
    expect(tab.row("Fen Wyrm")).to_have_count(0)


def test_saving_over_a_snapshot_name_asks_to_overwrite(app, signed_in_tab):
    tab = signed_in_tab
    save_snapshot(tab, "Swamp Bestiary")
    expect(tab.toast('Saved compendium "Swamp Bestiary".')).to_be_visible(timeout=SNAPSHOT_MS)
    dialog = save_snapshot(tab, "Swamp Bestiary")
    expect(dialog).to_contain_text(
        'Overwrite "Swamp Bestiary" with the current compendium?', timeout=SNAPSHOT_MS
    )
    dialog.get_by_role("button", name="Overwrite", exact=True).filter(
        has_text="Overwrite"
    ).click()
    expect(dialog).to_be_hidden(timeout=SNAPSHOT_MS)
    saves = api(tab.page, "GET", "/api/compendium/saves").json()
    assert [save["name"] for save in saves] == ["Swamp Bestiary"]


def test_signed_out_dm_is_told_to_sign_in_for_server_snapshots(tab):
    tab.button("📤 Export").click()
    dialog = tab.dialog("Save Compendium")
    dialog.get_by_role("radio", name="Server").check()
    expect(dialog).to_contain_text("Sign in to save your compendium to the eZpZ-dndZ server.")
    expect(dialog.get_by_role("button", name="Save", exact=True)).to_be_disabled()
    close_dialog(dialog)

    tab.button("📥 Import").click()
    dialog = tab.dialog("Load Compendium")
    dialog.get_by_role("radio", name="Server").check()
    expect(dialog).to_contain_text("Sign in to load your compendium from the eZpZ-dndZ server.")
