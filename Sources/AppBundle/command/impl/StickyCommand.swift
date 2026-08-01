import AppKit
import Common

/// Rebind every sticky window to the workspace that is currently active on its monitor.
///
/// AeroSpace's tree gives each window exactly one parent, so a window can't literally belong to all
/// workspaces at once. Instead the window is moved on every refresh, which keeps the invariant intact:
/// it is always attached to a visible workspace, and `layoutWorkspaces` only hides windows of
/// invisible ones.
@MainActor
func syncStickyWindows() {
    let sticky = Workspace.all.flatMap { $0.allLeafWindowsRecursive }.filter { $0.isSticky }
    if sticky.isEmpty { return }
    for window in sticky {
        // Follow the monitor the window sits on, not the focused one, otherwise a sticky window
        // would teleport between displays whenever focus moves
        guard let monitor = window.nodeMonitor else { continue }
        let target = monitor.activeWorkspace
        if target.isScratchpad || window.nodeWorkspace == target { continue }
        window.bindAsFloatingWindow(to: target)
    }
}

struct StickyCommand: Command {
    let args: StickyCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let newState: Bool = switch args.targetState.val {
            case .on: true
            case .off: false
            case .toggle: !window.isSticky
        }
        if newState == window.isSticky {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Window \(window.windowId) is already \(newState ? "sticky" : "not sticky"). Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }
        window.isSticky = newState
        if newState {
            // A sticky window must float. A tiling one would insert itself into the layout of every
            // workspace it visits and rearrange your windows behind your back
            if let workspace = window.nodeWorkspace {
                window.bindAsFloatingWindow(to: workspace)
            }
            syncStickyWindows()
        }
        return .succ
    }
}
