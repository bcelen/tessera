# Response to the aerospace-next review

Thanks, this was useful. Two of the four findings are real bugs and I've fixed both. The other two
point at real risks, but the patches don't do what they claim, so I've handled those differently.
Details below, in your numbering.

## 1. Sticky scratchpad windows escape the scratchpad

Correct, and it's the best catch in the review. Fixed as proposed.

The root cause is narrower than "syncStickyWindows scans every workspace." I had a guard, but it only
covered one direction:

```swift
if target.isScratchpad || window.nodeWorkspace == target { continue }
```

That stops a sticky window being dragged *into* a scratchpad. It does nothing about a window already
sitting in one, because the target is then a perfectly ordinary visible workspace. So the window gets
pulled back out on the next refresh, silently undoing `scratchpad move`.

`syncStickyWindows` now filters scratchpad workspaces out of the source list. I've added a test that
marks a window sticky, parks it, forces a refresh with a workspace switch, and asserts it's still
parked. It fails on the old code.

## 2. Window hints uses a non-strict sort comparator

Correct. Fixed as proposed.

`sorted { lhs, _ in lhs == focusedWorkspace }` ignores its right operand, so it isn't a strict weak
ordering and Swift's sort is entitled to trap on it. Partitioning is both correct and easier to read,
and it preserves the name ordering that `Workspace.all` already provides.

## 3. Layout snapshot restore can match the wrong window on duplicate titles

The observation is right. The patch isn't.

Falling through from "several exact title matches" to `candidates.first` returns the same window,
because the candidate list is in the same order either way. So the diff changes the code path without
changing the outcome. As written it also has an unbalanced brace and wouldn't compile.

More to the point, I cannot convince myself there's a fix here at all. When two windows of the same
app carry the same title, the snapshot holds no information that distinguishes them. What the code
actually does is assign duplicates positionally: candidates are filtered to unused windows and taken
in order, and snapshot slots are visited in DFS order, so the first unused window goes to the first
slot. That's deterministic and it's the only rule available without stable window identity.

The real gap is that this rule was undocumented. It's now written down in `dev-docs/fork-notes.md`.
Persisting identity across restarts is on the open list, and it would fix this properly along with
scratchpad and sticky membership not surviving a restart.

## 4. Snapshot names allow shell-hostile filenames

The risk is real. The proposed regex is too strict.

`^[A-Za-z0-9_-]+$` rejects `ödev`, and I name things in Turkish often enough for that to matter. It's
also stricter than the problem requires: nothing goes wrong with a space in a filename here, since
the name arrives as a positional argument and never reaches a shell.

What actually breaks is path traversal, a leading dot hiding the file, a leading dash reading as a
flag, and control characters mangling `list` output and menu labels. Validation now rejects exactly
those and leaves letters alone.

One of your triggers can't occur, by the way. `layout-snapshot save '--foo'` fails earlier, in the
argument parser, as an unknown flag. It never reaches name validation.

## On the four things you couldn't verify

**Stale build artifacts.** Confirmed, and thanks for pinning it down. `.build` and
`xcode/.xcode-build` still referenced `/Users/bogac/dev/forgejo/AeroSpace` from before the rename.
Removed both and rebuilt; the suite passes.

**Whether scratchpad windows are physically hidden.** They are. This one was tested by hand rather
than in code, and it also surfaced something static reading wouldn't: clicking a corner-hidden window
pulls macOS focus to it, AeroSpace syncs its own focus from macOS, and you end up focused inside the
scratchpad workspace. `toggle` then had nothing to hide and there was no way out. That's fixed, and
it's the failure mode I'd have ranked first.

**Monitor attach and detach.** Not verified. I'm on a single display, so the multi-monitor path is
reasoned about but untested. The intent is that a sticky window follows the active workspace of the
monitor it sits on rather than the focused workspace, which is why `syncStickyWindows` reads
`window.nodeMonitor` instead of `focus`.

**Whether weights survive normalization.** Not verified either, though I think they do:
`unbindEmptyAndAutoFlatten` rebinds a collapsed container's single child with
`previousBinding.adaptiveWeight`, so flattening carries the weight across. Your suggested test is the
right one and I haven't written it.

## Not addressed

`hotkey-inventory.py` and `disable-space-shortcuts.py` are exactly what you took them for: standalone
helpers, not part of the window manager. Layout snapshots are a deliberate addition rather than
scope creep. The whole point of this fork is four commands upstream doesn't have.
