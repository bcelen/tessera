import AppKit
import Common
import Foundation

struct LayoutSnapshotCommand: Command {
    let args: LayoutSnapshotCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        switch args.action.val {
            case .list: return list(io)
            case .delete: return delete(io)
            case .save: return await save(env, io)
            case .restore: return await restore(env, io)
        }
    }

    // =========================================================== save

    @MainActor
    private func save(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let url = resolveUrl(io) else { return .fail }
        guard let workspace = resolveWorkspaceOrReportError(env, io) else { return .fail }
        let snapshot = LayoutSnapshot(workspace: workspace.name, root: await capture(workspace.rootTilingContainer))
        return switch writeLayoutSnapshot(snapshot, to: url) {
            case .success: .succ(io.out("Saved layout of workspace '\(workspace.name)' to \(url.path)"))
            case .failure(let msg): .fail(io.err(msg))
        }
    }

    @MainActor
    private func capture(_ container: TilingContainer) async -> SnapshotNode {
        let total = container.children.sumOfDouble { Double($0.getWeight(container.orientation)) }
        var children: [SnapshotNode] = []
        for child in container.children {
            let weight = total > 0 ? Double(child.getWeight(container.orientation)) / total : 0
            switch child.nodeCases {
                case .window(let window):
                    let title = (try? await window.getTitle(.nonCancellable)) ?? ""
                    children.append(.window(window, title: title, weight: weight))
                case .tilingContainer(let nested):
                    var node = await capture(nested)
                    node.weight = weight
                    children.append(node)
                case .workspace, .floatingWindowsContainer, .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    break // Only the tiling tree is captured
            }
        }
        return .container(orientation: container.orientation, layout: container.layout, weight: 1, children: children)
    }

    // =========================================================== restore

    @MainActor
    private func restore(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let url = resolveUrl(io) else { return .fail }
        guard let snapshot = readLayoutSnapshot(url).getOrNil(appendErrorTo: &io.stderr) else { return .fail }
        guard let workspace = resolveWorkspaceOrReportError(env, io) else { return .fail }

        // Windows already on the workspace come first, then everything else, so that a layout can be
        // gathered back together after the windows have been scattered by a restart
        var pool: [Window] = workspace.allLeafWindowsRecursive
        pool += Workspace.all
            .filter { $0 != workspace && !$0.isScratchpad }
            .flatMap { $0.allLeafWindowsRecursive }

        var titles: [UInt32: String] = [:]
        for window in pool {
            titles[window.windowId] = (try? await window.getTitle(.nonCancellable)) ?? ""
        }

        let root = workspace.rootTilingContainer
        let oldChildren = root.children
        root.changeOrientation(snapshot.root.parsedOrientation)
        root.layout = snapshot.root.parsedLayout

        var used: Set<UInt32> = []
        build(snapshot.root, into: root, pool: pool, titles: titles, used: &used)

        // Windows that were already here but aren't part of the snapshot are appended at the end
        for child in oldChildren {
            for window in child.allLeafWindowsRecursive where !used.contains(window.windowId) {
                window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }

        let wanted = countWindows(snapshot.root)
        let msg = "Restored \(used.count) of \(wanted) window(s) of '\(url.deletingPathExtension().lastPathComponent)' on workspace '\(workspace.name)'"
        return used.count == wanted ? .succ(io.out(msg)) : .succ(io.err(msg))
    }

    @MainActor
    private func build(
        _ node: SnapshotNode,
        into parent: TilingContainer,
        pool: [Window],
        titles: [UInt32: String],
        used: inout Set<UInt32>,
    ) {
        guard let snapshotChildren = node.children else { return }
        var bound: [(SnapshotNode, TreeNode)] = []
        for child in snapshotChildren {
            switch child.kind {
                case .window:
                    guard let window = match(child, pool: pool, titles: titles, used: used) else { continue }
                    used.insert(window.windowId)
                    window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                    bound.append((child, window))
                case .container:
                    let container = TilingContainer(
                        parent: parent,
                        adaptiveWeight: WEIGHT_AUTO,
                        child.parsedOrientation,
                        child.parsedLayout,
                        index: INDEX_BIND_LAST,
                    )
                    bound.append((child, container))
            }
        }
        // Weights are stored as fractions, so they must be applied top down, once the parent's own
        // weight is already final
        if parent.layout == .tiles {
            let total = Double(parent.getWeight(parent.orientation))
            let sum = bound.sumOfDouble { $0.0.weight }
            if total > 0 && sum > 0 {
                for (snapshotChild, treeChild) in bound {
                    treeChild.setWeight(parent.orientation, CGFloat(snapshotChild.weight / sum * total))
                }
            }
        }
        for (snapshotChild, treeChild) in bound {
            if let container = treeChild as? TilingContainer {
                build(snapshotChild, into: container, pool: pool, titles: titles, used: &used)
            }
        }
    }

    @MainActor
    private func match(_ node: SnapshotNode, pool: [Window], titles: [UInt32: String], used: Set<UInt32>) -> Window? {
        let candidates = pool.filter { !used.contains($0.windowId) && isSameApp($0, node) }
        // Exact within the session that took the snapshot. Window ids don't survive a restart, so a
        // stale id simply fails to resolve and we fall through
        if let windowId = node.windowId, let exact = candidates.first(where: { $0.windowId == windowId }) {
            return exact
        }
        if let title = node.windowTitle, !title.isEmpty,
           let exact = candidates.first(where: { titles[$0.windowId] == title })
        {
            return exact
        }
        return candidates.first
    }

    @MainActor
    private func isSameApp(_ window: Window, _ node: SnapshotNode) -> Bool {
        if let bundleId = node.appBundleId {
            return window.app.rawAppBundleId == bundleId
        }
        return node.appName != nil && window.app.name == node.appName
    }

    private func countWindows(_ node: SnapshotNode) -> Int {
        switch node.kind {
            case .window: return 1
            case .container: return (node.children ?? []).reduce(0) { $0 + countWindows($1) }
        }
    }

    // =========================================================== list, delete

    private func list(_ io: CmdIo) -> BinaryExitCode {
        let names = listLayoutSnapshots()
        return names.isEmpty
            ? .succ(io.err("No layout snapshots in \(layoutSnapshotsDir().path)"))
            : .succ(io.out(names))
    }

    private func delete(_ io: CmdIo) -> BinaryExitCode {
        guard let url = resolveUrl(io) else { return .fail }
        if !FileManager.default.fileExists(atPath: url.path) {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("No layout snapshot named \((args.name ?? "").singleQuoted). Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return .fail(io.err("Can't delete \(url.path): \(error.localizedDescription)"))
        }
        return .succ
    }

    /// Scratchpad workspaces are an implementation detail of the `scratchpad` command. Saving one would
    /// record an empty tree, and restoring onto one would bury the windows out of sight
    @MainActor
    private func resolveWorkspaceOrReportError(_ env: CmdEnv, _ io: CmdIo) -> Workspace? {
        guard let target = args.resolveTargetOrReportError(env, io) else { return nil }
        let workspace = target.workspace
        if workspace.isScratchpad {
            io.err("'\(workspace.name)' is an internal scratchpad workspace. Switch to a real workspace first, or pass --workspace")
            return nil
        }
        return workspace
    }

    private func resolveUrl(_ io: CmdIo) -> URL? {
        guard let name = args.name else {
            io.err("Argument '<name>' is mandatory")
            return nil
        }
        return layoutSnapshotUrl(name).getOrNil(appendErrorTo: &io.stderr)
    }
}
