"""A fight in progress outlives reloads, restarts, tabs and devices."""

import pytest
from playwright.sync_api import expect

from pages.accounts import (
    MID_FIGHT,
    PRESET_SAMPLES,
    LoginPage,
    api,
    build_mid_fight,
    devices,  # noqa: F401  The fixture is used by name.
    error_toasts,
    expect_dice_log,
    fight_state,
    live_names,
    put_preset_samples,
    roll_d20,
    save_condition_preset,
    shot,
    signed_in_device,
    wait_for_cards,
    wait_signed_in,
    wait_until_saved,
)
from pages.app import ACTIVE_MARKER, DM, PASSWORD
from pages.fight import ConditionEditor, ManageHp, hp_button



def test_an_anonymous_fight_survives_a_reload(app):
    assert build_mid_fight(app) == MID_FIGHT
    shot(app, "before-reload")
    app.reload()
    wait_for_cards(app, MID_FIGHT["names"])
    assert fight_state(app) == MID_FIGHT
    shot(app, "after-reload")


def test_a_signed_in_fight_comes_back_from_the_server_on_reload(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    assert build_mid_fight(app) == MID_FIGHT
    wait_until_saved(app.page, MID_FIGHT["names"], "Web")
    app.page.evaluate("() => localStorage.clear()")
    app.reload()
    wait_signed_in(app, "Dee Em")
    wait_for_cards(app, MID_FIGHT["names"])
    assert fight_state(app) == MID_FIGHT


def test_a_fight_survives_a_server_restart_once_the_dm_signs_back_in(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    build_mid_fight(app)
    wait_until_saved(app.page, MID_FIGHT["names"], "Web")
    app.server.restart()
    app.reload()
    shot(app, "after-restart")
    LoginPage(app.page, app.server.base_url).goto().sign_in(DM)
    wait_signed_in(app, "Dee Em")
    wait_for_cards(app, MID_FIGHT["names"])
    assert fight_state(app) == MID_FIGHT
    shot(app, "signed-back-in")


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-06: a server restart signs every DM out",
)
def test_a_server_restart_keeps_the_dm_signed_in(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    app.server.restart()
    app.reload()
    expect(app.page.get_by_role("link", name="Dee Em", exact=True)).to_be_visible(timeout=3000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-06: after a restart the open tab says only 'Save failed: Server returned 401.'",
)
def test_an_open_tab_tells_the_dm_to_sign_in_again_after_a_restart(app):
    app.sign_up(DM, PASSWORD, "Dee Em")
    build_mid_fight(app)
    wait_until_saved(app.page, MID_FIGHT["names"], "Web")
    app.server.restart()
    ManageHp(app).open_for("Ogre").damage(5)
    expect(error_toasts(app.page).filter(has_text="Save failed")).to_be_visible()
    shot(app, "after-restart-edit")
    expect(error_toasts(app.page).filter(has_text="Save failed")).to_contain_text(
        "sign in", ignore_case=True
    )


@pytest.mark.cross_browser
def test_two_tabs_share_the_encounter_as_it_changes(app, devices):
    second = devices.tab("second")
    app.add("Goblin Warrior")
    app.add("Ogre")
    wait_for_cards(second, ["Goblin Warrior", "Ogre"])

    ManageHp(second).open_for("Ogre").damage(10)
    expect(hp_button(app.card("Ogre"), "Current")).to_have_text("58")
    app.begin_combat()
    expect(second.page.get_by_role("button", name=ACTIVE_MARKER)).to_have_count(1)
    assert second.active_name() == app.active_name()
    shot(second, "second-tab")


@pytest.mark.cross_browser
def test_two_tabs_share_dice_rolls(app, devices):
    second = devices.tab("second")
    second.panel("Dice Roller").open()
    roll_d20(app)
    roll_d20(app)
    expect_dice_log(app, 2)
    expect_dice_log(second, 2)
    shot(second, "second-tab-log")


def test_a_second_device_sees_the_same_fight_and_rolls(app, devices):
    app.sign_up(DM, PASSWORD, "Dee Em")
    build_mid_fight(app)
    roll_d20(app)
    wait_until_saved(app.page, MID_FIGHT["names"], "Web")

    laptop = devices.device("laptop", "/login")
    LoginPage(laptop.page, app.server.base_url).sign_in(DM)
    wait_signed_in(laptop, "Dee Em")
    wait_for_cards(laptop, MID_FIGHT["names"])
    assert fight_state(laptop) == MID_FIGHT
    laptop.panel("Dice Roller").open()
    expect_dice_log(laptop, 1)
    shot(laptop, "laptop")

    with laptop.page.expect_response(
        lambda r: r.url.endswith("/api/encounter") and r.request.method == "PUT"
    ):
        laptop.next_turn()
    app.reload()
    wait_for_cards(app, MID_FIGHT["names"])
    assert app.active_name() == "Ogre"


def test_a_condition_preset_follows_the_dm_to_a_second_device(app, devices):
    app.sign_up(DM, PASSWORD, "Dee Em")
    save_condition_preset(app, "Hag poison")
    assert "Hag poison" in api(app.page, "GET", "/api/condition-presets").json()

    laptop = signed_in_device(devices, "laptop", DM, "Dee Em")
    laptop.panel("Condition/Effect").open()
    menu = ConditionEditor(laptop).load_menu()
    menu.get_by_role("searchbox", name="Search presets").fill("Hag")
    expect(menu.get_by_role("option", name="Hag poison")).to_be_visible()
    shot(laptop, "preset-menu")


def test_save_chains_lore_groups_and_treasure_follow_the_dm_to_a_second_device(app, devices):
    app.sign_up(DM, PASSWORD, "Dee Em")
    put_preset_samples(app.page)
    stored = {path: api(app.page, "GET", path).json() for path in PRESET_SAMPLES}
    # A booting device writes the treasure table back with the bundled
    # rows filled in.  So only the DM's own gem is compared.
    stored["/api/treasure-table"] = stored["/api/treasure-table"]["gems"]

    laptop = signed_in_device(devices, "laptop", DM, "Dee Em")
    seen = {path: api(laptop.page, "GET", path).json() for path in PRESET_SAMPLES}
    seen["/api/treasure-table"] = seen["/api/treasure-table"]["gems"]
    assert seen == stored
    assert "Hag's Curse" in stored["/api/save-chain-presets"]
    assert stored["/api/lore-groups"][0]["name"] == "Hag coven"
    assert stored["/api/treasure-table"] == {"50gp": ["Swamp pearl"]}
    assert "Bog hoard" in stored["/api/treasure-profiles"]
    assert live_names(laptop.page) == []
