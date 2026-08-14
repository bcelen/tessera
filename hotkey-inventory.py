#!/usr/bin/env python3
"""
hotkey-inventory.py — one table for every keyboard shortcut on this Mac.

Reads four sources that actually live on disk:

  1. macOS system shortcuts   com.apple.symbolichotkeys
  2. Menu overrides you set   NSUserKeyEquivalents in per-app plists
  3. Keyboard Maestro         Keyboard Maestro Macros.plist
  4. AeroSpace                ~/.aerospace-next.toml or ~/.config/aerospace/aerospace.toml

Optionally walks a running app's menu bar over the Accessibility API (--menus).

Usage:
    python3 hotkey-inventory.py                     # Markdown to stdout
    python3 hotkey-inventory.py -o shortcuts.md     # Markdown to a file
    python3 hotkey-inventory.py --format json
    python3 hotkey-inventory.py --conflicts-only
    python3 hotkey-inventory.py --menus Safari --menus "Visual Studio Code"
    python3 hotkey-inventory.py --menus-all --menus-skip Xcode -o shortcuts.md

Standard library only. No network. Reads, never writes to your configs.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass, asdict
from pathlib import Path

HOME = Path.home()

# --------------------------------------------------------------------------
# Chord normalization
# --------------------------------------------------------------------------

# Canonical modifier order, matching how Apple prints them.
MOD_ORDER = ["ctrl", "opt", "shift", "cmd"]
MOD_GLYPH = {"ctrl": "\u2303", "opt": "\u2325", "shift": "\u21e7", "cmd": "\u2318", "fn": "fn"}

# Carbon virtual keycodes (kVK_*). Used by symbolichotkeys and Keyboard Maestro.
VKEY = {
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    10: "Section", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
    27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
    36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
    44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
    51: "Delete", 53: "Escape", 54: "RightCmd", 55: "Cmd", 56: "Shift",
    57: "CapsLock", 58: "Option", 59: "Control", 60: "RightShift",
    61: "RightOption", 62: "RightControl", 63: "Fn",
    65: "Keypad.", 67: "Keypad*", 69: "Keypad+", 71: "KeypadClear", 75: "Keypad/",
    76: "KeypadEnter", 78: "Keypad-", 81: "Keypad=", 82: "Keypad0", 83: "Keypad1",
    84: "Keypad2", 85: "Keypad3", 86: "Keypad4", 87: "Keypad5", 88: "Keypad6",
    89: "Keypad7", 91: "Keypad8", 92: "Keypad9",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
    105: "F13", 106: "F16", 107: "F14", 109: "F10", 110: "Menu", 111: "F12",
    113: "F15", 114: "Help", 115: "Home", 116: "PageUp", 117: "ForwardDelete",
    118: "F4", 119: "End", 120: "F2", 121: "PageDown", 122: "F1",
    123: "Left", 124: "Right", 125: "Down", 126: "Up",
}

# Cocoa NSEvent modifier flags, as stored in symbolichotkeys.
COCOA_FLAGS = [
    (1 << 17, "shift"), (1 << 18, "ctrl"), (1 << 19, "opt"),
    (1 << 20, "cmd"), (1 << 23, "fn"),
]

# Carbon modifier constants, as stored by Keyboard Maestro.
CARBON_FLAGS = [(256, "cmd"), (512, "shift"), (2048, "opt"), (4096, "ctrl")]

# NSUserKeyEquivalents prefix characters.
NSKEY_PREFIX = {"@": "cmd", "$": "shift", "~": "opt", "^": "ctrl"}

# AeroSpace modifier tokens.
AEROSPACE_MODS = {"cmd": "cmd", "alt": "opt", "ctrl": "ctrl", "shift": "shift"}

# AeroSpace key names that need a display alias.
AEROSPACE_KEY_ALIAS = {
    "leftSquareBracket": "[", "rightSquareBracket": "]", "semicolon": ";",
    "quote": "'", "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
    "minus": "-", "equal": "=", "backtick": "`", "space": "Space", "enter": "Return",
    "esc": "Escape", "tab": "Tab", "backspace": "Delete", "del": "ForwardDelete",
    "left": "Left", "right": "Right", "up": "Up", "down": "Down",
    "home": "Home", "end": "End", "pageUp": "PageUp", "pageDown": "PageDown",
}


def chord(mods, key: str) -> str:
    """Build a canonical chord string, e.g. '^~<shift>K' rendered with glyphs."""
    mods = set(mods)
    prefix = "".join(MOD_GLYPH[m] for m in MOD_ORDER if m in mods)
    if "fn" in mods:
        prefix = "fn" + prefix
    key = key if len(key) > 1 else key.upper()
    return prefix + key


def cocoa_mods(mask: int):
    return [name for bit, name in COCOA_FLAGS if mask & bit]


def carbon_mods(mask: int):
    return [name for bit, name in CARBON_FLAGS if mask & bit]


def vkey_name(code: int) -> str:
    return VKEY.get(code, "vkey%d" % code)


# --------------------------------------------------------------------------
# Record type
# --------------------------------------------------------------------------

@dataclass
class Binding:
    chord: str
    source: str          # "macOS" | "AppMenuOverride" | "KeyboardMaestro" | "AeroSpace" | "Menu:<App>"
    action: str
    scope: str = "global"  # "global", or an app / macro group / AeroSpace mode
    enabled: bool = True
    is_global: bool = True  # fires everywhere, regardless of front app or mode
    detail: str = ""

    def sort_key(self):
        return (self.chord.lower(), self.source, self.action)

    def match_chord(self) -> str:
        """Chord with the fn/Globe flag dropped, for conflict matching.

        macOS sets the fn bit in symbolichotkeys on arrow and function key
        shortcuts even when fn is not actually required to fire them, while
        AeroSpace and Keyboard Maestro never set it. Matching on the raw chord
        therefore hides real collisions such as macOS Mission Control on Ctrl-Up
        against a Ctrl-Up macro.
        """
        return self.chord[2:] if self.chord.startswith("fn") else self.chord

    def dedup_key(self):
        return (self.chord, self.source, self.scope, self.action, self.enabled)


# --------------------------------------------------------------------------
# 1. macOS system shortcuts
# --------------------------------------------------------------------------

# Well-established AppleSymbolicHotKeys IDs. Unknown IDs are reported by number
# rather than guessed at, so nothing here is invented.
SYMBOLIC = {
    7: "Move focus to the menu bar",
    8: "Move focus to the Dock",
    9: "Move focus to active or next window",
    10: "Move focus to window toolbar",
    11: "Move focus to floating window",
    12: "Turn keyboard access on or off",
    13: "Change the way Tab moves focus",
    15: "Turn zoom on or off",
    17: "Zoom in",
    19: "Zoom out",
    21: "Invert colors",
    23: "Turn VoiceOver on or off",
    25: "Move focus to status menus",
    27: "Move focus to next window in application",
    28: "Save picture of screen as a file",
    29: "Copy picture of screen to clipboard",
    30: "Save picture of selected area as a file",
    31: "Copy picture of selected area to clipboard",
    32: "Mission Control",
    33: "Application windows",
    34: "Show Dashboard (legacy)",
    35: "Show Dashboard (legacy)",
    36: "Show Spotlight window (legacy)",
    52: "Turn Dock hiding on or off",
    57: "Show Launchpad",
    59: "Move focus to next window (legacy)",
    60: "Select the previous input source",
    61: "Select next source in input menu",
    64: "Show Spotlight search",
    65: "Show Finder search window",
    79: "Move left a space",
    80: "Move left a space (alt)",
    81: "Move right a space",
    82: "Move right a space (alt)",
    98: "Show Help menu",
    118: "Switch to Desktop 1",
    119: "Switch to Desktop 2",
    120: "Switch to Desktop 3",
    121: "Switch to Desktop 4",
    122: "Switch to Desktop 5",
    123: "Switch to Desktop 6",
    124: "Switch to Desktop 7",
    125: "Switch to Desktop 8",
    126: "Switch to Desktop 9",
    159: "Show Launchpad",
    160: "Show Launchpad",
    162: "Show Desktop",
    163: "Show Notification Center",
    164: "Turn Do Not Disturb on or off",
    175: "Show Notification Center",
    179: "Toggle Dictation",
    184: "Show Finder search window",
    190: "Screenshot and recording options",
    222: "Quick Note",
}


def read_symbolichotkeys():
    out = []
    try:
        raw = subprocess.run(
            ["defaults", "export", "com.apple.symbolichotkeys", "-"],
            capture_output=True, check=True,
        ).stdout
        data = plistlib.loads(raw)
    except Exception as exc:
        print("warn: could not read symbolichotkeys: %s" % exc, file=sys.stderr)
        return out

    for hid, entry in sorted((data.get("AppleSymbolicHotKeys") or {}).items(),
                             key=lambda kv: int(kv[0])):
        try:
            hid_int = int(hid)
        except ValueError:
            continue
        value = entry.get("value") or {}
        params = value.get("parameters") or []
        if len(params) < 3:
            continue
        _ascii, keycode, mask = params[0], params[1], params[2]
        # 65535 in either slot means "unset".
        if keycode in (65535, None):
            continue
        name = SYMBOLIC.get(hid_int, "macOS hotkey #%d (undocumented ID)" % hid_int)
        out.append(Binding(
            chord=chord(cocoa_mods(int(mask)), vkey_name(int(keycode))),
            source="macOS",
            action=name,
            scope="global",
            is_global=True,
            enabled=bool(entry.get("enabled", False)),
            detail="symbolichotkey %d" % hid_int,
        ))
    return out


# --------------------------------------------------------------------------
# 2. NSUserKeyEquivalents (menu shortcuts you overrode in System Settings)
# --------------------------------------------------------------------------

def parse_nskey(spec: str):
    mods, i = [], 0
    while i < len(spec) and spec[i] in NSKEY_PREFIX:
        mods.append(NSKEY_PREFIX[spec[i]])
        i += 1
    key = spec[i:] or "?"
    # A bare uppercase letter with no $ still implies shift on macOS.
    if len(key) == 1 and key.isupper() and "shift" not in mods:
        mods.append("shift")
    return mods, key


def read_nsuserkeyequivalents():
    out = []
    roots = [
        HOME / "Library/Preferences",
        HOME / "Library/Containers",
    ]
    plists = []
    for root in roots:
        if not root.exists():
            continue
        if root.name == "Containers":
            plists += list(root.glob("*/Data/Library/Preferences/*.plist"))
        else:
            plists += list(root.glob("*.plist"))

    for p in plists:
        try:
            with p.open("rb") as fh:
                data = plistlib.load(fh)
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        eq = data.get("NSUserKeyEquivalents")
        if not isinstance(eq, dict):
            continue
        domain = p.stem
        app = "All apps" if domain in (".GlobalPreferences", "NSGlobalDomain") else domain
        for menu_item, spec in eq.items():
            if not isinstance(spec, str):
                continue
            mods, key = parse_nskey(spec)
            out.append(Binding(
                chord=chord(mods, key),
                source="AppMenuOverride",
                action=str(menu_item),
                scope=app,
                is_global=(app == "All apps"),
                enabled=True,
                detail=str(p),
            ))
    return out


# --------------------------------------------------------------------------
# 3. Keyboard Maestro
# --------------------------------------------------------------------------

KM_PLIST = HOME / "Library/Application Support/Keyboard Maestro/Keyboard Maestro Macros.plist"


def read_keyboard_maestro(path: Path = KM_PLIST):
    out = []
    if not path.exists():
        print("note: no Keyboard Maestro macro file at %s" % path, file=sys.stderr)
        return out
    try:
        with path.open("rb") as fh:
            data = plistlib.load(fh)
    except Exception as exc:
        print("warn: could not read Keyboard Maestro plist: %s" % exc, file=sys.stderr)
        return out

    groups = data if isinstance(data, list) else data.get("MacroGroups", [])
    for group in groups:
        if not isinstance(group, dict):
            continue
        gname = group.get("Name", "(unnamed group)")
        gactive = group.get("Activate", "") != "Disabled" and group.get("IsActive", True)
        # A macro group is global unless it is restricted to specific apps. KM
        # has used several key names for that list across versions, so identify
        # it by shape rather than by name: any list of dicts carrying a bundle
        # identifier is an application restriction.
        restricted_to = []
        for val in group.values():
            if not isinstance(val, list) or not val:
                continue
            for app in val:
                if isinstance(app, dict) and ("BundleIdentifier" in app or "Path" in app):
                    restricted_to.append(
                        app.get("Name") or app.get("BundleIdentifier") or "?")
        gglobal = not restricted_to
        gscope = gname if gglobal else "%s [%s]" % (gname, ", ".join(sorted(set(restricted_to))))
        for macro in group.get("Macros", []) or []:
            if not isinstance(macro, dict):
                continue
            mname = macro.get("Name", "(unnamed macro)")
            mactive = macro.get("IsActive", True)
            for trig in macro.get("Triggers", []) or []:
                if not isinstance(trig, dict):
                    continue
                if trig.get("MacroTriggerType") != "HotKey":
                    continue
                keycode = trig.get("KeyCode")
                if keycode is None:
                    continue
                mods = carbon_mods(int(trig.get("Modifiers", 0) or 0))
                out.append(Binding(
                    chord=chord(mods, vkey_name(int(keycode))),
                    source="KeyboardMaestro",
                    action=str(mname),
                    scope=gscope,
                    is_global=gglobal,
                    enabled=bool(gactive and mactive),
                    detail=str(trig.get("FireType", "")),
                ))
    return out


# --------------------------------------------------------------------------
# 4. AeroSpace
# --------------------------------------------------------------------------

AEROSPACE_PATHS = [
    HOME / ".aerospace-next.toml",
    HOME / ".config/aerospace-next/aerospace-next.toml",
]

SECTION_RE = re.compile(r"^\s*\[mode\.([A-Za-z0-9_-]+)\.binding\]\s*$")
ANY_SECTION_RE = re.compile(r"^\s*\[")
BINDING_RE = re.compile(r"^\s*([A-Za-z0-9_+-]+)\s*=\s*(.+?)\s*$")


def aerospace_chord(token: str) -> str:
    parts = token.split("-")
    mods, key = [], parts[-1]
    for part in parts[:-1]:
        mapped = AEROSPACE_MODS.get(part.lower())
        if mapped:
            mods.append(mapped)
        else:
            # Unrecognized token: keep it visible rather than dropping it.
            mods.append(part)
    key = AEROSPACE_KEY_ALIAS.get(key, key)
    known = [m for m in mods if m in MOD_GLYPH]
    unknown = [m for m in mods if m not in MOD_GLYPH]
    base = chord(known, key)
    return ("+".join(unknown) + "+" + base) if unknown else base


def read_aerospace(paths=None):
    out = []
    paths = paths or AEROSPACE_PATHS
    path = next((p for p in paths if p.exists()), None)
    if path is None:
        print("note: no aerospace.toml found in %s"
              % ", ".join(str(p) for p in paths), file=sys.stderr)
        return out

    mode = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.split("#", 1)[0].rstrip()
        m = SECTION_RE.match(stripped)
        if m:
            mode = m.group(1)
            continue
        if ANY_SECTION_RE.match(stripped):
            mode = None
            continue
        if mode is None or not stripped.strip():
            continue
        b = BINDING_RE.match(stripped)
        if not b:
            continue
        token, rhs = b.group(1), b.group(2).strip()
        action = rhs.strip("[]").strip()
        action = re.sub(r"^['\"]|['\"]$", "", action)
        action = action.replace("', '", " ; ").replace('", "', " ; ")
        out.append(Binding(
            chord=aerospace_chord(token),
            source="AeroSpace",
            action=action,
            scope="global" if mode == "main" else "mode:%s" % mode,
            # Non-main modes only fire once you have entered that mode.
            is_global=(mode == "main"),
            enabled=True,
            detail=str(path),
        ))
    return out


# --------------------------------------------------------------------------
# 5. Optional: walk a running app's menu bar
# --------------------------------------------------------------------------

MENU_JXA = r"""
function run(argv) {
  const appName = argv[0];
  const se = Application("System Events");
  const out = [];
  let proc;
  try { proc = se.processes[appName]; proc.name(); }
  catch (e) { return JSON.stringify({error: "not running: " + appName}); }
  const bar = proc.menuBars[0];
  const bItems = bar.menuBarItems();
  for (let i = 0; i < bItems.length; i++) {
    let title;
    try { title = bItems[i].name(); } catch (e) { continue; }
    let menus;
    try { menus = bItems[i].menus(); } catch (e) { continue; }
    if (!menus.length) continue;
    walk(menus[0], title, out, 0);
  }
  return JSON.stringify(out);
  function walk(menu, path, acc, depth) {
    if (depth > 3) return;
    let items;
    try { items = menu.menuItems(); } catch (e) { return; }
    for (let j = 0; j < items.length; j++) {
      let nm;
      try { nm = items[j].name(); } catch (e) { continue; }
      if (!nm) continue;
      try {
        const cc = items[j].attributes["AXMenuItemCmdChar"].value();
        const cm = items[j].attributes["AXMenuItemCmdModifiers"].value();
        if (cc) acc.push({path: path + " > " + nm, key: cc, mods: cm});
      } catch (e) {}
      try {
        const sub = items[j].menus();
        if (sub.length) walk(sub[0], path + " > " + nm, acc, depth + 1);
      } catch (e) {}
    }
  }
}
"""

# AXMenuItemCmdModifiers is a bitmask where cmd is implied unless bit 0 is set.
AX_MODS = [(1, "-cmd"), (2, "shift"), (4, "opt"), (8, "ctrl")]


def list_gui_apps():
    """Names of running processes that have a menu bar.

    "background only is false" is System Events' term for a process with a UI,
    which filters out daemons, helpers and agents that have no menus to walk.
    """
    script = ('tell application "System Events" to get name of every process '
              'whose background only is false')
    try:
        res = subprocess.run(["osascript", "-e", script],
                             capture_output=True, text=True, timeout=30)
    except Exception as exc:
        print("warn: could not list running apps: %s" % exc, file=sys.stderr)
        return []
    names = [n.strip() for n in res.stdout.strip().split(",") if n.strip()]
    return sorted(set(names))


def read_app_menus(app_name: str):
    out = []
    try:
        res = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", MENU_JXA, app_name],
            capture_output=True, text=True, timeout=90,
        )
        payload = json.loads(res.stdout.strip() or "[]")
    except Exception as exc:
        print("warn: menu walk failed for %s: %s" % (app_name, exc), file=sys.stderr)
        return out
    if isinstance(payload, dict) and payload.get("error"):
        print("warn: %s" % payload["error"], file=sys.stderr)
        return out

    for item in payload:
        mask = int(item.get("mods") or 0)
        mods = [] if (mask & 1) else ["cmd"]
        if mask & 2:
            mods.append("shift")
        if mask & 4:
            mods.append("opt")
        if mask & 8:
            mods.append("ctrl")
        out.append(Binding(
            chord=chord(mods, str(item.get("key", "?"))),
            source="Menu:%s" % app_name,
            action=str(item.get("path", "")),
            scope=app_name,
            is_global=False,
            enabled=True,
        ))
    return out


# --------------------------------------------------------------------------
# Conflicts
# --------------------------------------------------------------------------

def find_conflicts(bindings):
    """Return two {chord: [bindings]} maps for chords claimed more than once.

    hard = two or more enabled global claimants. Exactly one wins and which one
           depends on load order, so this is the category worth fixing.
    soft = a global claimant shadowing an app-scoped or modal shortcut, or two
           scoped claimants inside the same scope.
    """
    by_chord = defaultdict(list)
    for b in bindings:
        by_chord[b.match_chord()].append(b)

    hard, soft = {}, {}
    for c, group in by_chord.items():
        live = [b for b in group if b.enabled]
        if len(live) < 2:
            continue
        globals_ = [b for b in live if b.is_global]
        if len(globals_) >= 2:
            hard[c] = live
        elif globals_:
            soft[c] = live
        else:
            # Scoped claims only collide when they share a scope.
            scopes = [b.scope for b in live]
            if len(set(scopes)) < len(scopes):
                soft[c] = live
    return hard, soft


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def md_escape(text: str) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ")


def md_code(text: str) -> str:
    """Inline code span that survives a backtick in the content."""
    return "`` %s ``" % text if "`" in text else "`%s`" % text


def render_table(bindings) -> str:
    lines = ["| Chord | Source | Scope | Global | Action | On |",
             "|---|---|---|---|---|---|"]
    for b in sorted(bindings, key=lambda x: x.sort_key()):
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            md_code(md_escape(b.chord)), md_escape(b.source), md_escape(b.scope),
            "yes" if b.is_global else "no",
            md_escape(b.action), "yes" if b.enabled else "no"))
    return "\n".join(lines)


def render_markdown(bindings, hard, soft, conflicts_only=False) -> str:
    counts = defaultdict(int)
    for b in bindings:
        counts[b.source.split(":")[0]] += 1

    parts = ["# Keyboard shortcut inventory", ""]
    parts.append("%d bindings: %s." % (
        len(bindings),
        ", ".join("%d %s" % (n, s) for s, n in sorted(counts.items()))))
    parts.append("")

    parts.append("## Hard conflicts (%d)" % len(hard))
    parts.append("")
    parts.append("Two or more enabled global hotkeys on the same chord. "
                 "Only one of them fires and which one is not always predictable.")
    parts.append("")
    if hard:
        flat = [b for group in hard.values() for b in group]
        parts.append(render_table(flat))
    else:
        parts.append("None.")
    parts.append("")

    parts.append("## Soft conflicts (%d)" % len(soft))
    parts.append("")
    parts.append("A global hotkey shadowing an app-scoped one, or two claims inside "
                 "the same scope. Usually the global wins and the app shortcut goes dead.")
    parts.append("")
    if soft:
        flat = [b for group in soft.values() for b in group]
        parts.append(render_table(flat))
    else:
        parts.append("None.")
    parts.append("")

    if not conflicts_only:
        parts.append("## Everything")
        parts.append("")
        parts.append(render_table(bindings))
        parts.append("")

    return "\n".join(parts)


# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--output", help="write to this file instead of stdout")
    ap.add_argument("--format", choices=["markdown", "json"], default="markdown")
    ap.add_argument("--conflicts-only", action="store_true",
                    help="skip the full table")
    ap.add_argument("--menus", action="append", default=[], metavar="APP",
                    help="also walk this running app's menu bar (repeatable, slow)")
    ap.add_argument("--menus-all", action="store_true",
                    help="walk every running app that has a menu bar (very slow)")
    ap.add_argument("--menus-skip", action="append", default=[], metavar="APP",
                    help="exclude an app from --menus-all (repeatable)")
    ap.add_argument("--skip", action="append", default=[], metavar="SOURCE",
                    choices=["macos", "appmenu", "km", "aerospace"],
                    help="skip a source")
    ap.add_argument("--aerospace-config", help="explicit path to aerospace.toml")
    ap.add_argument("--km-plist", help="explicit path to the Keyboard Maestro plist")
    args = ap.parse_args(argv)

    bindings = []
    if "macos" not in args.skip:
        bindings += read_symbolichotkeys()
    if "appmenu" not in args.skip:
        bindings += read_nsuserkeyequivalents()
    if "km" not in args.skip:
        bindings += read_keyboard_maestro(
            Path(args.km_plist) if args.km_plist else KM_PLIST)
    if "aerospace" not in args.skip:
        bindings += read_aerospace(
            [Path(args.aerospace_config)] if args.aerospace_config else None)
    targets = list(args.menus)
    if args.menus_all:
        skip = {s.lower() for s in args.menus_skip}
        targets = [a for a in list_gui_apps() if a.lower() not in skip]
        if targets:
            print("walking %d apps, expect %d-%d minutes: %s"
                  % (len(targets), max(1, len(targets) // 2),
                     max(2, len(targets) * 2), ", ".join(targets)),
                  file=sys.stderr)
        else:
            print("no running apps with a menu bar were found", file=sys.stderr)
    for i, app in enumerate(targets, 1):
        started = time.time()
        found = read_app_menus(app)
        print("  [%d/%d] %-28s %3d shortcuts  %4.0fs"
              % (i, len(targets), app, len(found), time.time() - started),
              file=sys.stderr)
        bindings += found

    # The same override can appear in both ~/Library/Preferences and a sandbox
    # container, so collapse exact duplicates before counting or comparing.
    seen, unique = set(), []
    for b in bindings:
        k = b.dedup_key()
        if k in seen:
            continue
        seen.add(k)
        unique.append(b)
    bindings = unique

    hard, soft = find_conflicts(bindings)

    if args.format == "json":
        text = json.dumps({
            "bindings": [asdict(b) for b in sorted(bindings, key=lambda x: x.sort_key())],
            "hard_conflicts": {k: [asdict(b) for b in v] for k, v in hard.items()},
            "soft_conflicts": {k: [asdict(b) for b in v] for k, v in soft.items()},
        }, indent=2, ensure_ascii=False)
    else:
        text = render_markdown(bindings, hard, soft, args.conflicts_only)

    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print("wrote %s (%d bindings, %d hard conflicts, %d soft)"
              % (args.output, len(bindings), len(hard), len(soft)), file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
