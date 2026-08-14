# aerospace-next review

## 1. What I think this code does

The app keeps a tree model of monitors, workspaces, tiling containers, floating containers, and windows, then reacts to macOS accessibility events and CLI/menu commands by refreshing that model, mutating the tree, and laying out visible workspaces. Commands resolve their target from explicit flags, environment variables, or current focus, run inside a light session, refresh the model before and after the mutation, update the tray/menu model, apply layouts, and schedule a heavier refresh afterward. The new scratchpad feature parks windows in internal `_scratchpad.<name>` workspaces, summons them back to a visible workspace, and hides them again by rebinding them between floating containers. The new sticky feature marks a window as sticky, forces it to float, and on refresh rebinds it to the active workspace of the monitor it currently belongs to. The new layout snapshot feature serializes a workspace's tiling tree as JSON, then restores by matching current windows by bundle id/name and title and rebuilding the target workspace's tiling tree.

## 2. Places where behavior differs from the described app

1. `hotkey-inventory.py` and `disable-space-shortcuts.py` are utility scripts for auditing hotkeys and changing macOS space shortcuts; they are not part of the tiling window manager behavior you described. I did not count these as app bugs because they are standalone helper scripts, not control flow used by the manager.
2. The in-app menu restores saved layouts from state files under `~/.local/state/aerospace/layouts`; that is an extra stateful layout-profile feature beyond "a tiling window manager based on a tree paradigm." I count only the concrete failure modes below, not the mere existence of the feature.

I found 4 concrete failure modes in the reviewed code.

## 3. Failure modes ranked by probability x damage

### 1. Sticky scratchpad windows escape the scratchpad on refresh

Probability x damage: high x high.

Trigger: mark a window sticky with `aerospace sticky on`, then move it to a scratchpad with `aerospace scratchpad move`; the next refresh path calls `refreshModel_nonCancellable`, which calls `syncStickyWindows`.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/command/impl/StickyCommand.swift:12`.

Why it fails: `syncStickyWindows` scans every workspace, including scratchpad workspaces, and moves every sticky window to `window.nodeMonitor.activeWorkspace`. A scratchpad workspace has a monitor approximation, so the hidden sticky window can be rebound to a normal visible workspace even though the scratchpad command just hid it.

Smallest fix:

```diff
--- a/Sources/AppBundle/command/impl/StickyCommand.swift
+++ b/Sources/AppBundle/command/impl/StickyCommand.swift
@@
-    let sticky = Workspace.all.flatMap { $0.allLeafWindowsRecursive }.filter { $0.isSticky }
+    let sticky = Workspace.all
+        .filter { !$0.isScratchpad }
+        .flatMap { $0.allLeafWindowsRecursive }
+        .filter { $0.isSticky }
```

### 2. Window hints uses a non-strict sort comparator

Probability x damage: medium x medium.

Trigger: run `aerospace window-hints show` with windows on multiple workspaces.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/command/impl/WindowHintsCommand.swift:32`.

Why it fails: `sorted { lhs, _ in lhs == focusedWorkspace }` is not a strict ordering because it can return `true` when comparing the focused workspace with itself, and it ignores the right-hand side. Swift's exact behavior with a non-strict comparator is not something I can rely on; the intended behavior is just "focused workspace first."

Smallest fix:

```diff
--- a/Sources/AppBundle/command/impl/WindowHintsCommand.swift
+++ b/Sources/AppBundle/command/impl/WindowHintsCommand.swift
@@
-        let ordered = workspaces.sorted { lhs, _ in lhs == focusedWorkspace }
+        let ordered = workspaces.filter { $0 == focusedWorkspace } +
+            workspaces.filter { $0 != focusedWorkspace }
```

### 3. Layout snapshot restore can match the wrong window when the same app has duplicate titles

Probability x damage: medium x medium.

Trigger: save a layout containing two windows from the same app with the same or empty title, scatter/reopen them, then run `aerospace layout-snapshot restore <name>`.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift:143`.

Why it fails: restore matches by app bundle id, then by exact title if present, otherwise by the first candidate. Duplicate editor/browser/terminal windows commonly have identical titles, so a restore can silently swap them while still reporting success.

Smallest fix:

```diff
--- a/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift
+++ b/Sources/AppBundle/command/impl/LayoutSnapshotCommand.swift
@@
-        if let title = node.windowTitle, !title.isEmpty,
-           let exact = candidates.first(where: { titles[$0.windowId] == title })
+        if let title = node.windowTitle, !title.isEmpty {
+            let exactMatches = candidates.filter { titles[$0.windowId] == title }
+            if exactMatches.count == 1, let exact = exactMatches.first
         {
             return exact
         }
```

This does not fully solve duplicate matching, but it avoids pretending an ambiguous title match is exact.

### 4. Layout snapshot names allow shell-hostile filenames

Probability x damage: medium x low.

Trigger: run `aerospace layout-snapshot save 'a b'`, `save '--foo'`, or `save 'x\nbar'`, then try to restore/delete/list snapshots from scripts or the menu.

File and line: `/Users/bogac/dev/forgejo/aerospace-next/Sources/AppBundle/layoutSnapshot.swift:77`.

Why it fails: validation only rejects empty names, `/`, and leading `.`, so names with whitespace, control characters, or option-looking prefixes become state files and menu labels. That does not break tiling immediately, but it makes the CLI state feature behave unlike a reliable command surface.

Smallest fix:

```diff
--- a/Sources/AppBundle/layoutSnapshot.swift
+++ b/Sources/AppBundle/layoutSnapshot.swift
@@
-    if name.contains("/") || name.hasPrefix(".") {
-        return .failure("Snapshot name \(name.singleQuoted) must not contain '/' or start with '.'")
+    if name.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == nil {
+        return .failure("Snapshot name \(name.singleQuoted) must contain only letters, digits, '_' or '-'")
```

## 4. Correctness risks I could not verify without running the code

1. Existing tests did not run in this checkout. `swift test` first failed under the sandbox, then after approval failed because precompiled modules in `.build` refer to `/Users/bogac/dev/forgejo/AeroSpace` while the checkout is `/Users/bogac/dev/forgejo/aerospace-next`. Test that settles it: clean build artifacts outside this review, then run `swift test`.
2. I could not verify whether scratchpad windows are always physically hidden after `scratchpad move`, because that depends on the async refresh/layout cycle and macOS Accessibility behavior. Test that settles it: launch the app, move a visible floating and tiling window to the scratchpad, wait for one complete refresh, and assert both windows are offscreen and absent from the visible workspace tree.
3. I could not verify whether sticky windows follow the correct display through monitor attach/detach on Mac Studio and MacBook Pro. Test that settles it: with two monitors, mark a window sticky, switch workspaces on each display, disconnect/reconnect a display, and assert the sticky window remains on the active workspace of the same physical display or has a defined fallback.
4. I could not verify whether layout snapshot restore preserves weights after `runLightSession` normalizes containers. Test that settles it: create a nested split with non-equal weights, save, scramble, restore, then assert root/nested orientations, layouts, window order, and child weights.
