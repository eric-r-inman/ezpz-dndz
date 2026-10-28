"""Helpers for the editor column, the dice roller, themes and axe."""

import json
import os
import re

from playwright.sync_api import expect

from pages.app import settle_animations

DRAWER_TITLES_JS = """
root => Array.from(root.querySelectorAll('section.panel--drawer .panel__title--drawer'))
  .map(title => title.firstChild ? title.firstChild.textContent.trim() : '')
"""


def drawer_titles(page):
    """Panel titles in the order the column shows them."""
    return page.locator(".drawer-stack").evaluate(DRAWER_TITLES_JS)


def pinned_titles(page):
    """Titles of the pinned block's panels in column order."""
    block = page.locator(".drawer-pinned")
    return block.evaluate(DRAWER_TITLES_JS) if block.count() else []


def open_titles(page):
    """Titles of the panels whose bodies are showing."""
    return [
        title
        for title in drawer_titles(page)
        if page.locator("section.panel--drawer-open")
        .filter(has=page.locator(".panel__title--drawer", has_text=re.compile("^" + re.escape(title))))
        .count()
    ]


def pinned_held(page):
    """Whether the pinned block holds the top of the column."""
    block = page.locator(".drawer-pinned")
    return block.count() == 1 and "drawer-pinned--held" in (block.get_attribute("class") or "")


def heading(panel):
    """The heading row a mouse folds and drags a panel by."""
    return panel.root.locator(".panel__header--drawer")


def drag_panel(app, source, target):
    """Drags one panel's heading row onto another panel's slot."""
    heading(app.panel(source)).drag_to(heading(app.panel(target)))
    app.settle()


def hotkey(app, letter):
    app.page.keyboard.press(f"Alt+Shift+Key{letter}")
    app.settle()


def stack_scroll(page, top):
    """Scrolls the editor stack and reports where the pinned block sits.

    It returns the pinned block's offset from the top of the stack's
    visible area.  Zero means the block holds the top.
    """
    page.evaluate(
        """async () => {
          // An unfolded panel scrolls itself into view through a chain
          // of DOM tasks.  Each runs a frame after the last.  Eight
          // frames outlast the chain.
          for (let i = 0; i < 8; i++) {
            await new Promise(done => requestAnimationFrame(done));
          }
        }"""
    )
    settle_animations(page)
    return page.evaluate(
        """top => {
          const stack = document.querySelector('.drawer-stack');
          stack.scrollTop = top;
          const pinned = document.querySelector('.drawer-pinned');
          return {
            scrollTop: stack.scrollTop,
            scrollable: stack.scrollHeight - stack.clientHeight,
            pinnedOffset: pinned
              ? pinned.getBoundingClientRect().top - stack.getBoundingClientRect().top
              : null,
          };
        }""",
        top,
    )


def open_settings(app):
    trigger = app.page.get_by_role("button", name="Open settings")
    if trigger.get_attribute("aria-expanded") != "true":
        trigger.click()
    expect(trigger).to_have_attribute("aria-expanded", "true")
    return app.page.get_by_role("region", name="Settings")


def choose_theme(app, theme):
    open_settings(app).get_by_role("radio", name=re.compile("^" + theme)).check()
    app.settle()


def choose_profile(app, profile):
    open_settings(app).get_by_role("radio", name=profile, exact=True).check()
    app.settle()


def six_creature_fight(app):
    """A fight a DM might run: six creatures, combat begun."""
    app.add("Goblin Warrior", count=3)
    app.add("Bandit", count=2)
    app.add("Ogre")
    app.panel("Quick Add").fold()
    app.begin_combat()


class Dice:
    """The Dice Roller panel and its log."""

    def __init__(self, app):
        self.app = app
        self.panel = app.panel("Dice Roller")

    def open(self):
        """Unfolds the roller and its log.  The log boots folded."""
        self.panel.open()
        toggle = self.log_toggle()
        if toggle.get_attribute("aria-expanded") != "true":
            toggle.click()
        expect(toggle).to_have_attribute("aria-expanded", "true")
        return self

    @property
    def root(self):
        return self.panel.root

    def expression(self):
        return self.root.get_by_label("Expression:")

    def roll(self, text):
        """Types an expression and presses Enter."""
        field = self.expression()
        field.fill(text)
        field.press("Enter")
        self.app.settle()

    def button(self, name):
        return self.root.get_by_role("button", name=name, exact=True)

    def log_toggle(self):
        return self.root.get_by_role("button", name=re.compile(r"^\W*Log \(\d+\)"))

    def rows(self):
        return self.root.locator("li.dice-history__entry")

    def row_text(self, index=0):
        """One folded log row as the DM reads it.  Index 0 is the newest."""
        row = self.rows().nth(index)
        formula = row.locator(".dice-history__formula").inner_text()
        total = row.locator(".dice-history__total").inner_text()
        return " ".join(formula.split()), int(total)

    def row(self, index=0):
        """One log row parsed into its parts and its shown total."""
        text, total = self.row_text(index)
        return {**parse_row(text), "total": total}

    def wait_for_rows(self, count):
        expect(self.rows()).to_have_count(count)

    def reroll_button(self, index=0):
        # The re-roll trigger's only name is its glyph.
        return self.rows().nth(index).get_by_role("button", name="\u21bb")


def consistent(row, faces):
    """Whether a standard roll's dice are in range and add to its total."""
    return (
        all(1 <= face <= faces for face in row["faces"])
        and row["kept"] == row["faces"]
        and row["total"] == sum(row["faces"]) + row["modifier"]
    )


ROW = re.compile(
    r"^(?P<formula>.+?):\s*\((?P<faces>[\d,\[\]]*)\)(?P<mod>[+\u2212]\d+)?"
    r"(?P<kind>\s+[A-Za-z ]+?)?\s*=$"
)


def parse_row(text):
    """Splits a log row into its formula, faces, modifier and damage type.

    A row shows the formula, a colon, the faces, the modifier and an
    equals sign.  The total sits beside it.  A dropped die is in square
    brackets.  A negative modifier uses a real minus sign.
    """
    match = ROW.match(text)
    assert match, f"Unreadable log row: {text!r}"
    faces = [
        (int(face.strip("[]")), not face.startswith("["))
        for face in match.group("faces").split(",")
        if face
    ]
    mod = match.group("mod") or "+0"
    return {
        "formula": match.group("formula"),
        "faces": [face for face, _ in faces],
        "kept": [face for face, kept in faces if kept],
        "modifier": int(mod.replace("\u2212", "-")),
        "kind": (match.group("kind") or "").strip(),
    }


def axe_violations(page):
    """Runs axe-core on the page and returns its violations."""
    page.add_script_tag(path=os.environ["QA_AXE_JS"])
    return page.evaluate("() => axe.run(document, {resultTypes: ['violations']})")[
        "violations"
    ]


def axe_summary(violations):
    """One line per violated rule with its count and an example."""
    return "\n".join(
        f"{v['id']} [{v['impact']}] x{len(v['nodes'])}: {json.dumps(v['nodes'][0]['target'])}"
        f" {v['nodes'][0].get('failureSummary', '').splitlines()[-1].strip()[:160]}"
        for v in violations
    )


FOCUS_JS = """() => {
  const e = document.activeElement;
  if (!e || e === document.body) return null;
  const cs = getComputedStyle(e);
  return {
    tag: e.tagName,
    name: e.getAttribute('aria-label') || (e.innerText || '').trim().slice(0, 60)
      || e.getAttribute('placeholder') || e.id || '',
    ring: (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0)
      || cs.boxShadow !== 'none',
  };
}"""


def focused(page):
    """The focused element's tag, name and whether it shows a ring."""
    return page.evaluate(FOCUS_JS)
