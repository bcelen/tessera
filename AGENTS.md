# AGENTS.md

Instructions for any coding agent working in this repository, whatever the model or tool. Read this
first, then `dev-docs/fork-notes.md` before changing code.

## What this is

Tessera is a personal fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace), the i3-like
tiling window manager for macOS, written in Swift. Upstream is by Nikita Bobko, MIT licensed; keep
`LICENSE.txt` and the credit in `README.md` intact.

The fork adds five commands (`scratchpad`, `layout-snapshot`, `window-hints`, `sticky`, `place`),
menu bar changes, a custom icon, and its own identity so it can coexist with upstream:

| | value |
|---|---|
| App | `Tessera.app`, installed in `/Applications` |
| Bundle id | `bogac.tessera` (debug build: `bogac.tessera.debug`) |
| CLI | `tessera` |
| Config | `~/.tessera.toml` (or `~/.config/tessera/tessera.toml`) |
| Saved layouts | `~/.local/state/tessera/layouts/` |
| Signing certificate | `tessera-codesign-certificate`, self-signed, in the login keychain |

The repo was previously named `AeroSpace` and then `aerospace-next`. `dev-docs/reviews/` keeps the
old names on purpose, since those files record the code as it was. The internal target name
`AeroSpaceApp` and identifiers like `aeroSpaceAppId` are also deliberately unchanged, to keep merges
from upstream cheap. Don't rename them.

## Machines and how they stay in sync

The same repo is worked on from two Macs. Forgejo is the single source of truth between them.

```
BoStudio (Mac Studio)  <->  git.celen.cloud/bogac/tessera  <->  boMacBook (MacBook)
```

- Remote: `https://git.celen.cloud/bogac/tessera.git`, branch `main`. No other branches are used.
- Local path on both machines: `~/dev/forgejo/tessera`.
- At the start of any session: `git pull`. At the end, or before switching machines: commit, then
  `git push`. Never leave work uncommitted on one machine and start on the other; there is no other
  sync mechanism.
- If both machines have diverged, prefer `git pull --rebase` and resolve conflicts, rather than a
  merge commit.

### What git carries, and what it doesn't

In git, identical on both machines: all source, scripts, docs, the generated
`xcode/Tessera.xcodeproj`, and `personal/` (the user's config, Karabiner profile, hotkey tooling).

Per machine, never in git, so each Mac must be set up once:

- Full Xcode at `/Applications/Xcode.app`, selected with
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Command Line Tools alone are not
  enough: XCTest and `xcodebuild` need full Xcode. A fresh Xcode also needs
  `sudo xcodebuild -runFirstLaunch` once.
- `brew install bash`. The scripts source `script/setup.sh`, which requires bash 5; macOS ships 3.2.
- The signing certificate, created in Keychain Access: Certificate Assistant, Create a Certificate,
  Name `tessera-codesign-certificate`, Identity Type Self-Signed Root, Certificate Type Code Signing.
  Verify with `security find-identity -p codesigning`. Certificates don't travel with the repo.
- The Accessibility grant for `Tessera.app`, given on first launch.
- Saved layouts in `~/.local/state/tessera/`. These are machine-specific by nature (window ids and
  displays differ) and are not synced.
- Karabiner, for the hyper key. See `personal/README.md`.

### Keeping the config identical on both machines

`personal/tessera.toml` is the source of truth. The recommended setup on each Mac is a symlink, so
that `git pull` is all it takes to bring the config across:

```
ln -sf ~/dev/forgejo/tessera/personal/tessera.toml ~/.tessera.toml
```

Edit the repo file, commit, push, pull on the other machine, then `tessera reload-config`. To skip
that last step, set `auto-reload-config = true` in the config (off by default). It works through the
symlink: the watcher opens the target file, `git pull` replacing that file fires a delete event, and
the watcher is re-armed after every reload attempt, so it follows the new file.

Anything display-specific (gaps sized for one monitor) should be keyed by monitor name rather than
`monitor.main`, so one file works on both machines. Patterns are case-insensitive regexes matched
against the display name, which `tessera list-monitors` prints:

```toml
outer.bottom = [{ monitor."Built-in" = 200 }, { monitor."<studio display name>" = 400 }, 8]
```

## Building and testing

```
./build-debug.sh && ./swift-test.sh            # fast loop; must report "Executed N tests, with 0 failures"
./build-debug.sh -Xswiftc -warnings-as-errors  # what the release build will accept
./test.sh                                      # full gate: tests, swiftformat, swiftlint, periphery, generated files
./build-release.sh --skip-docs                 # signed Tessera.app and tessera CLI in .release/
```

Install: quit the running app (`osascript -e 'quit app "Tessera"'`), then
`cp -r .release/Tessera.app /Applications/` and open it. Only one window manager may run at a time;
two instances fight over the windows and everything visibly jitters.

Known traps, all hit before:

- `test.sh` and `build-release.sh` refuse to run on a dirty tree (`check-uncommitted-files.sh`).
  Commit first. A newly generated file shows up as untracked with an empty diff.
- Every Xcode update can break the release build, because it treats new compiler warnings as
  errors. Reproduce quickly with the `-warnings-as-errors` debug build above.
- `swift-test.sh` filters out passing XCTest lines; the final `Executed N tests` line is the evidence
  the suite ran. Ignore the Swift Testing runner's "0 tests in 0 suites".
- The two `NWError error 2` lines in `test.sh` output are expected: the CLI asks a debug server for
  its version and none is running.
- Unit tests use `TestWindow`, which never touches the Accessibility API. Focus, hiding and
  geometry bugs only show up when running the real app. Test the real thing.

## Rules for agents

- Read `dev-docs/fork-notes.md` before changing code. It lists the eight places a new command must
  be registered and the design decisions behind each feature.
- Never hand-edit `Sources/Common/cmdHelpGenerated.swift` or
  `Sources/Cli/subcommandDescriptionsGenerated.swift`; they are generated from `docs/*.adoc` by
  `./generate.sh`. Commit the regenerated output.
- Preserve executable bits on scripts. Some sandboxed environments drop them when a file is
  rewritten with `sed -i`; edit in place, and check with `ls -l *.sh` before committing.
- If your environment can create files in the repo but not delete them, don't run git commands that
  take locks (commit, add, checkout, remote set-url). They leave stale `.git/*.lock` files behind.
  Read-only inspection is fine with `git --no-optional-locks status`. Give the user the commands
  instead.
- Don't push. The user pushes.
- Ask before destructive actions: deleting files, rewriting history, changing identity (bundle id,
  app name, certificate name). Identity changes force the user to re-grant Accessibility.
- Keep upstream credit and the MIT notice. Don't reintroduce the sponsor item in the menu bar; the
  sponsor link lives in `README.md`.
- Respect the deliberate choices recorded in `fork-notes.md` (for example: hint letters rather than
  a search field, sticky as an emulation, restore never launching apps) unless the user asks to
  change them.
