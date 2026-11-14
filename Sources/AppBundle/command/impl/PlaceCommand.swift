import AppKit
import Common

/// Put a window at a fixed position and size.
///
/// Coordinates are relative to the visible area of the window's monitor: below the menu bar and
/// clear of the Dock, with (0, 0) at its top-left corner. So `--x 0 --y 50%` means the left edge,
/// halfway down, on whichever display the window is on.
struct PlaceCommand: Command {
    let args: PlaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }

        // A tiled window's frame belongs to the layout and would be overwritten on the next refresh.
        // Floating windows keep whatever frame they're given, so placing implies floating
        if !window.isFloating {
            guard let workspace = window.nodeWorkspace else {
                return .fail(io.err("Window \(window.windowId) doesn't belong to a workspace, so it can't be placed"))
            }
            window.bindAsFloatingWindow(to: workspace)
        }

        let area = (window.nodeMonitor ?? target.workspace.workspaceMonitor).visibleRect
        var topLeft: CGPoint? = nil
        if let x = args.x, let y = args.y {
            topLeft = CGPoint(
                x: area.topLeftX + x.resolve(against: area.width),
                y: area.topLeftY + y.resolve(against: area.height),
            )
        }
        var size: CGSize? = nil
        if let width = args.width, let height = args.height {
            size = CGSize(width: width.resolve(against: area.width), height: height.resolve(against: area.height))
        }
        if let size {
            // Remembered so that the window comes back at this size after being hidden in a corner
            window.lastFloatingSize = size
        }
        // Otherwise the next layout pass would stretch the window back over the screen
        window.isFullscreen = false
        window.setAxFrame(topLeft, size)
        return .succ
    }
}
