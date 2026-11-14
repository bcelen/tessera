@testable import AppBundle
import Common
import XCTest

@MainActor
final class LayoutSnapshotCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseSingleCommandSucc(
            "layout-snapshot save teaching",
            LayoutSnapshotCmdArgs(rawArgs: []).copy(\.action, .initialized(.save)).copy(\.name, "teaching"),
        )
        testParseSingleCommandSucc("layout-snapshot list", LayoutSnapshotCmdArgs(rawArgs: []).copy(\.action, .initialized(.list)))
        assertEquals(
            parseCommand("layout-snapshot").errorOrNil,
            "ERROR: Argument '(save|restore|delete|list)' is mandatory",
        )
        assertEquals(
            parseCommand("layout-snapshot save").errorOrNil,
            "Argument '<name>' is mandatory for save, restore and delete",
        )
        assertEquals(parseCommand("layout-snapshot list foo").errorOrNil, "'list' doesn't accept '<name>'")
        assertEquals(
            parseCommand("layout-snapshot list --workspace foo").errorOrNil,
            "--workspace is only compatible with 'save' and 'restore'",
        )
    }

    func testSnapshotNameValidation() {
        assertFail(layoutSnapshotUrl(""))
        assertFail(layoutSnapshotUrl("../../etc/passwd"))
        assertFail(layoutSnapshotUrl(".hidden"))
        assertFail(layoutSnapshotUrl("-foo"))
        assertFail(layoutSnapshotUrl("a\nb"))
        assertSucc(layoutSnapshotUrl("teaching"))
        assertSucc(layoutSnapshotUrl("m-imperfect"))
        // Letters are deliberately unrestricted, so Turkish names work
        assertSucc(layoutSnapshotUrl("ödev"))
    }

    /// A round trip through the JSON model must preserve the shape of the tree
    func testCaptureShape() throws {
        let node = SnapshotNode.container(
            orientation: .h,
            layout: .tiles,
            weight: 1,
            children: [
                SnapshotNode(kind: .window, weight: 0.7, appBundleId: "com.apple.Terminal", appName: "Terminal", windowTitle: "bash"),
                SnapshotNode.container(orientation: .v, layout: .accordion, weight: 0.3, children: [
                    SnapshotNode(kind: .window, weight: 1, appBundleId: "com.apple.Safari", appName: "Safari", windowTitle: "AeroSpace"),
                ]),
            ],
        )
        let snapshot = LayoutSnapshot(workspace: "teaching", root: node)
        let json = try XCTUnwrap(JSONEncoder.aeroSpaceDefault.encodeToString(snapshot))
        let decoded = try JSONDecoder().decode(LayoutSnapshot.self, from: try XCTUnwrap(json.data(using: .utf8)))

        assertEquals(decoded.workspace, "teaching")
        assertEquals(decoded.version, LayoutSnapshot.currentVersion)
        assertEquals(decoded.root.children?.count, 2)
        assertEquals(decoded.root.parsedOrientation, .h)
        assertEquals(decoded.root.children?.first?.appBundleId, "com.apple.Terminal")
        assertEquals(decoded.root.children?.last?.parsedOrientation, .v)
        assertEquals(decoded.root.children?.last?.parsedLayout, .accordion)
        assertEquals(decoded.root.children?.last?.children?.first?.windowTitle, "AeroSpace")
    }

    /// Restore must never pull a window that macOS is hiding into a tile: a cmd-h'd app's window or a
    /// native-fullscreen one would sit there invisible, holding a tile, until the app came back. Floating
    /// windows are left alone too, as the docs say
    func testHiddenAndFloatingWindowsAreNotRestorable() {
        let workspace = Workspace.get(byName: name)
        let tiled = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
        let hiddenApp = TestWindow.new(id: 3, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        let fullscreen = TestWindow.new(id: 4, parent: workspace.macOsNativeFullscreenWindowsContainer)

        assertTrue(tiled.isRestorable)
        assertFalse(floating.isRestorable)
        assertFalse(hiddenApp.isRestorable)
        assertFalse(fullscreen.isRestorable)
    }
}
