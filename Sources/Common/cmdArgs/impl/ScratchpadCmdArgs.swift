public struct ScratchpadCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scratchpad,
        help: scratchpad_help_generated,
        flags: [
            "--name": singleValueSubArgParser(\._name, "<name>", Result.success),
            "--window-id": windowIdSubArgParser(),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.action, parseScratchpadAction, placeholder: ScratchpadCmdArgs.Action.unionLiteral),
        ],
    )

    public var action: Lateinit<Action> = .uninitialized
    public var _name: String? = nil
    public var failIfNoop: Bool = false

    public enum Action: String, CaseIterable, Sendable {
        case move, show, hide, toggle, release
    }
}

extension ScratchpadCmdArgs {
    public var name: String { _name ?? defaultScratchpadName }
}

public let defaultScratchpadName = "default"

func parseScratchpadCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ScratchpadCmdArgs> {
    parseSpecificCmdArgs(ScratchpadCmdArgs(rawArgs: args), args)
        .filter("--window-id is only compatible with 'move' and 'release'") {
            ($0.windowId != nil).implies($0.action.val == .move || $0.action.val == .release)
        }
        .filterNot("--fail-if-noop is incompatible with 'toggle'") { $0.failIfNoop && $0.action.val == .toggle }
}

private func parseScratchpadAction(i: PosArgParserInput) -> ParsedCliArgs<ScratchpadCmdArgs.Action> {
    .init(parseEnum(i.arg, ScratchpadCmdArgs.Action.self), advanceBy: 1)
}
