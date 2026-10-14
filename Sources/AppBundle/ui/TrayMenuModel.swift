import AppKit
import Common

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var layoutSnapshots: [LayoutSnapshotViewModel] = []
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()
    @Published var lastReloadConfigContainedWarnings: Bool = false
    @Published var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

@MainActor func updateTrayText() {
    let sortedMonitors = sortedMonitors
    let focus = focus
    TrayMenuModel.shared.trayText = (activeMode?.takeIf { $0 != mainModeId }?.first.map { "(\($0.uppercased())) " } ?? "") +
        sortedMonitors
        .map {
            let hasFullscreenWindows = $0.activeWorkspace.allLeafWindowsRecursive.contains { $0.isFullscreen }
            let activeWorkspaceName = hasFullscreenWindows ? "[\($0.activeWorkspace.name)]" : $0.activeWorkspace.name
            return ($0.activeWorkspace == focus.workspace && sortedMonitors.count > 1 ? "*" : "") + activeWorkspaceName
        }
        .joined(separator: " │ ")
    // Empty workspaces are noise in the menu, and 'persistent-workspaces' can keep a lot of them
    // alive. The focused and visible ones stay so that you can always see where you are.
    // Scratchpad workspaces are an implementation detail and never belong here
    TrayMenuModel.shared.workspaces = Workspace.all
        .filter { !$0.isScratchpad && (!$0.isEffectivelyEmpty || $0.isVisible || $0 == focus.workspace) }
        .map {
            let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
            let dash = " - "
            let suffix = switch true {
                case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
                case $0.isVisible: dash + $0.workspaceMonitor.name
                default: ""
            }
            let hasFullscreenWindows = $0.allLeafWindowsRecursive.contains { $0.isFullscreen }
            return WorkspaceViewModel(
                name: $0.name,
                suffix: suffix,
                isFocused: focus.workspace == $0,
                isEffectivelyEmpty: $0.isEffectivelyEmpty,
                isVisible: $0.isVisible,
                hasFullscreenWindows: hasFullscreenWindows,
            )
        }
    scheduleLayoutSnapshotMenuRefresh()
    var items = sortedMonitors.map {
        let hasFullscreenWindows = $0.activeWorkspace.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return TrayItem(
            type: .workspace,
            name: $0.activeWorkspace.name,
            isActive: $0.activeWorkspace == focus.workspace,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    let mode = activeMode?.takeIf { $0 != mainModeId }?.first.map {
        TrayItem(type: .mode, name: $0.uppercased(), isActive: true, hasFullscreenWindows: false)
    }
    if let mode {
        items.insert(mode, at: 0)
    }
    TrayMenuModel.shared.trayItems = items
}

struct LayoutSnapshotViewModel: Hashable {
    let name: String
    /// The keys that restore this snapshot, if any binding does. Includes the keys that enter the
    /// binding mode first, so a snapshot bound inside a mode reads as 'alt-0 1'
    let shortcut: String?

    var label: String { shortcut.map { "\(name)   \($0)" } ?? name }
}

struct WorkspaceViewModel: Hashable {
    let name: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let isActive: Bool
    let hasFullscreenWindows: Bool
    var systemImageName: String? {
        // System image type is only valid for numbers 0 to 50 and single capital char workspace name
        switch Int(name) {
            case let number?: if !(0 ... 50).contains(number) { return nil }
            case nil where name.count == 1: if !validLetters.contains(name) { return nil }
            default: return nil
        }
        let lowercasedName = name.lowercased()
        return switch type {
            case .mode: "\(lowercasedName).circle"
            case .workspace where isActive: "\(lowercasedName).square.fill"
            case .workspace: "\(lowercasedName).square"
        }
    }
    var id: String {
        return type.rawValue + name
    }
}

@MainActor private var snapshotMenuRefreshTask: Task<Void, Never>?
@MainActor private var snapshotMenuDirty = false

@MainActor
private func scheduleLayoutSnapshotMenuRefresh() {
    snapshotMenuDirty = true
    guard snapshotMenuRefreshTask == nil else { return }
    snapshotMenuRefreshTask = Task.startUnstructured { @MainActor in
        defer { snapshotMenuRefreshTask = nil }
        while snapshotMenuDirty {
            snapshotMenuDirty = false
            let names = await Task.detached(priority: .utility) {
                listLayoutSnapshots()
            }.value
            let items = names.map {
                LayoutSnapshotViewModel(name: $0, shortcut: layoutSnapshotRestoreShortcut($0))
            }
            if items != TrayMenuModel.shared.layoutSnapshots {
                TrayMenuModel.shared.layoutSnapshots = items
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
