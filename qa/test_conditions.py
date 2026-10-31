"""The Condition/Effect editor and the chips it puts on cards."""

import re

import pytest
from playwright.sync_api import expect

from pages.fight import (
    ConditionEditor,
    ManageHp,
    advance,
    chip,
    chip_names,
    expect_pools,
    freeze_clock,
    hp_button,
    select,
    subtitle,
)
from pages.ui import Dice

A, B, C = "Goblin Warrior", "Goblin Warrior 2", "Goblin Warrior 3"


def three_goblins_in_combat(app):
    app.add("Goblin Warrior", count=3)
    app.begin_combat()
    assert app.active_name() == A


def expect_chip(app, name, label, present=True):
    expect(chip(app.card(name), label)).to_have_count(1 if present else 0)


def saved_notice(card, condition):
    return card.root.get_by_text(re.compile(f"^Saved: {condition}"))


def test_a_standard_condition_lands_as_a_chip_with_its_note(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Poisoned").note("from Lyra").apply()
    assert chip_names(app.card("Ogre")) == ["Poisoned (from Lyra)"]
    assert cond.log()[0] == "Poisoned Ogre Manual · from Lyra"
    app.shot("chip")


def test_a_custom_condition_lands_under_its_own_name(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.custom("Burning").note("1d4 fire").apply()
    assert chip_names(app.card("Ogre")) == ["Burning (1d4 fire)"]


def test_the_quick_apply_caret_applies_and_folds_the_editor(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Prone")
    cond.root.get_by_role("button", name="Quick apply to target, with note").click()
    expect_chip(app, "Ogre", "Prone")
    expect(cond.panel.fold_button()).to_have_attribute("aria-expanded", "false")


def apply_anew(cond, condition, scope="Target"):
    """Leaves the condition the editor just applied and applies one anew."""
    cond.root.get_by_role("button", name="New condition").click()
    cond.pick(condition).apply(scope)


def test_a_creature_cannot_take_the_same_condition_twice(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")
    cond.pick("Prone").apply()

    apply_anew(cond, "Prone")
    expect(app.page.get_by_text("Ogre already has Prone.")).to_be_visible()
    app.shot("already-has")
    assert chip_names(app.card("Ogre")) == ["Prone"]


def test_a_condition_on_a_selection_skips_the_creature_that_has_it(app):
    app.add("Ogre")
    app.add("Goblin Warrior")
    select(app, "Ogre", "Goblin Warrior")
    ConditionEditor(app).open_for("Goblin Warrior").pick("Prone").apply()

    ConditionEditor(app).open_for("Ogre").pick("Prone").apply("Selected (2)")
    expect(app.page.get_by_text("Skipped Goblin Warrior: it already has Prone.")).to_be_visible()
    assert chip_names(app.card("Goblin Warrior")) == ["Prone"]
    assert chip_names(app.card("Ogre")) == ["Prone"]


def test_exhaustion_on_a_creature_that_has_it_adds_a_level(app):
    app.add("Ogre")
    app.add("Goblin Warrior")
    select(app, "Ogre", "Goblin Warrior")
    cond = ConditionEditor(app).open_for("Ogre")
    cond.pick("Exhaustion").apply()

    apply_anew(cond, "Exhaustion", "Selected (2)")
    expect(app.page.get_by_text("Ogre gains an Exhaustion level.")).to_be_visible()
    for name, level in (("Ogre", 2), ("Goblin Warrior", 1)):
        badge = app.card(name).root.get_by_role("button", name=re.compile("^Exhaustion level "))
        expect(badge).to_have_accessible_name(f"Exhaustion level {level}")


def test_a_second_condition_on_the_same_creature_is_added_beside_the_first(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")
    cond.pick("Poisoned").apply()

    cond = ConditionEditor(app).open_for("Ogre")
    cond.pick("Prone")
    expect(cond.root.get_by_role("button", name="Target", exact=True)).to_be_visible(timeout=2000)
    cond.apply()
    assert chip_names(app.card("Ogre")) == ["Poisoned", "Prone"]


def test_new_condition_leaves_the_edited_one_and_adds_another(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")
    cond.pick("Poisoned").apply()
    expect(cond.root.get_by_role("button", name="Apply Changes")).to_be_visible()

    cond.root.get_by_role("button", name="New condition").click()
    cond.pick("Prone")
    cond.apply()
    assert chip_names(app.card("Ogre")) == ["Poisoned", "Prone"]


def test_until_the_end_of_another_creatures_next_turn_ends_with_that_turn(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(C)

    cond.pick("Frightened").duration("Next turn").phase("end").turns_of(B).apply()
    expect_chip(app, C, "Frightened")
    app.next_turn()
    expect_chip(app, C, "Frightened")
    app.next_turn()
    assert app.active_name() == C
    expect_chip(app, C, "Frightened", present=False)


def test_until_the_end_of_the_bearers_next_turn_outlasts_the_current_one(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.pick("Blinded").duration("Next turn").phase("end").turns_of(A).apply()
    advance(app, 3)
    assert (app.round_number(), app.active_name()) == (2, A)
    expect_chip(app, A, "Blinded")
    app.next_turn()
    expect_chip(app, A, "Blinded", present=False)


def test_until_the_start_of_a_creatures_next_turn_ends_as_that_turn_begins(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(B)

    cond.pick("Prone").duration("Next turn").phase("beginning").turns_of(A).apply()
    advance(app, 2)
    expect_chip(app, B, "Prone")
    app.next_turn()
    assert (app.round_number(), app.active_name()) == (2, A)
    expect_chip(app, B, "Prone", present=False)


def test_a_countdown_runs_out_after_its_number_of_the_bearers_turns(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(B)

    cond.pick("Restrained").duration("Countdown").countdown(2).phase("end").apply()
    for _ in range(4):
        app.next_turn()
        expect_chip(app, B, "Restrained")
    assert (app.round_number(), app.active_name()) == (2, B)
    app.next_turn()
    expect_chip(app, B, "Restrained", present=False)


def test_one_minute_lasts_ten_of_the_bearers_turns_after_this_one(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.custom("Bless").duration("1 Minute").apply()
    advance(app, 30)
    assert (app.round_number(), app.active_name()) == (11, A)
    expect_chip(app, A, "Bless")
    app.next_turn()
    expect_chip(app, A, "Bless", present=False)


def test_a_save_at_the_end_of_turn_ends_the_condition_and_posts_a_notice(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.pick("Poisoned").save_to_end("CON", dc=1, auto="End of turn").apply()
    expect_chip(app, A, "Poisoned")
    app.next_turn()
    expect_chip(app, A, "Poisoned", present=False)
    notice = saved_notice(app.card(A), "Poisoned")
    expect(notice).to_be_visible()
    app.shot("saved-notice")
    advance(app, 3)
    expect(notice).to_have_count(0)


def test_each_end_of_turn_save_rolls_its_own_d20(app):
    three_goblins_in_combat(app)
    conditions = ["Blinded", "Charmed", "Deafened", "Frightened", "Poisoned", "Prone"]
    for name in conditions:
        # A fresh aim is the only way back to adding rather than editing.
        ConditionEditor(app).open_for(B)
        ConditionEditor(app).open_for(A).pick(name).save_to_end("CON", dc=99, auto="End of turn").apply()
    assert chip_names(app.card(A)) == conditions

    freeze_clock(app)
    app.next_turn()
    dice = Dice(app).open()
    rolls = dice.root.locator(".dice-history__formula").filter(has_text="Save: CON DC 99")
    expect(rolls).to_have_count(6)
    faces = [re.search(r"1d20:\((\d+)\)", text).group(1) for text in rolls.all_text_contents()]
    assert len(set(faces)) >= 3, f"Six saves rolled {faces}"


def test_a_save_notice_dismisses_with_its_cross(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.pick("Poisoned").save_to_end("CON", dc=1, auto="End of turn").apply()
    app.next_turn()
    card = app.card(A)
    expect(saved_notice(card, "Poisoned")).to_be_visible()
    card.root.get_by_role("button", name="Dismiss save notice").click()
    expect(saved_notice(card, "Poisoned")).to_have_count(0)


def test_a_save_at_the_start_of_turn_rolls_as_the_turn_begins(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(B)

    cond.pick("Charmed").save_to_end("WIS", dc=1, auto="Start of turn").apply()
    app.next_turn()
    expect_chip(app, B, "Charmed", present=False)
    expect(saved_notice(app.card(B), "Charmed")).to_be_visible()


def test_a_manual_save_waits_for_the_chip_d20(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.pick("Stunned").save_to_end("CON", dc=1, auto="Manual").apply()
    advance(app, 3)
    expect_chip(app, A, "Stunned")
    app.card(A).root.get_by_role("button", name="Roll save for Stunned").click()
    expect_chip(app, A, "Stunned", present=False)
    expect(saved_notice(app.card(A), "Stunned")).to_be_visible()


def test_ask_at_end_of_turn_flashes_the_chip_instead_of_rolling(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(A)

    cond.pick("Frightened").save_to_end("WIS", dc=1, auto="Ask at end of turn").apply()
    app.next_turn()
    flashing = chip(app.card(A), "Frightened")
    # The reminder is a pulse with no text or role a reader can find.
    expect(flashing).to_have_class(re.compile("condition-chip--flash"))
    expect(flashing).not_to_have_class(re.compile("condition-chip--flash"), timeout=5000)
    expect_chip(app, A, "Frightened")


def test_a_failed_save_deals_its_damage_and_turns_into_another_condition(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Restrained").save_to_end("CON", dc=99, auto="Manual").on_fail(damage=7, becomes="Petrified").apply()
    ogre.root.get_by_role("button", name="Roll save for Restrained").click()
    expect_pools(ogre, 61, 68)
    assert chip_names(ogre) == ["Petrified"]
    expect(ogre.root.get_by_role("button", name=re.compile("^Roll save for"))).to_have_count(0)
    app.shot("petrified")


def test_a_failed_save_rolls_its_damage_formula(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.custom("Acid").save_to_end("CON", dc=99, auto="Manual").on_fail(damage="2d4").apply()
    ogre.root.get_by_role("button", name="Roll save for Acid").click()
    expect(hp_button(ogre, "Current")).not_to_have_text("68")
    assert 60 <= ogre.hp() <= 66
    assert chip_names(ogre) == ["Acid"]


def test_taking_damage_rolls_the_save_when_the_condition_says_so(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Charmed").save_to_end("WIS", dc=1).when_damaged("Roll the save").apply()
    ManageHp(app).open_for("Ogre").damage(5)
    expect_chip(app, "Ogre", "Charmed", present=False)
    expect(saved_notice(app.card("Ogre"), "Charmed")).to_be_visible()


def test_taking_damage_flashes_the_chip_when_the_condition_says_so(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Charmed").save_to_end("WIS", dc=1).when_damaged("Flash the chip").apply()
    ManageHp(app).open_for("Ogre").damage(5)
    expect(chip(app.card("Ogre"), "Charmed")).to_have_class(re.compile("condition-chip--flash"))
    expect_chip(app, "Ogre", "Charmed")


def test_exhaustion_climbs_a_level_a_click_and_wraps_after_six(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    ConditionEditor(app).open_for("Ogre").pick("Exhaustion").apply()

    level = ogre.root.get_by_role("button", name=re.compile("^Exhaustion level "))
    expect(level).to_have_accessible_name("Exhaustion level 1")
    for step in range(2, 7):
        level.click()
        expect(level).to_have_accessible_name(f"Exhaustion level {step}")
    app.shot("exhaustion-six")
    level.click()
    expect(level).to_have_accessible_name("Exhaustion level 0")


@pytest.mark.cross_browser
def test_a_companion_condition_ends_with_its_main_condition(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.pick("Charmed")
    cond.root.get_by_role("button", name="+ With").click()
    companion = cond.root.get_by_label("With:")
    expect(companion).to_be_focused()
    companion.fill("Incapacitated")
    companion.press("Enter")
    expect(cond.root.get_by_role("button", name="Remove Incapacitated")).to_be_visible()
    cond.apply()
    assert chip_names(ogre) == ["Charmed", "Incapacitated"]
    assert cond.log()[0] == "Charmed Ogre Manual · with Incapacitated"

    chip(ogre, "Charmed").get_by_role("button", name="Remove Charmed from Ogre").click()
    assert chip_names(ogre) == []


def test_removing_a_chip_and_undoing_an_apply(app):
    app.add("Ogre")
    app.add("Goblin Warrior")
    ogre = app.card("Ogre")

    ConditionEditor(app).open_for("Ogre").pick("Blinded").apply()
    chip(ogre, "Blinded").get_by_role("button", name="Remove Blinded from Ogre").click()
    assert chip_names(ogre) == []

    cond = ConditionEditor(app).open_for("Goblin Warrior").pick("Deafened").apply()
    assert chip_names(app.card("Goblin Warrior")) == ["Deafened"]
    cond.undo()
    assert chip_names(app.card("Goblin Warrior")) == []
    assert cond.log()[0] == "Blinded Ogre Manual"


def test_conditions_land_on_every_selected_creature(app):
    app.add("Goblin Warrior", count=3)
    select(app, A, C)
    cond = ConditionEditor(app).open_for(B)

    cond.pick("Prone").apply("Selected (2)")
    assert [chip_names(app.card(n)) for n in (A, B, C)] == [["Prone"], [], ["Prone"]]
    assert cond.log()[0] == f"Prone {A}, {C} Manual"


def test_editing_a_chip_changes_that_condition_in_place(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    ConditionEditor(app).open_for("Ogre").pick("Grappled").note("by Ogre").apply()
    app.panel("Condition/Effect").fold()

    ogre.root.get_by_role("button", name="Grappled (by Ogre)").click()
    cond = ConditionEditor(app)
    expect(cond.root.get_by_role("button", name="Apply Changes")).to_be_visible()
    cond.note("by Troll")
    cond.root.get_by_role("button", name="Apply Changes").click()
    expect(ogre.root.get_by_role("button", name="Grappled (by Troll)")).to_be_visible()
    assert chip_names(ogre) == ["Grappled (by Troll)"]


def test_a_bundled_preset_fills_the_form(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    menu = cond.load_menu()
    menu.get_by_role("searchbox", name="Search presets").fill("Hold Person")
    menu.get_by_role("option", name="Hold Person", exact=True).click()
    expect(cond.root.get_by_text("Loaded: Hold Person")).to_be_visible()
    expect(cond.root.get_by_role("radio", name=re.compile("^Paralyzed"))).to_be_checked()
    expect(cond.root.get_by_label("Lasts")).to_have_value("10")
    expect(cond.root.get_by_label("DC", exact=True)).to_have_value("13")
    expect(cond.root.get_by_label("Ability")).to_have_value("WIS")
    cond.apply()
    expect(app.card("Ogre").root.get_by_role("button", name="Roll save for Paralyzed")).to_be_visible()


def test_a_dm_saves_loads_and_deletes_a_preset(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")

    cond.custom("Burning").note("1d4 fire").duration("Countdown").countdown(3)
    cond.save_preset("Burning oil", "Items")
    expect(cond.root.get_by_text("Loaded: Burning oil")).to_be_visible()

    cond.root.get_by_role("button", name="Clear Settings").click()
    expect(cond.root.get_by_placeholder("e.g. Burning")).to_have_value("")
    menu = cond.load_menu()
    menu.get_by_role("button", name=re.compile("^▶ ?Items")).click()
    menu.get_by_role("option", name="Burning oil").click()
    expect(cond.root.get_by_placeholder("e.g. Burning")).to_have_value("Burning")
    expect(cond.root.get_by_label("Lasts")).to_have_value("3")
    app.shot("preset-loaded")

    menu = cond.load_menu()
    menu.get_by_role("searchbox", name="Search presets").fill("burning oil")
    menu.get_by_role("button", name="Delete preset Burning oil").click()
    expect(menu.get_by_text("No presets match")).to_be_visible()


def test_restoring_bundled_presets_keeps_the_dms_own(app):
    app.add("Ogre")
    cond = ConditionEditor(app).open_for("Ogre")
    cond.custom("Marked").save_preset("Marked", "Player Classes")

    menu = cond.load_menu()
    menu.get_by_role("button", name="Restore bundled presets").click()
    expect(app.page.get_by_text(re.compile("^Restored \\d+ bundled presets"))).to_be_visible()
    menu = cond.load_menu()
    menu.get_by_role("searchbox", name="Search presets").fill("Marked")
    expect(menu.get_by_role("option", name="Marked", exact=True)).to_be_visible()


def test_a_condition_being_built_survives_the_next_turn(app):
    three_goblins_in_combat(app)
    cond = ConditionEditor(app).open_for(B)
    cond.custom("Burning").note("1d4 fire").duration("Countdown").countdown(3)

    app.next_turn()
    expect(subtitle(cond.panel)).to_have_text(f"Target: {B}")
    expect(cond.root.get_by_placeholder("e.g. Burning")).to_have_value("Burning", timeout=2000)
    expect(cond.root.get_by_label("Lasts")).to_have_value("3", timeout=2000)
