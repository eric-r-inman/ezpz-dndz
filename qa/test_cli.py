"""The operator's CLI against the data a DM made through the app.

The CLI finds its database the way the server does.  --database-url wins.
Otherwise it opens ezpz-dndz.db inside --data-dir.  That defaults to the working
directory.  The scenarios point --data-dir at the scratch server's own data dir.
`compendium harvest` needs the Open5e API over the network.  So only its help is
checked here.
"""

import json
import os
import re
import subprocess
import uuid

import pytest

from conftest import CLI_BIN, REPO
from pages.accounts import (
    LoginPage,
    api,
    create_creature,
    own_creature_names,
    register,
    roll_d20,
    wait_for_saved_rolls,
    wait_signed_in,
    wait_until_saved,
)
from pages.app import DM

BOG_WIGHT = {"name": "Bog Wight", "kind": "enemy", "size": "medium", "armor_class": 12, "max_hp": 22}

SUBCOMMANDS = [
    (),
    ("compendium",),
    ("compendium", "list"),
    ("compendium", "count"),
    ("compendium", "show"),
    ("compendium", "import"),
    ("compendium", "harvest"),
    ("compendium", "infer-habitats"),
    ("encounter",),
    ("encounter", "show"),
    ("encounter", "count"),
    ("dice",),
    ("dice", "count"),
    ("dice", "tail"),
    ("dice", "clear"),
    ("users",),
    ("users", "reset-password"),
]


def on(server):
    return ["--data-dir", str(server.data_dir)]


def test_every_subcommand_explains_itself(cli):
    for words in SUBCOMMANDS:
        result = cli(*words, "--help")
        assert "Usage: ezpz-dndz-cli " + " ".join(words) in result.stdout, words
        assert "-h, --help" in result.stdout, words


def test_running_with_no_subcommand_points_at_help(cli):
    result = cli()
    assert "Run with --help for usage." in result.stdout


# Resetting a forgotten password.


def test_reset_password_lets_a_locked_out_dm_sign_in_again(app, cli):
    register(app.page, DM, "forgotten password", "Dee Em")
    api(app.page, "POST", "/api/auth/logout")
    result = cli(
        "users",
        "reset-password",
        "--email",
        "DM@Example.test",
        "--new-password",
        "a fresh password",
        *on(app.server),
    )
    assert "Reset password for Dee Em <dm@example.test>" in result.stdout

    form = LoginPage(app.page, app.server.base_url).goto()
    form.sign_in(DM, "forgotten password")
    form.page.get_by_text("Invalid email or password.").wait_for()
    form.sign_in(DM, "a fresh password")
    wait_signed_in(app, "Dee Em")


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-14: reset-password for an unknown email says 'Invalid email or password'",
)
def test_reset_password_for_an_unknown_email_names_the_problem(cli):
    result = cli(
        "users",
        "reset-password",
        "--email",
        "nobody@example.test",
        "--new-password",
        "long enough",
        check=False,
    )
    assert result.returncode == 1
    assert "No user with email nobody@example.test" in result.stderr


def test_reset_password_refuses_a_short_or_empty_password(cli):
    for password, message in [
        ("short", "at least 8 characters"),
        ("", "must not be empty"),
    ]:
        result = cli(
            "users", "reset-password", "--email", DM, "--new-password", password, check=False
        )
        assert result.returncode == 1, password
        assert message in result.stderr, password


def test_reset_password_without_a_terminal_fails_instead_of_hanging(cli):
    # A new session has no controlling terminal.  Cron and ssh -T run that way.
    result = subprocess.run(
        [str(CLI_BIN), "users", "reset-password", "--email", DM],
        capture_output=True,
        text=True,
        cwd=cli.data_dir,
        env={**os.environ, "NO_COLOR": "1"},
        stdin=subprocess.DEVNULL,
        start_new_session=True,
        timeout=30,
    )
    assert result.returncode == 1
    assert "Failed to read password from the terminal" in result.stderr


# Inspecting and importing creatures.


def test_compendium_inspection_shows_what_the_dm_made(app, cli):
    register(app.page, DM)
    hag = create_creature(app.page, "Bramble Hag")
    create_creature(app.page, "Swamp Troll")
    bundled = int(cli("compendium", "count", "--bundled").stdout)
    assert bundled > 0

    assert cli("compendium", "count", "--email", DM, *on(app.server)).stdout.strip() == "2"
    assert cli("compendium", "count", *on(app.server)).stdout.strip() == "2"
    total = cli("compendium", "count", "--bundled", *on(app.server)).stdout.strip()
    assert int(total) == bundled + 2

    rows = cli("compendium", "list", "--email", DM, *on(app.server)).stdout.splitlines()
    mine = [row for row in rows if row.endswith(DM)]
    assert [row.split("  ")[0] for row in mine] == ["Bramble Hag", "Swamp Troll"]

    shown = json.loads(cli("compendium", "show", hag["id"], *on(app.server)).stdout)
    assert shown["name"] == "Bramble Hag"
    assert shown["max_hp"] == 40

    missing = cli("compendium", "show", str(uuid.uuid4()), *on(app.server), check=False)
    assert missing.returncode == 1
    assert "not found" in missing.stderr


def creature_file(tmp_path, name, records):
    path = tmp_path / name
    path.write_text(json.dumps(records))
    return str(path)


def test_importing_creatures_merges_and_a_repeat_changes_nothing(app, cli, tmp_path):
    register(app.page, DM)
    hag = create_creature(app.page, "Bramble Hag")
    sisters = [
        {**hag, "id": str(uuid.uuid4()), "name": "Swamp Hag"},
        {**hag, "id": str(uuid.uuid4()), "name": "Sea Hag Sister"},
    ]
    coven = creature_file(tmp_path, "coven.json", sisters)

    first = cli("compendium", "import", coven, "--email", DM, *on(app.server))
    assert "Imported 2 creatures" in first.stdout and "now 3 user-owned" in first.stdout
    again = cli("compendium", "import", coven, "--email", DM, *on(app.server))
    assert "Imported 0 creatures" in again.stdout and "now 3 user-owned" in again.stdout
    assert own_creature_names(app.page) == ["Bramble Hag", "Sea Hag Sister", "Swamp Hag"]

    lone = creature_file(tmp_path, "lone.json", sisters[:1])
    replaced = cli("compendium", "import", lone, "--email", DM, "--replace", *on(app.server))
    assert "now 1 user-owned" in replaced.stdout
    assert own_creature_names(app.page) == ["Swamp Hag"]


def test_importing_skips_creatures_that_belong_to_the_bundled_set(app, cli, tmp_path):
    register(app.page, DM)
    everything = api(app.page, "GET", "/api/compendium/creatures").json()
    ogre = next(c for c in everything if c["is_bundled"] and c["name"] == "Ogre")
    homebrew = {**ogre, "id": str(uuid.uuid4()), "name": "Bog Ogre", "is_bundled": False}
    mixed = creature_file(tmp_path, "mixed.json", [ogre, homebrew])
    result = cli("compendium", "import", mixed, "--email", DM, *on(app.server))
    assert "Skipped 1 creatures whose ids belong to the read-only bundled set." in result.stdout
    assert "Imported 1 creatures" in result.stdout
    assert own_creature_names(app.page) == ["Bog Ogre"]


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-15: importing a file of drafts twice imports every creature twice",
)
def test_importing_a_draft_file_twice_does_not_duplicate_it(app, cli, tmp_path):
    register(app.page, DM)
    drafts = creature_file(
        tmp_path,
        "drafts.json",
        [BOG_WIGHT],
    )
    cli("compendium", "import", drafts, "--email", DM, *on(app.server))
    cli("compendium", "import", drafts, "--email", DM, *on(app.server))
    assert own_creature_names(app.page) == ["Bog Wight"]


# A DM's fight and dice as the CLI sees them.

PARTY = ["Goblin Warrior", "Goblin Warrior 2", "Ogre"]


def test_encounter_inspection_shows_the_fight_a_dm_is_running(app, cli):
    app.sign_up(DM)
    app.add("Goblin Warrior", count=2)
    app.add("Ogre")
    wait_until_saved(app.page, PARTY)
    assert cli("encounter", "count", "--email", DM, *on(app.server)).stdout.strip() == "3"
    shown = json.loads(cli("encounter", "show", "--email", DM, *on(app.server)).stdout)
    assert [c["name"] for c in shown["creatures"]] == PARTY

    register(app.page, "player@example.test", name="A Player")
    assert (
        cli("encounter", "show", "--email", "player@example.test", *on(app.server)).stdout.strip()
        == "null"
    )
    assert (
        cli("encounter", "count", "--email", "player@example.test", *on(app.server)).stdout.strip()
        == "0"
    )


def test_dice_inspection_and_clearing_follow_the_dms_rolls(app, cli):
    app.sign_up(DM)
    roll_d20(app)
    roll_d20(app)
    wait_for_saved_rolls(app.page, 2)
    assert cli("dice", "count", "--email", DM, *on(app.server)).stdout.strip() == "2"
    assert cli("dice", "count", *on(app.server)).stdout.strip() == "2"
    latest = json.loads(cli("dice", "tail", "--email", DM, "--n", "1", *on(app.server)).stdout)
    assert len(latest) == 1
    assert latest[0]["formula"] == "1d20" and 1 <= latest[0]["total"] <= 20

    unconfirmed = cli("dice", "clear", "--email", DM, *on(app.server))
    assert "Pass --yes to confirm." in unconfirmed.stderr
    assert cli("dice", "count", "--email", DM, *on(app.server)).stdout.strip() == "2"

    cleared = cli("dice", "clear", "--email", DM, "--yes", *on(app.server))
    assert cleared.stdout.strip() == "Cleared."
    assert cli("dice", "count", "--email", DM, *on(app.server)).stdout.strip() == "0"
    assert api(app.page, "GET", "/api/dice/history").json() == []


def test_unknown_users_and_bad_arguments_fail_with_a_clear_message(cli, tmp_path):
    drafts = creature_file(
        tmp_path, "one.json", [BOG_WIGHT]
    )
    for words in [
        ("encounter", "show"),
        ("encounter", "count"),
        ("dice", "count"),
        ("dice", "tail"),
        ("dice", "clear", "--yes"),
        ("compendium", "list"),
        ("compendium", "count"),
        ("compendium", "import", drafts),
    ]:
        result = cli(*words, "--email", "nobody@example.test", check=False)
        assert result.returncode == 1, words
        assert "No user with email nobody@example.test exists" in result.stderr, words

    for words, message in [
        (("encounter", "show"), "required arguments were not provided"),
        (("dice", "tail", "--email", DM, "--n", "lots"), "invalid value 'lots'"),
        (("compendium", "bogus"), "unrecognized subcommand 'bogus'"),
        (("users", "reset-password", "--new-password", "long enough"), "--email <EMAIL>"),
    ]:
        result = cli(*words, check=False)
        assert result.returncode == 2, words
        assert message in result.stderr, words


@pytest.mark.xfail(
    strict=True,
    reason="QA-ACCT-16: a mistyped --data-dir creates an empty database and reports 0",
)
def test_inspecting_a_mistyped_data_dir_fails_instead_of_creating_one(cli):
    typo = cli.data_dir / "no-such-dir"
    result = cli("compendium", "count", "--data-dir", str(typo), check=False)
    assert not typo.exists(), f"The CLI created {typo} and answered {result.stdout.strip()}"
    assert result.returncode != 0


# Authoring habitats in a creatures file.


def test_infer_habitats_dry_run_reports_and_leaves_the_file_alone(cli, tmp_path):
    bundled = json.loads((REPO / "crates/lib/data/bundled-creatures.json").read_text())
    sample = [{**c, "habitats": []} for c in bundled[:25]]
    scratch = tmp_path / "scratch.json"
    scratch.write_text(json.dumps(sample))
    before = scratch.read_bytes()

    dry = cli("compendium", "infer-habitats", "--path", str(scratch), "--dry-run")
    assert "total creatures:       25" in dry.stdout
    assert "--dry-run set; no changes written." in dry.stdout
    assert scratch.read_bytes() == before
    filled = int(re.search(r"filled by rules:\s+(\d+)", dry.stdout).group(1))
    assert filled > 0

    real = cli("compendium", "infer-habitats", "--path", str(scratch))
    assert f"Wrote {filled} creatures with new habitats." in real.stdout
    after = json.loads(scratch.read_text())
    assert sum(1 for c in after if c["habitats"]) == filled


def test_infer_habitats_on_a_missing_file_fails_clearly(cli, tmp_path):
    missing = tmp_path / "nowhere.json"
    result = cli("compendium", "infer-habitats", "--path", str(missing), "--dry-run", check=False)
    assert result.returncode == 1
    assert f"Failed to read creatures file at {missing}" in result.stderr
