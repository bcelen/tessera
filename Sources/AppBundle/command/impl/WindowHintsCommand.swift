import AppKit
import Common
import HotKey

/// Home row first, so that the most reachable keys are handed out to the first windows
private let hintAlphabet = "asdfghjklqwertyuiopzxcvbnm".map(String.init)

/// A binding mode that exists only while the hints panel is up. It is injected into `config.modes`
/// at runtime rather than declared in the config file
let windowHintsModeId = "_window-hints"

@MainActor private var modeBeforeWindowHints: String? = nil

struct WindowHintsCommand: Command {
    let args: WindowHintsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        switch args.action.val {
            case .show: return await show(io)
            case .hide: return await dismiss()
            case .pick: return await pick(io)
        }
    }

    @MainActor
    private func show(_ io: CmdIo) async -> BinaryExitCode {
        let workspaces = Workspace.all
            .filter { !$0.isScratchpad && (!args.visibleOnly || $0.isVisible) }
        let focusedWorkspace = focus.workspace
        // The focused workspace goes first, so its windows get the home row
        let ordered = workspaces.sorted { lhs, _ in lhs == focusedWorkspace }

        var hints: [WindowHint] = []
        for workspace in ordered {
            for window in workspace.allLeafWindowsRecursive {
                guard hints.count < hintAlphabet.count else { break }
                let title = (try? await window.getTitle(.nonCancellable)) ?? ""
                hints.append(WindowHint(
                    key: hintAlphabet[hints.count],
                    windowId: window.windowId,
                    appName: window.app.name ?? window.app.rawAppBundleId ?? "?",
                    workspace: workspace.name,
                    title: title,
                ))
            }
        }
        if hints.isEmpty {
            return .succ(io.err("There are no windows to pick from"))
        }

        guard let mode = buildHintsMode(hints) else {
            return .fail(io.err("Can't build the window hints binding mode"))
        }
        config.modes[windowHintsModeId] = mode
        WindowHintsPanel.shared.show(hints)
        if activeMode != windowHintsModeId {
            modeBeforeWindowHints = activeMode
        }
        await activateMode_nonCancellable(windowHintsModeId)
        return .succ
    }

    @MainActor
    private func pick(_ io: CmdIo) async -> BinaryExitCode {
        guard let windowId = args.windowId, let window = Window.get(byId: windowId) else {
            _ = await dismiss()
            return .fail(io.err("Window \(args.windowId?.description ?? "?") no longer exists"))
        }
        let focused = window.focusWindow()
        _ = await dismiss()
        return .from(bool: focused)
    }

    @MainActor
    private func dismiss() async -> BinaryExitCode {
        WindowHintsPanel.shared.hide()
        config.modes.removeValue(forKey: windowHintsModeId)
        let restoreTo = modeBeforeWindowHints ?? mainModeId
        modeBeforeWindowHints = nil
        // The mode may have disappeared if the config was reloaded while the panel was up
        await activateMode_nonCancellable(config.modes[restoreTo] != nil ? restoreTo : mainModeId)
        return .succ
    }

    @MainActor
    private func buildHintsMode(_ hints: [WindowHint]) -> Mode? {
        var bindings: [String: HotkeyBinding] = [:]
        for hint in hints {
            guard let keyCode = keyNotationToKeyCode[hint.key] else { continue }
            var pickArgs = WindowHintsCmdArgs(rawArgs: [])
            pickArgs.action = .initialized(.pick)
            pickArgs.windowId = hint.windowId
            let binding = HotkeyBinding(
                [],
                keyCode,
                .cmd(WindowHintsCommand(args: pickArgs) as any Command),
                descriptionWithKeyNotation: hint.key,
            )
            bindings[binding.descriptionWithKeyCode] = binding
        }
        guard let escape = keyNotationToKeyCode["esc"] else { return nil }
        var hideArgs = WindowHintsCmdArgs(rawArgs: [])
        hideArgs.action = .initialized(.hide)
        let escBinding = HotkeyBinding(
            [],
            escape,
            .cmd(WindowHintsCommand(args: hideArgs) as any Command),
            descriptionWithKeyNotation: "esc",
        )
        bindings[escBinding.descriptionWithKeyCode] = escBinding
        return bindings.isEmpty ? nil : Mode(bindings: bindings)
    }
}
