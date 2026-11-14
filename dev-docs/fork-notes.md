# Fork notes

Personal fork of AeroSpace with six commands and a layout that upstream doesn't have. Written down so
that neither I nor a future Claude session has to reconstruct the reasoning.

Added: `scratchpad`, `layout-snapshot`, `window-hints`, `sticky`, `place`, `column-width`, and the
`scrolling` layout.

## Running it

The repo lives at `~/dev/forgejo/tessera`. It was called `AeroSpace`, then `aerospace-next`, before
settling on Tessera (a single tile in a mosaic), so older shell history, aliases and the review
documents in `dev-docs/reviews/` still use the earlier names. The reviews are left as written, since
they're a record of the code at the time.

For a quick edit-and-try loop, run the SPM debug binary:

```
cd ~/dev/forgejo/tessera
./run-debug.sh                # occupies the terminal
# or, detached:
nohup ./.debug/AeroSpaceApp > /tmp/aerospace.log 2>&1 &
```

The debug binary can't start at login. It is unsigned and has no bundle identifier, so TCC has
nothing to attach an Accessibility grant to. When Terminal launches it, Terminal is the responsible
process and its own grant covers the child; launchd launching it directly gets nothing, and the app
sits there without opening its socket. A launch agent was tried and removed for exactly this reason.

For daily use, build the signed app instead:

```
./build-release.sh --skip-docs
cp -r ".release/Tessera.app" /Applications/
```

`--skip-docs` is a flag added in this fork. Upstream's script always builds man pages and shell
completions first, which need Ruby with bundler, Rust, and fish; the flag skips those and the
packaging steps that consume their output, leaving `.release/Tessera.app` and `.release/tessera`.
It needs the self-signed `tessera-codesign-certificate` described in `development.md`, and a clean
git tree. With a real signing identity the Accessibility grant sticks to the certificate and survives
rebuilds, and `start-at-login = true` works because an app bundle can register itself as a login item.

Environment gotchas, all hit at least once:

- `script/setup.sh` requires bash 5. macOS ships 3.2, so `brew install bash` is mandatory.
- XCTest lives inside Xcode, not the Command Line Tools. If `swift build --target AppBundleTests`
  reports "no such module 'XCTest'", run
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- swiftly is not installed, so builds fall back to the Xcode toolchain and print a warning. Harmless.
- `./test.sh` ends with `check-uncommitted-files.sh`, which fails on any dirty file. That is not a
  code failure, it just means commit first.

## Adding a command

Every new command touches the same eight places. Miss one and the build breaks in a confusing way.

1. `Sources/Common/cmdArgs/impl/<Name>CmdArgs.swift`, the arg parser.
2. `Sources/AppBundle/command/impl/<Name>Command.swift`, the behavior.
3. `Sources/Common/cmdArgs/cmdArgsManifest.swift`, twice: the `CmdKind` case and `initSubcommands()`.
4. `Sources/AppBundle/command/cmdManifest.swift`, the `toCommand()` switch.
5. `docs/aerospace-<name>.adoc`, with a `tag::synopsis` block.
6. `docs/commands.adoc`, an include block.
7. `grammar/commands-bnf-grammar.txt`, for shell completion.
8. Regenerate `Sources/Common/cmdHelpGenerated.swift` and
   `Sources/Cli/subcommandDescriptionsGenerated.swift` by running `./generate.sh`.

Both generated files are derived from the `.adoc` files by `script/generate-cmd-help.sh` and are
committed, so hand-editing them has to match the generator byte for byte. Note the glob order:
`aerospace-layout-snapshot.adoc` sorts before `aerospace-layout.adoc`, because `-` sorts before `.`.

Two things worth knowing about the parser. Error messages from `parseSpecificCmdArgs` (mandatory
argument missing, unknown flag) are prefixed with `ERROR: `, but messages from `.filter` and
`.filterNot` are not. And a positional arg parser with `argPlaceholderIfMandatory: nil` is treated
as optional, which is how `layout-snapshot list` gets away with taking no `<name>`.

## scratchpad

Park a window off-screen, summon it with one key.

Windows go into a workspace named `_scratchpad.<name>`, which is never assigned to a monitor. The
existing layout pass hides windows of invisible workspaces in a screen corner, so no new hiding
machinery was needed. `WorkspaceName.parse` rejects names starting with `_`, so users can't reach
these workspaces with `workspace` or `move-node-to-workspace` by accident.

Decisions:

- Summoned windows come back floating. A tiling scratchpad window would rearrange the layout of
  whatever workspace it lands on.
- Position and size are not restored explicitly. `unhideFromCorner` already restores the window's
  proportional position, which is the behavior we want and works across monitors of different sizes.
- Membership is per session. It does not survive an AeroSpace restart.

Two guards exist because of bugs found in live testing, not in unit tests:

- `getStubWorkspace` in `Workspace.swift` skips scratchpad workspaces. Without it, a scratchpad
  could be picked as the replacement workspace for a monitor and expose the hidden windows.
- `isSummonedOnFocusedWorkspace` returns false when the focused workspace is itself a scratchpad.
  Clicking a corner-hidden window pulls macOS focus to it, AeroSpace syncs its own focus from macOS,
  and you end up focused inside the scratchpad. Before the guard, `toggle` then chose `hide`, which
  had nothing to hide, and there was no way out. `show` now resolves a guaranteed non-scratchpad
  target via `Window.scratchpadSourceWorkspace`, recorded at `move` time.

The remaining sharp edge: don't park the terminal you are driving from.

## layout-snapshot

Save a workspace's tiling tree to `~/.local/state/tessera/layouts/<name>.json`, restore it later.

Per window it records the app bundle id, app name, and window title. Per container, the orientation,
the layout, and each child's share of its parent as a fraction, so proportions survive a move to a
different monitor. Weights are applied top down after the tree is built, because a fraction is
meaningless until the parent's own weight is final.

Decisions, all of which were explicit choices and are reversible:

- Restore never launches anything. Slots with no matching window collapse.
- Restore considers windows on the target workspace first, then windows anywhere else. This is what
  makes it useful after a restart, and it also means restoring mid-task yanks windows off other
  workspaces.
- Matching is tried in three steps: the recorded `windowId`, then an exact title match, then the
  first unused window of that app. The window id is exact but only within the session that took the
  snapshot, since ids don't survive a restart; a stale one simply fails to resolve and falls through.
  After a restart, two windows of the same app sharing a title are genuinely indistinguishable and
  get assigned positionally, first unused window to first slot in DFS order. Deterministic, but it
  can put the wrong browser window in the wrong pane.
- Only the tiling tree. Floating windows, fullscreen state, and scratchpad windows are left alone.

`save` and `restore` refuse to operate on a scratchpad workspace. Saving one produced an empty
snapshot, which is how the focus-drift bug above was first noticed.

## window-hints

A picker. Shows a panel listing windows, each with a hint letter; press the letter to focus it.

The interesting part is why it uses hint letters rather than a search field. AeroSpace is a
background accessory app. A panel with a text field has to take keyboard focus, which fights the
window manager and is the classic source of focus bugs. Instead, while the panel is up, a binding
mode called `_window-hints` is injected into `config.modes` at runtime and activated. Keystrokes go
through the existing global hotkey machinery and the panel, an `NSPanelHud` like the volume HUD,
never takes focus at all.

Hint letters are handed out home row first, focused workspace first, capped at 26 windows.

Known rough edge: only the hint letters and `esc` are bound, so any other key does nothing and you
stay in the mode with no feedback. `tessera mode main` is the escape hatch.

Reloading the config while the panel was open used to be worse: the new config has no
`_window-hints` mode, so reactivating it bound nothing, Escape included. Reload now dismisses the
panel first, and falls back to `main` if the active mode no longer exists in the new config. The fix is to bind every remaining letter to
`hide`; not done yet.

## sticky

A window that stays visible when you switch workspaces.

Upstream issue #2, open since the beginning, because the tree gives every window exactly one parent.
This is an emulation rather than a model change: `syncStickyWindows()` runs at the top of every
refresh and rebinds each sticky window to whichever workspace is active on its monitor. The window
always has exactly one parent, it just moves. Since the layout pass only hides windows of invisible
workspaces, a window always attached to the visible one is never hidden.

It follows the monitor the window sits on, not the focused workspace, so on multiple displays it
stays put instead of chasing focus. Turning it on forces the window to float, for the same reason as
the scratchpad. Turning it off leaves it floating where it is.

Because the tree position is not stable, sticky windows shouldn't be relied on in `layout-snapshot`
or in scripts that walk the tree.

## place

Put a window at a fixed position and size. Upstream deliberately manages only tiled geometry; a
floating window keeps whatever frame it last had, which is exactly why a frame set here sticks.

Coordinates are relative to the visible area of the window's monitor (below the menu bar, clear of
the Dock), and every value is points or a percentage. Percentages are the point: `--y 50%` means the
middle of whichever display the window is on, so a rule written on the Mac Studio still makes sense
on a projector.

Decisions:

- Placing a tiled window floats it first. Otherwise the next layout pass would overwrite the frame.
- `--x`/`--y` and `--width`/`--height` each come as a pair. Accepting `--x` alone would need the
  window's current frame, which is an async Accessibility read; pairs keep the command synchronous,
  and `setAxFrame` already takes nil for "leave this half alone".
- The size is written to `lastFloatingSize` too, so the window comes back at that size after being
  hidden in a corner by a workspace switch.

`TestWindow` now overrides `setAxFrame` to record the frame. Before this, any test path reaching
`setAxFrame` would have hit `die("Not implemented")`, which is why nothing tested geometry.

## scrolling layout and column-width

A third layout next to `tiles` and `accordion`, after niri and PaperWM: the root's children are
columns with a width of their own, on a strip that scrolls to keep the focused column in view.
Opening a window adds a column instead of squeezing the others. `column-width` sets the focused
column's width in percent; several values cycle.

Where the code is:

- `layout/scrollingLayout.swift` holds `ScrollingStrip`, the pure arithmetic (sizes, offset, where
  each column starts), plus the per-node width and per-container scroll offset. Both live in
  `TreeNode` user data rather than new stored properties, to keep upstream files untouched.
- `layoutScrolling` in `layoutRecursive.swift` turns the strip into frames. A column fully out of view
  is hidden with `hideInCorner`, the mechanism invisible workspaces already use. A column cut by the
  screen edge is left half off screen, which macOS allows horizontally.
- New windows go next to the focused column: `unbindAndGetBindingDataForNewTilingWindow` in
  `MacWindow.swift`.

Decisions:

- Root only. `layout scrolling` always targets the workspace root, even without `--root`, so
  `layout scrolling tiles` toggles the whole workspace from inside a stacked column. Nested scrolling
  would need clipping between siblings, which macOS windows can't do.
- Width is a fraction of the screen, not points, so a strip survives moving between the 52" Dell and
  the MacBook. A column of width f takes f of the screen including its share of the gaps, so two
  halves and the gap between them fill it exactly.
- The view scrolls as little as possible, and keeps `scrolling-peek` points of the neighbours in view
  so you can see there is more. Peek shrinks rather than push the focused column out of view.
- A cut column whose cut part would land on an adjacent monitor is hidden instead (`Monitor.neighbours`).
  On a single display nothing is ever hidden that is partly visible.
- Hiding scrolled-out columns runs on every refresh, so `hideInCorner(rememberPosition: false)` skips
  the Accessibility read that only floating windows need.
- When Tessera is disabled from the menu bar nothing may stay hidden, so `layoutWorkspace(hideCorner:
  nil)` lays a scrolling root out as tiles. That is also why `setWeight` accepts a scrolling parent.
- Flattening would replace a scrolling root that has a single column with the column itself, dropping
  out of the layout. `normalizeContainers` skips that case.
- `resize` works on columns too (in points), and `balance-sizes` resets every column to the default.
  Snapshots store the width as an optional `columnWidth`, so older snapshot files still load.
- Dragging a column's edge sets its width (`resizeScrollingColumnWithMouse`). Dragging a window onto
  another swaps them, and each keeps its width since the width lives on the node.
- Vertical scrolling works in principle but macOS keeps windows below the menu bar, so a column cut at
  the top gets pushed down; use it horizontally.

Swipe (`mouse/scrollingSwipe.swift`): a CGEvent tap, not an NSEvent global monitor, because a monitor
can only watch and the app under the pointer would scroll too. The tap needs no permission beyond
Accessibility. `ScrollingSwipeTracker` is the pure part: whether the modifiers were held is decided
when a swipe begins, the swipe steps once however long it is, and the tracker swallows the rest of it
including momentum, so releasing the modifiers mid-swipe doesn't leak a scroll into the app. Wheel
notches step one each. Smooth-scrolling wheels (Logitech with Options+, including the MX thumb wheel)
send continuous events with no gesture phases, so they step once per threshold of spin instead.
Whichever axis moved more counts, so a vertical wheel works too. Three- and four-finger swipes belong to macOS and can't be tapped.

Slide (`scrolling-animation-duration`): the strip is moved in about 16 ms steps inside the layout
pass, each step moving every column in view. Following the fingers live was ruled out: the only
public way to move another app's window is Accessibility, one message per window, and apps apply
frames at their own pace. `MacApp.setAxFrame` cancels a frame the app hasn't applied when the next
arrives, so a slow app skips steps rather than lagging behind. The slide holds the refresh session
for its duration, which is why it is capped at 1000 ms and off by default.

## Menu bar

Three changes in `MenuBar.swift` and `TrayMenuModel.swift`.

The workspace list now skips empty workspaces, keeping the focused and visible ones so you can still
see where you are. With eleven entries in `persistent-workspaces` the old list was mostly noise. It
also skips scratchpad workspaces, which were leaking an implementation detail into the UI.

A "Layouts:" section lists saved snapshots when any exist, and clicking one restores it. Each row
shows the keys bound to it, resolved from `config.modes` at display time rather than hardcoded. A
binding that lives inside a non-main mode is shown with the keys that enter the mode first, so a
snapshot bound to `1` inside a mode entered by `alt-0` reads as "opt-0 1". See
`layoutSnapshotRestoreShortcut` in `layoutSnapshot.swift`.

Those rows print `opt` where the config says `alt`, via `displayNotation` in the same file. It is
cosmetic only. The config parser still accepts `alt-` and nothing else, because that is upstream's
spelling and changing it would break every existing config; the key is just labelled Option on the
keyboard, so that is what the menu should say. Nothing round-trips through `displayNotation`, so it
cannot feed a rewritten string back into a binding lookup.

The "Sponsor AeroSpace on GitHub" item is removed, along with `sponsorshipPrompts.swift` and the
model property, because periphery's unused-code scan fails otherwise. The credit and the sponsor
link moved to the banner at the top of `README.md`. This is a personal-fork change and would never
go upstream.

## Identity

The fork has its own identity, so it can coexist with upstream AeroSpace rather than fighting it for
the same bundle id, socket, config file, and state directory.

| | upstream | this fork |
|---|---|---|
| Bundle id | `bobko.aerospace` | `bogac.tessera` |
| Debug bundle id | `bobko.aerospace.debug` | `bogac.tessera.debug` |
| App name | `AeroSpace` | `Tessera` |
| CLI | `aerospace` | `tessera` |
| Config | `~/.aerospace.toml` | `~/.tessera.toml` |
| XDG config | `~/.config/aerospace/aerospace.toml` | `~/.config/tessera/tessera.toml` |
| Socket | `/tmp/bobko.aerospace-<user>.sock` | `/tmp/bogac.tessera-<user>.sock` |
| Snapshots | n/a | `~/.local/state/tessera/layouts` |

The socket path and the Console log directory are both derived from the bundle id in
`Sources/Common/appMetadata.swift`, so they follow automatically. The rest is spelled out in
`Sources/AppBundle/config/ConfigFile.swift` (dotfile name and XDG path), `layoutSnapshotsDir()` in
`Sources/AppBundle/layoutSnapshot.swift`, `Package.swift` (CLI product name), and `xcode/project.yml`
(project name, target, product name, both bundle ids).

The debug identity is kept separate from release on purpose. `toggleReleaseServerIfDebug` uses it to
pause the installed release app while a debug build is running, so `./run-debug.sh` doesn't fight
`/Applications/Tessera.app` for control of your windows.

`cleanupPlistFromPrevVersions()` used to delete `~/Library/LaunchAgents/bobko.aerospace.plist` on
every config reload. That's upstream's file, not ours, and since the point of the separate identity
is coexistence, deleting it could break an upstream install's start at login. Removed.

The app name contains a space, so the release build produces `Tessera.app`. Every path in
`build-release.sh` that touches it is quoted; if you edit that script, keep the quotes.

Removed, on purpose: upstream's release and community plumbing. `install-from-sources.sh`,
`script/build-brew-cask.sh` and `script/publish-release.sh` built and published the `aerospace` cask
to `nikitabobko/tap`, and `publish-release.sh` would have pushed release tags to Nikita's GitHub.
`.github/` held his CI, issue templates and an issue-closing bot; Forgejo Actions also reads
`.github/workflows`, so the daily `build.yml` cron would have tried to run here. `CONTRIBUTING.md`
described contributing to upstream. The personal workflow is `build-release.sh --skip-docs` plus a
copy into `/Applications`, and without `--skip-docs` the script still builds a zip, just no cask.

## App icon

`icons/` holds the source PNGs in two sets at seven sizes each. `ground` is dark tiles on a light
field, `ink` is the inverse. Both carry one red tile.

`resources/Assets.xcassets/AppIcon.appiconset/Contents.json` wires all ten macOS slots twice: the
ground set as the default appearance, the ink set behind an `appearances` entry with
`"appearance": "luminosity", "value": "dark"`. So the icon inverts with the system appearance, and a
system too old to understand the key falls back to ground.

Every slot has a real file at the exact pixel size rather than letting Xcode downscale one 1024
master, which is why the 16 and 32 point versions stay legible.

The upstream `icon.png` is no longer referenced.

## Fixes from the October 2026 review

A full-project review found the following; all verified against the code before applying.

- Quit could hang. Resetting window frames on termination waited on a semaphore that was never
  signalled if the window had already vanished from the per-app cache. Now always signalled, and
  bounded by a 500 ms timeout so one app with a frozen Accessibility thread can't block quit.
- `layout-snapshot restore` gave snapshot windows the whole width before appending unmatched
  windows, so the layout pass subtracted from every tile and small ones went negative. The finished
  tree is now normalized and rescaled proportionally.
- `workspace next/prev` and relative moves could land on a scratchpad workspace. Filtered.
- `resize` could make a tile negative. It now computes every new size first and rejects the change
  as a whole if any would be non-positive.
- `place --width inf` was accepted, since `Double("inf")` is +infinity. Now requires a finite value.
- The config watcher stayed attached to the replaced file after a save with a TOML error, so the
  corrected save went unnoticed. It's re-armed after every automatic reload attempt.
- The socket trusted the client's 32-bit length prefix and reserved that much memory up front.
  Frames are now capped at 16 MiB, both directions. The review proposed 1 MiB; that would have
  silently broken `debug-windows`, whose answer carries full Accessibility dumps.
- The menu bar's snapshot list scanned the disk on the main actor on every refresh. It now refreshes
  off the main actor, coalesced to at most once a second.

## Testing

`./build-debug.sh && ./swift-test.sh` for the fast loop, `./test.sh` before committing.

Unit tests use `TestWindow`, which never touches the Accessibility layer. Every bug that mattered in
this work was found by running the real app, not by the tests: the scratchpad focus drift, the empty
snapshot, and the `ctrl-c` binding. Test the real thing.

Two test traps, both hit:

- `XCTestCase.name` is `-[SomeTest testFoo]`. Interpolating it into a command string makes the
  parser see a flag. Use fixed workspace names.
- Every command run ends with `refreshModel_nonCancellable`, which garbage collects empty invisible
  workspaces. Don't cache a `Workspace` reference across a command run; look it up by name again.

## Open items

- `window-hints` should bind unused letters to `hide`, so any key exits the mode.
- Scratchpad and sticky membership don't survive a restart. Both would need the same stable window
  identity that `layout-snapshot` uses for matching.
- None of this has been offered upstream. `scratchpad` is the most likely candidate to be wanted by
  others.

## Config

`~/.aerospace.toml` now contains command names the released AeroSpace can't parse. Comment out the
`scratchpad`, `layout-snapshot`, `window-hints`, and `sticky` bindings before running the released
version.

Unrelated but found while reading that file: `ctrl-a`, `ctrl-b`, `ctrl-c`, and `ctrl-d` were bound
to workspace moves. AeroSpace registers hotkeys globally, so the terminal never received them, which
is why Ctrl-C would not interrupt anything. They are now `ctrl-shift-*`.
