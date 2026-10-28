"""The creature card at the table.  It covers dying, postures, pools and copies."""

import re

import pytest
from playwright.sync_api import expect

from pages.fight import (
    ConditionEditor,
    ManageHp,
    advance,
    begin_death_saves,
    expect_pools,
    fix_d20,
    fix_d6,
    hp_button,
    lifecycle_badge,
    log_rows,
    readout,
    recharge_chip,
    select,
)
from pages.turns import knock_down
from pages.ui import Dice


def downed(app, name, begin=True):
    """Drops the creature to 0 HP.

    With `begin` it also opens its death saves.
    """
    knock_down(app, name)
    card = app.card(name)
    if begin:
        begin_death_saves(card)
    return card


def pip(card, kind, ordinal):
    return card.root.get_by_role("button", name=f"{kind} pip {ordinal}")


def expect_pips(card, successes, failures):
    for kind, filled in [("Success", successes), ("Failure", failures)]:
        for ordinal in (1, 2, 3):
            expect(pip(card, kind, ordinal)).to_have_attribute(
                "aria-pressed", "true" if ordinal <= filled else "false"
            )


def roll_death_save(app, card, face):
    fix_d20(app, face)
    card.root.get_by_role("button", name="Roll death save").click()
    app.settle()


# Death and dying.


def test_a_creature_at_zero_shows_down_and_opts_into_death_saves(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior", begin=False)

    expect(lifecycle_badge(card)).to_have_text("💤 DOWN")
    expect(card.root.get_by_role("group", name="Death saving throws")).to_have_count(0)
    begin_death_saves(card)
    expect_pips(card, 0, 0)
    expect(card.root.get_by_role("button", name="Roll death save")).to_be_visible()
    app.shot("death-saves")


def test_death_save_pips_fill_and_clear_like_a_rating(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    pip(card, "Success", 2).click()
    expect_pips(card, 2, 0)
    pip(card, "Success", 1).click()
    expect_pips(card, 0, 0)
    pip(card, "Success", 3).click()
    expect(lifecycle_badge(card)).to_have_text("💤 DOWN, STABLE")
    expect(card.root.get_by_role("button", name="Roll death save")).to_have_count(0)
    pip(card, "Failure", 3).click()
    expect(lifecycle_badge(card)).to_have_text("💀 DEAD")


def test_a_death_save_of_ten_succeeds_and_nine_fails(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    roll_death_save(app, card, 10)
    expect_pips(card, 1, 0)
    roll_death_save(app, card, 9)
    expect_pips(card, 1, 1)


def test_a_natural_one_counts_as_two_failed_death_saves(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    roll_death_save(app, card, 1)
    expect_pips(card, 0, 2)
    roll_death_save(app, card, 9)
    expect(lifecycle_badge(card)).to_have_text("💀 DEAD")
    app.shot("dead")


def test_a_natural_twenty_wakes_the_creature_at_one_hit_point(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    pip(card, "Failure", 2).click()
    roll_death_save(app, card, 20)
    expect_pools(card, 1, 10)
    expect(lifecycle_badge(card)).to_have_count(0)
    expect(card.root.get_by_role("group", name="Death saving throws")).to_have_count(0)
    app.shot("revived")


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-03: a creature a natural 20 revives at 1 HP is not marked Bloodied",
)
def test_a_creature_revived_by_a_natural_twenty_is_bloodied(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    roll_death_save(app, card, 20)
    expect_pools(card, 1, 10)
    # Bloodied shows only as a colour on the current HP.
    expect(hp_button(card, "Current")).to_have_class(re.compile("hp-display__current--bloodied"), timeout=2000)


def test_healing_a_downed_creature_clears_its_death_saves(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    pip(card, "Success", 1).click()
    pip(card, "Failure", 2).click()
    ManageHp(app).heal(4)
    expect_pools(card, 4, 10)
    expect(lifecycle_badge(card)).to_have_count(0)

    ManageHp(app).damage(10)
    begin_death_saves(card)
    expect_pips(card, 0, 0)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-04: damage taken at 0 HP does not add a failed death save",
)
def test_damage_while_down_counts_as_a_failed_death_save(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    ManageHp(app).damage(3)
    expect(pip(card, "Failure", 1)).to_have_attribute("aria-pressed", "true", timeout=2000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-04: damage past 0 that equals the HP maximum does not kill outright",
)
def test_massive_damage_kills_outright(app):
    app.add("Goblin Warrior")
    card = app.card("Goblin Warrior")

    ManageHp(app).open_for("Goblin Warrior").damage(20)
    expect(lifecycle_badge(card)).to_have_text("💀 DEAD", timeout=2000)


def test_the_lifecycle_badge_marks_dead_and_reverts_to_down(app):
    app.add("Goblin Warrior")
    card = downed(app, "Goblin Warrior")

    pip(card, "Success", 1).click()
    lifecycle_badge(card).click()
    expect(lifecycle_badge(card)).to_have_text("💀 DEAD")
    expect(card.root).to_have_class(re.compile("creature-card--dead"))
    app.shot("marked-dead")
    lifecycle_badge(card).click()
    expect(lifecycle_badge(card)).to_have_text("💤 DOWN")
    expect_pips(card, 1, 0)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-09: Begin combat hands the first turn to a creature that is down or dead",
)
def test_combat_does_not_open_on_a_creature_that_is_already_down(app):
    app.add("Goblin Warrior", count=2)
    downed(app, "Goblin Warrior", begin=False)

    app.begin_combat()
    assert app.active_name() == "Goblin Warrior 2"


# Status editor and card toggles.


def status_panel(app, name):
    ConditionEditor(app).open_for(name)
    return app.panel("Status")


def test_the_status_editor_puts_cover_concentration_and_postures_on_the_card(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    status = status_panel(app, "Ogre")

    cover = status.root.get_by_role("button", name=re.compile("^Cover: "))
    cover.click()
    expect(cover).to_have_accessible_name("Cover: Half cover")
    cover.click()
    expect(cover).to_have_accessible_name("Cover: Three-quarters cover")
    for flag in ["hiding", "dodging", "concentrating"]:
        toggle = status.root.get_by_role("button", name=flag, exact=True)
        toggle.click()
        expect(toggle).to_have_attribute("aria-pressed", "true")
    status.root.get_by_role("textbox", name="What the creature is concentrating on").fill("Bless")
    status.root.get_by_role("button", name="Target", exact=True).click()

    for label in ["¾ cover", "concen.", "hiding", "dodging"]:
        expect(ogre.root.get_by_role("button", name=f"Edit Ogre's statuses ({label})")).to_be_visible()
    expect(ogre.root.get_by_text("(Bless)")).to_be_visible()
    expect(status.root.get_by_role("button", name="hiding", exact=True)).to_have_attribute("aria-pressed", "false")
    assert log_rows(status)[0] == "Status Ogre Three-quarters cover, Concentrating, Hiding, Dodging"
    app.shot("statuses")


def test_a_status_clears_from_the_card_and_undo_brings_the_set_back(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    status = status_panel(app, "Ogre")

    status.root.get_by_role("button", name="hiding", exact=True).click()
    status.root.get_by_role("button", name="dodging", exact=True).click()
    status.root.get_by_role("button", name="Target", exact=True).click()
    ogre.root.get_by_role("button", name="Clear hiding for Ogre").click()
    expect(ogre.root.get_by_role("button", name="Edit Ogre's statuses (hiding)")).to_have_count(0)
    expect(ogre.root.get_by_role("button", name="Edit Ogre's statuses (dodging)")).to_be_visible()

    status.root.get_by_role("button", name="Undo status on Ogre").click()
    expect(ogre.root.get_by_role("button", name="Edit Ogre's statuses (dodging)")).to_have_count(0)


def test_statuses_land_on_every_selected_creature(app):
    app.add("Goblin Warrior", count=3)
    select(app, "Goblin Warrior", "Goblin Warrior 3")
    status = status_panel(app, "Goblin Warrior")

    status.root.get_by_role("button", name="dodging", exact=True).click()
    status.root.get_by_role("button", name="Selected (2)").click()
    for name, dodging in [("Goblin Warrior", 1), ("Goblin Warrior 2", 0), ("Goblin Warrior 3", 1)]:
        expect(
            app.card(name).root.get_by_role("button", name=f"Edit {name}'s statuses (dodging)")
        ).to_have_count(dodging)


def test_flight_height_steps_by_five_feet_and_stops_at_the_ground(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    status = status_panel(app, "Ogre")

    status.root.get_by_role("button", name="flying", exact=True).click()
    for _ in range(3):
        status.root.get_by_role("button", name="Increase flight height by 5 feet").click()
    status.root.get_by_role("button", name="Target", exact=True).click()
    height = ogre.root.locator(".fly-height__value")
    expect(height).to_have_text("15")

    ogre.root.get_by_role("button", name="Increase flight height by 5 feet").click()
    expect(height).to_have_text("20")
    for _ in range(5):
        ogre.root.get_by_role("button", name="Decrease flight height by 5 feet").click()
    expect(height).to_have_text("0")


def test_falling_damage_rolls_a_d6_per_ten_feet_and_grounds_the_creature(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    status = status_panel(app, "Ogre")

    status.root.get_by_role("button", name="flying", exact=True).click()
    for _ in range(7):
        status.root.get_by_role("button", name="Increase flight height by 5 feet").click()
    status.root.get_by_role("button", name="Target", exact=True).click()
    expect(ogre.root.locator(".fly-height__value")).to_have_text("35")

    ogre.root.get_by_role("button", name="Roll falling damage").click()
    expect(ogre.root.get_by_role("button", name="Edit Ogre's statuses (flying)")).to_have_count(0)
    dice = Dice(app).open()
    expect(dice.root.get_by_text("Fall damage → Ogre")).to_be_visible()
    expect(dice.root.get_by_text(re.compile(r"3d6:\(\d,\d,\d\) bludgeoning"))).to_be_visible()
    app.shot("fall")
    # The DM applies the fall damage.  The card keeps its hit points.
    expect_pools(ogre, 68, 68)


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-05: a concentrating creature dropped to 0 HP keeps concentrating",
)
def test_concentration_ends_when_the_creature_drops_to_zero(app):
    app.add("Ogre")
    ogre = app.card("Ogre")
    status = status_panel(app, "Ogre")

    status.root.get_by_role("button", name="concentrating", exact=True).click()
    status.root.get_by_role("button", name="Target", exact=True).click()
    concentrating = ogre.root.get_by_role("button", name="Edit Ogre's statuses (concen.)")
    expect(concentrating).to_be_visible()
    ManageHp(app).open_for("Ogre").damage(68)
    expect(concentrating).to_have_count(0, timeout=2000)


# Legendary pools, recharge and special reactions.


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-06: every legendary creature gets its in-lair pools, with no way to say it is out of its lair",
)
def test_a_dragon_outside_its_lair_has_three_legendary_actions_and_resistances(app):
    app.add("Adult Red Dragon")
    dragon = app.card("Adult Red Dragon")

    app.shot("legendary")
    expect(readout(dragon, "Legendary Action")).to_have_text("LA: 3(3)", timeout=2000)
    expect(readout(dragon, "Legendary Resistance")).to_have_text("LR: 3(3)", timeout=2000)


def test_a_spent_recharge_ability_prompts_a_roll_at_the_next_turn(app):
    app.add("Adult Red Dragon")
    app.add("Ogre")
    dragon = app.card("Adult Red Dragon")
    app.begin_combat()

    chip = recharge_chip(dragon, "Fire Breath")
    expect(chip).to_have_attribute("aria-pressed", "false")
    chip.click()
    expect(chip).to_have_attribute("aria-pressed", "true")
    roll = dragon.root.get_by_role("button", name="Roll Recharge 5–6 for Fire Breath")
    expect(roll).to_have_count(0)

    advance(app, 2)
    expect(roll).to_be_visible()
    app.shot("recharge-prompt")
    fix_d6(app, 2)
    roll.click()
    expect(roll).to_have_count(0)
    expect(chip).to_have_attribute("aria-pressed", "true")

    advance(app, 2)
    fix_d6(app, 6)
    roll.click()
    expect(chip).to_have_attribute("aria-pressed", "false")

    chip.click()
    advance(app, 2)
    dragon.root.get_by_role("button", name="Mark Fire Breath ready (no roll)").click()
    expect(chip).to_have_attribute("aria-pressed", "false")


def test_a_special_reaction_badge_spends_and_refreshes_at_its_turn(app):
    app.add("Goblin Boss")
    app.add("Ogre")
    badge = app.card("Goblin Boss").root.get_by_role("button", name="Special reaction: Redirect Attack")
    app.begin_combat()

    expect(badge).to_have_attribute("aria-pressed", "false")
    badge.click()
    expect(badge).to_have_attribute("aria-pressed", "true")
    app.next_turn()
    expect(badge).to_have_attribute("aria-pressed", "true")
    app.next_turn()
    expect(badge).to_have_attribute("aria-pressed", "false")


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-07: the bundled Black Pudding names its Split reaction Parry, so no badge shows",
)
def test_the_black_pudding_shows_its_split_reaction(app):
    app.add("Black Pudding")

    expect(
        app.card("Black Pudding").root.get_by_role("button", name="Special reaction: Split")
    ).to_be_visible(timeout=2000)


# The Duplicate editor.


def duplicate(app, mode, scope="Target"):
    panel = app.panel("Duplicate").open()
    panel.root.get_by_role("radio", name=mode, exact=True).click()
    panel.root.get_by_role("button", name=re.compile(f"^{re.escape(scope)}")).click()
    app.settle()
    return panel


def test_an_exact_duplicate_copies_the_current_state(app):
    app.add("Ogre")
    ManageHp(app).open_for("Ogre").damage(28)
    ConditionEditor(app).open_for("Ogre").pick("Poisoned").apply()

    panel = duplicate(app, "Exact")
    assert app.card_names() == ["Ogre", "Ogre 2"]
    copy = app.card("Ogre 2")
    expect_pools(copy, 40, 68)
    expect(copy.root.get_by_role("button", name="Poisoned", exact=True)).to_be_visible()
    assert log_rows(panel)[0] == "Exact Ogre → Ogre 2"


def test_a_fresh_duplicate_starts_from_the_stat_block(app):
    app.add("Ogre")
    ManageHp(app).open_for("Ogre").damage(28)
    ConditionEditor(app).open_for("Ogre").pick("Poisoned").apply()

    duplicate(app, "Fresh")
    copy = app.card("Ogre 2")
    expect_pools(copy, 68, 68)
    expect(copy.root.get_by_role("button", name="Poisoned", exact=True)).to_have_count(0)
    assert copy.initiative() == app.card("Ogre").initiative()


def test_a_half_minion_has_half_the_hit_point_maximum(app):
    app.add("Ogre")
    duplicate(app, "Minion (½ max hp)")
    assert app.card_names() == ["Ogre", "Ogre Minion 1"]
    expect_pools(app.card("Ogre Minion 1"), 34, 34)


def test_a_one_hit_point_minion_has_one_hit_point(app):
    app.add("Ogre")
    duplicate(app, "Minion (1 hp)")
    duplicate(app, "Minion (1 hp)")
    assert app.card_names() == ["Ogre", "Ogre Minion 2", "Ogre Minion 1"]
    expect_pools(app.card("Ogre Minion 2"), 1, 1)


def test_duplicating_the_selection_copies_each_creature(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    select(app, "Goblin Warrior", "Ogre")
    duplicate(app, "Fresh", scope="Selected (2)")
    assert app.card_names() == ["Goblin Warrior", "Goblin Warrior 2", "Ogre", "Ogre 2"]


def test_a_pudding_split_divides_its_hit_points_between_two_new_puddings(app):
    app.add("Black Pudding")
    ManageHp(app).open_for("Black Pudding").damage(35)
    expect_pools(app.card("Black Pudding"), 33, 68)

    duplicate(app, "Pudding")
    assert app.card_names() == ["Black Pudding Minion 1", "Black Pudding Minion 2"]
    for name in app.card_names():
        expect_pools(app.card(name), 16, 34)
    app.shot("pudding")


@pytest.mark.xfail(
    strict=True,
    reason="QA-FIGHT-08: the halves of a Bloodied pudding are not marked Bloodied",
)
def test_the_halves_of_a_bloodied_pudding_are_bloodied(app):
    app.add("Black Pudding")
    ManageHp(app).open_for("Black Pudding").damage(35)
    duplicate(app, "Pudding")

    half = app.card("Black Pudding Minion 1")
    expect_pools(half, 16, 34)
    expect(hp_button(half, "Current")).to_have_class(re.compile("hp-display__current--bloodied"), timeout=2000)
