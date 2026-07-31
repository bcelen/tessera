@testable import AppBundle
import Common
import XCTest

@MainActor
final class ScratchpadCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc("scratchpad move", ScratchpadCmdArgs(rawArgs: []).copy(\.action, .initialized(.move)))
        testParseSingleCommandSucc("scratchpad toggle", ScratchpadCmdArgs(rawArgs: []).copy(\.action, .initialized(.toggle)))
        testParseSingleCommandSucc(
            "scratchpad show --name notes",
            ScratchpadCmdArgs(rawArgs: []).copy(\.action, .initialized(.show)).copy(\._name, "notes"),
        )
        assertEquals(parseCommand("scratchpad").errorOrNil, "ERROR: Argument '(move|show|hide|toggle|release)' is mandatory")
        assertEquals(
            parseCommand("scratchpad foo").errorOrNil,
            "ERROR: Can't parse 'foo'.\n       Possible values: (move|show|hide|toggle|release)",
        )
    }

    func testDefaultName() {
        assertEquals(ScratchpadCmdArgs(rawArgs: []).name, defaultScratchpadName)
        assertEquals(ScratchpadCmdArgs(rawArgs: []).copy(\._name, "notes").name, "notes")
    }

    func testIncompatibleFlags() {
        assertEquals(
            parseCommand("scratchpad show --window-id 42").errorOrNil,
            "--window-id is only compatible with 'move' and 'release'",
        )
        assertEquals(
            parseCommand("scratchpad toggle --fail-if-noop").errorOrNil,
            "--fail-if-noop is incompatible with 'toggle'",
        )
    }

    /// Every command run ends with `refreshModel_nonCancellable`, which garbage collects empty invisible
    /// workspaces. So a scratchpad workspace reference must never be cached across a command run
    private func scratchpadWindowIds(_ scratchpad: String = defaultScratchpadName) -> [UInt32] {
        Workspace.getScratchpad(scratchpad).allLeafWindowsRecursive.map(\.windowId)
    }

    func testMoveShowHide() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertEquals(workspace.focusWorkspace(), true)
        let window1 = Window.get(byId: 1).orDie()
        assertEquals(window1.focusWindow(), true)

        assertEquals(Workspace.getScratchpad(defaultScratchpadName).isScratchpad, true)

        await parseCommand("scratchpad move").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId), [2])
        assertEquals(scratchpadWindowIds(), [1])
        // Focus must not follow the window into the hidden workspace
        assertEquals(focus.workspace, workspace)

        await parseCommand("scratchpad toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertEquals(scratchpadWindowIds(), [])
        assertEquals(focus.windowOrNil?.windowId, 1)

        await parseCommand("scratchpad toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId), [2])
        assertEquals(scratchpadWindowIds(), [1])
    }

    /// Clicking a window that is hidden in the corner syncs macOS focus into the scratchpad workspace.
    /// `toggle` must then summon the window back out, not report that there is nothing to hide
    func testToggleRecoversWhenFocusDriftsIntoScratchpad() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        await parseCommand("scratchpad move").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratchpadWindowIds(), [1])

        // Simulate the click on the hidden window
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        assertEquals(focus.workspace.isScratchpad, true)

        await parseCommand("scratchpad toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratchpadWindowIds(), [])
        assertEquals(workspace.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertEquals(focus.workspace.isScratchpad, false)
    }

    func testNamedScratchpadsAreIndependent() async {
        let workspace = Workspace.get(byName: name).apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(Window.get(byId: 1).orDie().focusWindow(), true)
        await parseCommand("scratchpad move --name notes").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(scratchpadWindowIds("notes"), [1])
        assertEquals(scratchpadWindowIds(), [])

        // The default scratchpad is empty, so toggling it must not pull the 'notes' window out
        await parseCommand("scratchpad toggle").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(scratchpadWindowIds("notes"), [1])
    }
}
