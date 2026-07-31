import AppKit
import Common
import Foundation

/// A saved tiling layout of a single workspace. See `LayoutSnapshotCommand`
struct LayoutSnapshot: Codable {
    static let currentVersion = 1

    var version: Int = LayoutSnapshot.currentVersion
    /// The workspace the snapshot was taken on. Informational only, restore targets whatever workspace you ask for
    var workspace: String
    var root: SnapshotNode
}

struct SnapshotNode: Codable {
    enum Kind: String, Codable {
        case container, window
    }

    var kind: Kind
    /// Share of the parent container taken by this node, in `0...1`. Meaningless for the root
    var weight: Double

    // Container only
    var orientation: String?
    var layout: String?
    var children: [SnapshotNode]?

    // Window only
    var appBundleId: String?
    var appName: String?
    var windowTitle: String?
}

extension SnapshotNode {
    static func container(orientation: Orientation, layout: Layout, weight: Double, children: [SnapshotNode]) -> SnapshotNode {
        SnapshotNode(
            kind: .container,
            weight: weight,
            orientation: orientation.snapshotValue,
            layout: layout.rawValue,
            children: children,
        )
    }

    static func window(_ window: Window, title: String, weight: Double) -> SnapshotNode {
        SnapshotNode(
            kind: .window,
            weight: weight,
            appBundleId: window.app.rawAppBundleId,
            appName: window.app.name,
            windowTitle: title,
        )
    }

    var parsedOrientation: Orientation { orientation == "v" ? .v : .h }
    var parsedLayout: Layout { layout?.parseLayout() ?? .tiles }
}

extension Orientation {
    var snapshotValue: String { self == .h ? "h" : "v" }
}

// =========================================================== Storage

/// Snapshots are state rather than configuration, so they live under XDG_STATE_HOME
func layoutSnapshotsDir() -> URL {
    let stateHome = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/state/")
    return stateHome.appending(path: "aerospace").appending(path: "layouts")
}

func layoutSnapshotUrl(_ name: String) -> ResOrStr<URL> {
    if name.isEmpty {
        return .failure("Snapshot name must not be empty")
    }
    if name.contains("/") || name.hasPrefix(".") {
        return .failure("Snapshot name \(name.singleQuoted) must not contain '/' or start with '.'")
    }
    return .success(layoutSnapshotsDir().appending(path: name + ".json"))
}

func writeLayoutSnapshot(_ snapshot: LayoutSnapshot, to url: URL) -> ResOrStr<()> {
    guard let json = JSONEncoder.aeroSpaceDefault.encodeToString(snapshot) else {
        return .failure("Can't encode the layout snapshot to JSON")
    }
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (json + "\n").write(to: url, atomically: true, encoding: .utf8)
        return .success(())
    } catch {
        return .failure("Can't write \(url.path): \(error.localizedDescription)")
    }
}

func readLayoutSnapshot(_ url: URL) -> ResOrStr<LayoutSnapshot> {
    guard let data = FileManager.default.contents(atPath: url.path) else {
        return .failure("No layout snapshot at \(url.path)")
    }
    do {
        let snapshot = try JSONDecoder().decode(LayoutSnapshot.self, from: data)
        if snapshot.version > LayoutSnapshot.currentVersion {
            return .failure("\(url.path) was written by a newer AeroSpace (format version \(snapshot.version))")
        }
        return .success(snapshot)
    } catch {
        return .failure("Can't parse \(url.path): \(error.localizedDescription)")
    }
}

func listLayoutSnapshots() -> [String] {
    let urls = try? FileManager.default.contentsOfDirectory(
        at: layoutSnapshotsDir(),
        includingPropertiesForKeys: nil,
    )
    return (urls ?? [])
        .filter { $0.pathExtension == "json" }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted()
}
