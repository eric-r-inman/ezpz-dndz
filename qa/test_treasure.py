"""Session prep: a DM rolls the loot the party will find.

These scenarios cover the Treasure panel, its Tune your rolls knobs and profiles
and the Treasure Table editor.
"""

import re

import pytest
from playwright.sync_api import expect

from pages.app import settle
from pages.building import number

GP_PER_COIN = {"pp": 10, "gp": 1, "ep": 0.5, "sp": 0.1, "cp": 0.01}


def treasure_panel(app):
    app.panel("Quick Add").fold()
    return app.panel("Treasure").open()


def roll(panel, kind=None):
    if kind:
        panel.root.get_by_role("combobox", name="Roll:").select_option(label=kind)
    panel.root.get_by_role("button", name="🎲 Roll").click()
    settle(panel.page)
    expect(panel.root.locator(".treasure__summary")).to_be_visible()


def coins(scope):
    """Rolled coins by denomination.  The rows name only their remove button."""
    lines = scope.locator(".treasure__coin-text").all_inner_texts()
    return {line.split()[1]: number(line) for line in lines}


def coin_value(by_denomination):
    return sum(GP_PER_COIN[coin] * amount for coin, amount in by_denomination.items())


def summary(panel):
    chunks = panel.root.locator(".treasure__summary-chunk").all_inner_texts()
    values = {chunk.split()[0]: number(chunk) for chunk in chunks}
    values["Total"] = number(panel.root.locator(".treasure__summary-total").inner_text())
    return values


def section(panel, title):
    return panel.root.locator(".treasure__section").filter(
        has=panel.page.locator(".treasure__section-title", has_text=re.compile(f"^{title}$"))
    )


def valued_rows(panel, title):
    """Rows in a gems, art or gear section.

    Each is a name, a count and a value.
    """
    return [valued_row(row) for row in section(panel, title).locator(".treasure__row").all()]


def valued_row(row):
    count = row.locator(".treasure__row-count")
    return (
        row.locator(".treasure__row-name").evaluate("el => el.firstChild.textContent"),
        number(count.inner_text()) if count.count() else 1,
        number(row.locator(".treasure__row-value").inner_text()),
    )


def open_tune(panel):
    toggle = panel.root.get_by_role("button", name=re.compile("Tune your rolls"))
    if toggle.inner_text().startswith("▶"):
        toggle.click()
    expect(panel.root.get_by_text("Presets:")).to_be_visible()


def knob_row(panel, label):
    """One Tune your rolls row."""
    return panel.root.locator(".treasure__settings-row").filter(
        has=panel.page.locator(".treasure__settings-row-label", has_text=re.compile(f"^{label}$"))
    )


def active_knobs(panel, label):
    return knob_row(panel, label).locator(".treasure__settings-segment--active").all_inner_texts()


def skipped(panel, label):
    return knob_row(panel, label).get_by_role("switch").get_attribute("aria-checked") == "true"


def test_each_knob_names_its_row_and_says_which_is_pressed(app):
    panel = treasure_panel(app)
    open_tune(panel)
    amount = panel.root.get_by_role("group", name="Coins amount")
    expect(amount.get_by_role("button", name="Normal")).to_have_attribute("aria-pressed", "true")
    expect(amount.get_by_role("button", name="More")).to_have_attribute("aria-pressed", "false")
    rarity = panel.root.get_by_role("group", name="Magic rarity")
    expect(rarity.get_by_role("button", name="Higher")).to_have_attribute("aria-pressed", "false")
    expect(panel.root.get_by_role("switch", name="Gems none")).to_have_attribute(
        "aria-checked", "false"
    )


def preset(panel, name):
    open_tune(panel)
    panel.root.get_by_role("button", name=name, exact=True).click()
    settle(panel.page)


# Rolling.


def test_a_boss_roll_adds_up_its_coins_and_gems(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    expect(panel.root.get_by_text("Pick a kind above and hit Roll.")).to_be_visible()
    expect(panel.root.get_by_text("Average ≈ 200 gp")).to_be_visible()
    roll(panel, "Boss (lair hoard)")
    totals = summary(panel)
    # The strip rounds each denomination down.  It may trail by a coin or two.
    assert 0 <= coin_value(coins(panel.root)) - totals["Coins"] < 3
    gems = valued_rows(panel, "Gems")
    assert totals["Gems"] == sum(count * value for _, count, value in gems)
    assert totals["Total"] == totals["Coins"] + totals["Gems"] + totals["Art"]
    panel.root.scroll_into_view_if_needed()
    app.shot("boss-roll")


def test_an_individual_roll_breaks_down_by_creature(app):
    app.add("Goblin Warrior", count=3)
    app.add_placeholder()
    panel = treasure_panel(app)
    panel.root.get_by_role("combobox", name="Roll:").select_option(label="All (individual loot)")
    expect(panel.root.get_by_text("Average ≈ 75 gp")).to_be_visible()
    preset(panel, "Coins only")
    roll(panel)
    toggle = panel.root.get_by_role("button", name=re.compile("By creature"))
    expect(toggle).to_contain_text("3 enemies")
    toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "true")
    rows = panel.root.locator(".treasure__contributions-row")
    expect(rows).to_have_count(3)
    names = rows.locator(".treasure__contributions-name").all_inner_texts()
    assert [name.split(" — ")[0] for name in names] == [
        "Goblin Warrior",
        "Goblin Warrior 2",
        "Goblin Warrior 3",
    ]
    assert all("CR 0–4" in text for text in rows.all_inner_texts())
    assert sum(contribution_coins(rows).values()) == sum(coins(panel.root).values())
    app.shot("by-creature")


def contribution_coins(rows):
    """Coins summed across the By creature rows.

    Each denomination is summed apart.
    """
    totals = {}
    for text in rows.locator(".treasure__contributions-line").all_inner_texts():
        if text.startswith("Coins: "):
            for amount, coin in re.findall(r"([\d,]+) (pp|gp|ep|sp|cp)", text):
                totals[coin] = totals.get(coin, 0) + number(amount)
    return totals


def test_removing_a_coin_row_updates_the_by_creature_breakdown(app):
    app.add("Goblin Warrior", count=3)
    panel = treasure_panel(app)
    preset(panel, "Coins only")
    roll(panel, "All (individual loot)")
    panel.root.get_by_role("button", name=re.compile("By creature")).click()
    rows = panel.root.locator(".treasure__contributions-row")
    expect(rows).to_have_count(3)
    assert contribution_coins(rows) == coins(panel.root)

    first = section(panel, "Coins").get_by_role("listitem").first
    removed = first.inner_text().split()[1]
    first.get_by_role("button", name=re.compile(f"^Remove [0-9,]+ {removed}$")).click()
    settle(app.page)
    assert removed not in coins(panel.root)
    app.shot("after-remove")
    assert contribution_coins(rows) == coins(panel.root)


def test_rerolling_one_category_keeps_the_rest_of_the_hoard(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    preset(panel, "+ Gems")
    roll(panel, "Boss (lair hoard)")
    gems_before = valued_rows(panel, "Gems")
    coins_before = coins(panel.root)
    changed = False
    for _ in range(5):
        panel.root.get_by_role("button", name="Re-roll coins").click()
        settle(app.page)
        assert valued_rows(panel, "Gems") == gems_before
        changed = changed or coins(panel.root) != coins_before
    assert changed, "Five coin re-rolls never changed the coins."


def test_removing_a_rolled_row_takes_it_off_the_total(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    preset(panel, "+ Gems")
    for _ in range(10):
        roll(panel, "Boss (lair hoard)")
        if valued_rows(panel, "Gems"):
            break
    gems = valued_rows(panel, "Gems")
    assert gems, "Ten hoard rolls produced no gems."
    before = summary(panel)
    name, count, value = gems[0]
    section(panel, "Gems").get_by_role("listitem").first.get_by_role(
        "button", name=f"Remove {name}", exact=True
    ).click()
    settle(app.page)
    after = summary(panel)
    assert after["Gems"] == before["Gems"] - value
    assert after["Total"] == before["Total"] - value
    remaining = [row for row in valued_rows(panel, "Gems") if row[0] == name]
    assert remaining == ([(name, count - 1, value)] if count > 1 else [])


def test_a_rolled_hoard_stays_with_the_encounter_after_a_reload(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    roll(panel)
    before = (coins(panel.root), summary(panel))
    app.reload()
    panel = treasure_panel(app)
    assert (coins(panel.root), summary(panel)) == before


def test_no_enemies_means_no_average_and_an_empty_roll(app):
    app.add_placeholder()
    panel = treasure_panel(app)
    expect(panel.root.get_by_text(re.compile("^Average"))).to_have_count(0)
    roll(panel, "All (individual loot)")
    expect(panel.root.get_by_text("(no coins)")).to_be_visible()


# Tune your rolls.


@pytest.mark.parametrize(
    "name, rolled",
    [
        ("Coins only", {"Coins"}),
        ("+ Gems", {"Coins", "Gems"}),
        ("Full SRD", {"Coins", "Gems", "Art", "Magic"}),
        ("Wizard's lair", {"Coins", "Magic"}),
        ("Bandit camp", {"Coins", "Weapons", "Armor"}),
    ],
)
def test_presets_set_which_categories_roll(app, name, rolled):
    app.add("Ogre")
    panel = treasure_panel(app)
    preset(panel, name)
    for label in ["Coins", "Gems", "Art", "Magic", "Mundane", "Weapons", "Armor"]:
        assert skipped(panel, label) == (label not in rolled), label
    titles = {
        "Gems": "Gems",
        "Art": "Art objects",
        "Magic": "Magic items",
        "Mundane": "Mundane gear",
        "Weapons": "Weapons",
        "Armor": "Armor",
    }
    for _ in range(3):
        roll(panel, "Boss (lair hoard)")
        for label, title in titles.items():
            if label not in rolled:
                expect(section(panel, title)).to_have_count(0)


def test_wizards_lair_sets_a_high_scroll_chance_and_reset_restores_defaults(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    chance = panel.root.get_by_role("spinbutton", name=re.compile("^Swap chance"))
    open_tune(panel)
    expect(chance).to_have_value("15")
    preset(panel, "Wizard's lair")
    expect(chance).to_have_value("75")
    knob_row(panel, "Coins").get_by_role("button", name="More").click()
    settle(app.page)
    assert active_knobs(panel, "Coins") == ["More"]

    panel.root.get_by_role("button", name="↺ Reset to defaults").click()
    settle(app.page)
    expect(chance).to_have_value("15")
    assert active_knobs(panel, "Coins") == ["Normal"]
    assert [skipped(panel, label) for label in ["Gems", "Art", "Magic", "Weapons"]] == [
        False,
        False,
        False,
        True,
    ]


def test_more_coins_rolls_richer_hoards_than_fewer(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    preset(panel, "Coins only")

    def hoard_coin_total(setting):
        knob_row(panel, "Coins").get_by_role("button", name=setting).click()
        settle(app.page)
        total = 0
        for _ in range(6):
            roll(panel, "Boss (lair hoard)")
            # Platinum turns up in few rows and swamps the rest.  It sits out.
            rolled = coins(panel.root)
            rolled.pop("pp", None)
            total += coin_value(rolled)
        return total

    fewer = hoard_coin_total("Fewer")
    more = hoard_coin_total("More")
    assert more > 1.5 * fewer, (fewer, more)


def gem_values_with(app, setting):
    app.add("Ogre")
    panel = treasure_panel(app)
    preset(panel, "+ Gems")
    knob_row(panel, "Gems").get_by_role("button", name=setting).click()
    settle(app.page)
    assert setting in active_knobs(panel, "Gems")
    seen = set()
    # About a third of hoards at this tier carry the gems Higher lifts.
    for _ in range(20):
        roll(panel, "Boss (lair hoard)")
        seen |= {value for _, _, value in valued_rows(panel, "Gems")}
    assert seen, "Twenty hoard rolls produced no gems."
    return seen


def test_lower_gem_value_rolls_only_the_cheapest_gems(app):
    assert gem_values_with(app, "Lower") == {10}


def test_higher_gem_value_reaches_the_next_tier_up(app):
    # A rolled gem may split into cheaper ones.  Only the top matters.
    assert 100 in gem_values_with(app, "Higher")


@pytest.mark.cross_browser
def test_tune_your_rolls_fits_inside_the_editor_column(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    open_tune(panel)
    app.shot("tune")
    edge = panel.root.locator(".treasure__settings").bounding_box()
    right = edge["x"] + edge["width"]
    cut_off = [
        label
        for label in ["Coins", "Gems", "Art", "Magic", "Mundane", "Weapons", "Armor"]
        if (box := knob_row(panel, label).get_by_role("switch").bounding_box())["x"]
        + box["width"]
        > right
    ]
    assert cut_off == []


def test_tuned_knobs_stay_with_the_encounter_after_a_reload(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    open_tune(panel)
    knob_row(panel, "Coins").get_by_role("button", name="More").click()
    knob_row(panel, "Magic").get_by_role("switch").click()
    settle(app.page)
    app.reload()
    panel = treasure_panel(app)
    open_tune(panel)
    assert active_knobs(panel, "Coins") == ["More"]
    assert skipped(panel, "Magic")


# Named profiles.


def save_profile(panel, name):
    open_tune(panel)
    field = panel.root.get_by_role("textbox", name="Save current as…")
    save = panel.root.locator(".treasure__settings-profile-save").get_by_role("button", name="Save")
    expect(save).to_be_disabled()
    field.fill(name)
    save.click()
    expect(field).to_have_value("")
    expect(panel.root.get_by_role("button", name=name, exact=True)).to_be_visible()


def test_a_signed_in_dm_saves_loads_and_deletes_a_named_profile(app):
    app.sign_up()
    app.add("Ogre")
    panel = treasure_panel(app)
    open_tune(panel)
    knob_row(panel, "Coins").get_by_role("button", name="More").click()
    save_profile(panel, "Dragon hoard")

    panel.root.get_by_role("button", name="↺ Reset to defaults").click()
    settle(app.page)
    assert active_knobs(panel, "Coins") == ["Normal"]
    panel.root.get_by_role("button", name="Dragon hoard", exact=True).click()
    settle(app.page)
    assert active_knobs(panel, "Coins") == ["More"]

    app.reload()
    panel = treasure_panel(app)
    open_tune(panel)
    chip = panel.root.get_by_role("button", name="Dragon hoard", exact=True)
    expect(chip).to_be_visible()
    app.shot("profile-saved")
    panel.root.get_by_role("button", name="Delete profile Dragon hoard").click()
    expect(chip).to_have_count(0)
    expect(panel.root.get_by_text("(none saved yet)")).to_be_visible()
    app.reload()
    panel = treasure_panel(app)
    open_tune(panel)
    expect(panel.root.get_by_text("(none saved yet)")).to_be_visible()


def test_an_anonymous_dms_named_profile_survives_a_reload(app):
    app.add("Ogre")
    panel = treasure_panel(app)
    save_profile(panel, "Pocket change")
    app.reload()
    panel = treasure_panel(app)
    open_tune(panel)
    expect(panel.root.get_by_role("button", name="Pocket change", exact=True)).to_be_visible(
        timeout=2000
    )


# The Treasure Table editor.


def open_table(app):
    panel = treasure_panel(app)
    panel.root.get_by_role("button", name="Edit treasure table…").click()
    dialog = app.page.get_by_role("dialog", name=re.compile("^📜 Treasure Table"))
    expect(dialog).to_be_visible()
    return dialog


def unfold(dialog, label):
    """Opens one editor section and returns it.

    Several sections share a label.  The three Items lists do.  The label then
    carries the entry count where it has to.
    """
    toggles = dialog.locator(".treasure-table__section-toggle")
    names = toggles.evaluate_all(
        "els => els.map(e => e.querySelector('.treasure-table__section-label').textContent"
        " + ' ' + e.querySelector('.treasure-table__section-count').textContent)"
    )
    pattern = re.compile("^" + re.escape(label) + "( |$)")
    matches = [index for index, name in enumerate(names) if pattern.search(name)]
    assert len(matches) == 1, (label, names)
    toggle = toggles.nth(matches[0])
    if toggle.get_attribute("aria-expanded") != "true":
        toggle.click()
    expect(toggle).to_have_attribute("aria-expanded", "true")
    return dialog.locator(".treasure-table__section").nth(matches[0])


def table_response(method):
    """Matches the server's reply to a `method` request for the treasure table."""
    return lambda response: (
        response.url.endswith("/api/treasure-table") and response.request.method == method
    )


def save_table(app, dialog):
    """Saves a signed-in DM's table edits and reloads.

    What the editor shows next then comes back from the server.
    """
    with app.page.expect_response(table_response("PUT")) as saved:
        dialog.get_by_role("button", name="Save", exact=True).click()
    assert saved.value.ok
    reload_with_table(app)


def reload_with_table(app):
    """Reloads a signed-in DM's page and waits for their table to arrive.

    An editor opened before the table arrives shows the bundled defaults.
    """
    with app.page.expect_response(table_response("GET")) as loaded:
        app.reload()
    assert loaded.value.ok
    settle(app.page)


def toggle_of(section):
    return section.locator(".treasure-table__section-toggle")


@pytest.mark.cross_browser
def test_table_editor_sections_fold_and_unfold(app):
    dialog = open_table(app)
    gems = unfold(dialog, "10gp gems")
    names = gems.get_by_role("textbox")
    expect(names).to_have_count(12)
    app.shot("table-editor")
    toggle_of(gems).click()
    expect(toggle_of(gems)).to_have_attribute("aria-expanded", "false")
    expect(names).to_have_count(0)


@pytest.mark.cross_browser
@pytest.mark.parametrize("way", ["Cancel", "Close", "Escape", "Save"])
def test_the_table_editor_closes(app, way):
    if way == "Save":
        app.sign_up()
    dialog = open_table(app)
    unfold(dialog, "Items 133 entries").get_by_role("button", name="+ Add item").click()
    if way == "Escape":
        app.page.keyboard.press("Escape")
    else:
        dialog.get_by_role("button", name=way, exact=True).click()
    expect(dialog).to_be_hidden(timeout=2000)


@pytest.mark.cross_browser
def test_no_row_shows_below_the_table_editor_buttons(app):
    dialog = open_table(app)
    unfold(dialog, "Items 133 entries")
    footer = dialog.locator(".treasure-table__save-row").bounding_box()
    body = dialog.locator(".modal__body").bounding_box()
    assert footer["y"] + footer["height"] == pytest.approx(body["y"] + body["height"], abs=1)


@pytest.mark.cross_browser
def test_an_anonymous_dm_is_told_to_sign_in_to_save_table_edits(app):
    dialog = open_table(app)
    unfold(dialog, "10gp gems").get_by_role("button", name="+ Add entry").click()
    expect(dialog).to_have_accessible_name("📜 Treasure Table · unsaved changes")
    expect(dialog.get_by_text("Unsaved changes", exact=True)).to_be_visible()
    dialog.get_by_role("button", name="Save", exact=True).click()
    expect(
        app.page.get_by_text("You must be signed in to save edits to the treasure tables.")
    ).to_be_visible()
    expect(dialog).to_be_visible()


def test_reset_to_bundled_throws_away_the_draft(app):
    dialog = open_table(app)
    gems = unfold(dialog, "10gp gems")
    gems.get_by_role("button", name="Remove this entry").first.click()
    gems.get_by_role("button", name="Remove this entry").first.click()
    expect(gems).to_contain_text("10 entries")
    mundane = unfold(dialog, "Items 133 entries")
    mundane.get_by_role("button", name="+ Add item").click()
    expect(mundane).to_contain_text("134 entries")

    dialog.get_by_role("button", name="↺ Reset to bundled defaults").click()
    expect(gems).to_contain_text("12 entries")
    expect(mundane).to_contain_text("133 entries")
    expect(dialog.get_by_text("No changes", exact=True)).to_be_visible()


def one_row_individual_table(app, dialog, gold):
    """Edits Individual CR 0-4 down to one row that always rolls gold gp."""
    bracket = unfold(dialog, "CR 0–4 5 rows")
    for _ in range(4):
        bracket.get_by_role("button", name="Remove row").first.click()
    expect(bracket).to_contain_text("1 rows")
    for coin in ["cp", "sp", "ep", "gp", "pp"]:
        clear = bracket.get_by_role("button", name=f"Clear {coin}")
        if clear.count():
            clear.click()
    bracket.get_by_role("button", name="Add a gp formula to this row").click()
    bracket.get_by_role("spinbutton", name="gp count").fill("1")
    bracket.get_by_role("spinbutton", name="gp faces").fill("1")
    bracket.get_by_role("spinbutton", name="gp multiplier").fill(str(gold))
    settle(app.page)
    return bracket


def test_a_signed_in_dms_table_edits_drive_the_next_roll(app):
    app.sign_up()
    app.add("Goblin Warrior")
    dialog = open_table(app)
    bracket = one_row_individual_table(app, dialog, 7)
    expect(bracket.get_by_text(re.compile("^Weights sum: "))).to_be_visible()
    app.shot("one-row-table")
    save_table(app, dialog)

    panel = treasure_panel(app)
    preset(panel, "Coins only")
    for _ in range(3):
        roll(panel, "All (individual loot)")
        assert coins(panel.root) == {"gp": 7}

    reload_with_table(app)
    dialog = open_table(app)
    expect(dialog.get_by_role("button", name="↺ Revert")).to_be_visible()
    unfold(dialog, "CR 0–4 1 rows")


def save_one_extra_mundane_item(app):
    dialog = open_table(app)
    unfold(dialog, "Items 133 entries").get_by_role("button", name="+ Add item").click()
    save_table(app, dialog)


def test_revert_asks_first_then_drops_the_custom_table(app):
    app.sign_up()
    save_one_extra_mundane_item(app)
    dialog = open_table(app)
    unfold(dialog, "Items 134 entries")
    dialog.get_by_role("button", name="↺ Revert").click()
    expect(dialog.get_by_text("Revert to bundled?")).to_be_visible()
    app.shot("revert-confirm")
    dialog.locator(".treasure-table__revert-confirm").get_by_role("button", name="Cancel").click()
    expect(dialog.get_by_role("button", name="↺ Revert")).to_be_visible()

    dialog.get_by_role("button", name="↺ Revert").click()
    dialog.get_by_role("button", name="Confirm Revert").click()
    expect(dialog.get_by_role("button", name="↺ Revert")).to_have_count(0)
    expect(dialog.get_by_text("Revert to bundled?")).to_have_count(0)


def test_a_reverted_table_stays_reverted_after_a_reload(app):
    app.sign_up()
    save_one_extra_mundane_item(app)
    dialog = open_table(app)
    dialog.get_by_role("button", name="↺ Revert").click()
    # A reload before the server has dropped the table would bring it back.
    with app.page.expect_response(table_response("DELETE")) as reverted:
        dialog.get_by_role("button", name="Confirm Revert").click()
    assert reverted.value.ok
    expect(dialog.get_by_role("button", name="↺ Revert")).to_have_count(0)

    reload_with_table(app)
    dialog = open_table(app)
    expect(dialog.get_by_role("button", name="↺ Revert")).to_have_count(0, timeout=2000)


def test_edited_gem_art_magic_scroll_and_gear_names_are_saved(app):
    app.sign_up()
    dialog = open_table(app)
    edits = [
        ("10gp gems", "QA pebble"),
        ("25gp art objects", "QA carving"),
        ("Table A — Common consumables", "QA tonic"),
        ("Cantrip  (30 gp)", "QA spark"),
    ]
    for label, new_name in edits:
        unfold(dialog, label).get_by_role("textbox").first.fill(new_name)
    mundane = unfold(dialog, "Items 133 entries").get_by_role("listitem").first
    mundane.get_by_role("textbox").fill("QA rope")
    mundane.get_by_role("spinbutton").fill("3")
    save_table(app, dialog)

    dialog = open_table(app)
    for label, new_name in edits:
        expect(unfold(dialog, label).get_by_role("textbox").first).to_have_value(new_name)
    mundane = unfold(dialog, "Items 133 entries").get_by_role("listitem").first
    expect(mundane.get_by_role("textbox")).to_have_value("QA rope")
    expect(mundane.get_by_role("spinbutton")).to_have_value("3")
