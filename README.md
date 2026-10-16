# Tessera

A personal fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace), the i3-like tiling window
manager for macOS.

<img src="./icons/icon_ground_1024.png" width="30%" align="right">

## Credit

AeroSpace is written by [Nikita Bobko](https://github.com/nikitabobko) and is MIT licensed. Every
good idea in this repository is his: the tree paradigm, the workspace emulation that avoids macOS
Spaces, the command surface, the CLI-first design, the whole architecture. This fork is a handful of
commands bolted onto his work for one person's habits.

If you want AeroSpace, get it from upstream rather than here. If you already use it and it saves you
time, [sponsor him](https://github.com/sponsors/nikitabobko).

The upstream documentation applies to this fork almost completely, and it's better than anything I
would write:
[Guide](https://nikitabobko.github.io/AeroSpace/guide) ·
[Commands](https://nikitabobko.github.io/AeroSpace/commands) ·
[Goodies](https://nikitabobko.github.io/AeroSpace/goodies)

## What's different

Five commands upstream doesn't have.

**`scratchpad`** parks a window out of sight and summons it back with one key, i3 style. The window
keeps running and reappears floating, in the same relative position it had when you hid it. Several
named scratchpads can coexist, so a terminal and a notes window can live on different keys.

```
scratchpad move        # park the focused window
scratchpad toggle      # bring it back, or send it away again
scratchpad move --name notes
```

**`layout-snapshot`** saves a workspace's tiling layout to a file and rebuilds it later, so you can
flip between a teaching desk and a research desk. It matches saved slots to windows that are running
now, gathering them back from wherever they ended up after a restart. It never launches anything.

```
layout-snapshot save teaching
layout-snapshot restore teaching
layout-snapshot list
```

**`window-hints`** shows a panel listing every window with a hint letter; press the letter to jump
there. It uses letters rather than a search field on purpose: AeroSpace is a background accessory
app, so a text field would have to steal keyboard focus and hand it back, which is where focus bugs
come from. The hints run through the existing global hotkey machinery instead, and the panel never
takes focus at all.

**`sticky`** keeps a window visible on every workspace, for a timer or a video call. Upstream issue
#2, approached as an emulation rather than a model change: the window is rebound to whichever
workspace is active on its monitor, so it always has exactly one parent.

```
sticky toggle
```

**`place`** puts a window at a fixed position and size, in points or as a percentage of the screen,
so an app can always open in the same spot or be snapped back there with one key. Upstream leaves
floating geometry alone entirely.

```
place --x 0 --y 50% --width 100% --height 50%     # the lower half
```

Smaller changes. The menu bar lists saved layouts with the keys that restore them and hides empty
workspaces, which matters when `persistent-workspaces` keeps eleven of them alive. `build-release.sh`
takes a `--skip-docs` flag that builds just the app and the CLI, skipping the man pages and shell
completions that need Ruby, Rust and fish. New app icon, light and dark. The sponsor item is gone
from the menu, which is why the ask is at the top of this file instead.

## Identity

This fork has its own bundle id, config file, socket and state directory, so it coexists with
upstream rather than replacing it.

| | upstream | this fork |
|---|---|---|
| App | `AeroSpace.app` | `Tessera.app` |
| Bundle id | `bobko.aerospace` | `bogac.tessera` |
| CLI | `aerospace` | `tessera` |
| Config | `~/.aerospace.toml` | `~/.tessera.toml` |
| Snapshots | n/a | `~/.local/state/tessera/layouts` |

Run both at once and they will fight over your windows, since neither can see the other any more.
Quit one.

## Building

Needs Xcode, bash 5 (`brew install bash`, since macOS ships 3.2), and a self-signed code signing
certificate named `tessera-codesign-certificate`. See
[dev-docs/development.md](dev-docs/development.md) for the Keychain Access steps.

```
./build-debug.sh && ./swift-test.sh          # fast loop
./build-release.sh --skip-docs               # signed app
cp -r ".release/Tessera.app" /Applications/
```

Grant Accessibility permission on first launch. Because the app is signed, the grant survives
rebuilds, and `start-at-login = true` works.

## Layout

```
Sources/            upstream's code, plus the five commands
docs/               upstream's asciidoc, plus one page per new command
dev-docs/           architecture and development notes
  fork-notes.md     why this fork does what it does, and the traps
  reviews/          code reviews of the fork and the replies
personal/           my config, cheatsheet and hotkey tooling
icons/              app icon masters
```

[dev-docs/fork-notes.md](dev-docs/fork-notes.md) is the file to read before changing anything. It
covers the eight places a new command has to be registered, the design decisions behind each feature,
and the mistakes that cost the most time.

## License

MIT, same as upstream. See [LICENSE.txt](LICENSE.txt), which retains Nikita Bobko's copyright.
