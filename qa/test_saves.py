"""Session prep: a DM saves the prepared encounter and loads it at the table.

These scenarios cover the Encounter menu in the app bar.  A save goes to a
file on the DM's machine or to the DM's account on the server.
"""

import json
import re
import urllib.request

import pytest
from playwright.sync_api import expect

from pages.building import encounter_menu, has_unsaved_mark, open_encounter_dialog


def build_ambush(app):
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    app.panel("Quick Add").fold()


def download(app, name=None):
    dialog = open_encounter_dialog(app.page, "Save")
    expect(dialog.get_by_role("button", name="A file on this device")).to_have_attribute(
        "aria-pressed", "true"
    )
    if name is not None:
        dialog.get_by_role("textbox", name="File name:").fill(name)
    with app.page.expect_download() as pending:
        dialog.get_by_role("button", name="Download").click()
    expect(dialog).to_be_hidden()
    return pending.value


def load_file(app, path):
    dialog = open_encounter_dialog(app.page, "Load")
    with app.page.expect_file_chooser() as chooser:
        dialog.get_by_role("button", name="Load from file…").click()
    chooser.value.set_files(str(path))
    return dialog


def clear_encounter(app):
    app.page.get_by_role("button", name="Clear encounter").click()
    app.page.get_by_role("dialog", name="Clear Encounter").get_by_role(
        "button", name="Clear"
    ).click()
    expect(app.page.get_by_role("article")).to_have_count(0)


# A file on this device.


@pytest.mark.cross_browser
def test_downloading_saves_the_encounter_as_a_named_json_file(app, tmp_path):
    build_ambush(app)
    assert has_unsaved_mark(app.page)
    saved = download(app, "Goblin Ambush")
    assert saved.suggested_filename == "Goblin Ambush.json"
    path = tmp_path / saved.suggested_filename
    saved.save_as(path)
    body = json.loads(path.read_text())
    assert [creature["name"] for creature in body["creatures"]] == app.card_names()
    assert body["round"] == 1

    expect(encounter_menu(app.page)).to_have_accessible_name("Encounter")
    expect(app.page.get_by_label("from file: Goblin Ambush")).to_have_count(1)
    app.shot("downloaded")


@pytest.mark.cross_browser
def test_a_nameless_download_is_called_encounter(app):
    build_ambush(app)
    assert download(app).suggested_filename == "encounter.json"


@pytest.mark.cross_browser
def test_a_downloaded_file_loads_back_in_pre_combat(app, tmp_path):
    build_ambush(app)
    app.card("Ogre").remove()
    app.add("Bugbear Warrior")
    expected = app.card_names()
    path = tmp_path / "ambush.json"
    download(app, "ambush").save_as(path)

    clear_encounter(app)
    app.add("Owlbear")
    app.begin_combat()
    app.next_turn()
    assert app.round_number() == 2

    dialog = load_file(app, path)
    expect(dialog).to_be_hidden()
    expect(app.page.get_by_text("Loaded encounter from file.")).to_be_visible()
    assert app.card_names() == expected
    assert app.round_number() == 1
    assert app.active_name() is None
    assert not has_unsaved_mark(app.page)
    app.shot("loaded-from-file")


@pytest.mark.cross_browser
def test_a_file_that_is_not_json_is_refused_and_the_encounter_is_kept(app, tmp_path):
    build_ambush(app)
    before = app.card_names()
    path = tmp_path / "notes.txt"
    path.write_text("Goblins hide in the ferns.  Ogre sleeps by the fire.")
    dialog = load_file(app, path)
    expect(dialog.get_by_text(re.compile("^Couldn't parse file: "))).to_be_visible()
    expect(dialog).to_be_visible()
    app.shot("not-json")
    dialog.get_by_role("button", name="Close").click()
    assert app.card_names() == before


@pytest.mark.cross_browser
def test_a_json_file_that_is_not_an_encounter_fails_with_a_short_message(app, tmp_path):
    build_ambush(app)
    before = app.card_names()
    path = tmp_path / "creatures.json"
    with urllib.request.urlopen(app.server.base_url + "/bundled-creatures.json") as body:
        path.write_bytes(body.read())
    dialog = load_file(app, path)
    error = dialog.get_by_text(re.compile("^Couldn't parse file: "))
    expect(error).to_be_visible()
    assert app.card_names() == before
    app.shot("wrong-json")
    assert len(error.inner_text()) < 300


# This server.


def save_to_server(app, name):
    dialog = open_encounter_dialog(app.page, "Save")
    expect(dialog.get_by_role("button", name="This server")).to_have_attribute(
        "aria-pressed", "true"
    )
    field = dialog.get_by_role("textbox", name="Encounter Name:")
    field.fill(name)
    dialog.get_by_role("button", name="Save", exact=True).click()
    return dialog


def saved_names(dialog):
    return dialog.get_by_role("listbox").get_by_role("option").all_inner_texts()


def pick_save(dialog, name):
    option = dialog.get_by_role("option", name=name, exact=True)
    option.click()
    expect(option).to_have_attribute("aria-selected", "true")


def test_an_anonymous_dm_is_sent_to_sign_in_for_server_saves(app):
    build_ambush(app)
    dialog = open_encounter_dialog(app.page, "Save")
    dialog.get_by_role("button", name="This server").click()
    expect(
        dialog.get_by_text(re.compile("^Saving to the server keeps an encounter"))
    ).to_be_visible()
    expect(dialog.get_by_role("link", name="Sign in")).to_have_attribute("href", "/login")
    dialog.get_by_role("button", name="Close").click()

    dialog = open_encounter_dialog(app.page, "Load")
    expect(dialog.get_by_text("Saved on this server (0)")).to_be_visible()
    expect(dialog.get_by_role("link", name="Sign in")).to_be_visible()


def test_a_server_save_lists_and_loads_back(app):
    app.sign_up()
    build_ambush(app)
    dialog = save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()
    expect(dialog).to_be_hidden()
    assert not has_unsaved_mark(app.page)
    expected = app.card_names()

    clear_encounter(app)
    assert has_unsaved_mark(app.page)
    dialog = open_encounter_dialog(app.page, "Load")
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_be_visible()
    load = dialog.get_by_role("button", name="Load", exact=True)
    expect(load).to_be_disabled()
    pick_save(dialog, "Bridge Fight")
    load.click()
    expect(
        dialog.get_by_text('Load "Bridge Fight"? This replaces the encounter on screen.')
    ).to_be_visible()
    app.shot("load-confirm")
    dialog.locator(".save-load__confirm").get_by_role("button", name="Load").click()
    expect(app.page.get_by_text('Loaded "Bridge Fight".')).to_be_visible()
    expect(dialog).to_be_hidden()
    assert app.card_names() == expected


def test_a_server_save_survives_a_server_restart(app):
    app.sign_up()
    build_ambush(app)
    save_to_server(app, "Keep me")
    expect(app.page.get_by_text('Saved "Keep me".')).to_be_visible()
    # Sessions live in memory.  A restart signs everyone out.
    app.server.restart()
    app.sign_in()
    dialog = open_encounter_dialog(app.page, "Load")
    expect(dialog.get_by_role("option", name="Keep me", exact=True)).to_be_visible()


def test_saving_under_a_taken_name_asks_before_overwriting(app):
    app.sign_up()
    app.add("Goblin Warrior", count=2)
    save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()
    app.add("Ogre")

    dialog = open_encounter_dialog(app.page, "Save")
    expect(dialog.get_by_role("textbox", name="Encounter Name:")).to_have_value("Bridge Fight")
    expect(
        dialog.get_by_text("Saving under a name you already have will ask before replacing it.")
    ).to_be_visible()
    dialog.get_by_role("button", name="Save", exact=True).click()
    prompt = dialog.get_by_text('Overwrite "Bridge Fight" with the current encounter?')
    expect(prompt).to_be_visible()
    app.shot("overwrite-confirm")
    dialog.locator(".save-load__confirm").get_by_role("button", name="Cancel").click()
    expect(prompt).to_be_hidden()
    expect(dialog).to_be_visible()

    dialog.get_by_role("button", name="Save", exact=True).click()
    dialog.locator(".save-load__confirm").get_by_role("button", name="Overwrite").click()
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()

    clear_encounter(app)
    dialog = open_encounter_dialog(app.page, "Load")
    assert saved_names(dialog).count("Bridge Fight") == 1
    pick_save(dialog, "Bridge Fight")
    dialog.get_by_role("button", name="Load", exact=True).click()
    dialog.locator(".save-load__confirm").get_by_role("button", name="Load").click()
    expect(app.card("Ogre").root).to_be_visible()


def test_renaming_a_server_save(app):
    app.sign_up()
    build_ambush(app)
    save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()

    dialog = open_encounter_dialog(app.page, "Load")
    pick_save(dialog, "Bridge Fight")
    dialog.get_by_role("button", name="Rename").click()
    field = dialog.get_by_role("textbox", name="New name for the save")
    expect(field).to_have_value("Bridge Fight")
    field.fill("Bridge Fight, take two")
    field.press("Enter")
    expect(dialog.get_by_role("option", name="Bridge Fight, take two", exact=True)).to_be_visible()
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_have_count(0)
    expect(
        dialog.get_by_role("option", name="Bridge Fight, take two", exact=True)
    ).to_have_attribute("aria-selected", "true")

    dialog.get_by_role("button", name="Rename").click()
    dialog.get_by_role("textbox", name="New name for the save").fill("Never mind")
    dialog.get_by_role("button", name="Cancel").click()
    expect(dialog.get_by_role("option", name="Bridge Fight, take two", exact=True)).to_be_visible()


@pytest.mark.parametrize("problem", ["a taken name", "a slash"])
def test_a_refused_save_name_says_why(app, problem):
    app.sign_up()
    app.add("Ogre")
    save_to_server(app, "Camp")
    expect(app.page.get_by_text('Saved "Camp".')).to_be_visible()
    if problem == "a taken name":
        save_to_server(app, "Cave")
        expect(app.page.get_by_text('Saved "Cave".')).to_be_visible()
        dialog = open_encounter_dialog(app.page, "Load")
        pick_save(dialog, "Cave")
        dialog.get_by_role("button", name="Rename").click()
        field = dialog.get_by_role("textbox", name="New name for the save")
        field.fill("Camp")
        field.press("Enter")
    else:
        dialog = save_to_server(app, "Act 1/Scene 2")
    error = dialog.locator(".cond-section__caption--danger")
    expect(error).to_be_visible()
    app.shot("refused")
    expect(error).not_to_contain_text("Server returned")


def test_deleting_a_server_save_asks_first(app):
    app.sign_up()
    build_ambush(app)
    save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()

    dialog = open_encounter_dialog(app.page, "Load")
    pick_save(dialog, "Bridge Fight")
    delete = dialog.get_by_role("button", name="Delete")
    delete.click()
    prompt = dialog.get_by_text('Delete "Bridge Fight"? This cannot be undone.')
    expect(prompt).to_be_visible()
    dialog.locator(".save-load__confirm").get_by_role("button", name="Cancel").click()
    expect(prompt).to_be_hidden()
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_be_visible()

    delete.click()
    dialog.locator(".save-load__confirm").get_by_role("button", name="Delete").click()
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_have_count(0)
    app.reload()
    dialog = open_encounter_dialog(app.page, "Load")
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_have_count(0)


@pytest.mark.cross_browser
def test_the_arrow_keys_walk_the_save_list(app):
    app.sign_up()
    build_ambush(app)
    save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()
    save_to_server(app, "Cave Fight")
    expect(app.page.get_by_text('Saved "Cave Fight".')).to_be_visible()
    dialog = open_encounter_dialog(app.page, "Load")
    options = dialog.get_by_role("listbox").get_by_role("option")
    expect(options).to_have_count(2)
    options.nth(0).focus()
    app.page.keyboard.press("ArrowDown")
    expect(options.nth(1)).to_have_attribute("aria-selected", "true")
    expect(options.nth(1)).to_be_focused()
    app.page.keyboard.press("ArrowUp")
    expect(options.nth(0)).to_have_attribute("aria-selected", "true")
    expect(options.nth(0)).to_be_focused()


@pytest.mark.cross_browser
def test_a_keyboard_dm_can_pick_a_server_save(app):
    app.sign_up()
    build_ambush(app)
    save_to_server(app, "Bridge Fight")
    expect(app.page.get_by_text('Saved "Bridge Fight".')).to_be_visible()
    dialog = open_encounter_dialog(app.page, "Load")
    dialog.get_by_role("button", name="Load from file…").focus()
    for _ in range(4):
        app.page.keyboard.press("Tab")
        if dialog.get_by_role("option", name="Bridge Fight", exact=True).evaluate(
            "el => el === document.activeElement"
        ):
            break
    app.page.keyboard.press("Enter")
    expect(dialog.get_by_role("option", name="Bridge Fight", exact=True)).to_have_attribute(
        "aria-selected", "true", timeout=2000
    )
