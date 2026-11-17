# personal

My own setup. None of this is read by the window manager; it lives here so the repo root stays
upstream's.

**`tessera.BoStudio.toml`** and **`tessera.boMacBook.toml`** are the configs I actually run, one per
Mac, since the screens and some bindings differ. On each Mac `~/.tessera.toml` is a symlink to that
Mac's file, so after editing here it only takes:

```
tessera reload-config
```

A change meant for both Macs goes into both files. See "One config file per machine" in AGENTS.md.

Four rules organize the bindings. `alt` is where you go and what things look like. `ctrl` is windows:
focus, move, join, send to a workspace. Hyper, which is Caps Lock through Karabiner, is the four
commands only this fork has. `alt-cmd` is layout snapshots, with shift to save.

Two things it depends on. The eight macOS `ctrl`-arrow and `ctrl-shift`-arrow shortcuts have to be
off, which `disable-space-shortcuts.py` does. And `karabiner-hyper.json` is what makes Caps Lock
produce `ctrl-alt-shift-cmd`.

Letter workspaces are W X Y Z rather than A B C D. On a US layout `alt-c` is how you type ç, so
binding it stole every ç. `alt-w/x/y/z` produce ∑ ≈ ¥ Ω, which don't appear in Turkish or English.

`ctrl-a`, `ctrl-b`, `ctrl-c` and `ctrl-d` are deliberately not bound. AeroSpace registers hotkeys
globally, so binding them would swallow start-of-line, back, interrupt and EOF in every terminal and
text field. That one cost an evening before it was understood.

**`cheatsheet.md`** is the printable version of the same bindings.

**`hotkey-inventory.py`** reads macOS symbolic hotkeys, per-app menu overrides, Keyboard Maestro
macros and this config, then reports collisions. Run it before adding a binding.

**`disable-space-shortcuts.py`** turns off the macOS Mission Control shortcuts that collide with the
`ctrl`-arrow bindings.
