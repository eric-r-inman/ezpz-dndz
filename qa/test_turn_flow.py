"""Running the fight: turns, rounds, per-turn resets and the table aids."""

import re

import pytest
from playwright.sync_api import expect

from pages.app import ACTIVE_MARKER, BEGIN_COMBAT, NEXT_TURN
from pages.fight import advance, begin_death_saves, lifecycle_badge, readout
from pages.turns import (
    ROLL_ROW,
    Initiative,
    card_is_in_view,
    drag_card,
    fill_timer,
    heal,
    inactive_toggle,
    initiatives,
    knock_down,
    make_active,
    manage_hp_target,
    mark_dead,
    open_round_setter,
    open_timer,
    press_manage_hp,
    quick_view,
    reaction,
    readied,
    scroll_queue_to_top,
    set_initiatives,
    start_timer,
    strip,
    timer_pill,
    toggle_inactive,
    turn_arrow,
    turn_order,
    wait_until_card_in_view,
)

ORDER = ["Goblin Warrior 2", "Wolf", "Goblin Warrior", "Ogre"]


def fight(app):
    """Four creatures with fixed initiatives.  Combat has not started."""
    app.add("Goblin Warrior", count=2)
    app.add("Wolf")
    app.add("Ogre")
    set_initiatives(app, {"Goblin Warrior 2": 18, "Wolf": 15, "Goblin Warrior": 12, "Ogre": 5})
    assert app.card_names() == ORDER


def skipped_badge(app, name):
    return app.card(name).root.get_by_role("status").filter(has_text="SKIPPED")


# Turns and rounds.


def test_begin_combat_hands_the_first_turn_to_the_highest_initiative(app):
    fight(app)
    assert app.active_name() is None
    expect(app.page.get_by_role("button", name=NEXT_TURN)).to_have_count(0)

    app.begin_combat()
    assert app.active_name() == "Goblin Warrior 2"
    assert app.round_number() == 1
    expect(app.page.get_by_role("button", name=ACTIVE_MARKER)).to_have_count(1)
    expect(app.card("Goblin Warrior 2").root).to_have_class(re.compile("creature-card--active"))
    expect(app.page.get_by_role("button", name="Scroll to Goblin Warrior 2", exact=True)).to_be_visible()
    expect(app.page.get_by_role("button", name=BEGIN_COMBAT)).to_have_count(0)
    app.shot("combat-begun")


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-01: after Quick Add and Begin combat, Manage HP aims at nobody",
)
def test_begin_combat_aims_manage_hp_at_the_creature_whose_turn_it_is(app):
    app.add("Ogre")
    app.add("Goblin Warrior")
    app.begin_combat()
    first = app.active_name()
    app.shot("manage-hp-unaimed")

    press_manage_hp(app, "Damage", 5)
    assert app.card(first).hp() == app.card(first).max_hp() - 5
    expect(manage_hp_target(app)).to_have_text(f"Target: {first}")


def test_next_turn_walks_the_queue_and_starts_round_two(app):
    fight(app)
    app.begin_combat()
    assert turn_order(app, 4) == [
        (1, "Wolf"),
        (1, "Goblin Warrior"),
        (1, "Ogre"),
        (2, "Goblin Warrior 2"),
    ]
    expect(app.page.get_by_role("button", name=ACTIVE_MARKER)).to_have_count(1)
    app.shot("round-two")


def test_round_setter_corrects_the_round_without_moving_the_turn(app):
    fight(app)
    app.begin_combat()
    app.next_turn()

    dialog = open_round_setter(app)
    field = dialog.get_by_role("spinbutton", name="Manual:")
    expect(field).to_have_value("1")
    field.fill("5")
    app.shot("round-setter")
    dialog.get_by_role("button", name="Set", exact=True).click()
    expect(dialog).to_have_count(0)
    assert (app.round_number(), app.active_name()) == (5, "Wolf")

    dialog = open_round_setter(app)
    dialog.get_by_role("button", name="Set to 1").click()
    expect(dialog).to_have_count(0)
    assert (app.round_number(), app.active_name()) == (1, "Wolf")

    dialog = open_round_setter(app)
    dialog.get_by_role("spinbutton", name="Manual:").fill("3")
    dialog.get_by_role("button", name="Close").click()
    expect(dialog).to_have_count(0)
    assert app.round_number() == 1

    dialog = open_round_setter(app)
    dialog.get_by_role("spinbutton", name="Manual:").fill("0")
    dialog.get_by_role("button", name="Set", exact=True).click()
    app.settle()
    assert app.round_number() == 1
    dialog.get_by_role("button", name="Close").click()

    app.next_turn()
    assert (app.round_number(), app.active_name()) == (1, "Goblin Warrior")


@pytest.mark.cross_browser
def test_round_setter_answers_enter_and_escape(app):
    fight(app)
    app.begin_combat()
    dialog = open_round_setter(app)
    field = dialog.get_by_role("spinbutton", name="Manual:")
    field.fill("4")
    field.press("Enter")
    expect(dialog).to_have_count(0)
    assert app.round_number() == 4

    dialog = open_round_setter(app)
    dialog.get_by_role("spinbutton", name="Manual:").fill("9")
    app.page.keyboard.press("Escape")
    expect(dialog).to_have_count(0)
    assert app.round_number() == 4


@pytest.mark.cross_browser
def test_keyboard_starts_and_advances_the_fight(app):
    fight(app)
    begin = app.page.get_by_role("button", name=BEGIN_COMBAT)
    begin.focus()
    app.page.keyboard.press("Enter")
    app.settle()
    assert app.active_name() == "Goblin Warrior 2"

    advance = app.page.get_by_role("button", name=NEXT_TURN)
    advance.focus()
    app.page.keyboard.press("Enter")
    app.settle()
    assert app.active_name() == "Wolf"
    advance.focus()
    app.page.keyboard.press("Space")
    app.settle()
    assert app.active_name() == "Goblin Warrior"


def test_set_as_active_moves_the_marker_without_a_new_round(app):
    fight(app)
    app.begin_combat()
    make_active(app, "Ogre")
    assert (app.round_number(), app.active_name()) == (1, "Ogre")
    expect(turn_arrow(app, "Goblin Warrior 2")).to_have_accessible_name("Set as active creature")
    expect(turn_arrow(app, "Ogre")).to_have_accessible_name(ACTIVE_MARKER)

    app.next_turn()
    assert (app.round_number(), app.active_name()) == (2, "Goblin Warrior 2")


def test_inactive_creatures_are_skipped_until_brought_back(app):
    fight(app)
    app.begin_combat()
    toggle_inactive(app, "Wolf")
    expect(inactive_toggle(app, "Wolf")).to_have_attribute("aria-pressed", "true")
    expect(skipped_badge(app, "Wolf")).to_be_visible()
    app.shot("wolf-skipped")

    assert turn_order(app, 3) == [
        (1, "Goblin Warrior"),
        (1, "Ogre"),
        (2, "Goblin Warrior 2"),
    ]
    toggle_inactive(app, "Wolf")
    expect(inactive_toggle(app, "Wolf")).to_have_attribute("aria-pressed", "false")
    expect(skipped_badge(app, "Wolf")).to_have_count(0)
    assert turn_order(app, 1) == [(2, "Wolf")]


def test_downed_and_dead_creatures_lose_their_turns(app):
    fight(app)
    app.begin_combat()
    knock_down(app, "Wolf")
    mark_dead(app, "Goblin Warrior")
    expect(lifecycle_badge(app.card("Goblin Warrior"))).to_have_text("💀 DEAD")
    app.shot("down-and-dead")

    assert turn_order(app, 2) == [(1, "Ogre"), (2, "Goblin Warrior 2")]

    begin_death_saves(app.card("Wolf"))
    assert turn_order(app, 3) == [(2, "Wolf"), (2, "Ogre"), (3, "Goblin Warrior 2")]


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-02: Begin combat hands the first turn to an inactive creature",
)
def test_begin_combat_passes_over_an_inactive_top_creature(app):
    fight(app)
    toggle_inactive(app, "Goblin Warrior 2")
    app.begin_combat()
    assert app.active_name() == "Wolf"


def test_removing_the_active_creature_passes_the_turn_on(app):
    fight(app)
    app.begin_combat()
    app.card("Goblin Warrior 2").remove()
    assert (app.round_number(), app.active_name()) == (1, "Wolf")
    assert app.card_names() == ORDER[1:]


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-03: removing the active creature hands the turn to an inactive one",
)
def test_removing_the_active_creature_passes_over_an_inactive_successor(app):
    fight(app)
    app.begin_combat()
    toggle_inactive(app, "Wolf")
    app.card("Goblin Warrior 2").remove()
    assert app.active_name() == "Goblin Warrior"


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-03: removing the active creature starts no turn for its successor",
)
def test_removing_the_active_creature_starts_the_successors_turn(app):
    fight(app)
    app.begin_combat()
    reaction(app, "Wolf").click()
    expect(reaction(app, "Wolf")).to_have_attribute("aria-pressed", "true")
    app.card("Goblin Warrior 2").remove()
    assert app.active_name() == "Wolf"
    expect(reaction(app, "Wolf")).to_have_attribute("aria-pressed", "false")


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-03: removing the last creature on its turn wraps without a new round",
)
def test_removing_the_last_creature_on_its_turn_starts_the_next_round(app):
    fight(app)
    app.begin_combat()
    make_active(app, "Ogre")
    app.card("Ogre").remove()
    assert (app.round_number(), app.active_name()) == (2, "Goblin Warrior 2")


def test_a_creature_added_mid_fight_waits_for_its_place_in_the_order(app):
    fight(app)
    app.begin_combat()
    app.next_turn()
    assert app.active_name() == "Wolf"

    app.add("Wolf")
    assert app.card_names()[-1] == "Wolf 2"
    assert app.active_name() == "Wolf"
    set_initiatives(app, {"Wolf 2": 20})
    assert app.card_names()[0] == "Wolf 2"
    assert app.active_name() == "Wolf"

    app.add("Skeleton")
    set_initiatives(app, {"Skeleton": 10})
    assert app.card_names() == ["Wolf 2", *ORDER[:3], "Skeleton", "Ogre"]
    assert turn_order(app, 5) == [
        (1, "Goblin Warrior"),
        (1, "Skeleton"),
        (1, "Ogre"),
        (2, "Wolf 2"),
        (2, "Goblin Warrior 2"),
    ]


# Per-turn resets.


def test_reactions_come_back_at_the_start_of_their_own_turn(app):
    fight(app)
    app.begin_combat()
    for name in ["Wolf", "Ogre"]:
        reaction(app, name).click()
        app.settle()
        expect(reaction(app, name)).to_have_attribute("aria-pressed", "true")
        expect(reaction(app, name)).to_have_accessible_name("Reaction spent — click to refund")
    app.shot("reactions-spent")

    app.next_turn()
    expect(reaction(app, "Wolf")).to_have_attribute("aria-pressed", "false")
    expect(reaction(app, "Ogre")).to_have_attribute("aria-pressed", "true")
    app.next_turn()
    expect(reaction(app, "Ogre")).to_have_attribute("aria-pressed", "true")
    app.next_turn()
    assert app.active_name() == "Ogre"
    expect(reaction(app, "Ogre")).to_have_attribute("aria-pressed", "false")

    reaction(app, "Wolf").click()
    reaction(app, "Wolf").click()
    expect(reaction(app, "Wolf")).to_have_attribute("aria-pressed", "false")


@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-04: a readied action never clears at the start of its next turn",
)
def test_a_readied_action_ends_at_the_start_of_its_next_turn(app):
    fight(app)
    app.begin_combat()
    readied(app, "Goblin Warrior 2").click()
    app.settle()
    expect(readied(app, "Goblin Warrior 2")).to_have_accessible_name("Action Readied")
    expect(readied(app, "Goblin Warrior 2")).to_have_attribute("aria-pressed", "true")

    advance(app, 3)
    expect(readied(app, "Goblin Warrior 2")).to_have_attribute("aria-pressed", "true")
    app.next_turn()
    assert app.active_name() == "Goblin Warrior 2"
    expect(readied(app, "Goblin Warrior 2")).to_have_attribute("aria-pressed", "false")


def legendary_fight(app):
    app.add("Adult Red Dragon")
    app.add("Goblin Warrior")
    app.add("Ogre")
    set_initiatives(app, {"Adult Red Dragon": 20, "Goblin Warrior": 10, "Ogre": 5})
    app.begin_combat()
    assert app.active_name() == "Adult Red Dragon"


def test_legendary_actions_refresh_at_the_start_of_the_dragons_turn(app):
    legendary_fight(app)
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 4(4)")
    expect(strip(app, "Legendary actions")).to_have_count(0)

    app.next_turn()
    la_strip = strip(app, "Legendary actions")
    expect(la_strip).to_contain_text("Adult Red Dragon (4)")
    readout(app.card("Adult Red Dragon"), "Legendary Action").click()
    readout(app.card("Adult Red Dragon"), "Legendary Action").click()
    readout(app.card("Adult Red Dragon"), "Legendary Resistance").click()
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 2(4)")
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_accessible_name(
        "Legendary Action: 2 of 4 remaining. Click to use. Resets after 0."
    )
    expect(readout(app.card("Adult Red Dragon"), "Legendary Resistance")).to_have_text("LR: 3(4)")
    expect(la_strip).to_contain_text("Adult Red Dragon (2)")
    app.shot("two-legendary-actions-spent")

    app.next_turn()
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 2(4)")
    app.next_turn()
    assert (app.round_number(), app.active_name()) == (2, "Adult Red Dragon")
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 4(4)")
    expect(readout(app.card("Adult Red Dragon"), "Legendary Resistance")).to_have_text("LR: 3(4)")

    app.next_turn()
    for _ in range(4):
        readout(app.card("Adult Red Dragon"), "Legendary Action").click()
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 0(4)")
    expect(strip(app, "Legendary actions")).to_have_count(0)
    readout(app.card("Adult Red Dragon"), "Legendary Action").click()
    expect(readout(app.card("Adult Red Dragon"), "Legendary Action")).to_have_text("LA: 4(4)")


def test_special_reaction_badges_clear_at_the_bearers_turn_start(app):
    app.add("Vampire")
    app.add("Ogre")
    set_initiatives(app, {"Vampire": 15, "Ogre": 5})
    app.begin_combat()
    app.next_turn()
    badge = app.card("Vampire").root.get_by_role("button", name="Special reaction: Misty Escape")
    badge.click()
    app.settle()
    expect(badge).to_have_attribute("aria-pressed", "true")
    expect(reaction(app, "Vampire")).to_have_attribute("aria-pressed", "true")

    app.next_turn()
    assert app.active_name() == "Vampire"
    expect(badge).to_have_attribute("aria-pressed", "false")
    expect(reaction(app, "Vampire")).to_have_attribute("aria-pressed", "false")


# The queue itself.


@pytest.mark.cross_browser
def test_dragging_a_card_moves_it_without_changing_initiative(app):
    fight(app)
    drag_card(app, "Ogre", onto="Goblin Warrior 2", half="upper")
    assert app.card_names() == ["Ogre", "Goblin Warrior 2", "Wolf", "Goblin Warrior"]
    assert initiatives(app)["Ogre"] == 5

    drag_card(app, "Ogre", onto="Wolf", half="lower")
    assert app.card_names() == ["Goblin Warrior 2", "Wolf", "Ogre", "Goblin Warrior"]
    app.shot("dragged")


@pytest.mark.cross_browser
def test_a_dragged_order_decides_who_acts_next(app):
    fight(app)
    app.begin_combat()
    drag_card(app, "Ogre", onto="Goblin Warrior 2", half="lower")
    assert app.card_names() == ["Goblin Warrior 2", "Ogre", "Wolf", "Goblin Warrior"]
    assert app.active_name() == "Goblin Warrior 2"
    assert turn_order(app, 2) == [(1, "Ogre"), (1, "Wolf")]


@pytest.mark.cross_browser
def test_quick_add_mid_fight_puts_a_dragged_queue_back_in_initiative_order(app):
    fight(app)
    app.begin_combat()
    drag_card(app, "Ogre", onto="Goblin Warrior 2", half="lower")
    app.add("Skeleton")
    assert app.card_names() == [*ORDER, "Skeleton"]
    assert app.active_name() == "Goblin Warrior 2"


@pytest.mark.cross_browser
def test_shift_click_selects_everyone_and_clears_everyone(app):
    fight(app)
    editor = Initiative(app).open()
    selected = editor.scope_button(ROLL_ROW, "Selected")
    app.card("Wolf").select()
    expect(selected).to_have_text("Selected (1)")

    app.card("Ogre").select(shift=True)
    for name in ORDER:
        expect(app.card(name).checkbox()).to_be_checked()
    expect(selected).to_have_text("Selected (4)")

    app.card("Ogre").select(shift=True)
    for name in ORDER:
        expect(app.card(name).checkbox()).not_to_be_checked()
    expect(selected).to_have_text("Selected (0)")
    expect(selected).to_be_disabled()


# Quick view, reminder strips and scrolling.


def test_quick_view_lists_the_queue_and_can_show_enemies_alone(app):
    fight(app)
    app.add_placeholder()
    knock_down(app, "Wolf")
    toggle = app.page.get_by_role("button", name="Show quick-view")
    expect(toggle).to_have_attribute("aria-pressed", "false")
    toggle.click()
    hide = app.page.get_by_role("button", name="Hide quick-view")
    expect(hide).to_have_attribute("aria-pressed", "true")

    column = quick_view(app)
    names = column.get_by_role("button", name=re.compile("^Scroll to "))
    expect(names).to_have_text([*ORDER, "Placeholder 1"])
    expect(column).to_contain_text("68/68")
    expect(names.filter(has_text="Wolf")).to_have_class(re.compile("quick-view__name--down"))
    app.shot("quick-view-all")

    enemies = column.get_by_role("button", name="Enemies only")
    enemies.click()
    expect(enemies).to_have_attribute("aria-pressed", "true")
    expect(names).to_have_text(ORDER)
    app.shot("quick-view-enemies")

    hide.click()
    expect(column).to_have_count(0)
    app.page.get_by_role("button", name="Show quick-view").click()
    expect(column.get_by_role("button", name="Enemies only")).to_have_attribute("aria-pressed", "true")
    column.get_by_role("button", name="Enemies only").click()
    expect(names).to_have_count(5)


def long_queue(app):
    """Ten goblins over an ogre.  That is enough to scroll the queue."""
    app.add("Goblin Warrior", count=10)
    app.add("Ogre")
    assert app.card_names()[-1] == "Ogre"


def test_quick_view_name_scrolls_the_queue_to_that_card(app):
    long_queue(app)
    app.page.get_by_role("button", name="Show quick-view").click()
    scroll_queue_to_top(app)
    assert not card_is_in_view(app, "Ogre")

    quick_view(app).get_by_role("button", name="Scroll to Ogre's card").click()
    wait_until_card_in_view(app, "Ogre")
    app.shot("scrolled-to-ogre")


def test_encounter_bar_name_scrolls_back_to_the_active_card(app):
    long_queue(app)
    make_active(app, "Ogre")
    wait_until_card_in_view(app, "Ogre")
    scroll_queue_to_top(app)
    assert not card_is_in_view(app, "Ogre")

    app.page.get_by_role("button", name="Scroll to Ogre", exact=True).click()
    wait_until_card_in_view(app, "Ogre")


def test_a_strip_name_brings_its_card_to_the_top_of_the_queue(app):
    app.add("Goblin Warrior", count=6)
    app.add("Vampire")
    Initiative(app).open().apply(5, scope="All")
    set_initiatives(app, {"Vampire": 3})
    app.add("Ogre", count=8)
    assert app.card_names().index("Vampire") == 6
    scroll_queue_to_top(app)
    assert not card_is_in_view(app, "Vampire")

    strip(app, "Legendary actions").get_by_role("button", name="Scroll to Vampire's card").click()
    wait_until_card_in_view(app, "Vampire", near_top=True)
    app.shot("vampire-at-top")


def test_strip_labels_open_and_close_their_reference_lists(app):
    app.add("Vampire")
    app.add("Mage")
    labels = {
        "Legendary actions": "Show what each creature's legendary actions do",
        "Special reactions": "Show what each creature's special reactions do",
        "Spells": "List every spell the creatures in this encounter can cast",
    }
    for name in labels.values():
        app.page.get_by_role("button", name=name).click()
        expect(app.page.get_by_role("button", name=name)).to_have_attribute("aria-expanded", "true")

    main = app.page.locator("section.panel--main")
    expect(main.get_by_role("heading", name=re.compile(r"Vampire.* — 3 uses \(4 in lair\)"))).to_be_visible()
    expect(main).to_contain_text("Misty Escape")
    expect(main.get_by_role("listitem").filter(has_text="Fireball")).to_have_count(1)
    app.shot("three-references-open")

    for name in labels.values():
        app.page.get_by_role("button", name=name).click()
        expect(app.page.get_by_role("button", name=name)).to_have_attribute("aria-expanded", "false")
    expect(main.get_by_role("listitem").filter(has_text="Fireball")).to_have_count(0)


# Timers.


def test_a_timer_counts_down_the_bearers_turns_and_rings_at_zero(app):
    fight(app)
    app.begin_combat()
    start_timer(app, "Wolf", 2, "end", "Bless")
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^2\s*Bless"))
    expect(timer_pill(app, "Wolf")).to_have_attribute(
        "data-tooltip", re.compile("^Timer: 2 left, ticks at end")
    )

    app.next_turn()
    assert app.active_name() == "Wolf"
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^2"))
    app.next_turn()
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^1"))
    advance(app, 3)
    assert app.active_name() == "Wolf"
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^1"))
    expect(timer_pill(app, "Wolf")).not_to_have_class(re.compile("timer-pill--ringing"))

    app.next_turn()
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^0"))
    expect(timer_pill(app, "Wolf")).to_have_class(re.compile("timer-pill--ringing"))
    app.shot("timer-ringing")
    advance(app, 4)
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^0"))

    app.card("Wolf").root.get_by_role("button", name="Cancel timer").click()
    expect(timer_pill(app, "Wolf")).to_have_count(0)
    expect(app.card("Wolf").root.get_by_role("button", name="Set timer")).to_be_visible()


def test_a_start_of_turn_timer_ticks_as_the_bearers_turn_begins(app):
    fight(app)
    app.begin_combat()
    start_timer(app, "Goblin Warrior", 1, "beginning")
    app.next_turn()
    expect(timer_pill(app, "Goblin Warrior")).to_have_text(re.compile(r"^1"))
    app.next_turn()
    assert app.active_name() == "Goblin Warrior"
    expect(timer_pill(app, "Goblin Warrior")).to_have_class(re.compile("timer-pill--ringing"))


def test_an_end_of_turn_timer_set_on_the_bearers_turn_counts_that_turn(app):
    fight(app)
    app.begin_combat()
    app.next_turn()
    assert app.active_name() == "Wolf"
    start_timer(app, "Wolf", 1, "end")
    app.next_turn()
    expect(timer_pill(app, "Wolf")).to_have_class(re.compile("timer-pill--ringing"))


def test_a_timer_length_stays_between_one_and_ninety_nine(app):
    fight(app)
    start_timer(app, "Wolf", 150, "end")
    expect(timer_pill(app, "Wolf")).to_have_text(re.compile(r"^99"))
    start_timer(app, "Ogre", 0, "end")
    expect(timer_pill(app, "Ogre")).to_have_text(re.compile(r"^1"))


def test_timer_presets_save_load_and_delete(app):
    fight(app)
    form = open_timer(app, "Wolf")
    expect(form.get_by_role("button", name="Load ▼")).to_be_disabled()
    fill_timer(form, 5, "beginning", "Rage")
    form.get_by_role("button", name="Save", exact=True).click()
    name_field = form.get_by_placeholder("Name this preset")
    name_field.fill("Rage")
    name_field.press("Enter")
    expect(name_field).to_have_count(0)
    form.get_by_role("button", name="Cancel", exact=True).click()
    expect(timer_pill(app, "Wolf")).to_have_count(0)

    app.reload()
    form = open_timer(app, "Ogre")
    form.get_by_role("button", name="Load ▼").click()
    form.get_by_role("option", name="Rage").click()
    expect(form.get_by_role("spinbutton", name="Timer lasts")).to_have_value("5")
    expect(form.get_by_text("beginning", exact=True)).to_have_class(re.compile("cond-phase--on"))
    expect(form.get_by_role("textbox", name="Label")).to_have_value("Rage")
    app.shot("preset-loaded")
    form.get_by_role("button", name="Start Timer").click()
    expect(timer_pill(app, "Ogre")).to_have_text(re.compile(r"^5\s*Rage"))

    form = open_timer(app, "Goblin Warrior")
    form.get_by_role("button", name="Load ▼").click()
    form.get_by_role("button", name="Delete preset Rage").click()
    expect(form.get_by_role("button", name="Load ▼")).to_be_disabled()


@pytest.mark.cross_browser
def test_timer_setup_is_discarded_by_cancel_escape_or_its_own_button(app):
    fight(app)
    form = open_timer(app, "Wolf")
    form.get_by_role("spinbutton", name="Timer lasts").fill("7")
    form.get_by_role("button", name="Cancel", exact=True).click()
    expect(form.get_by_role("spinbutton", name="Timer lasts")).to_have_count(0)

    form = open_timer(app, "Wolf")
    app.page.keyboard.press("Escape")
    expect(form.get_by_role("spinbutton", name="Timer lasts")).to_have_count(0)

    form = open_timer(app, "Wolf")
    form.get_by_role("button", name="Set timer").click()
    expect(form.get_by_role("spinbutton", name="Timer lasts")).to_have_count(0)
    expect(timer_pill(app, "Wolf")).to_have_count(0)


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-08: the timer's begin and end choice is hidden from the keyboard",
)
def test_the_timer_phase_can_be_chosen_from_the_keyboard(app):
    fight(app)
    form = open_timer(app, "Wolf")
    form.get_by_role("spinbutton", name="Timer lasts").focus()
    app.page.keyboard.press("Tab")
    focused = app.page.evaluate("() => document.activeElement.getAttribute('type')")
    assert focused == "radio"


@pytest.mark.cross_browser
@pytest.mark.xfail(
    strict=True,
    reason="QA-TURN-09: the memo, note and timer fields open without the cursor in them",
)
def test_opening_a_card_editor_puts_the_cursor_in_its_field(app):
    fight(app)
    card = app.card("Wolf").root
    focused = {}
    for trigger, field in [
        ("Add memo", card.get_by_role("textbox", name="Edit memo for Wolf")),
        ("Add note", card.get_by_role("textbox", name="Edit note for Wolf")),
        ("Set timer", card.get_by_role("spinbutton", name="Timer lasts")),
    ]:
        card.get_by_role("button", name=trigger).click()
        expect(field).to_be_visible()
        app.settle()
        focused[trigger] = field.evaluate("el => el === document.activeElement")
        card.get_by_role("button", name=trigger).click()
        expect(field).to_have_count(0)
    assert focused == {"Add memo": True, "Add note": True, "Set timer": True}


# Memos and notes.


@pytest.mark.cross_browser
def test_a_memo_is_added_edited_and_cleared(app):
    fight(app)
    card = app.card("Wolf").root
    card.get_by_role("button", name="Add memo").click()
    field = card.get_by_role("textbox", name="Edit memo for Wolf")
    field.fill("LR used")
    field.press("Enter")
    expect(card.get_by_role("button", name="LR used")).to_be_visible()

    card.get_by_role("button", name="LR used").click()
    expect(field).to_have_value("LR used")
    field.fill("LR used x2")
    card.get_by_role("button", name="Add", exact=True).click()
    expect(card.get_by_role("button", name="LR used x2")).to_be_visible()

    card.get_by_role("button", name="LR used x2").click()
    field.fill("scratch")
    field.press("Escape")
    expect(field).to_have_count(0)
    expect(card.get_by_role("button", name="LR used x2")).to_be_visible()
    app.shot("memo")

    card.get_by_role("button", name="Clear memo").click()
    expect(card.get_by_role("button", name="Add memo")).to_be_visible()


@pytest.mark.cross_browser
def test_a_note_rides_beside_the_name_and_clears_when_emptied(app):
    fight(app)
    app.begin_combat()
    app.next_turn()
    card = app.card("Wolf").root
    card.get_by_role("button", name="Add note").click()
    field = card.get_by_role("textbox", name="Edit note for Wolf")
    field.fill("alpha of the pack, scarred")
    expect(field).to_have_value("alpha of the pack, s")
    field.fill("alpha")
    field.press("Enter")
    expect(card.get_by_role("button", name="Edit note: alpha")).to_have_text("(alpha)")
    expect(app.page.locator(".encounter-bar").get_by_text("(alpha)")).to_be_visible()
    app.shot("note")

    card.get_by_role("button", name="Edit note: alpha").click()
    field.fill("beta")
    field.press("Escape")
    expect(card.get_by_role("button", name="Edit note: alpha")).to_be_visible()

    card.get_by_role("button", name="Edit note: alpha").click()
    field.fill("")
    card.get_by_role("button", name="Add", exact=True).click()
    expect(card.get_by_role("button", name="Add note")).to_be_visible()
    expect(app.page.locator(".encounter-bar").get_by_text("(alpha)")).to_have_count(0)


# A long fight.


def test_three_rounds_with_skipped_downed_and_dead_creatures_stay_coherent(app):
    fight(app)
    app.add_placeholder()
    set_initiatives(app, {"Placeholder 1": 2})
    everyone = [*ORDER, "Placeholder 1"]
    assert app.card_names() == everyone
    app.begin_combat()

    assert turn_order(app, 1) == [(1, "Wolf")]
    toggle_inactive(app, "Ogre")
    assert turn_order(app, 3) == [(1, "Goblin Warrior"), (1, "Placeholder 1"), (2, "Goblin Warrior 2")]

    knock_down(app, "Wolf")
    assert turn_order(app, 1) == [(2, "Goblin Warrior")]
    toggle_inactive(app, "Ogre")
    assert turn_order(app, 1) == [(2, "Ogre")]
    mark_dead(app, "Goblin Warrior")
    assert turn_order(app, 2) == [(2, "Placeholder 1"), (3, "Goblin Warrior 2")]

    reaction(app, "Placeholder 1").click()
    assert turn_order(app, 1) == [(3, "Ogre")]
    expect(reaction(app, "Placeholder 1")).to_have_attribute("aria-pressed", "true")
    heal(app, "Wolf", 5)
    assert turn_order(app, 4) == [
        (3, "Placeholder 1"),
        (4, "Goblin Warrior 2"),
        (4, "Wolf"),
        (4, "Ogre"),
    ]
    expect(reaction(app, "Placeholder 1")).to_have_attribute("aria-pressed", "false")
    expect(app.page.get_by_role("button", name=ACTIVE_MARKER)).to_have_count(1)
    assert app.card_names() == everyone
    app.shot("round-four")

    app.page.wait_for_function(
        "() => { const saved = localStorage.getItem('encounter') || '';"
        " return saved.includes('\"round\":4') && saved.includes('\"activeName\":\"Ogre\"'); }"
    )
    app.reload()
    assert (app.round_number(), app.active_name()) == (4, "Ogre")
    assert app.card_names() == everyone
    expect(lifecycle_badge(app.card("Goblin Warrior"))).to_have_text("💀 DEAD")
    assert app.card("Wolf").hp() == 5
    assert turn_order(app, 2) == [(4, "Placeholder 1"), (5, "Goblin Warrior 2")]
