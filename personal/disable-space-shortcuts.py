#!/usr/bin/env python3
"""
Turn off the 8 macOS shortcuts that sit on ctrl-arrow and ctrl-shift-arrow,
so AeroSpace can have them.

Four of these have no checkbox in System Settings. This flips them all.

    python3 disable-space-shortcuts.py --dry-run    # show what would change
    python3 disable-space-shortcuts.py              # do it
    python3 disable-space-shortcuts.py --restore FILE

Sets "enabled" to false and leaves each shortcut's key binding intact, so
re-enabling later in System Settings gives you the original keys back. Writes a
full backup before touching anything.
"""

import argparse
import plistlib
import subprocess
import sys
from datetime import datetime
from pathlib import Path

DOMAIN = "com.apple.symbolichotkeys"

TARGETS = {
    32: "Mission Control (ctrl-up)",
    33: "Application windows (ctrl-down)",
    35: "Show Dashboard, legacy (ctrl-shift-up)",
    36: "Show Spotlight window, legacy (ctrl-down)",
    37: "Undocumented (ctrl-shift-down)",
    79: "Move left a space (ctrl-left)",
    80: "Move left a space, secondary (ctrl-shift-left)",
    81: "Move right a space (ctrl-right)",
    82: "Move right a space, secondary (ctrl-shift-right)",
    242: "Undocumented (ctrl-up)",
    243: "Undocumented (ctrl-down)",
}


def export_domain():
    raw = subprocess.run(["defaults", "export", DOMAIN, "-"],
                         capture_output=True, check=True).stdout
    return plistlib.loads(raw)


def import_domain(data):
    subprocess.run(["defaults", "import", DOMAIN, "-"],
                   input=plistlib.dumps(data), check=True)


def activate():
    path = ("/System/Library/PrivateFrameworks/SystemAdministration.framework"
            "/Resources/activateSettings")
    if Path(path).exists():
        subprocess.run([path, "-u"], check=False)
        return True
    return False


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="show changes, write nothing")
    ap.add_argument("--restore", metavar="FILE", help="put back a backup made by this script")
    args = ap.parse_args(argv)

    if args.restore:
        with open(args.restore, "rb") as fh:
            import_domain(plistlib.load(fh))
        activate()
        print("restored from %s" % args.restore)
        return 0

    try:
        data = export_domain()
    except Exception as exc:
        print("could not read %s: %s" % (DOMAIN, exc), file=sys.stderr)
        return 1

    hotkeys = data.get("AppleSymbolicHotKeys") or {}
    changed, already, missing = [], [], []

    for hid, label in sorted(TARGETS.items()):
        entry = hotkeys.get(str(hid))
        if entry is None:
            missing.append((hid, label))
            continue
        if not entry.get("enabled", False):
            already.append((hid, label))
            continue
        entry["enabled"] = False
        changed.append((hid, label))

    for hid, label in changed:
        print("  off   %-4d %s" % (hid, label))
    for hid, label in already:
        print("  was   %-4d %s" % (hid, label))
    for hid, label in missing:
        print("  n/a   %-4d %s" % (hid, label))

    if not changed:
        print("\nnothing to change.")
        return 0

    if args.dry_run:
        print("\ndry run, wrote nothing. %d would be turned off." % len(changed))
        return 0

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = Path.home() / ("symbolichotkeys-backup-%s.plist" % stamp)
    with backup.open("wb") as fh:
        plistlib.dump(export_domain(), fh)

    data["AppleSymbolicHotKeys"] = hotkeys
    import_domain(data)
    ok = activate()

    print("\n%d turned off. backup: %s" % (len(changed), backup))
    print("undo with: python3 %s --restore %s" % (Path(__file__).name, backup))
    if not ok:
        print("could not run activateSettings, so log out and back in to apply.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
