import AppKit

extension Workspace {
    /// - Parameter hideCorner: where columns scrolled out of view are hidden. Nil means nothing may be hidden,
    ///   so scrolling containers are laid out as tiles instead
    @MainActor
    func layoutWorkspace(hideCorner: OptimalHideCorner?) async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect, LayoutContext(self, hideCorner: hideCorner))
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                try await workspace.floatingWindowsContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
            case .floatingWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId {
                    lastAppliedLayoutVirtualRect = virtual
                    if window.isFullscreen && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        window.isFullscreen = false
                        window.setAxFrame(point, CGSize(width: width, height: height))
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                switch container.layout {
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .accordion:
                        try await container.layoutAccordion(point, width: width, height: height, virtual: virtual, context)
                    case .scrolling:
                        if let hideCorner = context.hideCorner {
                            try await container.layoutScrolling(point, width: width, height: height, hideCorner: hideCorner, context)
                        } else {
                            try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                        }
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps
    let hideCorner: OptimalHideCorner?

    @MainActor
    init(_ workspace: Workspace, hideCorner: OptimalHideCorner?) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        self.hideCorner = hideCorner
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let windowRect = try await getAxRect(.cancellable) // Probably not idempotent
        let currentMonitor = windowRect?.center.monitorApproximation
        if let currentMonitor, let windowRect, workspace != currentMonitor.activeWorkspace {
            let windowTopLeftCorner = windowRect.topLeftCorner
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let workspaceRect = workspace.workspaceMonitor.visibleRect
            var newX = workspaceRect.topLeftX + xProportion * workspaceRect.width
            var newY = workspaceRect.topLeftY + yProportion * workspaceRect.height

            let windowWidth = windowRect.width
            let windowHeight = windowRect.height
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
        }
        if isFullscreen {
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        guard let delta = ((orientation == .h ? width : height) - CGFloat(children.sumOfDouble { $0.getWeight(orientation) }))
            .div(children.count) else { return }

        let lastIndex = children.indices.last
        for (i, child) in children.enumerated() {
            child.setWeight(orientation, child.getWeight(orientation) + delta)
            let rawGap = context.resolvedGaps.inner.get(orientation).toDouble()
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child   let rawGap = gaps.inner.get(orientation).toDouble()
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            try await child.layoutRecursive(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? child.hWeight - gap : width,
                height: orientation == .v ? child.vWeight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? child.hWeight : width,
                    height: orientation == .v ? child.vWeight : height,
                ),
                context,
            )
            virtualPoint = orientation == .h ? virtualPoint.addingXOffset(child.hWeight) : virtualPoint.addingYOffset(child.vWeight)
            point = orientation == .h ? point.addingXOffset(child.hWeight) : point.addingYOffset(child.vWeight)
        }
    }

    @MainActor
    fileprivate func layoutAccordion(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        for (index, child) in children.enumerated() {
            let padding = CGFloat(config.accordionPadding)
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
        }
    }

    /// Columns keep their own size and sit on a strip that scrolls so the focused column is in view. Columns
    /// out of view are hidden in the corner, the same way windows of invisible workspaces are
    @MainActor
    fileprivate func layoutScrolling(_ point: CGPoint, width: CGFloat, height: CGFloat, hideCorner: OptimalHideCorner, _ context: LayoutContext) async throws {
        let viewport = orientation == .h ? width : height
        let gap = context.resolvedGaps.inner.get(orientation).toDouble()
        let strip = ScrollingStrip(
            columnWidths: children.map(\.effectiveScrollingColumnWidth),
            focusedIndex: mostRecentChild?.ownIndex ?? 0,
            viewport: viewport,
            gap: gap,
            peek: CGFloat(config.scrollingPeek),
            previousOffset: scrollOffset,
        )
        let previousOffset = scrollOffset
        scrollOffset = strip.offset
        let neighbours = context.workspace.workspaceMonitor.neighbours(orientation)
        let isOutOfView = { (start: CGFloat, size: CGFloat) -> Bool in
            // A column cut by the edge stays where it is, half off screen, unless the cut part would land on
            // the next monitor
            start + size <= 0 || start >= viewport || (start < 0 && neighbours.before) || (start + size > viewport && neighbours.after)
        }
        let duration = config.scrollingAnimationDuration
        if duration > 0 && abs(strip.offset - previousOffset) > 1 {
            // Slide in steps, each moving every column in view through Accessibility. setAxFrame drops a frame
            // the app hasn't applied yet when the next one arrives, so a slow app skips steps instead of lagging
            let frames = max(2, duration / 16)
            for frame in 1 ..< frames {
                let t = CGFloat(frame) / CGFloat(frames)
                let eased = 1 - (1 - t) * (1 - t) * (1 - t) // Ease out: fast start, gentle landing
                let shift = (strip.offset - previousOffset) * (1 - eased)
                for (i, child) in children.enumerated() where !isOutOfView(strip.starts[i] + shift, strip.sizes[i]) {
                    try await layoutScrollingColumn(child, at: strip.starts[i] + shift, size: strip.sizes[i], point, width: width, height: height, gap: gap, context)
                }
                try await Task.sleep(for: .milliseconds(16))
            }
        }
        for (i, child) in children.enumerated() {
            if isOutOfView(strip.starts[i], strip.sizes[i]) {
                try await child.hideScrolledOutColumn(hideCorner)
                continue
            }
            try await layoutScrollingColumn(child, at: strip.starts[i], size: strip.sizes[i], point, width: width, height: height, gap: gap, context)
        }
    }

    @MainActor
    private func layoutScrollingColumn(
        _ child: TreeNode,
        at start: CGFloat,
        size: CGFloat,
        _ point: CGPoint,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat,
        _ context: LayoutContext,
    ) async throws {
        let childPoint = point.addingOffset(orientation, start)
        let childWidth = orientation == .h ? size : width
        let childHeight = orientation == .v ? size : height
        let virtualPoint = childPoint.addingOffset(orientation, -gap / 2)
        try await child.layoutRecursive(
            childPoint,
            width: childWidth,
            height: childHeight,
            virtual: Rect(
                topLeftX: virtualPoint.x,
                topLeftY: virtualPoint.y,
                width: orientation == .h ? childWidth + gap : childWidth,
                height: orientation == .v ? childHeight + gap : childHeight,
            ),
            context,
        )
    }
}

extension TreeNode {
    @MainActor
    fileprivate func hideScrolledOutColumn(_ corner: OptimalHideCorner) async throws {
        lastAppliedLayoutPhysicalRect = nil
        lastAppliedLayoutVirtualRect = nil
        for window in allLeafWindowsRecursive where window.windowId != currentlyManipulatedWithMouseWindowId {
            window.lastAppliedLayoutPhysicalRect = nil
            window.lastAppliedLayoutVirtualRect = nil
            // Test windows have no Accessibility frame to hide
            try await (window as? MacWindow)?.hideInCorner(corner, rememberPosition: false)
        }
    }
}
