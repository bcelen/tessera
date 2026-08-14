# aerospace-next second review

## 1. What I think this code does

The app keeps an in-memory tree of monitors, workspaces, containers, and windows, and uses that tree as the source of truth for tiling, focus, and command behavior. macOS Accessibility events and CLI/menu commands enter refresh sessions, refresh the native window model, mutate the tree, update focus/tray state, and then lay out visible workspaces while hiding invisible ones. Scratchpads are implemented as internal `_scratchpad.<name>` workspaces whose windows are moved in and out as floating windows. Sticky windows are marked on the `Window` object and are re-bound on refresh to the active workspace of the monitor they currently belong to, except now scratchpad workspaces are excluded as a source. Layout snapshots serialize the tiling tree of one workspace to JSON, then restore by matching live windows from a pool and rebuilding the target workspace's tiling containers.

## 2. Places where code does something other than described

1. The fork is still runtime-labelled as upstream AeroSpace in app id, app name, Xcode product, config paths, socket path, and snapshot state path. If "relabelled as aerospace-next" means the fork should run independently from upstream AeroSpace, this is not just naming: it shares identity and state with the original app.
2. `./swift-test.sh` says the Swift tests passed, but with the current Swift toolchain it runs the Swift Testing runner and reports `0 tests in 0 suites`; the XCTest suite is not exercised unless XCTest is explicitly enabled.
3. Layout snapshots still cannot distinguish two same-app/same-title windows, even during the same app run when `windowId` would be available.

I found 3 concrete failure modes in the current code.

## 3. Failure modes ranked by probability x damage

### 1. The fork collides with upstream AeroSpace identity and state

Probability x damage: high x high.

Trigger: install or run `aerospace-next` on a machine that also has upstream AeroSpace config/state/socket assumptions, or try to run both while testing the fork.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/Common/appMetadata.swift:1`, `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/config/ConfigFile.swift:4`, `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/config/ConfigFile.swift:13`, `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/server.swift:23`, `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/layoutSnapshot.swift:70`, `/Users/bogac/dev/forgejo/aerospace-next/xcode/project.yml:4`, `/Users/bogac/dev/forgejo/aerospace-next/xcode/project.yml:39`, `/Users/bogac/dev/forgejo/aerospace-next/xcode/project.yml:40`, `/Users/bogac/dev/forgejo/aerospace-next/xcode/project.yml:42`, `/Users/bogac/dev/forgejo/aerospace-next/xcode/project.yml:43`.

Why it fails: the code still uses `bobko.aerospace`, `AeroSpace`, `.aerospace.toml`, `.config/aerospace/aerospace.toml`, `/tmp/bobko.aerospace-<user>.sock`, and `~/.local/state/aerospace/layouts`. That can make the fork read upstream config, share layout snapshots, talk to or disable the wrong server, and install as the same app bundle id.

Smallest fix:

```diff
--- a/Sources/Common/appMetadata.swift
+++ b/Sources/Common/appMetadata.swift
@@
-public let stableAeroSpaceAppId: String = "bobko.aerospace"
+public let stableAeroSpaceAppId: String = "bogac.aerospace-next"
@@
-    public let aeroSpaceAppName: String = "AeroSpace-Debug"
+    public let aeroSpaceAppName: String = "aerospace-next-debug"
@@
-    public let aeroSpaceAppName: String = "AeroSpace"
+    public let aeroSpaceAppName: String = "aerospace-next"
```

```diff
--- a/Sources/AppBundle/config/ConfigFile.swift
+++ b/Sources/AppBundle/config/ConfigFile.swift
@@
-let configDotfileName = ".aerospace.toml"
+let configDotfileName = ".aerospace-next.toml"
@@
-                xdgConfigHome.appending(path: "aerospace").appending(path: "aerospace.toml"),
+                xdgConfigHome.appending(path: "aerospace-next").appending(path: "aerospace-next.toml"),
```

Also make the same namespace change in `layoutSnapshotsDir()` and `xcode/project.yml`.

### 2. The test script reports success while running zero tests

Probability x damage: high x high for future changes.

Trigger: run exactly what you ran: `./build-debug.sh && ./swift-test.sh`.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/swift-test.sh:5`.

Why it fails: `swift test` currently returns success with `0 tests in 0 suites` in this checkout. I verified the real XCTest suite with `swift test --enable-xctest --disable-swift-testing`; that ran 399 tests with 0 failures, including `StickyCommandTest/testStickyWindowStaysInTheScratchpad`.

Smallest fix:

```diff
--- a/swift-test.sh
+++ b/swift-test.sh
@@
-if swift test \
+if swift test --enable-xctest --disable-swift-testing \
```

### 3. Layout snapshot restore still silently swaps indistinguishable duplicate windows

Probability x damage: medium x medium.

Trigger: in one running session, open two windows from the same app with the same title, save a layout, move those windows around, then restore the snapshot.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift:143`.

Why it fails: the response is right that my earlier diff was not a working fix. The conclusion that no fix exists is too strong: for same-session restores, the snapshot can store `windowId` and prefer that before falling back to app/title matching. That will not solve post-restart identity, but it prevents unnecessary swaps when the original windows are still alive.

Smallest fix:

```diff
--- a/Sources/AppBundle/layoutSnapshot.swift
+++ b/Sources/AppBundle/layoutSnapshot.swift
@@
     var windowTitle: String?
+    var windowId: UInt32?
@@
             windowTitle: title,
+            windowId: window.windowId,
```

```diff
--- a/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift
+++ b/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift
@@
         let candidates = pool.filter { !used.contains($0.windowId) && isSameApp($0, node) }
+        if let id = node.windowId, let exact = candidates.first(where: { $0.windowId == id }) {
+            return exact
+        }
```

## 4. Correctness risks I could not verify without running the app

1. Whether scratchpad windows are physically hidden in real macOS windows after the focus-drift fix. Test that settles it: run the app, move one real tiling window and one real floating window to the scratchpad, wait for a full refresh, and assert neither is visible on the active workspace.
2. Whether sticky windows follow the intended physical display through monitor attach/detach. Test that settles it: on two monitors, mark a window sticky, switch workspaces on each display, disconnect and reconnect one display, and assert the window follows the intended monitor rather than focus.
3. Whether layout snapshot weights survive restore plus normalization for nested non-equal splits. Test that settles it: create nested horizontal/vertical splits with non-equal weights, save, scramble, restore, and assert order, layout, orientation, and weights.
4. Whether the `aerospace-next` relabel is intended to keep upstream config/state for migration. Test that settles it: explicitly decide whether upstream and fork should coexist; if yes, run both with separate config, socket, bundle id, and state directories.
