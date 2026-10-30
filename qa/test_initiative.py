"""Initiative as a DM sets it up: typed values, rolls, ties and sorting."""

import pytest
from playwright.sync_api import expect

from pages.turns import (
    ROLL_ROW,
    Initiative,
    drag_card,
    initiative_badge,
    initiative_rolls,
    initiatives,
    open_initiative_for,
    set_initiatives,
)
from pages.ui import Dice

BONUS = {"Ogre": -1, "Goblin Warrior": 2, "Goblin Warrior 2": 2, "Placeholder 1": 0}


def roster(app):
    """Two goblins, an ogre and a placeholder.  Every one starts at 99."""
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.add_placeholder()
    editor = open_initiative_for(app, "Ogre")
    editor.apply(99, scope="All")
    assert set(initiatives(app).values()) == {99}
    return editor


def wait_until_rolled(app, names):
    for name in names:
        expect(initiative_badge(app, name)).not_to_have_text("(99)")


def assert_sorted(app, bonus):
    order = [(value, bonus[name]) for name, value in initiatives(app).items()]
    assert order == sorted(order, reverse=True), initiatives(app)


def test_typed_initiatives_sort_the_queue_highest_first(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    set_initiatives(app, {"Ogre": 5, "Goblin Warrior": 12, "Goblin Warrior 2": 18})
    assert initiatives(app) == {"Goblin Warrior 2": 18, "Goblin Warrior": 12, "Ogre": 5}
    app.shot("typed-and-sorted")


def test_initiative_badge_aims_the_editor_at_its_creature(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    assert not app.panel("Initiative").is_open()

    editor = open_initiative_for(app, "Ogre")
    assert editor.target() == "Ogre"
    editor.type_value(7)

    open_initiative_for(app, "Goblin Warrior")
    assert editor.target() == "Goblin Warrior"
    assert editor.field().input_value() == ""

    editor.type_value(4)
    editor.panel.fold()
    open_initiative_for(app, "Goblin Warrior")
    assert editor.field().input_value() == "4"
    app.shot("badge-reopens-same-target")


def test_rolling_for_the_target_rolls_a_d20_plus_its_bonus(app):
    roster(app)
    editor = open_initiative_for(app, "Ogre")
    editor.roll("Target")
    wait_until_rolled(app, ["Ogre"])

    values = initiatives(app)
    assert 1 + BONUS["Ogre"] <= values["Ogre"] <= 20 + BONUS["Ogre"]
    assert {n: v for n, v in values.items() if n != "Ogre"} == {
        "Goblin Warrior": 99,
        "Goblin Warrior 2": 99,
        "Placeholder 1": 99,
    }
    [roll] = initiative_rolls(app)
    assert roll["name"] == "Ogre"
    assert roll["mode"] is None
    assert roll["total"] == values["Ogre"] == roll["faces"][0] + BONUS["Ogre"]


def test_rolling_for_all_rolls_everyone_and_sorts_the_queue(app):
    editor = roster(app)
    editor.roll("All")
    wait_until_rolled(app, BONUS)

    for name, value in initiatives(app).items():
        assert 1 + BONUS[name] <= value <= 20 + BONUS[name], (name, value)
    assert_sorted(app, BONUS)
    assert sorted(r["name"] for r in initiative_rolls(app)) == sorted(BONUS)
    app.shot("rolled-all")


def test_rolling_for_selected_leaves_the_rest_alone(app):
    editor = roster(app)
    app.card("Ogre").select()
    app.card("Goblin Warrior 2").select()
    expect(editor.scope_button(ROLL_ROW, "Selected")).to_have_text("Selected (2)")

    editor.roll("Selected")
    wait_until_rolled(app, ["Ogre", "Goblin Warrior 2"])

    values = initiatives(app)
    assert values["Goblin Warrior"] == 99
    assert values["Placeholder 1"] == 99
    assert values["Ogre"] <= 19
    assert values["Goblin Warrior 2"] <= 22


def test_rolling_for_enemies_skips_the_placeholder(app):
    editor = roster(app)
    editor.roll("Enemies only")
    wait_until_rolled(app, ["Ogre", "Goblin Warrior", "Goblin Warrior 2"])

    values = initiatives(app)
    assert values["Placeholder 1"] == 99
    assert app.card_names()[0] == "Placeholder 1"
    assert max(v for n, v in values.items() if n != "Placeholder 1") <= 22


def test_advantage_keeps_the_higher_d20_and_disadvantage_the_lower(app):
    editor = roster(app)
    editor.pick_mode("Advantage")
    expect(editor.mode("Advantage")).to_be_checked()
    editor.roll("All")
    wait_until_rolled(app, BONUS)

    advantage = initiative_rolls(app)
    assert len(advantage) == 4
    for roll in advantage:
        assert roll["mode"] == "Adv"
        assert len(roll["faces"]) == 2
        assert roll["total"] == max(roll["faces"]) + roll["bonus"]
        assert roll["total"] == app.card(roll["name"]).initiative()

    editor.pick_mode("Disadvantage")
    expect(editor.mode("Disadvantage")).to_be_checked()
    expect(editor.mode("Advantage")).not_to_be_checked()
    editor.roll("All")
    Dice(app).wait_for_rows(8)

    disadvantage = initiative_rolls(app)[:4]
    for roll in disadvantage:
        assert roll["mode"] == "Dis"
        assert roll["total"] == min(roll["faces"]) + roll["bonus"]
        assert roll["total"] == app.card(roll["name"]).initiative()

    editor.pick_mode("Disadvantage")
    expect(editor.mode("Disadvantage")).not_to_be_checked()
    expect(editor.mode("Advantage")).not_to_be_checked()
    app.shot("modes-cleared")


def test_typed_initiative_lands_on_selected_enemies_or_everyone(app):
    editor = roster(app)
    app.card("Ogre").select()
    app.card("Goblin Warrior").select()
    editor.apply(7, scope="Selected")
    assert initiatives(app) == {
        "Goblin Warrior 2": 99,
        "Placeholder 1": 99,
        "Goblin Warrior": 7,
        "Ogre": 7,
    }

    editor.apply(3, scope="Enemies only")
    assert initiatives(app) == {
        "Placeholder 1": 99,
        "Goblin Warrior": 3,
        "Goblin Warrior 2": 3,
        "Ogre": 3,
    }

    editor.apply(15, scope="All")
    assert set(initiatives(app).values()) == {15}


@pytest.mark.cross_browser
def test_enter_in_the_initiative_field_sets_the_target(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    editor = open_initiative_for(app, "Ogre")
    field = editor.field()
    field.fill("17")
    field.press("Enter")
    expect(initiative_badge(app, "Ogre")).to_have_text("(17)")
    assert app.card_names() == ["Ogre", "Goblin Warrior"]


def test_a_negative_initiative_sorts_last_and_junk_is_ignored(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    set_initiatives(app, {"Goblin Warrior": -3, "Ogre": 1})
    assert initiatives(app) == {"Ogre": 1, "Goblin Warrior": -3}

    editor = Initiative(app)
    editor.apply("x?", scope="All")
    assert initiatives(app) == {"Ogre": 1, "Goblin Warrior": -3}


def test_ties_go_to_the_higher_initiative_bonus(app):
    app.add("Ogre")
    app.add_placeholder()
    app.add("Goblin Warrior")
    app.add("Adult Red Dragon")
    open_initiative_for(app, "Ogre").apply(10, scope="All")
    assert app.card_names() == ["Adult Red Dragon", "Goblin Warrior", "Placeholder 1", "Ogre"]


def test_tied_copies_keep_their_numbered_order(app):
    app.add("Goblin Warrior", count=10)
    expected = ["Goblin Warrior"] + [f"Goblin Warrior {n}" for n in range(2, 11)]
    app.shot("ten-tied-goblins")
    assert app.card_names() == expected


@pytest.mark.cross_browser
def test_quick_sort_puts_a_dragged_queue_back_in_initiative_order(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    app.add("Wolf")
    set_initiatives(app, {"Goblin Warrior": 15, "Wolf": 10, "Ogre": 5})
    drag_card(app, "Ogre", onto="Goblin Warrior", half="upper")
    assert app.card_names() == ["Ogre", "Goblin Warrior", "Wolf"]

    Initiative(app).quick_sort()
    assert app.card_names() == ["Goblin Warrior", "Wolf", "Ogre"]


def test_resorting_mid_fight_keeps_whose_turn_it_is(app):
    app.add("Goblin Warrior")
    app.add("Ogre")
    app.add("Wolf")
    set_initiatives(app, {"Goblin Warrior": 15, "Wolf": 10, "Ogre": 5})
    app.begin_combat()
    app.next_turn()
    assert app.active_name() == "Wolf"

    set_initiatives(app, {"Ogre": 20})
    assert app.card_names() == ["Ogre", "Goblin Warrior", "Wolf"]
    assert app.active_name() == "Wolf"
    assert app.round_number() == 1

    app.next_turn()
    assert (app.round_number(), app.active_name()) == (2, "Ogre")
