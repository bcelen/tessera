public struct StickyCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .sticky,
        help: sticky_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [newMandatoryPosArgParser(\.targetState, parseStickyState, placeholder: StickyCmdArgs.State.unionLiteral)],
    )

    public var targetState: Lateinit<State> = .uninitialized
    public var failIfNoop: Bool = false

    public init(rawArgs: [String], targetState: State) {
        self.commonState = .init(rawArgs.slice)
        self.targetState = .initialized(targetState)
    }

    public enum State: String, CaseIterable, Sendable {
        case on, off, toggle
    }
}

func parseStickyCmdArgs(_ args: StrArrSlice) -> ParsedCmd<StickyCmdArgs> {
    parseSpecificCmdArgs(StickyCmdArgs(rawArgs: args), args)
        .filterNot("--fail-if-noop is incompatible with 'toggle' argument") { $0.targetState.val == .toggle && $0.failIfNoop }
}

private func parseStickyState(i: PosArgParserInput) -> ParsedCliArgs<StickyCmdArgs.State> {
    .init(parseEnum(i.arg, StickyCmdArgs.State.self), advanceBy: 1)
}
