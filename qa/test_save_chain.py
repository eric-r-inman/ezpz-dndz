"""Save Chain is a beta editor.

It runs one save and what each side of it does.
"""

import re

import pytest
from playwright.sync_api import expect

from pages.fight import SaveChain, chip, chip_names, expect_pools, hp_button, select

FAIL, PASS = "On failed save", "On successful save"

# A batch of one advantage roll at this instant rolls a 3 and a 17.
SPLIT_D20S_AT = "2027-01-01T00:00:00.018Z"


def two_ogres(app):
    app.add("Ogre", count=2)
    return app.card("Ogre"), app.card("Ogre 2")


def test_a_failed_save_takes_the_damage_and_a_pass_takes_half_rounded_down(app):
    ogre, ogre2 = two_ogres(app)
    chain = SaveChain(app).name("Flame Jet").ability("DEX").dc(15)
    chain.hp(FAIL, "Damage", 27).hp(PASS, "Half of Fail damage")

    chain.press("Fail")
    expect_pools(ogre, 41, 68)
    select(app, "Ogre 2")
    chain.scope_selected(1).press("Pass")
    expect_pools(ogre2, 55, 68)
    assert chain.log()[:2] == [("PASS", "Ogre 2", "13 damage applied"), ("FAIL", "Ogre", "27 damage applied")]
    app.shot("fail-and-pass")


def test_a_fail_formula_is_rolled_and_a_pass_halves_a_roll_of_it(app):
    ogre, ogre2 = two_ogres(app)
    chain = SaveChain(app).name("Fire").ability("DEX").dc(15)
    chain.hp(FAIL, "Damage", "8d6").hp(PASS, "Half of Fail damage")

    chain.press("Fail")
    expect(hp_button(ogre, "Current")).not_to_have_text("68")
    assert 68 - 48 <= ogre.hp() <= 68 - 8
    select(app, "Ogre 2")
    chain.scope_selected(1).press("Pass")
    expect(hp_button(ogre2, "Current")).not_to_have_text("68")
    assert 68 - 24 <= ogre2.hp() <= 68 - 4


def test_drain_lowers_the_maximum_by_the_damage_dealt(app):
    ogre, _ = two_ogres(app)
    chain = SaveChain(app).name("Life Drain").ability("CON").dc(13)
    chain.hp(FAIL, "Drain", 10)

    chain.press("Fail")
    expect_pools(ogre, 58, 58)
    assert chain.log()[0] == ("FAIL", "Ogre", "10 damage applied; max HP lowered")
    expect(ogre.root.get_by_text("(68)")).to_be_visible()


def test_a_heal_outcome_restores_hit_points(app):
    ogre, _ = two_ogres(app)
    chain = SaveChain(app).name("Soothing Mist").dc(10)
    chain.hp(FAIL, "Damage", 20).hp(PASS, "Heal", 6)

    chain.press("Fail").press("Pass")
    expect_pools(ogre, 54, 68)


def test_an_effect_with_save_to_end_lands_as_a_chip_that_rolls_its_save(app):
    ogre, _ = two_ogres(app)
    chain = SaveChain(app).name("Stare").ability("WIS")
    chain.add_effect(FAIL, "Paralyzed", save_to_end=True)

    expect(chain.button("Fail")).to_be_disabled()
    chain.dc(13).press("Fail")
    assert chip_names(ogre) == ["Paralyzed"]
    expect(ogre.root.get_by_role("button", name="Roll save for Paralyzed")).to_be_visible()
    app.shot("effect-chip")


def test_an_effect_lasts_for_its_chosen_duration(app):
    app.add("Goblin Warrior", count=2)
    app.begin_combat()
    chain = SaveChain(app).name("Daze").dc(12)
    effect = chain.add_effect(FAIL, "Dazed")
    effect.get_by_role("radio", name="This turn", exact=True).click()

    chain.press("Fail")
    assert chip_names(app.card("Goblin Warrior")) == ["Dazed"]
    app.next_turn()
    assert chip_names(app.card("Goblin Warrior")) == []


def test_a_successful_save_can_grant_immunity_to_the_chain(app):
    ogre, _ = two_ogres(app)
    chain = SaveChain(app).name("Horrify").ability("WIS").dc(14)
    chain.add_effect(FAIL, "Frightened")
    chain.root.get_by_role("checkbox", name="Grants immunity").click()

    chain.press("Pass")
    assert chip_names(ogre) == ["Immune: Horrify"]
    chain.press("Fail")
    assert chip_names(ogre) == ["Immune: Horrify"]
    assert chain.log()[0] == ("FAIL", "Ogre", "immune", "(no effect)")


def test_rolled_saves_send_each_target_down_its_side(app):
    app.add("Goblin Warrior", count=2)
    select(app, "Goblin Warrior", "Goblin Warrior 2")
    chain = SaveChain(app).name("Dart").ability("DEX").scope_selected(2)
    chain.hp(FAIL, "Damage", 4)

    chain.dc(1).press("🎲 Roll saves")
    expect(chain.root.get_by_text("PASS", exact=True)).to_have_count(2)
    expect_pools(app.card("Goblin Warrior"), 10, 10)
    chain.dc(99).press("🎲 Roll saves")
    expect(chain.root.get_by_text("FAIL", exact=True)).to_have_count(2)
    expect_pools(app.card("Goblin Warrior"), 6, 10)
    expect_pools(app.card("Goblin Warrior 2"), 6, 10)
    side, target, roll, applied = chain.log()[0]
    assert (side, applied) == ("FAIL", "4 damage applied")
    assert re.fullmatch(r"rolled \d+ vs DC 99", roll)


def test_advantage_keeps_the_higher_d20_and_disadvantage_the_lower(app):
    app.add("Goblin Warrior")
    chain = SaveChain(app).name("Dart").ability("DEX").dc(12)
    chain.hp(FAIL, "Damage", 1)

    app.page.clock.set_fixed_time(SPLIT_D20S_AT)
    chain.press("Roll Adv.")
    expect(chain.root.get_by_text("rolled 19 vs DC 12")).to_be_visible()
    chain.press("Roll Disadv.")
    expect(chain.root.get_by_text("rolled 5 vs DC 12")).to_have_count(1)
    chain.press("🎲 Roll saves")
    expect(chain.root.get_by_text("rolled 5 vs DC 12")).to_have_count(2)
    assert [row[0] for row in chain.log()[:3]] == ["FAIL", "FAIL", "PASS"]


def test_rolled_saves_damage_is_the_formulas_average(app):
    app.add("Goblin Warrior")
    chain = SaveChain(app).name("Dart").ability("DEX").dc(99)
    chain.hp(FAIL, "Damage", "2d4")

    chain.press("🎲 Roll saves")
    expect_pools(app.card("Goblin Warrior"), 5, 10)


def area_chain(app, name):
    chain = SaveChain(app)
    chain.name(name)
    return chain.ability("CON").dc(99).area("Re-save at turn start").hp(FAIL, "Damage", 5)


def test_a_creature_marked_in_an_area_takes_the_save_each_turn(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    app.begin_combat()
    assert app.active_name() == "Goblin Warrior"
    ogre = app.card("Ogre")
    select(app, "Ogre")
    chain = area_chain(app, "Fumes").scope_selected(1)
    chain.press("Save preset")

    chain.press("Mark in area")
    expect(chip(ogre, "In: Fumes")).to_have_count(1)
    expect_pools(ogre, 68, 68)
    app.next_turn()
    expect_pools(ogre, 63, 68)
    app.shot("area-turn")
    app.next_turn()
    app.next_turn()
    expect_pools(ogre, 58, 68)

    chip(ogre, "In: Fumes").get_by_role("button", name="Remove condition").click()
    app.next_turn()
    app.next_turn()
    expect_pools(ogre, 58, 68)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-11: an area chain not saved as a preset marks creatures that then never resolve",
)
def test_an_area_chain_resolves_without_being_saved_as_a_preset(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    app.begin_combat()
    ogre = app.card("Ogre")
    select(app, "Ogre")
    chain = area_chain(app, "Fumes").scope_selected(1)

    chain.press("Mark in area")
    expect(chip(ogre, "In: Fumes")).to_have_count(1)
    app.next_turn()
    app.shot("area-unsaved")
    expect_pools(ogre, 63, 68)


def test_a_bundled_preset_loads_into_the_form(app):
    two_ogres(app)
    chain = SaveChain(app)

    chain.preset_picker().select_option("Fireball")
    expect(chain.root.get_by_text("Loaded: Fireball")).to_be_visible()
    expect(chain.root.get_by_placeholder("e.g. Hold Person")).to_have_value("Fireball")
    expect(chain.root.get_by_role("radio", name="DEX", exact=True)).to_be_checked()
    expect(chain.side(FAIL).get_by_placeholder("12 or 2d6+3")).to_have_value("8d6")
    expect(chain.side(PASS).get_by_role("radio", name="Half of Fail damage")).to_be_checked()
    expect(chain.button("Fail")).to_be_enabled()
    expect(chain.button("🎲 Roll saves")).to_be_disabled()
    app.shot("fireball")


def test_a_dm_saves_clears_and_deletes_a_preset(app):
    two_ogres(app)
    chain = SaveChain(app).name("Goblin Bomb").ability("DEX").dc(12)
    chain.hp(FAIL, "Damage", "2d6")

    chain.press("Save preset")
    expect(chain.preset_picker()).to_have_value("Goblin Bomb")
    chain.press("Clear")
    expect(chain.root.get_by_placeholder("e.g. Hold Person")).to_have_value("Goblin Bomb")
    expect(chain.side(FAIL).get_by_role("radio", name="None", exact=True)).to_be_checked()

    chain.press("New")
    expect(chain.root.get_by_placeholder("e.g. Hold Person")).to_have_value("")
    chain.preset_picker().select_option("Goblin Bomb")
    expect(chain.side(FAIL).get_by_placeholder("12 or 2d6+3")).to_have_value("2d6")
    chain.press("Delete")
    expect(chain.preset_picker().locator("option", has_text="Goblin Bomb")).to_have_count(0)


def test_restore_brings_back_a_deleted_bundled_preset(app):
    two_ogres(app)
    chain = SaveChain(app)

    chain.preset_picker().select_option("Fireball")
    chain.press("Delete")
    expect(chain.preset_picker().locator("option", has_text="Fireball")).to_have_count(0)
    chain.press("Restore")
    expect(app.page.get_by_text(re.compile("^Restored \\d+ bundled presets"))).to_be_visible()
    expect(chain.preset_picker().locator("option", has_text="Fireball")).to_have_count(1)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-12: every turn advance resets the Save Chain form to blank",
)
def test_a_chain_being_built_survives_the_next_turn(app):
    app.add("Goblin Warrior", count=2)
    app.begin_combat()
    chain = SaveChain(app).name("Fumes").ability("CON").dc(14)
    chain.hp(FAIL, "Damage", 5)

    app.next_turn()
    expect(chain.root.get_by_placeholder("e.g. Hold Person")).to_have_value("Fumes", timeout=2000)
    expect(chain.side(FAIL).get_by_placeholder("12 or 2d6+3")).to_have_value("5", timeout=2000)
