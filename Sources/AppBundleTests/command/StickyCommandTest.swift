@testable import AppBundle
import Common
import XCTest

@MainActor
final class StickyCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc("sticky on", StickyCmdArgs(rawArgs: [], targetState: .on))
        testParseSingleCommandSucc("sticky toggle", StickyCmdArgs(rawArgs: [], targetState: .toggle))
        assertEquals(parseCommand("sticky").errorOrNil, "ERROR: Argument '(on|off|toggle)' is mandatory")
        assertEquals(
            parseCommand("sticky toggle --fail-if-noop").errorOrNil,
            "--fail-if-noop is incompatible with 'toggle' argument",
        )
    }

    /// Making a window sticky must force it to float, otherwise it would insert itself into the
    /// tiling layout of every workspace it visits
    func testStickyImpliesFloating() async {
        let workspace = twoWindowWorkspace()
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)

        await parseCommand("sticky on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Window.get(byId: 1).orDie().isSticky, true)
        assertEquals(Window.get(byId: 1).orDie().isFloating, true)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [2])
    }

    func testStickyFollowsTheActiveWorkspace() async {
        let workspace = twoWindowWorkspace()
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        await parseCommand("sticky on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        await parseCommand("workspace \(secondWorkspaceName)").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, secondWorkspaceName)
        // The sticky window came along, the plain one stayed behind
        assertEquals(Workspace.get(byName: secondWorkspaceName).allLeafWindowsRecursive.map(\.windowId), [1])
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId), [2])

        // And it comes back when we return
        await parseCommand("workspace \(firstWorkspaceName)").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertEquals(Workspace.get(byName: secondWorkspaceName).allLeafWindowsRecursive.map(\.windowId), [])
    }

    /// A window that is both sticky and parked in a scratchpad must stay parked. Following the
    /// monitor's active workspace would undo 'scratchpad move' on the very next refresh
    func testStickyWindowStaysInTheScratchpad() async {
        let workspace = twoWindowWorkspace()
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        await parseCommand("sticky on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("scratchpad move --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(Workspace.getScratchpad(defaultScratchpadName).allLeafWindowsRecursive.map(\.windowId), [1])
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId), [2])

        // A refresh is what used to pull it back out
        await parseCommand("workspace \(secondWorkspaceName)").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Workspace.getScratchpad(defaultScratchpadName).allLeafWindowsRecursive.map(\.windowId), [1])
        assertEquals(Workspace.get(byName: secondWorkspaceName).allLeafWindowsRecursive.map(\.windowId), [])
    }

    func testStickyOffStopsFollowing() async {
        let workspace = twoWindowWorkspace()
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        await parseCommand("sticky on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("sticky off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Window.get(byId: 1).orDie().isSticky, false)

        await parseCommand("workspace \(secondWorkspaceName)").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Workspace.get(byName: secondWorkspaceName).allLeafWindowsRecursive.map(\.windowId), [])
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
    }

    // XCTestCase.name is '-[StickyCommandTest testFoo]', which can't be interpolated into a command
    private let firstWorkspaceName = "sticky-one"
    private let secondWorkspaceName = "sticky-two"

    private func twoWindowWorkspace() -> Workspace {
        let workspace = Workspace.get(byName: firstWorkspaceName).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertEquals(workspace.focusWorkspace(), true)
        return workspace
    }
}
