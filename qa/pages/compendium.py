"""The full-page compendium as a DM drives it in its own tab."""

import json
import re

from playwright.sync_api import expect

from pages.accounts import api, success_toast
from pages.app import settle

KINDS = "(?:Player|Enemy|NPC)"


def row_name_pattern(name):
    """The name of a creature row's pick button.

    It joins the creature name and the meta line.  For the Ogre it starts
    "Ogre Enemy".
    """
    return re.compile("^" + re.escape(name) + "(?: in encounter)? " + KINDS + " · ")


def server_creatures(page):
    """The signed-in DM's compendium on the server.  It is keyed by name."""
    reply = api(page, "GET", "/api/compendium/creatures")
    assert reply.status == 200, reply
    return {creature["name"]: creature for creature in reply.json()}


def server_groups(page):
    """The signed-in DM's creature groups as the server holds them."""
    reply = api(page, "GET", "/api/compendium/groups")
    assert reply.status == 200, reply
    return reply.json()


def tab_for(app, page):
    """The compendium in another tab of the DM's browser."""
    return Compendium(app.beside(page, "compendium"))


def open_from(app):
    """Clicks the editor column's books button and returns the new tab."""
    with app.page.context.expect_page() as opened:
        app.page.get_by_role("button", name="Compendium (new tab)").click()
    return tab_for(app, opened.value).wait_ready()


def open_at(app, path):
    """Opens a compendium URL in a fresh tab of the DM's browser."""
    compendium = tab_for(app, app.page.context.new_page())
    compendium.page.goto(app.server.base_url + path)
    return compendium


def add_row(section, button, rows):
    """Presses an add button and waits for one more row to appear."""
    before = rows.count()
    section.get_by_role("button", name=button).click()
    expect(rows).to_have_count(before + 1)


def group_row(tab, name):
    return tab.page.locator(".compendium__row--group").filter(
        has=tab.page.get_by_role("button", name=re.compile("^👥 " + re.escape(name) + " "))
    )


def add_entry(pane, creature, count, minion="Normal"):
    pickers = pane.get_by_role("combobox", name="Creature")
    add_row(pane, "+ Add Entry", pickers)
    pickers.last.select_option(label=creature)
    pane.get_by_role("spinbutton", name="Instance count").last.fill(str(count))
    pane.get_by_role("combobox", name="Minion type").last.select_option(label=minion)


def create_group(tab, name, entries, initiative="Each rolls", manual=None):
    tab.button("👥 Create Group").click()
    pane = tab.editor()
    expect(pane.get_by_role("heading", name="👥 Create Group")).to_be_visible()
    pane.get_by_label("Name").fill(name)
    pane.get_by_role("radio", name=initiative).check()
    if manual is not None:
        pane.get_by_role("spinbutton", name="Manual initiative value").fill(str(manual))
    for entry in entries:
        add_entry(pane, *entry)
    pane.get_by_role("button", name="Create Group", exact=True).click()
    expect(tab.toast(re.compile(f'Group "{re.escape(name)}" (created|saved)\\.'))).to_be_visible()
    expect(group_row(tab, name)).to_be_visible()
    return pane


def duplicate(app, original, new_name):
    """Makes a custom creature from a bundled one the way a DM does."""
    app.page.goto(app.server.base_url + "/compendium")
    tab = Compendium(app).wait_ready()
    tab.search(original)
    tab.select(original)
    tab.button(re.compile("Duplicate")).first.click()
    expect(tab.field("Name")).to_have_value(f"{original} (copy)")
    tab.field("Name").fill(new_name)
    tab.editor().get_by_role("button", name="Create", exact=True).click()
    tab.search(new_name)
    expect(tab.row(new_name)).to_be_visible()
    app.goto("/")


class Compendium:
    def __init__(self, tab):
        self.tab = tab
        self.page = tab.page
        self.page.set_default_timeout(10_000)

    def wait_ready(self):
        expect(self.search_box()).to_be_visible()
        expect(self.rows().first).to_be_visible()
        return self

    def settle(self):
        settle(self.page)

    def assert_quiet(self):
        """Fails when this tab threw.

        The app fixture does that for its page.
        """
        assert not self.tab.page_errors, "The compendium tab threw:\n" + "\n".join(
            self.tab.page_errors
        )

    def shot(self, step):
        return self.tab.shot(step)

    # The filter bar.

    def search_box(self):
        return self.page.get_by_role("searchbox", name="Search compendium")

    def search(self, text):
        self.search_box().fill(text)
        self.settle()

    def kind_chip(self, label):
        return self.page.get_by_role("button", name=label, exact=True)

    def sort_by(self, label):
        self.page.get_by_role("combobox", name="Sort compendium").select_option(
            label=label
        )
        self.settle()

    def tag_filter(self):
        return self.page.get_by_role("combobox", name="Filter compendium by tag")

    # The library list.

    def rows(self):
        return self.page.locator(".compendium__row--creature")

    def row(self, name):
        return self.rows().filter(
            has=self.page.get_by_role("button", name=row_name_pattern(name))
        )

    def pick(self, name):
        return self.row(name).get_by_role("button", name=row_name_pattern(name))

    def row_names(self):
        """Creature names in list order.

        No role can find a row's name on its own.  This reads the name span by
        its class.
        """
        return self.rows().evaluate_all(
            "els => els.map(e =>"
            " e.querySelector('.compendium__row-name').textContent.trim())"
        )

    def row_metas(self):
        return self.rows().evaluate_all(
            "els => els.map(e =>"
            " e.querySelector('.compendium__row-meta').textContent.trim())"
        )

    def select(self, name):
        self.pick(name).click()
        expect(self.detail_name()).to_have_text(name)
        return self

    def check(self, name):
        self.row(name).get_by_role("checkbox", name="Select for bulk action").check()
        self.settle()

    # The detail pane.

    def detail_name(self):
        """The creature name atop the stat block in the detail pane.

        The stat block renders its name in a plain div.  It is not a heading.
        """
        return self.page.locator(".compendium__detail .statblock__name")

    def statblock(self):
        return self.page.locator(".compendium__detail .statblock")

    def badge(self):
        return self.page.get_by_text(re.compile(r"^\d+ in Encounter$"))

    def button(self, name):
        return self.page.get_by_role("button", name=name, exact=True)

    def delete_shown(self):
        """Deletes the creature on show and confirms."""
        self.page.get_by_role("button", name="Delete creature").click()
        self.button("Delete").click()

    def add_to_encounter(self):
        self.button("➕ Add to Encounter").click()
        self.settle()

    def toast(self, text):
        """One success toast with this text.

        A repeat of the same action stacks a second toast with the same words.
        This picks the newest.
        """
        return success_toast(self.page, text).last

    def dialog(self, title):
        return self.page.get_by_role("dialog", name=title)

    # The creature editor.

    def editor(self):
        return self.page.locator(".compendium__editor-pane")

    def field(self, label):
        return self.editor().get_by_label(label, exact=True)

    def ability_field(self, short):
        """An ability score input.  Its label also carries the modifier hint."""
        return self.editor().get_by_label(re.compile("^" + short + r"\(")).first

    def section(self, legend):
        """One fieldset of the editor.  Its legend finds it."""
        return self.editor().get_by_role("group", name=legend, exact=True)

    def new_creature(self):
        self.button("➕ New Creature").click()
        expect(self.editor()).to_be_visible()
        return self

    def create(self, name, ac="13", hp="22", **fields):
        """Fills the required and extra fields and saves a new creature."""
        self.new_creature()
        self.field("Name").fill(name)
        self.field("AC").fill(ac)
        self.field("Max HP").fill(hp)
        for label, value in fields.items():
            self.field(label.replace("_", " ")).fill(value)
        return self.submit(name, "Create")

    def submit(self, name, button="Save"):
        """Saves the editor and waits for it to close on its toast."""
        self.editor().get_by_role("button", name=button, exact=True).click()
        expect(self.toast("Saved " + name)).to_be_visible()
        expect(self.editor()).to_be_hidden()
        return self

    # The anonymous session's browser storage.

    def local(self, key):
        raw = self.page.evaluate(f"() => localStorage.getItem({json.dumps(key)})")
        return None if raw is None else json.loads(raw)
