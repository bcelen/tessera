@testable import AppBundle
import Common
import XCTest

@MainActor
final class ScrollingLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    // =========================================================== The strip arithmetic

    func testTwoHalvesAndTheGapFillTheViewport() {
        let strip = ScrollingStrip(columnWidths: [0.5, 0.5], focusedIndex: 0, viewport: 1000, gap: 10, peek: 0, previousOffset: 0)
        assertEquals(strip.sizes, [495, 495])
        assertEquals(strip.starts, [0, 505])
        assertEquals(strip.offset, 0)
    }

    func testScrollsJustEnoughToShowTheFocusedColumnAndAPeek() {
        let strip = ScrollingStrip(columnWidths: [0.5, 0.5, 0.5, 0.5], focusedIndex: 2, viewport: 1000, gap: 0, peek: 40, previousOffset: 0)
        assertEquals(strip.offset, 540)
        assertEquals(strip.starts, [-540, -40, 460, 960])
    }

    func testDoesNotScrollWhileTheFocusedColumnIsInView() {
        let strip = ScrollingStrip(columnWidths: [0.5, 0.5, 0.5, 0.5], focusedIndex: 2, viewport: 1000, gap: 0, peek: 40, previousOffset: 540)
        assertEquals(strip.offset, 540)
    }

    func testLastColumnHasNoPeekAfterIt() {
        let strip = ScrollingStrip(columnWidths: [0.5, 0.5, 0.5, 0.5], focusedIndex: 3, viewport: 1000, gap: 0, peek: 40, previousOffset: 540)
        assertEquals(strip.offset, 1000)
    }

    func testPeekNeverPushesAFullWidthColumnOutOfView() {
        let strip = ScrollingStrip(columnWidths: [1, 1, 1], focusedIndex: 1, viewport: 1000, gap: 0, peek: 40, previousOffset: 0)
        assertEquals(strip.offset, 1000)
        assertEquals(strip.starts[1], 0)
    }

    func testAStripShorterThanTheViewportDoesNotScroll() {
        let strip = ScrollingStrip(columnWidths: [0.3], focusedIndex: 0, viewport: 1000, gap: 0, peek: 40, previousOffset: 300)
        assertEquals(strip.offset, 0)
    }

    func testWidthsAreClamped() {
        let strip = ScrollingStrip(columnWidths: [0, 5], focusedIndex: 0, viewport: 1000, gap: 0, peek: 0, previousOffset: 0)
        assertEquals(strip.sizes, [100, 1000])
    }

    // =========================================================== Layout

    func testColumnsOutOfViewAreHiddenAndCutColumnsStay() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        _ = windows[2].focusWindow()

        try await workspace.layoutWorkspace(hideCorner: .bottomRightCorner)

        // 1920 wide test monitor, columns of 960, 40 of peek: the strip scrolls by 960 * 3 + 40 - 1920 = 1000
        assertEquals(windows[0].lastAppliedLayoutPhysicalRect == nil, true)
        assertEquals(windows[1].rectForTests?.topLeftX, -40)
        assertEquals(windows[2].rectForTests?.topLeftX, 920)
        assertEquals(windows[2].rectForTests?.width, 960)
        assertEquals(windows[3].rectForTests?.topLeftX, 1880)
        assertEquals(workspace.rootTilingContainer.scrollOffset, 1000)
    }

    func testWithoutAHideCornerScrollingFallsBackToTiles() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }

        try await workspace.layoutWorkspace(hideCorner: nil)

        assertEquals(windows.map { $0.rectForTests?.topLeftX }, [0, 480, 960, 1440])
    }

    func testNewWindowOpensAColumnNextToTheFocusedOne() async throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .scrolling
        let newWindow = TestWindow.new(id: 4, parent: workspace.floatingWindowsContainer)
        TestWindow.new(id: 1, parent: root)
        let column = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let inColumn = TestWindow.new(id: 2, parent: column)
        TestWindow.new(id: 3, parent: root)
        _ = inColumn.focusWindow()

        try await newWindow.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)

        assertEquals(root.layoutDescription, .h_scrolling([.window(1), .v_tiles([.window(2)]), .window(4), .window(3)]))
    }

    func testScrollingRootWithOneColumnIsNotFlattened() {
        config.enableNormalizationFlattenContainers = true
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let column = TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: column)
        TestWindow.new(id: 2, parent: column)

        workspace.normalizeContainers()

        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_scrolling([.v_tiles([.window(1), .window(2)])]))
    }

    // =========================================================== layout command

    func testLayoutScrollingAlwaysActsOnTheRoot() async {
        let workspace = Workspace.get(byName: name)
        let column = TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 1, parent: column)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()

        await parseCommand("layout scrolling tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.rootTilingContainer.layout, .scrolling)
        assertEquals(column.layout, .tiles)

        await parseCommand("layout scrolling tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.rootTilingContainer.layout, .tiles)
    }

    // =========================================================== column-width

    func testParseColumnWidth() {
        testParseSingleCommandSucc("column-width 50%", ColumnWidthCmdArgs(rawArgs: [], widths: [.set(50)]))
        testParseSingleCommandSucc("column-width 33% 50% 67%", ColumnWidthCmdArgs(rawArgs: [], widths: [.set(33), .set(50), .set(67)]))
        testParseSingleCommandSucc("column-width +10%", ColumnWidthCmdArgs(rawArgs: [], widths: [.add(10)]))
        testParseSingleCommandSucc("column-width -10%", ColumnWidthCmdArgs(rawArgs: [], widths: [.subtract(10)]))
        assertEquals(parseCommand("column-width").errorOrNil, "ERROR: Argument '<width>' is mandatory")
        assertEquals(parseCommand("column-width 50% +10%").errorOrNil, "A relative width (+N% or -N%) must be the only <width>")
    }

    func testColumnWidthCyclesThroughPresets() async {
        let window = scrollingWorkspaceWithFocusedWindow()

        await parseCommand("column-width 33% 50% 67%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 0.67)
        await parseCommand("column-width 33% 50% 67%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 0.33)
        await parseCommand("column-width 33% 50% 67%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 0.5)
    }

    func testColumnWidthRelativeAndClamped() async {
        let window = scrollingWorkspaceWithFocusedWindow()

        await parseCommand("column-width +10%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 0.6)
        await parseCommand("column-width 150%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 1)
    }

    func testColumnWidthActsOnTheWholeColumn() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let column = TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        _ = TestWindow.new(id: 1, parent: column).focusWindow()
        TestWindow.new(id: 2, parent: column)

        await parseCommand("column-width 100%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(column.scrollingColumnWidth, 1)
    }

    func testColumnWidthFailsOutsideTheScrollingLayout() async {
        _ = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer).focusWindow()
        let result = await parseCommand("column-width 50%").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
    }

    // =========================================================== resize, balance-sizes

    func testResizeWidthChangesOnlyTheColumn() async {
        let window = scrollingWorkspaceWithFocusedWindow()
        let other = TestWindow.new(id: 2, parent: Workspace.get(byName: name).rootTilingContainer)

        // 960 of 1920 points, plus 192 is 1152, which is 60%
        await parseCommand("resize width +192").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, 0.6)
        assertEquals(other.scrollingColumnWidth, nil)
    }

    func testBalanceSizesResetsColumnWidths() async {
        let window = scrollingWorkspaceWithFocusedWindow()
        window.scrollingColumnWidth = 0.8

        await parseCommand("balance-sizes").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.scrollingColumnWidth, nil)
    }

    // =========================================================== Snapshots

    func testSnapshotsWithoutColumnWidthStillDecode() throws {
        let json = #"{"kind":"window","weight":1,"appName":"Terminal"}"#
        let node = try JSONDecoder().decode(SnapshotNode.self, from: Data(json.utf8))
        assertEquals(node.columnWidth, nil)
    }

    // =========================================================== Slide

    func testSlideEndsWhereAJumpWould() async throws {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        _ = windows[0].focusWindow()
        try await workspace.layoutWorkspace(hideCorner: .bottomRightCorner)

        config.scrollingAnimationDuration = 48
        _ = windows[2].focusWindow()
        try await workspace.layoutWorkspace(hideCorner: .bottomRightCorner)

        assertEquals(windows[2].rectForTests?.topLeftX, 920)
        assertEquals(windows[3].rectForTests?.topLeftX, 1880)
        assertEquals(windows[0].lastAppliedLayoutPhysicalRect == nil, true)
    }

    // =========================================================== Swipe

    func testSwipeStepsOncePerSwipeAndSwallowsItsMomentum() {
        var tracker = ScrollingSwipeTracker()
        assertEquals(tracker.handle(.trackpad(-10, .began), isArmed: true).step, nil)
        assertEquals(tracker.handle(.trackpad(-25, .changed), isArmed: true).step, 1)
        // A long swipe still counts once
        assertEquals(tracker.handle(.trackpad(-200, .changed), isArmed: true).step, nil)
        assertEquals(tracker.handle(.trackpad(0, .ended), isArmed: true).consume, true)
        // Momentum belongs to the swipe even once the modifiers are released
        assertEquals(tracker.handle(.trackpad(-50, .none, momentum: .began), isArmed: false).consume, true)
        assertEquals(tracker.handle(.trackpad(0, .none, momentum: .ended), isArmed: false).consume, true)
        assertEquals(tracker.handle(.trackpad(-5, .none), isArmed: false).consume, false)
    }

    func testSwipeRightGoesToThePreviousColumn() {
        var tracker = ScrollingSwipeTracker()
        _ = tracker.handle(.trackpad(10, .began), isArmed: true)
        assertEquals(tracker.handle(.trackpad(25, .changed), isArmed: true).step, -1)
    }

    func testSwipeWithoutModifiersPassesThroughEvenIfTheyArePressedLater() {
        var tracker = ScrollingSwipeTracker()
        assertEquals(tracker.handle(.trackpad(-10, .began), isArmed: false).consume, false)
        assertEquals(tracker.handle(.trackpad(-100, .changed), isArmed: true).consume, false)
    }

    func testWheelNotchIsOneStep() {
        var tracker = ScrollingSwipeTracker()
        let notchDown = ScrollSample(deltaX: 0, deltaY: -1, isContinuous: false, phase: .none, momentumPhase: .none)
        assertEquals(tracker.handle(notchDown, isArmed: true).step, 1)
        assertEquals(tracker.handle(notchDown, isArmed: false).consume, false)
    }

    func testSmoothWheelStepsEveryThreshold() {
        var tracker = ScrollingSwipeTracker()
        let spin = ScrollSample(deltaX: -12, deltaY: 0, isContinuous: true, phase: .none, momentumPhase: .none)
        assertEquals(tracker.handle(spin, isArmed: true).step, nil)
        assertEquals(tracker.handle(spin, isArmed: true).step, nil)
        assertEquals(tracker.handle(spin, isArmed: true).step, 1)
        assertEquals(tracker.handle(spin, isArmed: true).step, nil)
        assertEquals(tracker.handle(spin, isArmed: false).consume, false)
    }

    func testSmoothWheelIsNotSwallowedAfterASwipeWithoutMomentum() {
        var tracker = ScrollingSwipeTracker()
        _ = tracker.handle(.trackpad(-40, .began), isArmed: true)
        _ = tracker.handle(.trackpad(0, .ended), isArmed: true)
        let spin = ScrollSample(deltaX: 0, deltaY: -12, isContinuous: true, phase: .none, momentumPhase: .none)
        assertEquals(tracker.handle(spin, isArmed: false).consume, false)
    }

    func testParseSwipeConfig() {
        let result = parseConfig(
            """
            scrolling-swipe-modifiers = 'ctrl-alt-shift-cmd'
            scrolling-animation-duration = 150
            """,
        )
        assertEquals(result.errors, [])
        assertEquals(result.config.scrollingSwipeModifiers, [.control, .option, .shift, .command])
        assertEquals(result.config.scrollingAnimationDuration, 150)

        assertEquals(parseConfig("scrolling-swipe-modifiers = ''").config.scrollingSwipeModifiers, nil)
        assertEquals(parseConfig("scrolling-swipe-modifiers = 'hyper'").errors.count, 1)
        assertEquals(parseConfig("scrolling-animation-duration = 5000").errors.count, 1)
    }

    private func scrollingWorkspaceWithFocusedWindow() -> Window {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.layout = .scrolling
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()
        return window
    }
}

extension ScrollSample {
    fileprivate static func trackpad(_ deltaX: CGFloat, _ phase: Phase, momentum: Phase = .none) -> ScrollSample {
        ScrollSample(deltaX: deltaX, deltaY: 0, isContinuous: true, phase: phase, momentumPhase: momentum)
    }
}
