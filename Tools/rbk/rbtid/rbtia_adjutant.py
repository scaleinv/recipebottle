#!/usr/bin/env python3
#
# Copyright 2026 Scale Invariant, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Brad Hyslop <bhyslop@scaleinvariant.org>
#
# RBTIA - Ifrit sortie adjutant
#
# Reads the roster (rbtid_roster.txt), dispatches sorties (rbtis_*.py),
# collects debriefs. Roster-based dispatch: no dynamic discovery.
# Designed to run inside the bottle container behind the sentry.
#
# Usage:
#   python3 rbtia_adjutant.py                  # run all rostered sorties
#   python3 rbtia_adjutant.py dns              # run rostered sorties matching front
#   python3 rbtia_adjutant.py dns_exfil        # run rostered sorties matching substring

import importlib.util
import json
import sys
import time
import traceback
from pathlib import Path

RBTID_DIR = Path(__file__).parent
SORTIE_PREFIX = "rbtis_"
ROSTER_FILE = RBTID_DIR / "rbtid_roster.txt"
DEBRIEF_FILE = RBTID_DIR / "rbtid_debrief.json"


def read_roster():
    """Read roster file, return list of sortie names (without prefix/extension)."""
    if not ROSTER_FILE.exists():
        print(f"FATAL: roster not found: {ROSTER_FILE}", file=sys.stderr)
        sys.exit(2)
    names = []
    for line in ROSTER_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            names.append(line)
    return names


def detect_rogues(roster_names):
    """Find rbtis_*.py files not on the roster — present but unregistered."""
    rostered = {f"{SORTIE_PREFIX}{name}.py" for name in roster_names}
    on_disk = {p.name for p in RBTID_DIR.glob(f"{SORTIE_PREFIX}*.py")}
    return sorted(on_disk - rostered)


def load_sortie(path):
    """Dynamically load a sortie module by file path."""
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def dispatch_sortie(path):
    """Execute a single sortie, return structured debrief entry."""
    entry = {
        "sortie": path.stem,
        "front": extract_front(path.stem),
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    try:
        mod = load_sortie(path)

        if not hasattr(mod, "run"):
            entry["verdict"] = "ERROR"
            entry["detail"] = "Sortie missing run() function"
            return entry

        outcome = mod.run()

        if not isinstance(outcome, dict):
            entry["verdict"] = "ERROR"
            entry["detail"] = f"run() returned {type(outcome).__name__}, expected dict"
            return entry

        entry["verdict"] = outcome.get("verdict", "ERROR")
        entry["detail"] = outcome.get("detail", "")
        entry["assertions"] = outcome.get("assertions", [])

    except Exception:
        entry["verdict"] = "ERROR"
        entry["detail"] = traceback.format_exc()

    entry["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    return entry


def extract_front(stem):
    """Extract front from sortie name: rbtis_dns_exfil_subdomain → dns."""
    parts = stem.removeprefix(SORTIE_PREFIX).split("_", 1)
    return parts[0] if parts else "unknown"


def print_entry(entry):
    """Print a single debrief entry in human-readable form."""
    verdict = entry["verdict"]
    marker = {"SECURE": "+", "BREACH": "!", "ERROR": "?"}.get(verdict, "?")
    print(f"  [{marker}] {entry['sortie']}: {verdict}")
    if entry.get("detail") and verdict != "SECURE":
        for line in str(entry["detail"]).strip().splitlines():
            print(f"      {line}")
    for assertion in entry.get("assertions", []):
        a_marker = "+" if assertion.get("passed") else "!"
        print(f"    [{a_marker}] {assertion.get('name', '?')}: {assertion.get('detail', '')}")


def main():
    filter_pattern = sys.argv[1] if len(sys.argv) > 1 else None

    # Read roster
    roster_names = read_roster()
    if filter_pattern:
        roster_names = [n for n in roster_names if filter_pattern in n]

    if not roster_names:
        print("No rostered sorties" +
              (f" matching '{filter_pattern}'" if filter_pattern else ""))
        sys.exit(0)

    # Detect rogues (unrostered rbtis_*.py files)
    rogues = detect_rogues(read_roster())
    if rogues:
        print("WARNING: rogue sorties (present but not rostered):")
        for rogue in rogues:
            print(f"  ! {rogue}")
        print()

    # Validate roster entries reference existing modules
    missing = []
    sortie_paths = []
    for name in roster_names:
        path = RBTID_DIR / f"{SORTIE_PREFIX}{name}.py"
        if not path.exists():
            missing.append(name)
        else:
            sortie_paths.append(path)

    if missing:
        print("FATAL: roster references missing sorties:", file=sys.stderr)
        for name in missing:
            print(f"  ! {SORTIE_PREFIX}{name}.py", file=sys.stderr)
        sys.exit(2)

    # Dispatch
    print(f"Ifrit adjutant — {len(sortie_paths)} sortie(s)")
    print()

    entries = []
    for path in sortie_paths:
        entry = dispatch_sortie(path)
        entries.append(entry)
        print_entry(entry)

    print()

    # Summary
    by_verdict = {}
    for e in entries:
        v = e["verdict"]
        by_verdict[v] = by_verdict.get(v, 0) + 1

    parts = []
    for v in ["SECURE", "BREACH", "ERROR"]:
        if v in by_verdict:
            parts.append(f"{by_verdict[v]} {v}")
    print(f"Summary: {', '.join(parts)}")

    # Write debrief
    with open(DEBRIEF_FILE, "w") as f:
        json.dump({"entries": entries}, f, indent=2)
    print(f"Debrief: {DEBRIEF_FILE}")

    # Exit code: 0 if all SECURE, 1 if any BREACH or ERROR
    failing = by_verdict.get("BREACH", 0) + by_verdict.get("ERROR", 0)
    sys.exit(1 if failing else 0)


if __name__ == "__main__":
    main()
