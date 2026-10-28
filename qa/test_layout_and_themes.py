"""Screen sizes, themes, settings, toasts, the static pages and modal chrome."""

import re
import urllib.parse

import pytest
from playwright.sync_api import expect

from pages.accounts import error_toasts, success_toast
from pages.app import NEXT_TURN
from pages.fight import hp_button
from pages.turns import open_round_setter
from pages.ui import choose_theme, open_settings, six_creature_fight

VIEWPORTS = {
    "phone": {"width": 390, "height": 844},
    "tablet": {"width": 820, "height": 1180},
    "laptop": {"width": 1280, "height": 720},
}



def luminance(css_color):
    """Relative brightness of a CSS rgb colour.  Black is 0 and white is 1."""
    red, green, blue = (int(part) for part in re.findall(r"\d+", css_color)[:3])
    return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255


def page_background(page):
    return page.evaluate("() => getComputedStyle(document.body).backgroundColor")


def shell_theme(page):
    return page.locator(".app-shell").get_attribute("data-theme")


# Screen sizes.


def horizontal_overflow(page):
    return page.evaluate(
        "() => document.documentElement.scrollWidth - document.documentElement.clientWidth"
    )


def reachable(locator):
    """Whether a control sits inside the screen's width and nothing covers it.

    Vertical scrolling is fine.  A control is not reachable when it needs a
    sideways scroll or another element paints over it.
    """
    return locator.evaluate(
        """el => {
          el.scrollIntoView({block: 'center', inline: 'nearest'});
          window.scrollTo(0, window.scrollY);
          const r = el.getBoundingClientRect();
          const vw = document.documentElement.clientWidth;
          const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
          return r.left >= 0 && r.right <= vw && r.width > 0 && (hit === el || el.contains(hit));
        }"""
    )


def at_size(app, size):
    app.page.set_viewport_size(VIEWPORTS[size])
    app.settle()


@pytest.mark.cross_browser
@pytest.mark.parametrize(
    "size",
    [
        pytest.param(
            "phone",
            marks=pytest.mark.xfail(
                strict=True,
                reason="QA-UI-01: the app bar is wider than a phone, so the page scrolls sideways",
            ),
        ),
        "tablet",
        "laptop",
    ],
)
def test_a_six_creature_fight_never_scrolls_sideways(app, size):
    six_creature_fight(app)
    at_size(app, size)
    app.shot(f"fight-{size}")
    assert horizontal_overflow(app.page) <= 0


@pytest.mark.cross_browser
@pytest.mark.parametrize(
    "size",
    [
        pytest.param(
            "phone",
            marks=pytest.mark.xfail(
                strict=True,
                reason="QA-UI-01: Donate and the settings button sit off a phone's screen",
            ),
        ),
        "tablet",
        "laptop",
    ],
)
def test_the_controls_a_dm_needs_are_reachable_at_every_size(app, size):
    six_creature_fight(app)
    at_size(app, size)
    page = app.page
    controls = {
        "next turn": page.get_by_role("button", name=NEXT_TURN),
        "dice roller": page.get_by_role("button", name="Dice Roller", exact=True),
        "quick d20": page.get_by_role("button", name=re.compile("^Roll a d20")),
        "round": page.get_by_role("button", name="Set the round number"),
        "quick add": page.get_by_role("button", name="Quick Add", exact=True),
        "manage hp damage": page.get_by_role("button", name="Damage", exact=True),
        "last card hp": hp_button(app.card("Ogre"), "Current"),
        "last card remove": app.card("Ogre").root.get_by_role("button", name="Remove", exact=True),
        "about": page.get_by_role("link", name="About"),
        "donate": page.get_by_role("link", name="Donate"),
        "settings": page.get_by_role("button", name="Open settings"),
    }
    unreachable = [name for name, control in controls.items() if not reachable(control)]
    app.shot(f"controls-{size}")
    assert unreachable == []


# Themes and settings.


@pytest.mark.cross_browser
def test_the_dm_switches_between_modern_dark_and_accessible(app):
    six_creature_fight(app)
    assert shell_theme(app.page) == "modern"
    light = luminance(page_background(app.page))
    assert light > 0.8

    choose_theme(app, "Dark")
    assert shell_theme(app.page) == "dark"
    assert app.page.locator("html").get_attribute("data-theme") == "dark"
    assert luminance(page_background(app.page)) < 0.3
    app.shot("dark")

    choose_theme(app, "Accessible")
    assert shell_theme(app.page) == "accessible"
    app.shot("accessible")

    app.reload()
    assert shell_theme(app.page) == "accessible"
    choose_theme(app, "Modern")
    assert shell_theme(app.page) == "modern"
    assert luminance(page_background(app.page)) == pytest.approx(light)


@pytest.mark.cross_browser
def test_a_dark_operating_system_leaves_the_modern_theme_whole(app, browser):
    context = browser.new_context(viewport={"width": 1440, "height": 900}, color_scheme="dark")
    try:
        dark_os = app.beside(context.new_page(), "dark-os")
        dark_os.goto("/")
        dark_os.add("Goblin Warrior", count=2)
        assert shell_theme(dark_os.page) == "modern"
        assert luminance(page_background(dark_os.page)) > 0.8
        field = dark_os.page.get_by_label("HP:", exact=True)
        assert luminance(field.evaluate("e => getComputedStyle(e).backgroundColor")) > 0.8
        dark_os.shot("os-dark-modern")
        choose_theme(dark_os, "Dark")
        assert luminance(page_background(dark_os.page)) < 0.3
        dark_os.shot("os-dark-dark")
        assert not dark_os.page_errors
    finally:
        context.close()


@pytest.mark.parametrize(
    "theme",
    [
        "Modern",
        "Dark",
        pytest.param(
            "Accessible",
            marks=pytest.mark.xfail(
                strict=True,
                reason="QA-UI-17: the Encounter Difficulty title is half again as big as the others",
            ),
        ),
    ],
)
def test_every_panel_title_in_the_column_is_the_same_size(app, theme):
    choose_theme(app, theme)
    sizes = app.page.locator(".panel__title--drawer").evaluate_all(
        "els => els.map(e => [e.firstChild.textContent, getComputedStyle(e).fontSize])"
    )
    app.shot(f"titles-{theme}")
    assert len({size for _, size in sizes}) == 1, sizes


def test_the_settings_popover_closes_on_a_click_elsewhere(app):
    open_settings(app)
    app.page.locator(".panel--main").click(position={"x": 300, "y": 400})
    trigger = app.page.get_by_role("button", name="Open settings")
    expect(trigger).to_have_attribute("aria-expanded", "false")
    expect(app.page.get_by_role("region", name="Settings")).to_have_count(0)


def test_the_settings_popover_groups_its_choices_under_named_fieldsets(app):
    settings = open_settings(app)
    expect(settings.get_by_role("group", name="Theme").get_by_role("radio")).to_have_count(3)
    expect(settings.get_by_role("group", name="Profile").get_by_role("radio")).to_have_count(3)
    expect(settings.get_by_role("radio", name="Modern")).to_be_checked()
    expect(settings.get_by_role("radio", name="Beta")).to_be_checked()
    app.shot("settings-open")


# Toasts.


def test_signing_up_with_a_local_fight_raises_a_toast_that_fades_on_its_own(app):
    app.add("Goblin Warrior", count=2)
    app.sign_up()
    toast = success_toast(app.page, "pre-sign-in encounter")
    expect(toast).to_be_visible()
    app.shot("migration-toast")
    expect(toast).to_have_count(0, timeout=8000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-11: every new account is greeted by a Save Chain decode error toast",
)
def test_a_fresh_sign_up_raises_no_error_toast(app):
    app.sign_up()
    app.page.wait_for_load_state("networkidle")
    app.shot("fresh-sign-up")
    expect(error_toasts(app.page)).to_have_count(0, timeout=1000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-12: a sign-up with nothing to import still toasts that it imported 0 creatures",
)
def test_a_fresh_sign_up_does_not_announce_importing_nothing(app):
    app.sign_up()
    app.page.wait_for_load_state("networkidle")
    expect(app.page.get_by_text("Imported 0 creatures")).to_have_count(0, timeout=1000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-13: toasts sit on top of the app bar and hide its links and settings",
)
def test_a_toast_leaves_the_app_bar_usable(app):
    app.add("Goblin Warrior")
    app.sign_up()
    expect(success_toast(app.page, "pre-sign-in encounter")).to_be_visible()
    covered = [
        name
        for name, control in {
            "about": app.page.get_by_role("link", name="About"),
            "donate": app.page.get_by_role("link", name="Donate"),
            "settings": app.page.get_by_role("button", name="Open settings"),
        }.items()
        if not reachable(control)
    ]
    assert covered == []


def test_a_save_that_fails_raises_an_alert_the_dm_can_dismiss(app):
    app.sign_up()
    app.add("Goblin Warrior")
    app.server.stop()
    app.add("Ogre")
    alert = error_toasts(app.page).filter(has_text="Save failed")
    expect(alert).to_be_visible()
    app.shot("save-failed")
    alert.get_by_role("button", name="Dismiss notification").click()
    expect(alert).to_have_count(0)
    app.server.start()


# The static pages and links.


def test_the_about_page_lists_every_keyboard_shortcut(app):
    app.goto("/about")
    expect(app.page.get_by_role("heading", level=1)).to_have_text("eZpZ-dndZ")
    keys = app.page.locator("kbd").all_inner_texts()
    assert keys == ["Alt+Shift+C", "Alt+Shift+P", "Alt+Shift+H"]
    app.shot("about")


def test_the_donate_page_says_it_is_under_construction(app):
    app.page.get_by_role("link", name="Donate").click()
    expect(app.page).to_have_url(re.compile("/donate$"))
    expect(app.page.get_by_text("This page is under construction.")).to_be_visible()
    app.shot("donate")


def test_an_unknown_address_says_not_found_inside_the_app(app):
    app.goto("/no-such-page")
    expect(app.page.get_by_text("The page you requested does not exist.")).to_be_visible()
    app.page.get_by_role("link", name="Go to the Encounter page").click()
    app.wait_ready()
    app.shot("back-home")


def links_on(app, path):
    app.goto(path)
    app.page.wait_for_load_state("networkidle")
    return app.page.locator("a[href]").evaluate_all(
        "els => els.map(e => ({href: e.getAttribute('href'), text: e.innerText.trim(),"
        " target: e.getAttribute('target'), rel: e.getAttribute('rel')}))"
    )


@pytest.mark.parametrize("path", ["/", "/about", "/donate", "/login"])
def test_every_link_on_a_page_leads_somewhere_real(app, path):
    links = links_on(app, path)
    assert links
    for link in links:
        href = link["href"]
        if href.startswith("#"):
            continue
        if href.startswith("/"):
            response = app.page.request.get(app.server.base_url + href)
            assert response.ok, f"{link} answered {response.status}"
        elif href.startswith("https://"):
            parts = urllib.parse.urlparse(href)
            assert parts.netloc and "." in parts.netloc, link
            assert link["target"] == "_blank"
            assert "noopener" in (link["rel"] or ""), link
        else:
            assert href.startswith("mailto:"), link


EMAIL = re.compile(r"^[^@\s]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$")


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-02: the footer's Contact link mails feedback@ezpzdndz, which has no domain suffix",
)
def test_the_contact_link_mails_a_well_formed_address(app):
    href = app.page.get_by_role("link", name="Contact").get_attribute("href")
    assert href.startswith("mailto:")
    assert EMAIL.match(href.removeprefix("mailto:")), href


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-04: the Manage HP field takes focus on load, so the first Tab skips the skip link",
)
@pytest.mark.cross_browser
def test_the_first_tab_on_the_encounter_page_reaches_the_skip_link(app):
    app.page.keyboard.press("Tab")
    expect(app.page.get_by_role("link", name="Skip to main content")).to_be_focused(timeout=2000)


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-03: the skip link only rewrites the address to /#main and leaves focus where it was",
)
@pytest.mark.cross_browser
def test_the_skip_link_shows_on_focus_and_jumps_to_the_encounter(app):
    skip = app.page.get_by_role("link", name="Skip to main content")
    expect(skip).not_to_be_in_viewport()
    for _ in range(20):
        app.page.keyboard.press("Shift+Tab")
        if skip.evaluate("el => el === document.activeElement"):
            break
    expect(skip).to_be_focused()
    expect(skip).to_be_in_viewport()
    app.shot("skip-link")
    app.page.keyboard.press("Enter")
    expect(app.page).to_have_url(re.compile("#main$"))
    expect(app.page.locator("main#main")).to_be_focused(timeout=2000)
    app.page.keyboard.press("Tab")
    expect(app.page.get_by_role("button", name="Compendium (new tab)")).to_be_focused()


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-03: the skip link points at #main, which only the encounter page has",
)
@pytest.mark.parametrize("path", ["/about", "/donate", "/login", "/no-such-page"])
def test_the_skip_link_has_a_target_on_every_page(app, path):
    app.goto(path)
    expect(app.page.get_by_role("link", name="Skip to main content")).to_have_count(1)
    expect(app.page.locator("#main")).to_have_count(1, timeout=2000)


# Modal chrome.


def drag(page, start, delta):
    page.mouse.move(*start)
    page.mouse.down()
    page.mouse.move(start[0] + delta[0], start[1] + delta[1], steps=8)
    page.mouse.up()


@pytest.mark.cross_browser
def test_a_modal_moves_when_dragged_by_its_title(app):
    dialog = open_round_setter(app)
    before = dialog.bounding_box()
    title = dialog.get_by_role("heading", name="Set Round").bounding_box()
    drag(app.page, (title["x"] + 10, title["y"] + title["height"] / 2), (-150, 90))
    app.settle()
    after = dialog.bounding_box()
    assert after["x"] - before["x"] == pytest.approx(-150, abs=2)
    assert after["y"] - before["y"] == pytest.approx(90, abs=2)
    assert after["width"] == pytest.approx(before["width"], abs=1)
    expect(dialog).to_be_visible()
    app.shot("dragged")


def grip(page, dialog, inset):
    """A point on the bottom-right resize handle and the class found there.

    The point sits inset pixels in from the corner.
    """
    box = dialog.bounding_box()
    point = (box["x"] + box["width"] - inset, box["y"] + box["height"] - inset)
    # The resize handles have no accessible name.
    hit = page.evaluate("([x, y]) => document.elementFromPoint(x, y).className", list(point))
    return point, hit


@pytest.mark.cross_browser
def test_a_modal_grows_when_its_corner_is_dragged(app):
    dialog = open_round_setter(app)
    before = dialog.bounding_box()
    point, hit = grip(app.page, dialog, inset=5)
    assert "modal__resize--se" in hit
    drag(app.page, point, (120, 80))
    app.settle()
    after = dialog.bounding_box()
    assert after["width"] - before["width"] == pytest.approx(120, abs=3)
    assert after["height"] - before["height"] == pytest.approx(80, abs=3)
    expect(dialog).to_be_visible()
    app.shot("resized")


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-10: the corner grip lies outside the rounded corner, and a press there closes the modal",
)
@pytest.mark.cross_browser
def test_pressing_on_the_very_corner_of_a_modal_resizes_rather_than_closes_it(app):
    dialog = open_round_setter(app)
    before = dialog.bounding_box()
    point, _ = grip(app.page, dialog, inset=1)
    drag(app.page, point, (60, 40))
    app.settle()
    expect(dialog).to_be_visible(timeout=2000)
    assert dialog.bounding_box()["width"] > before["width"]


@pytest.mark.xfail(
    strict=True,
    reason="QA-UI-10: a resize released outside the modal closes it",
)
@pytest.mark.cross_browser
def test_a_modal_shrinks_no_smaller_than_its_floor_and_stays_open(app):
    dialog = open_round_setter(app)
    point, hit = grip(app.page, dialog, inset=5)
    assert "modal__resize--se" in hit
    drag(app.page, point, (-600, -400))
    app.settle()
    app.shot("shrunk")
    expect(dialog).to_be_visible(timeout=2000)
    after = dialog.bounding_box()
    assert after["width"] >= 320 - 1
    assert after["height"] >= 200 - 1


@pytest.mark.cross_browser
def test_a_dragged_modal_opens_centred_again_next_time(app):
    dialog = open_round_setter(app)
    centred = dialog.bounding_box()
    title = dialog.get_by_role("heading", name="Set Round").bounding_box()
    drag(app.page, (title["x"] + 10, title["y"] + 5), (200, 100))
    dialog.get_by_role("button", name="Close").click()
    expect(dialog).to_have_count(0)
    dialog = open_round_setter(app)
    again = dialog.bounding_box()
    assert again["x"] == pytest.approx(centred["x"], abs=2)
    assert again["y"] == pytest.approx(centred["y"], abs=2)
