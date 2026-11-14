@testable import AppBundle
import Common
import XCTest

@MainActor
final class PlaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc(
            "place --x 0 --y 50% --width 100% --height 50%",
            PlaceCmdArgs(rawArgs: [])
                .copy(\.x, .points(0)).copy(\.y, .fraction(0.5))
                .copy(\.width, .fraction(1)).copy(\.height, .fraction(0.5)),
        )
        testParseSingleCommandSucc(
            "place --width 800 --height 600",
            PlaceCmdArgs(rawArgs: []).copy(\.width, .points(800)).copy(\.height, .points(600)),
        )
    }

    func testParseErrors() {
        assertEquals(parseCommand("place").errorOrNil, "Give a position (--x and --y), a size (--width and --height), or both")
        assertEquals(parseCommand("place --x 10").errorOrNil, "--x and --y must be given together")
        assertEquals(parseCommand("place --width 10").errorOrNil, "--width and --height must be given together")
        assertFail(parsePlaceLength("150%"))
        assertFail(parsePlaceLength("-5"))
        assertFail(parsePlaceLength("wide"))
        // Double("inf") parses as +infinity and passes a plain >= 0 check
        assertFail(parsePlaceLength("inf"))
        assertFail(parsePlaceLength("nan"))
    }

    /// The test monitor is 1920x1080 at the origin, so the lower half is (0, 540) at 1920x540
    func testPlacesInTheLowerHalfAndFloats() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)

        await parseCommand("place --x 0 --y 50% --width 100% --height 50%").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let window = Window.get(byId: 1).orDie() as! TestWindow
        assertEquals(window.isFloating, true)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [2])
        let rect = window.rectForTests.orDie()
        assertEquals(rect.topLeftX, 0)
        assertEquals(rect.topLeftY, 540)
        assertEquals(rect.width, 1920)
        assertEquals(rect.height, 540)
        assertEquals(window.lastFloatingSize, CGSize(width: 1920, height: 540))
    }

    /// A fullscreen window that is placed must end up at the place, not stretched back over the screen
    func testPlacingAFullscreenWindowEndsFullscreen() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply { TestWindow.new(id: 1, parent: $0) }
        }
        assertEquals(workspace.focusWorkspace(), true)
        let window = Window.get(byId: 1).orDie()
        assertEquals(window.focusWindow(), true)
        window.isFullscreen = true

        await parseCommand("place --x 0 --y 50% --width 100% --height 50%").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(window.isFullscreen, false)
    }

    func testSizeOnlyKeepsPosition() async {
        let workspace = Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 10, height: 10))
        }
        assertEquals(workspace.focusWorkspace(), true)

        await parseCommand("place --width 800 --height 600").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let rect = (Window.get(byId: 1).orDie() as! TestWindow).rectForTests.orDie()
        assertEquals(rect.topLeftX, 100)
        assertEquals(rect.topLeftY, 200)
        assertEquals(rect.width, 800)
        assertEquals(rect.height, 600)
    }
}
