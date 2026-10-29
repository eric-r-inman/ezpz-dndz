"""Manage HP at the table: damage, healing, temporary and maximum hit points."""

import re

import pytest
from playwright.sync_api import expect

from pages.fight import ManageHp, expect_pools, freeze_clock, hp_button, lifecycle_badge, select


def test_damage_spends_temporary_hit_points_first(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.temp(10)
    expect_pools(ogre, 68, 68, temp=10)
    hp.damage(4)
    expect_pools(ogre, 68, 68, temp=6)
    hp.damage(15)
    expect_pools(ogre, 59, 68)
    app.shot("temp-spent")


def test_temporary_hit_points_keep_the_larger_pool(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.temp(8)
    hp.amount_field().fill("5")
    expect(hp.root.get_by_text("5 < 8")).to_be_visible()
    app.shot("smaller-pool-warning")
    hp.verb("+ Temp").click()
    expect_pools(ogre, 68, 68, temp=8)

    hp.temp(12)
    expect_pools(ogre, 68, 68, temp=12)


def test_healing_stops_at_the_hit_point_maximum(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.temp(5)
    hp.damage(25)
    expect_pools(ogre, 48, 68)
    hp.heal(7)
    expect_pools(ogre, 55, 68)
    hp.heal(50)
    expect_pools(ogre, 68, 68)


def test_hit_points_never_drop_below_zero(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    # The 32 left over past 0 falls short of the 68 that would kill outright.
    hp.damage(100)
    expect_pools(ogre, 0, 68)
    expect(lifecycle_badge(ogre)).to_have_text("💤 DOWN")
    app.shot("down")


def test_a_negative_amount_never_heals_or_wounds(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.damage(10)
    hp.damage(-5)
    expect_pools(ogre, 58, 68)
    hp.heal(-5)
    expect_pools(ogre, 58, 68)


def test_plus_max_raises_the_maximum_and_current_like_aid(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.damage(10)
    hp.raise_max(5)
    expect_pools(ogre, 63, 73)
    expect(ogre.root.get_by_text("(68)")).to_be_visible()
    app.shot("aid")


def test_a_rolled_damage_formula_lands_within_its_range(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.roll_field().fill("2d6+3")
    expect(hp.amount_field()).to_be_disabled()
    hp.verb("Damage").click()
    expect(hp_button(ogre, "Current")).not_to_have_text("68")
    left = ogre.hp()
    assert 68 - 15 <= left <= 68 - 5
    assert hp.log()[0] == f"Damage Ogre {68 - left} · 68/68 → {left}/68"


def test_an_unparseable_formula_is_named_and_changes_nothing(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.roll_field().fill("2d6+")
    hp.verb("Damage").click()
    expect(hp.root.get_by_text("Couldn't parse: 2d6+")).to_be_visible()
    expect_pools(ogre, 68, 68)
    assert hp.log() == []


def test_damage_to_the_selection_shares_one_roll(app):
    app.add("Ogre", count=3)
    names = app.card_names()
    select(app, *names)
    hp = ManageHp(app).open_for("Ogre")

    hp.scope_selected(3)
    expect(hp.root.get_by_text("Target: Selected (3)")).to_be_visible()
    hp.roll_field().fill("2d20")
    hp.verb("Damage").click()
    expect(hp_button(app.card("Ogre 3"), "Current")).not_to_have_text("68")
    totals = {app.card(name).hp() for name in names}
    assert len(totals) == 1
    assert 28 <= totals.pop() <= 66
    assert "Ogre, Ogre 2, Ogre 3" in hp.log()[0]


def test_a_fresh_roll_per_creature_gives_each_its_own_total(app):
    app.add("Ogre", count=5)
    names = app.card_names()
    select(app, *names)
    hp = ManageHp(app).open_for("Ogre")

    hp.scope_selected(5)
    hp.roll_field().fill("1d60")
    hp.fresh_rolls()
    freeze_clock(app)
    hp.verb("Damage").click()
    for name in names:
        expect(hp_button(app.card(name), "Current")).not_to_have_text("68")
    app.shot("fresh-rolls")
    totals = [app.card(name).hp() for name in names]
    assert len(set(totals)) >= 3, f"Five fresh 1d60 rolls left {totals}"


def test_undo_steps_back_through_the_log(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.damage(10)
    hp.temp(5)
    hp.raise_max(4)
    expect_pools(ogre, 62, 72, temp=5)
    assert [row.split(" · ")[0] for row in hp.log()] == [
        "+Max HP Ogre 4",
        "Temp HP Ogre 5",
        "Damage Ogre 10",
    ]
    app.shot("log")

    hp.undo()
    expect_pools(ogre, 58, 68, temp=5)
    hp.undo()
    expect_pools(ogre, 58, 68)
    hp.undo()
    expect_pools(ogre, 68, 68)
    assert hp.log() == []
    expect(hp.root.get_by_text("No changes yet.")).to_be_visible()


def test_undo_after_a_selection_restores_every_creature(app):
    app.add("Ogre", count=2)
    select(app, "Ogre", "Ogre 2")
    hp = ManageHp(app).open_for("Ogre")

    hp.scope_selected(2)
    hp.damage(7)
    expect_pools(app.card("Ogre"), 61, 68)
    expect_pools(app.card("Ogre 2"), 61, 68)
    hp.undo()
    expect_pools(app.card("Ogre"), 68, 68)
    expect_pools(app.card("Ogre 2"), 68, 68)


def test_set_hp_writes_the_pools_outright(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.set_pools(hp=30, max_hp=80, temp=5)
    expect_pools(ogre, 30, 80, temp=5)
    app.shot("set")

    hp.set_pools(hp=90)
    expect_pools(ogre, 90, 90, temp=5)

    hp.set_pools(max_hp=50)
    expect_pools(ogre, 50, 50, temp=5)

    hp.set_pools(hp=60, max_hp=40, temp=0)
    expect_pools(ogre, 40, 40)
    assert hp.log()[0].startswith("Set Ogre")


def test_set_hp_roll_sets_hit_points_within_the_formula(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.open_set()
    hp.set_field("or Roll HP:").fill("8d10+24")
    expect(hp.set_field("Set HP to:")).to_be_disabled()
    hp.root.get_by_role("button", name="Target", exact=True).click()
    expect(hp.root.get_by_text(re.compile("^Roll Ogre"))).to_be_visible()
    rolled = ogre.hp()
    assert 32 <= rolled <= 104
    assert ogre.max_hp() == max(68, rolled)


def test_set_hp_roll_gives_each_selected_creature_its_own_hit_points(app):
    app.add("Ogre", count=6)
    names = app.card_names()
    select(app, *names)
    hp = ManageHp(app).open_for("Ogre")

    hp.open_set()
    hp.set_field("or Roll HP:").fill("1d60")
    freeze_clock(app)
    hp.root.get_by_role("button", name="Selected (6)").click()
    expect(hp.root.get_by_text(re.compile("^Roll Ogre"))).to_have_count(6)
    totals = [app.card(name).hp() for name in names]
    assert len(set(totals)) >= 3, f"Six rolls of 1d60 for hit points left {totals}"


def test_reset_to_default_puts_the_creature_back_as_it_arrived(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.damage(20)
    hp.raise_max(10)
    hp.temp(6)
    expect_pools(ogre, 58, 78, temp=6)
    hp.reset()
    expect_pools(ogre, 68, 68)
    expect(ogre.root.get_by_text("(68)")).to_have_count(0)
    assert hp.log()[0].startswith("Reset Ogre")
    hp.undo()
    expect_pools(ogre, 58, 78, temp=6)


@pytest.mark.cross_browser
def test_enter_in_the_amount_field_deals_damage(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    hp = ManageHp(app).open_for("Ogre")

    hp.amount_field().fill("12")
    hp.amount_field().press("Enter")
    expect_pools(ogre, 56, 68)
    hp.amount_field().fill("")
    hp.roll_field().fill("1d4")
    hp.roll_field().press("Enter")
    expect(hp_button(ogre, "Current")).not_to_have_text("56")
    assert 52 <= ogre.hp() <= 55


@pytest.mark.cross_browser
def test_card_armor_class_commits_on_enter_and_cancels_on_escape(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    ac = ogre.root.get_by_role("button", name=re.compile("^Armor Class \\d+ for Ogre"))
    # The inline edit field has no accessible name.
    field = ogre.root.locator("input.hp-display__edit")

    ac.click()
    field.fill("17")
    field.press("Enter")
    expect(ac).to_have_text("17")

    ac.click()
    field.fill("25")
    app.shot("ac-editing")
    field.press("Escape")
    expect(ac).to_have_text("17")

    ac.click()
    field.fill("13")
    app.page.mouse.click(900, 750)
    expect(ac).to_have_text("13")


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-02: clicking the card's AC opens a field without focus, so typing goes nowhere",
)
def test_typing_straight_after_clicking_the_armor_class_edits_it(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    ac = ogre.root.get_by_role("button", name=re.compile("^Armor Class \\d+ for Ogre"))

    ac.click()
    app.page.keyboard.press("ControlOrMeta+A")
    app.page.keyboard.type("16")
    app.page.keyboard.press("Enter")
    expect(ac).to_have_text("16", timeout=2000)


def test_card_hit_point_values_open_manage_hp_aimed_at_their_creature(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    hp = ManageHp(app)

    hp_button(app.card("Goblin Warrior"), "Max").click()
    expect(hp.root.get_by_text("Target: Goblin Warrior")).to_be_visible()
    hp.temp(3)
    expect_pools(app.card("Goblin Warrior"), 10, 10, temp=3)

    hp_button(app.card("Ogre"), "Current").click()
    expect(hp.root.get_by_text("Target: Ogre")).to_be_visible()
    hp_button(app.card("Goblin Warrior"), "Temp").click()
    expect(hp.root.get_by_text("Target: Goblin Warrior")).to_be_visible()
