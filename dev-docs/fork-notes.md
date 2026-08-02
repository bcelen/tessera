# Fork notes

Personal fork of AeroSpace with four commands that upstream doesn't have. Written down so that
neither I nor a future Claude session has to reconstruct the reasoning.

Added: `scratchpad`, `layout-snapshot`, `window-hints`, `sticky`.

## Running it

This fork is not installed as an app. It runs as the SPM debug binary:

```
cd ~/dev/forgejo/AeroSpace
./run-debug.sh                # occupies the terminal
# or, detached:
nohup ./.debug/AeroSpaceApp > /tmp/aerospace.log 2>&1 &
```

Nothing starts it at login. See "Open items" below.

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

Save a workspace's tiling tree to `~/.local/state/aerospace/layouts/<name>.json`, restore it later.

Per window it records the app bundle id, app name, and window title. Per container, the orientation,
the layout, and each child's share of its parent as a fraction, so proportions survive a move to a
different monitor. Weights are applied top down after the tree is built, because a fraction is
meaningless until the parent's own weight is final.

Decisions, all of which were explicit choices and are reversible:

- Restore never launches anything. Slots with no matching window collapse.
- Matching is by bundle id, preferring an exact window-title match, falling back to any unused
  window of that app.
- Restore considers windows on the target workspace first, then windows anywhere else. This is what
  makes it useful after a restart, and it also means restoring mid-task yanks windows off other
  workspaces.
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
stay in the mode with no feedback. Reloading the config while the panel is open also strands you
there. `aerospace mode main` is the escape hatch. The fix is to bind every remaining letter to
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

- No autostart. The launch agent approach failed: launchd launches the bare binary directly, and an
  unsigned executable with no bundle identifier has nothing for TCC to attach an Accessibility grant
  to. When Terminal launches it, Terminal is the responsible process and its grant covers it. The
  real fix is a signed build. Create the self-signed `aerospace-codesign-certificate` described in
  `development.md`, then either sign the debug binary or run `build-release.sh`. The release script
  also runs `build-docs.sh` and `build-shell-completion.sh`, which want Ruby, Rust, and fish, so
  trimming those two lines for a personal build is the cheaper path.
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
