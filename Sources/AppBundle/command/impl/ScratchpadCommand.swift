import AppKit
import Common

/// Windows that belong to a scratchpad are parked in a dedicated workspace that is never assigned to a monitor.
/// Such workspaces are hidden the same way any invisible workspace is hidden (see `hideInCorner`).
/// The name is prefixed with an underscore, which `WorkspaceName.parse` reserves, so that users can't reach the
/// workspace by accident with `workspace`, `move-node-to-workspace`, etc.
let scratchpadWorkspacePrefix = "_scratchpad."

extension Workspace {
    @MainActor
    static func getScratchpad(_ name: String) -> Workspace {
        Workspace.get(byName: scratchpadWorkspacePrefix + name)
    }

    var isScratchpad: Bool { name.starts(with: scratchpadWorkspacePrefix) }
}

struct ScratchpadCommand: Command {
    let args: ScratchpadCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        switch args.action.val {
            case .move: return move(env, io)
            case .release: return release(env, io)
            case .show: return show(io)
            case .hide: return hide(io)
            case .toggle: return isSummonedOnFocusedWorkspace ? hide(io) : show(io)
        }
    }

    /// Windows tagged with this scratchpad that currently live outside of the scratchpad workspace
    @MainActor
    private var summonedWindows: [Window] {
        Workspace.all
            .filter { !$0.isScratchpad }
            .flatMap { $0.allLeafWindowsRecursive }
            .filter { $0.scratchpadName == args.name }
    }

    @MainActor
    private var isSummonedOnFocusedWorkspace: Bool {
        let workspace = focus.workspace
        // If focus somehow ended up inside the scratchpad itself, the window is hidden, not summoned.
        // Reporting it as summoned would make `toggle` pick `hide`, which has nothing to hide
        return !workspace.isScratchpad && workspace.allLeafWindowsRecursive.contains { $0.scratchpadName == args.name }
    }

    /// A workspace that a summoned window can be moved to. Never a scratchpad workspace, otherwise
    /// `show` would be unable to get a window back out
    @MainActor
    private func visibleWorkspace(for window: Window) -> Workspace {
        let focused = focus.workspace
        if !focused.isScratchpad { return focused }
        let source = window.scratchpadSourceWorkspace.map { (name: String) in Workspace.get(byName: name) }
        return source?.takeIf { !$0.isScratchpad }
            ?? prevFocusedWorkspace?.takeIf { !$0.isScratchpad }
            ?? Workspace.get(byName: "1")
    }

    @MainActor
    private func move(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let scratchpad = Workspace.getScratchpad(args.name)
        if window.nodeWorkspace == scratchpad {
            return noop(io, "Window \(window.windowId) is already in scratchpad '\(args.name)'")
        }
        // Remembered so that `show` can put the window back on a real workspace even if focus itself
        // has drifted into the scratchpad
        window.scratchpadSourceWorkspace = window.nodeWorkspace?.takeIf { !$0.isScratchpad }?.name
        window.scratchpadName = args.name
        window.bindAsFloatingWindow(to: scratchpad)
        return .succ
    }

    @MainActor
    private func release(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        if window.scratchpadName == nil {
            return noop(io, "Window \(window.windowId) doesn't belong to any scratchpad")
        }
        window.scratchpadName = nil
        if window.nodeWorkspace?.isScratchpad == true {
            window.bindAsFloatingWindow(to: visibleWorkspace(for: window))
            window.scratchpadSourceWorkspace = nil
            return .from(bool: window.focusWindow())
        }
        window.scratchpadSourceWorkspace = nil
        return .succ
    }

    @MainActor
    private func show(_ io: CmdIo) -> BinaryExitCode {
        let scratchpad = Workspace.getScratchpad(args.name)
        // Prefer an already summoned window, so that `show` always brings the window to the focused workspace
        // instead of dragging one more window out of the scratchpad
        let window = summonedWindows.first
            ?? scratchpad.mostRecentWindowRecursive
            ?? scratchpad.anyLeafWindowRecursive
        guard let window else {
            return noop(io, "Scratchpad '\(args.name)' is empty. Put a window there with 'aerospace-next scratchpad move'")
        }
        let targetWorkspace = visibleWorkspace(for: window)
        if window.nodeWorkspace != targetWorkspace {
            window.bindAsFloatingWindow(to: targetWorkspace)
        }
        return .from(bool: window.focusWindow())
    }

    @MainActor
    private func hide(_ io: CmdIo) -> BinaryExitCode {
        let windows = summonedWindows
        if windows.isEmpty {
            return noop(io, "No window of scratchpad '\(args.name)' is currently summoned")
        }
        let scratchpad = Workspace.getScratchpad(args.name)
        for window in windows {
            window.bindAsFloatingWindow(to: scratchpad)
        }
        return .succ
    }

    @MainActor
    private func noop(_ io: CmdIo, _ msg: String) -> BinaryExitCode {
        return switch args.failIfNoop {
            case true: .fail
            case false: .succ(io.err("\(msg). Tip: use --fail-if-noop to exit with non-zero code"))
        }
    }
}
