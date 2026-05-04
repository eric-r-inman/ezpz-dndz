#!/usr/bin/env python3
"""Promote a custom creature from the running dev server's compendium
into the embedded bundle (`crates/lib/data/bundled-creatures.json`).

Workflow this automates:

  1. GET ``<server>/api/compendium/creatures/<id>`` to fetch the
     current state of the user's creature.
  2. Compute the next sequential bundle id by scanning existing
     entries that match the bundle's stable-UUID pattern
     (``01914741-0001-4001-a001-XXXXXXXXXXXX``).
  3. Rewrite the fetched creature's ``id`` (stable bundle id),
     ``source`` (``"Bundled"``), and ``created_at`` /
     ``updated_at`` (both ``0``) — the server backfills
     ``updated_at`` later if the creature is ever edited.
  4. Append to ``bundled-creatures.json`` with stable indentation.
  5. Bump ``BUNDLED_VERSION`` in
     ``crates/server/src/compendium/store.rs`` so existing
     deployments pick up the new entry on next launch via the
     ADD-ONLY merge.

Usage:

  scripts/promote-to-bundle.py <creature-id> [--server URL]

The default server URL matches `just dev` (http://127.0.0.1:4040).
After running, rebuild + commit; existing deployments backfill
the new bundled creature on next boot.
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUNDLE_PATH = REPO / "crates" / "lib" / "data" / "bundled-creatures.json"
STORE_PATH = REPO / "crates" / "server" / "src" / "compendium" / "store.rs"
BUNDLE_PREFIX = "01914741-0001-4001-a001-"


def fetch_creature(server_url: str, creature_id: str) -> dict:
    url = f"{server_url.rstrip('/')}/api/compendium/creatures/{creature_id}"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            sys.exit(f"Creature id '{creature_id}' not found in the compendium.")
        sys.exit(f"Server returned {e.code} for {url}: {e}")
    except urllib.error.URLError as e:
        sys.exit(
            f"Couldn't reach {server_url}: {e.reason}\n"
            f"Is the dev server running? Try `just dev`."
        )


def next_bundle_id(bundle: list) -> str:
    suffixes: list[int] = []
    for c in bundle:
        cid = c.get("id", "")
        if cid.startswith(BUNDLE_PREFIX):
            tail = cid[len(BUNDLE_PREFIX):]
            try:
                suffixes.append(int(tail, 16))
            except ValueError:
                # Non-hex tail — skip it; the next-id calc only
                # cares about stable-pattern bundle ids.
                pass
    next_n = (max(suffixes) + 1) if suffixes else 1
    return f"{BUNDLE_PREFIX}{next_n:012x}"


def bump_bundle_version() -> tuple[int, int]:
    text = STORE_PATH.read_text()
    pattern = r"pub const BUNDLED_VERSION: i32 = (\d+);"
    m = re.search(pattern, text)
    if not m:
        sys.exit(f"Couldn't find BUNDLED_VERSION constant in {STORE_PATH}")
    old = int(m.group(1))
    new = old + 1
    text = re.sub(
        pattern,
        f"pub const BUNDLED_VERSION: i32 = {new};",
        text,
        count=1,
    )
    STORE_PATH.write_text(text)
    return old, new


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Promote a custom creature into the bundled set."
    )
    parser.add_argument(
        "creature_id",
        help="UUID of the creature in the running server's compendium.",
    )
    parser.add_argument(
        "--server",
        default="http://127.0.0.1:4040",
        help="Base URL of the running dev server "
        "(default: http://127.0.0.1:4040, matches `just dev`).",
    )
    args = parser.parse_args()

    creature = fetch_creature(args.server, args.creature_id)
    print(f"Fetched: {creature['name']}")

    bundle = json.loads(BUNDLE_PATH.read_text())
    new_id = next_bundle_id(bundle)

    creature["id"] = new_id
    creature["source"] = "Bundled"
    creature["created_at"] = 0
    creature["updated_at"] = 0
    bundle.append(creature)

    BUNDLE_PATH.write_text(json.dumps(bundle, indent=2) + "\n")
    print(f"Appended to {BUNDLE_PATH.relative_to(REPO)} with id {new_id}")
    print(f"Bundle now has {len(bundle)} creatures")

    old_v, new_v = bump_bundle_version()
    print(f"Bumped BUNDLED_VERSION: {old_v} → {new_v}")

    print()
    print("Next steps:")
    print("  1. Rebuild: `cargo build --workspace`")
    print("  2. Restart the dev server (or `just dev` again)")
    print("  3. Verify: open the Compendium browser; the new creature appears")
    print(
        "  4. Commit: "
        f"{BUNDLE_PATH.relative_to(REPO)} + "
        f"{STORE_PATH.relative_to(REPO)}"
    )


if __name__ == "__main__":
    main()
