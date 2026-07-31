public struct WindowHintsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .windowHints,
        help: window_hints_help_generated,
        flags: [
            "--visible": trueBoolFlag(\.visibleOnly),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.action, parseHintsAction, placeholder: WindowHintsCmdArgs.Action.unionLiteral),
        ],
    )

    public var action: Lateinit<Action> = .uninitialized
    public var visibleOnly: Bool = false

    public enum Action: String, CaseIterable, Sendable {
        case show, hide, pick
    }
}

func parseWindowHintsCmdArgs(_ args: StrArrSlice) -> ParsedCmd<WindowHintsCmdArgs> {
    parseSpecificCmdArgs(WindowHintsCmdArgs(rawArgs: args), args)
        .filter("--window-id is mandatory for 'pick' and incompatible with the other arguments") {
            ($0.action.val == .pick) == ($0.windowId != nil)
        }
        .filter("--visible is only compatible with 'show'") {
            $0.visibleOnly.implies($0.action.val == .show)
        }
}

private func parseHintsAction(i: PosArgParserInput) -> ParsedCliArgs<WindowHintsCmdArgs.Action> {
    .init(parseEnum(i.arg, WindowHintsCmdArgs.Action.self), advanceBy: 1)
}
