import AppKit
import Common

/// Width of the focused column in the scrolling layout. See `ScrollingStrip`
struct ColumnWidthCommand: Command {
    let args: ColumnWidthCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        guard let column = window.scrollingColumn else {
            return .fail(io.err("The window isn't in a scrolling layout. Switch to one with 'layout --root scrolling'"))
        }
        let current = column.effectiveScrollingColumnWidth * 100
        let widths = args.widths.val
        let newWidth: CGFloat = switch widths.singleOrNil() {
            case .set(let percent): CGFloat(percent)
            case .add(let percent): current + CGFloat(percent)
            case .subtract(let percent): current - CGFloat(percent)
            case nil: nextPreset(after: current, widths)
        }
        column.scrollingColumnWidth = newWidth / 100
        return .succ
    }
}

/// The first preset wider than the current width, wrapping around to the first one. Half a percent of slack,
/// so that 33% counts as reached once the column is at a third
private func nextPreset(after current: CGFloat, _ widths: [ColumnWidthCmdArgs.Width]) -> CGFloat {
    let presets: [CGFloat] = widths.compactMap {
        if case .set(let percent) = $0 { CGFloat(percent) } else { nil }
    }
    return presets.first(where: { $0 > current + 0.5 }) ?? presets.first ?? current
}
