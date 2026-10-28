"""Fixtures that give every scenario its own server, data dir and page.

A scenario never touches the repository's own data files.  Each one boots
the debug server on a free port against a fresh directory under pytest's
tmp_path, so scenarios can run side by side.
"""

import json
import os
import pathlib
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

from pages import compendium as library
from pages.app import App

REPO = pathlib.Path(__file__).resolve().parent.parent
# A checkout without its own build can borrow another one's binaries.
BIN_DIR = pathlib.Path(os.environ.get("QA_BIN_DIR", REPO / "target" / "debug"))
SERVER_BIN = BIN_DIR / "ezpz-dndz-server"
CLI_BIN = BIN_DIR / "ezpz-dndz-cli"
ARTIFACTS = REPO / "target" / "qa"


def pytest_configure(config):
    config.addinivalue_line(
        "markers", "cross_browser: also run this scenario in Firefox."
    )
    # pytest-playwright writes traces and failure screenshots here.  Its own
    # default is a folder in the working directory.
    if config.option.output == "test-results":
        config.option.output = str(ARTIFACTS / "artifacts")


def pytest_collection_modifyitems(config, items):
    """Firefox runs only the scenarios marked cross_browser."""
    kept, dropped = [], []
    for item in items:
        browser = getattr(item, "callspec", None) and item.callspec.params.get(
            "browser_name"
        )
        unmarked = item.get_closest_marker("cross_browser") is None
        (dropped if browser == "firefox" and unmarked else kept).append(item)
    if dropped:
        config.hook.pytest_deselected(items=dropped)
        items[:] = kept


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class Server:
    """One scratch server process and the data dir it owns."""

    def __init__(self, data_dir, log_path):
        self.data_dir = data_dir
        self.log_path = log_path
        self.port = free_port()
        self.process = None
        # A scenario that provokes a server error on purpose lists a
        # fragment of the expected message here.
        self.expected_errors = []

    @property
    def base_url(self):
        return f"http://127.0.0.1:{self.port}"

    def start(self):
        if not SERVER_BIN.exists():
            pytest.exit(f"{SERVER_BIN} is missing.  Run `just qa`, which builds it.")
        log = open(self.log_path, "a")
        self.process = subprocess.Popen(
            [
                str(SERVER_BIN),
                "--listen",
                f"127.0.0.1:{self.port}",
                "--data-dir",
                str(self.data_dir),
                "--log-format",
                "json",
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                pytest.fail(f"The server exited at boot.  Log:\n{self.log_text()}")
            if self.responds():
                return
            time.sleep(0.05)
        pytest.fail(f"The server never answered.  Log:\n{self.log_text()}")

    def responds(self):
        try:
            urllib.request.urlopen(self.base_url + "/api/auth/me", timeout=1)
            return True
        except urllib.error.HTTPError:
            return True
        except OSError:
            return False

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=10)

    def restart(self):
        """Stops and boots the server again on the same port and data."""
        self.stop()
        self.start()

    def log_text(self):
        return self.log_path.read_text() if self.log_path.exists() else ""

    def error_lines(self):
        """Log records at ERROR level, and any panic, minus the expected."""
        lines = self.log_text().splitlines()
        records = [json_or_none(line) for line in lines]
        errors = [
            line
            for line, record in zip(lines, records)
            if (record and record.get("level") == "ERROR")
            or (record is None and "panicked" in line)
        ]
        return [
            line
            for line in errors
            if not any(fragment in line for fragment in self.expected_errors)
        ]


def json_or_none(line):
    try:
        return json.loads(line)
    except ValueError:
        return None


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args):
    """A DM's laptop screen, the size the column layout is built for."""
    return {**browser_context_args, "viewport": {"width": 1440, "height": 900}}


@pytest.fixture
def server(tmp_path):
    """A fresh server.  The scenario fails if the server logged an error."""
    data_dir = tmp_path / "data"
    data_dir.mkdir()
    instance = Server(data_dir, tmp_path / "server.log")
    instance.start()
    yield instance
    instance.stop()
    errors = instance.error_lines()
    assert not errors, "The server logged errors:\n" + "\n".join(errors)


@pytest.fixture
def app(page, server, request, browser_name):
    """The encounter page, booted and ready for a DM's first click."""
    shots = ARTIFACTS / "shots" / browser_name / request.node.name
    instance = App(page, server, shots)
    instance.goto("/")
    yield instance
    assert not instance.page_errors, "The page threw:\n" + "\n".join(
        instance.page_errors
    )


@pytest.fixture
def tab(app):
    """The compendium tab.  It opens the way a DM opens it."""
    compendium = library.open_from(app)
    yield compendium
    compendium.assert_quiet()


@pytest.fixture
def signed_in_tab(app):
    """The compendium tab of a DM who just made an account."""
    app.sign_up()
    compendium = library.open_from(app)
    yield compendium
    compendium.assert_quiet()


@pytest.fixture
def cli(tmp_path):
    """Runs ezpz-dndz-cli against a scratch data dir."""
    if not CLI_BIN.exists():
        pytest.exit(f"{CLI_BIN} is missing.  Run `just qa`, which builds it.")
    data_dir = tmp_path / "cli-data"
    data_dir.mkdir()

    def run(*args, check=True, input=None):
        result = subprocess.run(
            [str(CLI_BIN), *args],
            capture_output=True,
            text=True,
            input=input,
            cwd=data_dir,
            env={**os.environ, "NO_COLOR": "1"},
            timeout=60,
        )
        if check and result.returncode != 0:
            pytest.fail(
                f"ezpz-dndz-cli {' '.join(args)} exited {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        return result

    run.data_dir = data_dir
    return run
