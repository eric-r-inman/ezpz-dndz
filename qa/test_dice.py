"""The Dice Roller as a DM uses it mid-fight and between sessions."""


import pytest
from playwright.sync_api import expect

from pages.accounts import wait_for_saved_rolls
from pages.ui import Dice, consistent

QUICK_D20 = "Roll a d20 \u2014 straight, with advantage, and with disadvantage"


def spin(app, what, direction, times=1):
    button = app.page.get_by_role("button", name=f"{direction} {what} by 1")
    for _ in range(times):
        button.click()
    app.settle()


def test_an_expression_rolls_dice_that_add_up_to_its_total(app):
    dice = Dice(app).open()
    for count in range(1, 6):
        dice.roll("3d6+2")
        dice.wait_for_rows(count)
        row = dice.row()
        assert row["formula"] == "3d6+2"
        assert len(row["faces"]) == 3
        assert row["modifier"] == 2
        assert consistent(row, 6), row
    expect(app.page.locator(".recent-roll--latest")).to_have_text(str(dice.row()["total"]))
    app.shot("five-rolls")


def test_an_expression_with_several_terms_and_a_damage_type_rolls_them_all(app):
    dice = Dice(app).open()
    dice.roll("1d8 + 2d6 - 1 fire")
    dice.wait_for_rows(1)
    row = dice.row()
    assert row["formula"] == "1d8+2d6-1"
    assert row["kind"] == "fire"
    assert len(row["faces"]) == 3
    assert 1 <= row["faces"][0] <= 8
    assert all(1 <= face <= 6 for face in row["faces"][1:])
    assert row["total"] == sum(row["faces"]) - 1


@pytest.mark.parametrize("typed", ["3d6+", "abc", "2d6 + goblin", "1d6*2", "4d6kh3", "d"])
def test_a_malformed_expression_says_it_could_not_be_read_and_rolls_nothing(app, typed):
    dice = Dice(app).open()
    dice.roll(typed)
    expect(dice.root.get_by_text(f"Couldn't parse: {typed}")).to_be_visible()
    dice.wait_for_rows(0)
    dice.expression().fill("2d4")
    expect(dice.root.get_by_text("Couldn't parse")).to_have_count(0)


@pytest.mark.parametrize("typed", ["0d6", "1d0"])
def test_an_impossible_die_is_refused_rather_than_rolled_as_something_else(app, typed):
    dice = Dice(app).open()
    dice.roll(typed)
    expect(dice.root.get_by_text(f"Couldn't parse: {typed}")).to_be_visible(timeout=2000)
    dice.wait_for_rows(0)


def test_count_and_modifier_arrows_shape_what_a_die_button_rolls(app):
    dice = Dice(app).open()
    count = dice.root.get_by_label("Count:")
    modifier = dice.root.get_by_label("Modifier:")

    spin(app, "count", "Decrease")
    expect(count).to_have_value("1")
    spin(app, "count", "Increase", times=2)
    expect(count).to_have_value("3")
    spin(app, "modifier", "Increase", times=2)
    expect(modifier).to_have_value("2")
    spin(app, "modifier", "Decrease", times=3)
    expect(modifier).to_have_value("-1")

    dice.button("d8").click()
    dice.wait_for_rows(1)
    row = dice.row()
    assert row["formula"] == "3d8-1"
    assert len(row["faces"]) == 3
    assert consistent(row, 8), row

    count.fill("4")
    modifier.fill("5")
    dice.button("d4").click()
    dice.wait_for_rows(2)
    assert dice.row()["formula"] == "4d4+5"
    assert consistent(dice.row(), 4)

    dice.root.get_by_role("button", name="Reset count and modifier").click()
    expect(count).to_have_value("1")
    expect(modifier).to_have_value("0")
    app.shot("after-reset")


def test_every_die_face_button_rolls_its_own_die(app):
    dice = Dice(app).open()
    faces = [4, 6, 8, 10, 12, 20, 100]
    for index, size in enumerate(faces, start=1):
        dice.button(f"d{size}").click()
        dice.wait_for_rows(index)
        row = dice.row()
        assert row["formula"] == f"1d{size}"
        assert consistent(row, size), row


def test_advantage_keeps_the_higher_d20_and_disadvantage_the_lower(app):
    dice = Dice(app).open()
    spin(app, "modifier", "Increase", times=3)
    for index in range(1, 9):
        advantage = index % 2 == 1
        dice.button("Advantage (d20)" if advantage else "Disadvantage (d20)").click()
        dice.wait_for_rows(index)
        row = dice.row()
        assert row["formula"] == ("Adv: 1d20+3" if advantage else "Dis: 1d20+3")
        assert len(row["faces"]) == 2
        assert all(1 <= face <= 20 for face in row["faces"])
        keep = max(row["faces"]) if advantage else min(row["faces"])
        assert set(row["kept"]) == {keep}, row
        assert row["total"] == keep + 3


def test_a_coin_flip_lands_heads_or_tails(app):
    dice = Dice(app).open()
    for index in range(1, 7):
        dice.button("Flip a coin").click()
        dice.wait_for_rows(index)
        row = dice.row()
        assert row["formula"] in {"Coin \u2192 heads", "Coin \u2192 tails"}
        assert row["faces"] == [1 if row["formula"].endswith("heads") else 2]


def test_the_reroll_menu_repeats_a_roll_with_or_without_its_modifier(app):
    dice = Dice(app).open()
    dice.roll("2d6+5")
    dice.wait_for_rows(1)

    trigger = dice.reroll_button(0)
    trigger.click()
    expect(trigger).to_have_attribute("aria-expanded", "true")
    dice.root.get_by_role("menuitem", name="Reroll", exact=True).click()
    dice.wait_for_rows(2)
    expect(dice.root.get_by_role("menu")).to_have_count(0)
    assert dice.row()["formula"] == "2d6+5"
    assert consistent(dice.row(), 6)

    dice.reroll_button(0).click()
    dice.root.get_by_role("menuitem", name="Reroll, no modifier").click()
    dice.wait_for_rows(3)
    row = dice.row()
    assert row["formula"] == "2d6"
    assert row["modifier"] == 0
    assert consistent(row, 6), row

    spin(app, "modifier", "Increase", times=4)
    dice.button("Advantage (d20)").click()
    dice.wait_for_rows(4)
    dice.reroll_button(0).click()
    dice.root.get_by_role("menuitem", name="Reroll, no modifier").click()
    dice.wait_for_rows(5)
    assert dice.row()["formula"] == "Adv: 1d20"
    app.shot("rerolls")


def test_an_open_reroll_menu_stays_with_the_roll_it_was_opened_on(app):
    dice = Dice(app).open()
    dice.roll("2d6+5")
    dice.wait_for_rows(1)
    dice.reroll_button(0).click()
    dice.button("d4").click()
    dice.wait_for_rows(2)
    app.shot("menu-after-a-new-roll")
    expect(dice.reroll_button(0)).to_have_attribute("aria-expanded", "false")
    open_menu = dice.root.get_by_role("menuitem", name="Reroll", exact=True)
    if open_menu.count():
        open_menu.click()
        dice.wait_for_rows(3)
        assert dice.row()["formula"] == "2d6+5"


def test_escape_closes_the_reroll_menu_and_leaves_the_roller_open(app):
    dice = Dice(app).open()
    dice.roll("1d6")
    dice.wait_for_rows(1)
    dice.reroll_button(0).click()
    expect(dice.root.get_by_role("menu")).to_be_visible()
    app.page.keyboard.press("Escape")
    app.settle()
    assert dice.panel.is_open()
    expect(dice.root.get_by_role("menu")).to_have_count(0)


def test_a_click_elsewhere_closes_the_reroll_menu(app):
    dice = Dice(app).open()
    dice.roll("1d6")
    dice.wait_for_rows(1)
    dice.reroll_button(0).click()
    expect(dice.root.get_by_role("menu")).to_be_visible()
    app.page.locator(".panel--main .panel__body--encounter").click(position={"x": 400, "y": 300})
    app.settle()
    expect(dice.root.get_by_role("menu")).to_have_count(0)


def test_the_log_folds_away_and_clear_empties_it(app):
    dice = Dice(app).open()
    dice.roll("1d6")
    dice.roll("1d8")
    dice.wait_for_rows(2)
    toggle = dice.log_toggle()
    expect(toggle).to_contain_text("Log (2)")

    toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "false")
    dice.wait_for_rows(0)
    toggle.click()
    dice.wait_for_rows(2)

    dice.root.get_by_role("button", name="Clear", exact=True).click()
    dice.wait_for_rows(0)
    expect(dice.root.get_by_text("No rolls yet.")).to_be_visible()
    expect(toggle).to_contain_text("Log (0)")
    expect(dice.root.get_by_role("button", name="Clear", exact=True)).to_have_count(0)
    expect(app.page.locator(".recent-roll")).to_have_count(0)


def test_the_log_keeps_the_last_thirty_rolls(app):
    dice = Dice(app).open()
    for _ in range(32):
        dice.button("d4").click()
    expect(dice.log_toggle()).to_contain_text("Log (30)")
    dice.wait_for_rows(30)


def test_the_column_d20_rolls_straight_advantage_and_disadvantage_at_once(app):
    dice = Dice(app)
    app.page.get_by_role("button", name=QUICK_D20).click()
    expect(app.page.locator(".roll-popup")).to_have_count(3)
    expect(app.page.locator(".recent-roll")).to_have_count(3)
    app.shot("triple-popups")

    # A roll landing while the roller is folded marks its title.
    expect(dice.root.locator(".panel__title-mark")).to_be_visible()
    dice.open()
    expect(dice.root.locator(".panel__title-mark")).to_have_count(0)
    dice.wait_for_rows(3)
    rows = [dice.row(index) for index in range(3)]
    assert [row["formula"] for row in rows] == [
        "d20 1d20",
        "d20 Adv: 1d20",
        "d20 Dis: 1d20",
    ]
    # An ellipsis leaves the chip's text whole in the DOM.
    # Only its width shows the cut.
    clipped = dice.root.locator(".dice-history__source").evaluate_all(
        "els => els.filter(e => e.scrollWidth > e.clientWidth).map(e => e.textContent)"
    )
    assert clipped == [], clipped
    assert consistent(rows[0], 20)
    assert set(rows[1]["kept"]) == {max(rows[1]["faces"])}
    assert set(rows[2]["kept"]) == {min(rows[2]["faces"])}
    assert [row["total"] for row in rows[1:]] == [
        max(rows[1]["faces"]),
        min(rows[2]["faces"]),
    ]

    badges = app.page.locator(".recent-roll")
    assert badges.all_inner_texts() == [str(row["total"]) for row in rows]
    assert [
        cls.split()[-1] for cls in badges.evaluate_all("els => els.map(e => e.className)")
    ] == ["recent-roll--standard", "recent-roll--advantage", "recent-roll--disadvantage"]

    dice.button("d6").click()
    expect(app.page.locator(".recent-roll--latest")).to_have_count(1)
    app.shot("after-a-single-roll")


def test_rolls_survive_a_reload_for_an_anonymous_dm(app):
    dice = Dice(app).open()
    dice.roll("2d10+1")
    dice.roll("1d4")
    dice.wait_for_rows(2)
    before = [dice.row_text(index) for index in range(2)]
    app.reload()
    dice = Dice(app).open()
    dice.wait_for_rows(2)
    assert [dice.row_text(index) for index in range(2)] == before


def test_rolls_follow_a_signed_in_dm_across_a_reload_and_a_server_restart(app):
    app.sign_up(email="dice@example.test", password="dice dice dice dice")
    dice = Dice(app).open()
    dice.roll("2d10+1")
    dice.roll("1d4")
    dice.button("Advantage (d20)").click()
    dice.wait_for_rows(3)
    before = [dice.row_text(index) for index in range(3)]
    wait_for_saved_rolls(app.page, 3)

    app.reload()
    dice = Dice(app).open()
    dice.wait_for_rows(3)
    assert [dice.row_text(index) for index in range(3)] == before

    # A restart ends the session.  The DM signs in again.
    app.server.restart()
    app.sign_in("dice@example.test", "dice dice dice dice")
    dice = Dice(app).open()
    dice.wait_for_rows(3)
    assert [dice.row_text(index) for index in range(3)] == before

    dice.root.get_by_role("button", name="Clear", exact=True).click()
    dice.wait_for_rows(0)
    wait_for_saved_rolls(app.page, 0)
    app.reload()
    dice = Dice(app).open()
    expect(dice.root.get_by_text("No rolls yet.")).to_be_visible()
