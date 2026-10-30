"""The editor column: folding, pinning, dragging, hotkeys and profiles."""

import re

import pytest
from playwright.sync_api import expect

from pages.turns import manage_hp_target, press_manage_hp
from pages.ui import (
    choose_profile,
    drag_panel,
    drawer_titles,
    heading,
    hotkey,
    open_titles,
    pinned_held,
    pinned_titles,
    stack_scroll,
)

BOOT_ORDER = [
    "Manage HP",
    "Dice Roller",
    "Status",
    "Condition/Effect",
    "Initiative",
    "Duplicate",
    "Replace",
    "Encounter Difficulty",
    "Encounter XP",
    "Quick Add",
    "Save Chain",
    "Treasure",
    "Random Encounter",
]
BETA = ["Save Chain", "Treasure", "Random Encounter"]


def test_the_column_boots_with_manage_hp_pinned_open_and_the_rest_folded(app):
    assert drawer_titles(app.page) == BOOT_ORDER
    assert pinned_titles(app.page) == ["Manage HP"]
    assert open_titles(app.page) == ["Manage HP"]
    assert app.panel("Manage HP").is_pinned()
    assert not app.panel("Dice Roller").is_pinned()
    for title in BETA:
        expect(app.panel(title).root.locator(".panel__title-beta")).to_have_text("beta")
    app.shot("boot")


def test_the_open_manage_hp_aims_at_the_head_of_the_queue_before_combat(app):
    app.add("Goblin Warrior", count=2)
    expect(manage_hp_target(app)).to_have_text("Target: Goblin Warrior", timeout=2000)
    press_manage_hp(app, "Damage", 3)
    assert app.card("Goblin Warrior").hp() == 7


def test_manage_hp_damages_the_active_creature_on_the_first_turn(app):
    app.add("Goblin Warrior", count=2)
    app.begin_combat()
    active = app.active_name()
    press_manage_hp(app, "Damage", 3)
    app.shot("first-turn-damage")
    assert [app.card(name).hp() for name in app.card_names()] == [
        7 if name == active else 10 for name in app.card_names()
    ]


def test_manage_hp_damages_the_active_creature_from_the_second_turn(app):
    app.add("Goblin Warrior", count=2)
    app.begin_combat()
    app.next_turn()
    active = app.active_name()
    expect(manage_hp_target(app)).to_have_text(f"Target: {active}")
    press_manage_hp(app, "Damage", 3)
    assert app.card(active).hp() == 7


def test_a_panel_folds_and_unfolds_from_its_caret_and_from_its_heading(app):
    status = app.panel("Status")
    status.fold_button().click()
    expect(status.fold_button()).to_have_attribute("aria-expanded", "true")
    expect(status.root.locator(".panel__body--drawer")).to_be_visible()
    status.fold_button().click()
    expect(status.fold_button()).to_have_attribute("aria-expanded", "false")
    expect(status.root.locator(".panel__body--drawer")).to_have_count(0)

    status.root.locator(".panel__title--drawer").click()
    expect(status.fold_button()).to_have_attribute("aria-expanded", "true")
    status.root.locator(".panel__title--drawer").click()
    expect(status.fold_button()).to_have_attribute("aria-expanded", "false")


def test_pinning_and_unpinning_never_folds_the_panel(app):
    dice = app.panel("Dice Roller")
    dice.toggle_pin()
    assert dice.is_pinned()
    assert not dice.is_open()
    dice.open().toggle_pin()
    assert not dice.is_pinned()
    assert dice.is_open()


def test_a_pinned_panel_joins_the_bottom_of_the_pinned_block(app):
    app.panel("Treasure").toggle_pin()
    app.panel("Status").toggle_pin()
    assert pinned_titles(app.page) == ["Manage HP", "Treasure", "Status"]
    assert drawer_titles(app.page)[:3] == ["Manage HP", "Treasure", "Status"]


def test_an_unpinned_panel_lands_at_the_top_of_the_rest(app):
    app.panel("Treasure").toggle_pin()
    app.panel("Status").toggle_pin()
    app.panel("Manage HP").toggle_pin()
    assert pinned_titles(app.page) == ["Treasure", "Status"]
    assert drawer_titles(app.page)[:4] == ["Treasure", "Status", "Manage HP", "Dice Roller"]
    app.panel("Treasure").toggle_pin()
    app.panel("Status").toggle_pin()
    assert pinned_titles(app.page) == []
    assert drawer_titles(app.page)[:3] == ["Status", "Treasure", "Manage HP"]
    expect(app.page.locator(".drawer-pinned")).to_have_count(0)


def test_the_pinned_block_holds_the_top_only_while_every_pinned_panel_is_folded(app):
    app.panel("Dice Roller").toggle_pin()
    app.panel("Quick Add").open()
    app.panel("Random Encounter").open()
    assert not pinned_held(app.page)

    app.panel("Manage HP").fold()
    assert pinned_held(app.page)
    scrolled = stack_scroll(app.page, 400)
    assert scrolled["scrollTop"] > 0, "The stack should be tall enough to scroll."
    assert abs(scrolled["pinnedOffset"]) <= 1, scrolled
    app.shot("held-while-folded")

    app.panel("Dice Roller").open()
    assert not pinned_held(app.page)


@pytest.mark.cross_browser
def test_an_open_pinned_editor_scrolls_away_with_the_rest_of_the_column(app):
    app.panel("Dice Roller").toggle_pin()
    app.panel("Dice Roller").open()
    app.panel("Quick Add").open()
    app.panel("Random Encounter").open()
    top = stack_scroll(app.page, 0)
    assert abs(top["pinnedOffset"]) <= 1
    bottom = stack_scroll(app.page, 100000)
    assert bottom["scrollTop"] == bottom["scrollable"] > 0
    assert bottom["pinnedOffset"] < -100, bottom
    expect(heading(app.panel("Manage HP"))).not_to_be_in_viewport()
    expect(heading(app.panel("Dice Roller"))).not_to_be_in_viewport()
    expect(app.panel("Random Encounter").root.get_by_role("button", name="Add to Encounter")).to_be_in_viewport()
    app.shot("scrolled-past-open-pinned")


def test_unfolding_a_panel_from_its_heading_scrolls_it_into_view(app):
    app.panel("Quick Add").open()
    stack_scroll(app.page, 0)
    random = app.panel("Random Encounter")
    expect(heading(random)).not_to_be_in_viewport()
    random.open()
    expect(heading(random)).to_be_in_viewport()
    app.shot("scrolled-to-random-encounter")


@pytest.mark.cross_browser
def test_dragging_a_panel_by_its_heading_moves_it(app):
    drag_panel(app, "Initiative", "Dice Roller")
    assert drawer_titles(app.page)[:4] == ["Manage HP", "Initiative", "Dice Roller", "Status"]
    drag_panel(app, "Initiative", "Random Encounter")
    assert drawer_titles(app.page)[-2:] == ["Random Encounter", "Initiative"]
    app.shot("after-drags")


@pytest.mark.cross_browser
def test_a_loose_panel_dragged_into_the_pinned_block_stops_below_it(app):
    app.panel("Dice Roller").toggle_pin()
    drag_panel(app, "Treasure", "Manage HP")
    assert pinned_titles(app.page) == ["Manage HP", "Dice Roller"]
    assert drawer_titles(app.page)[:3] == ["Manage HP", "Dice Roller", "Treasure"]
    assert not app.panel("Treasure").is_pinned()


@pytest.mark.cross_browser
def test_a_pinned_panel_dragged_below_the_rest_stops_at_the_bottom_of_the_block(app):
    app.panel("Dice Roller").toggle_pin()
    app.panel("Status").toggle_pin()
    drag_panel(app, "Manage HP", "Random Encounter")
    assert pinned_titles(app.page) == ["Dice Roller", "Status", "Manage HP"]
    assert drawer_titles(app.page)[3] == "Condition/Effect"
    assert app.panel("Manage HP").is_pinned()


@pytest.mark.cross_browser
def test_a_drag_within_the_pinned_block_reorders_it(app):
    app.panel("Dice Roller").toggle_pin()
    app.panel("Status").toggle_pin()
    drag_panel(app, "Status", "Manage HP")
    assert pinned_titles(app.page) == ["Status", "Manage HP", "Dice Roller"]


@pytest.mark.cross_browser
def test_shift_click_on_an_open_heading_folds_every_panel(app):
    for title in ["Dice Roller", "Status", "Initiative"]:
        app.panel(title).open()
    heading(app.panel("Status")).click(modifiers=["Shift"])
    app.settle()
    assert open_titles(app.page) == []


@pytest.mark.cross_browser
def test_shift_click_on_a_folded_heading_just_unfolds_it(app):
    heading(app.panel("Status")).click(modifiers=["Shift"])
    app.settle()
    assert open_titles(app.page) == ["Manage HP", "Status"]


@pytest.mark.cross_browser
def test_escape_folds_the_lowest_open_panel_first(app):
    app.panel("Initiative").open()
    app.panel("Status").open()
    assert open_titles(app.page) == ["Manage HP", "Status", "Initiative"]
    app.page.keyboard.press("Escape")
    app.settle()
    assert open_titles(app.page) == ["Manage HP", "Status"]
    app.page.keyboard.press("Escape")
    app.settle()
    assert open_titles(app.page) == ["Manage HP"]
    app.page.keyboard.press("Escape")
    app.settle()
    assert open_titles(app.page) == []
    app.page.keyboard.press("Escape")
    app.settle()
    assert drawer_titles(app.page) == BOOT_ORDER


@pytest.mark.cross_browser
def test_escape_on_the_settings_popover_closes_only_the_popover(app):
    trigger = app.page.get_by_role("button", name="Open settings")
    trigger.click()
    expect(trigger).to_have_attribute("aria-expanded", "true")
    app.page.keyboard.press("Escape")
    expect(trigger).to_have_attribute("aria-expanded", "false")
    assert app.panel("Manage HP").is_open()


@pytest.mark.cross_browser
def test_escape_on_the_encounter_menu_closes_only_the_menu(app):
    trigger = app.page.get_by_role("button", name=re.compile("^Encounter"))
    trigger.click()
    expect(trigger).to_have_attribute("aria-expanded", "true")
    app.page.keyboard.press("Escape")
    expect(trigger).to_have_attribute("aria-expanded", "false")
    assert app.panel("Manage HP").is_open()


@pytest.mark.cross_browser
def test_alt_shift_c_collapses_every_editor(app):
    for title in ["Dice Roller", "Status", "Quick Add"]:
        app.panel(title).open()
    hotkey(app, "C")
    assert open_titles(app.page) == []


@pytest.mark.cross_browser
def test_alt_shift_p_opens_only_the_pinned_editors(app):
    app.panel("Treasure").toggle_pin()
    app.panel("Status").open()
    app.panel("Manage HP").fold()
    hotkey(app, "P")
    assert open_titles(app.page) == ["Manage HP", "Treasure"]


@pytest.mark.cross_browser
def test_alt_shift_h_opens_only_manage_hp(app):
    app.panel("Treasure").toggle_pin()
    app.panel("Treasure").open()
    app.panel("Status").open()
    app.panel("Manage HP").fold()
    hotkey(app, "H")
    assert open_titles(app.page) == ["Manage HP"]


@pytest.mark.cross_browser
def test_hotkeys_fire_while_typing_and_type_nothing_into_the_field(app):
    quick_add = app.panel("Quick Add").open()
    search = quick_add.root.get_by_role("searchbox", name="Filter Quick Add by name")
    search.fill("gob")
    search.press("Alt+Shift+KeyC")
    app.settle()
    assert open_titles(app.page) == []
    quick_add.open()
    expect(search).to_have_value("gob")


def test_hotkeys_leave_other_pages_alone(app):
    app.goto("/about")
    expect(app.page.get_by_role("heading", name="Keyboard shortcuts")).to_be_visible()
    app.page.keyboard.press("Alt+Shift+KeyC")
    app.page.keyboard.press("Alt+Shift+KeyH")
    app.goto("/")
    assert open_titles(app.page) == ["Manage HP"]


def test_the_session_profile_keeps_only_the_editors_a_fight_needs(app):
    choose_profile(app, "Session")
    assert drawer_titles(app.page) == [
        "Manage HP",
        "Dice Roller",
        "Status",
        "Condition/Effect",
        "Initiative",
        "Duplicate",
    ]
    app.shot("session-profile")


def test_the_builder_profile_keeps_only_the_editors_that_build_a_fight(app):
    app.panel("Dice Roller").open()
    choose_profile(app, "Builder")
    assert drawer_titles(app.page) == [
        "Initiative",
        "Duplicate",
        "Replace",
        "Encounter Difficulty",
        "Encounter XP",
        "Quick Add",
    ]
    assert open_titles(app.page) == []
    app.shot("builder-profile")


def test_a_hidden_editor_still_opens_from_its_trigger_and_leaves_when_folded(app):
    choose_profile(app, "Session")
    app.page.get_by_role("button", name="Quick Add", exact=True).click()
    app.settle()
    assert "Quick Add" in open_titles(app.page)
    app.panel("Quick Add").fold_button().click()
    expect(app.panel("Quick Add").root).to_have_count(0)
    assert "Quick Add" not in drawer_titles(app.page)


def test_the_beta_profile_shows_every_editor_and_the_profile_survives_a_reload(app):
    choose_profile(app, "Builder")
    app.reload()
    assert "Dice Roller" not in drawer_titles(app.page)
    choose_profile(app, "Beta")
    assert drawer_titles(app.page) == BOOT_ORDER
    app.reload()
    assert drawer_titles(app.page) == BOOT_ORDER


@pytest.mark.cross_browser
def test_the_column_order_and_pins_survive_a_reload(app):
    drag_panel(app, "Quick Add", "Dice Roller")
    app.panel("Treasure").toggle_pin()
    app.panel("Manage HP").toggle_pin()
    arranged = drawer_titles(app.page)
    assert arranged[:3] == ["Treasure", "Manage HP", "Quick Add"]
    app.reload()
    assert drawer_titles(app.page) == arranged
    assert pinned_titles(app.page) == ["Treasure"]
    app.shot("after-reload")


def test_the_column_layout_survives_a_reload_for_a_signed_in_dm(app):
    app.sign_up()
    app.panel("Status").toggle_pin()
    drag_panel(app, "Random Encounter", "Dice Roller")
    arranged = drawer_titles(app.page)
    app.reload()
    assert drawer_titles(app.page) == arranged
    assert pinned_titles(app.page) == ["Manage HP", "Status"]
