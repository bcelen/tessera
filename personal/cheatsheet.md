# AeroSpace cheat sheet

55 bindings, no modes. Two rules: **Option is AeroSpace**, **Control is windows**.

## Option: where you go

| Keys | Does |
|---|---|
| `⌥1` … `⌥7` | Go to workspace 1 through 7 |
| `⌥W` `⌥X` `⌥Y` `⌥Z` | Go to lettered workspace |
| `` ⌥` `` | Back to the last workspace you were on |

## Option: what things look like

| Keys | Does |
|---|---|
| `⌥/` | Tiles |
| `⌥,` | Accordion |
| `⌥.` | Toggle floating and tiling |
| `⌥F` | Flatten the workspace tree |
| `⌥−` | Resize smaller |
| `⌥=` | Resize bigger |

## Option: your fork only

Not in released AeroSpace. Comment these out before running a stock build.

| Keys | Does |
|---|---|
| `⌥Z` | Toggle the scratchpad |
| `⌥⇧Z` | Send this window to the scratchpad |
| `⌥H` | Show window hints |
| `⌥T` | Toggle sticky |

## Option: layouts

Plain restores, shift saves. Same digit either way.

| Keys | Does |
|---|---|
| `⌥⌘1` `⌥⌘2` `⌥⌘3` `⌥⌘4` | Restore teaching / research / writing / admin |
| `⌥⇧⌘1` … `⌥⇧⌘4` | Save into that slot, overwriting it |

## Option: the two dangerous ones

Both need shift because one reloads and the other closes windows.

| Keys | Does |
|---|---|
| `⌥⇧R` | Reload the config |
| `⌥⇧⌫` | Close every window except this one |

## Control: windows

| Keys | Does |
|---|---|
| `⌃←` `⌃↓` `⌃↑` `⌃→` | Move focus |
| `⌃⇧←` `⌃⇧↓` `⌃⇧↑` `⌃⇧→` | Move the window |
| `⌃⌥←` `⌃⌥↓` `⌃⌥↑` `⌃⌥→` | Join with the neighbour |
| `⌃1` … `⌃7` | Send this window to that workspace and follow it |
| `⌃⇧W` … `⌃⇧Z` | Same, lettered workspaces |

Letters use `⌃⇧` rather than plain `⌃` because `⌃A`, `⌃B`, `⌃D` and `⌃E` are
readline bindings that every macOS text field honors. Binding them globally
breaks start-of-line and end-of-line everywhere.

## Not AeroSpace

| Keys | Does |
|---|---|
| tap Caps Lock | Escape |
| hold Caps Lock | Hyper, `⌃⌥⇧⌘`. Keyboard Maestro owns this layer. |
| `⌃⌥⇧⌘K` `L` `N` `S` | Skim, Elgato lights, Notes, Sleep Screen |
| `⌘R` `⌘A` `⌘E` `⌘F` `⌘J` `⌘D` | Keyboard Maestro, Outlook only |

## macOS shortcuts that had to go

Turned off so Control could have the arrows. Undo with
`disable-space-shortcuts.py --restore <backup>`.

`⌃↑` `⌃↓` `⌃←` `⌃→` `⌃⇧↑` `⌃⇧↓` `⌃⇧←` `⌃⇧→`

Six were native Spaces, which AeroSpace does not use anyway. Mission Control on
`⌃↑` is the only real loss; three-finger swipe up still does it.

## Starting it

The fork is not installed as an app and nothing starts it at login. Launch from
Terminal, never from Finder or a launch agent: the binary is unsigned and only
inherits Accessibility permission through Terminal as the responsible process.

```
cd ~/dev/forgejo/AeroSpace
nohup ./.debug/AeroSpaceApp > /tmp/aerospace.log 2>&1 &
```

Config errors print at startup, so `/tmp/aerospace.log` is where you find out
whether your bindings parsed.
