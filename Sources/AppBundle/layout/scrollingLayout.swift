import AppKit
import Common

/// Narrowest a column may get, as a fraction of the screen
let minScrollingColumnWidth: CGFloat = 0.1

private let columnWidthKey = TreeNodeUserDataKey<CGFloat>(key: "scrollingColumnWidth")
private let scrollOffsetKey = TreeNodeUserDataKey<CGFloat>(key: "scrollOffset")

extension TreeNode {
    /// Width of the node as a column of a scrolling container, as a fraction of the screen. Nil means
    /// `scrolling-default-column-width`. Kept on the node, so a column keeps its width while it moves
    @MainActor var scrollingColumnWidth: CGFloat? {
        get { getUserData(key: columnWidthKey) }
        set {
            if let newValue {
                putUserData(key: columnWidthKey, data: newValue.coerce(in: minScrollingColumnWidth ... 1))
            } else {
                cleanUserData(key: columnWidthKey)
            }
        }
    }

    @MainActor var effectiveScrollingColumnWidth: CGFloat {
        scrollingColumnWidth ?? (CGFloat(config.scrollingDefaultColumnWidth) / 100).coerce(in: minScrollingColumnWidth ... 1)
    }

    /// The column of the closest scrolling container this node is in, if any
    @MainActor var scrollingColumn: TreeNode? {
        parentsWithSelf.first(where: { ($0.parent as? TilingContainer)?.layout == .scrolling })
    }
}

extension TilingContainer {
    /// How far the strip is scrolled, in points. Remembered between layouts, so the view only moves
    /// when focus leaves it
    @MainActor var scrollOffset: CGFloat {
        get { getUserData(key: scrollOffsetKey) ?? 0 }
        set { putUserData(key: scrollOffsetKey, data: newValue) }
    }

    /// The length of the visible part of the strip and the gap between its columns
    @MainActor var scrollingViewport: (length: CGFloat, gap: CGFloat)? {
        guard let workspace = nodeWorkspace else { return nil }
        let rect = workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        let gap = CGFloat(ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor).inner.get(orientation))
        return (orientation == .h ? rect.width : rect.height, gap)
    }
}

/// Converts between a column's width fraction and its size in points. A column of width f takes f of the
/// viewport including its share of the gaps, so that two halves and the gap between them fill it exactly
func scrollingColumnSize(width: CGFloat, viewport: CGFloat, gap: CGFloat) -> CGFloat {
    max(1, width * (viewport + gap) - gap)
}

func scrollingColumnWidth(size: CGFloat, viewport: CGFloat, gap: CGFloat) -> CGFloat {
    viewport + gap > 0 ? (size + gap) / (viewport + gap) : 1
}

/// Where the columns of a scrolling container go. Pure, so the arithmetic can be tested without windows.
/// All positions are along the container's orientation
struct ScrollingStrip: Equatable {
    /// Size of every column
    let sizes: [CGFloat]
    /// Start of every column, relative to the start of the visible area. Negative or past the viewport
    /// means the column is partly or fully out of view
    let starts: [CGFloat]
    /// How far the strip is scrolled
    let offset: CGFloat

    /// - Parameters:
    ///   - columnWidths: fractions of the viewport, see `TreeNode.scrollingColumnWidth`
    ///   - focusedIndex: the column that must be fully in view
    ///   - peek: how much of the neighbouring columns to keep in view around the focused one, room permitting
    ///   - previousOffset: the offset from the last layout. The strip scrolls as little as possible from it
    init(columnWidths: [CGFloat], focusedIndex: Int, viewport: CGFloat, gap: CGFloat, peek: CGFloat, previousOffset: CGFloat) {
        let sizes = columnWidths.map { scrollingColumnSize(width: $0.coerce(in: minScrollingColumnWidth ... 1), viewport: viewport, gap: gap) }
        var absoluteStarts: [CGFloat] = []
        var cursor: CGFloat = 0
        for size in sizes {
            absoluteStarts.append(cursor)
            cursor += size + gap
        }
        let length = max(0, cursor - gap)

        var offset = previousOffset
        if sizes.indices.contains(focusedIndex) {
            let start = absoluteStarts[focusedIndex]
            let end = start + sizes[focusedIndex]
            var before = focusedIndex > 0 ? max(0, peek) : 0
            var after = focusedIndex < sizes.count - 1 ? max(0, peek) : 0
            // Peeking must never push the focused column itself out of view
            let room = max(0, viewport - sizes[focusedIndex])
            if before + after > room {
                let scale = room / (before + after)
                before *= scale
                after *= scale
            }
            if end + after > offset + viewport { offset = end + after - viewport }
            // Second, so that the start of a column wider than the viewport wins over its end
            if start - before < offset { offset = start - before }
        }
        offset = offset.coerce(in: 0 ... max(0, length - viewport))

        self.sizes = sizes
        self.starts = absoluteStarts.map { $0 - offset }
        self.offset = offset
    }
}

extension Monitor {
    /// Whether another monitor sits directly before (left or above) and after (right or below) this one.
    /// A column partly out of view would show up on that monitor, so it is hidden instead
    @MainActor func neighbours(_ orientation: Orientation) -> (before: Bool, after: Bool) {
        let rect = self.rect
        // Any monitor touching the edge counts, even one that covers only part of it, since a column runs the
        // whole height (or width) of the screen
        func touches(_ other: Rect, atEdge edge: CGFloat, isAfter: Bool) -> Bool {
            let (near, lo, hi, otherLo, otherHi) = orientation == .h
                ? (isAfter ? other.minX : other.maxX, rect.minY, rect.maxY, other.minY, other.maxY)
                : (isAfter ? other.minY : other.maxY, rect.minX, rect.maxX, other.minX, other.maxX)
            return abs(near - edge) <= 1 && otherLo < hi && otherHi > lo
        }
        let others = monitors.map(\.rect)
        let (beforeEdge, afterEdge) = orientation == .h ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
        return (
            others.contains { touches($0, atEdge: beforeEdge, isAfter: false) },
            others.contains { touches($0, atEdge: afterEdge, isAfter: true) },
        )
    }
}
