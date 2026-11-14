import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        let orientation: Orientation?
        let parent: TilingContainer?
        let node: TreeNode?
        switch args.dimension.val {
            case .width:
                orientation = .h
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .height:
                orientation = .v
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .smart:
                node = candidates.first
                parent = node?.parent as? TilingContainer
                orientation = parent?.orientation
            case .smartOpposite:
                orientation = (candidates.first?.parent as? TilingContainer)?.orientation.opposite
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
        }
        guard let parent else {
            if let result = resizeScrollingColumn(target.windowOrNil, args) { return result }
            return .fail(io.err("resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9"))
        }
        guard let orientation else { return .fail }
        guard let node else { return .fail }
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else { return .fail }
        let updates = parent.children.map { child in
            (child, child.getWeight(orientation) + (child == node ? diff : -childDiff))
        }
        guard updates.allSatisfy({ $0.1.isFinite && $0.1 > 0 }) else {
            return .fail(io.err("Resize would make a tile non-positive"))
        }
        for (child, weight) in updates {
            child.setWeight(orientation, weight)
        }
        return .succ
    }
}

/// In the scrolling layout a column has a size of its own rather than a share of the screen, so resizing it
/// leaves the other columns alone. Nil if the window isn't in a column that can be resized that way
@MainActor
private func resizeScrollingColumn(_ window: Window?, _ args: ResizeCmdArgs) -> BinaryExitCode? {
    guard let column = window?.scrollingColumn, let strip = column.parent as? TilingContainer else { return nil }
    let orientation: Orientation? = switch args.dimension.val {
        case .width: .h
        case .height: .v
        case .smart: strip.orientation
        case .smartOpposite: nil
    }
    guard orientation == strip.orientation, let (viewport, gap) = strip.scrollingViewport else { return nil }
    let size = scrollingColumnSize(width: column.effectiveScrollingColumnWidth, viewport: viewport, gap: gap)
    let newSize: CGFloat = switch args.units.val {
        case .set(let unit): CGFloat(unit)
        case .add(let unit): size + CGFloat(unit)
        case .subtract(let unit): size - CGFloat(unit)
    }
    column.scrollingColumnWidth = scrollingColumnWidth(size: newSize, viewport: viewport, gap: gap)
    return .succ
}
