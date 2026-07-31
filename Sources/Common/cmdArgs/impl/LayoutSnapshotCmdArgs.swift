public struct LayoutSnapshotCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .layoutSnapshot,
        help: layout_snapshot_help_generated,
        flags: [
            "--workspace": workspaceSubArgParser(),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.action, parseSnapshotAction, placeholder: LayoutSnapshotCmdArgs.Action.unionLiteral),
            newOptionalPosArgParser(\.name, consumeStrCliArg),
        ],
    )

    public var action: Lateinit<Action> = .uninitialized
    public var name: String? = nil
    public var failIfNoop: Bool = false

    public enum Action: String, CaseIterable, Sendable {
        case save, restore, delete, list
    }
}

func parseLayoutSnapshotCmdArgs(_ args: StrArrSlice) -> ParsedCmd<LayoutSnapshotCmdArgs> {
    parseSpecificCmdArgs(LayoutSnapshotCmdArgs(rawArgs: args), args)
        .filter("Argument '<name>' is mandatory for \(LayoutSnapshotCmdArgs.Action.save.rawValue), \(LayoutSnapshotCmdArgs.Action.restore.rawValue) and \(LayoutSnapshotCmdArgs.Action.delete.rawValue)") {
            ($0.action.val != .list).implies($0.name != nil)
        }
        .filterNot("'\(LayoutSnapshotCmdArgs.Action.list.rawValue)' doesn't accept '<name>'") { $0.action.val == .list && $0.name != nil }
        .filter("--workspace is only compatible with 'save' and 'restore'") {
            ($0.workspaceName != nil).implies($0.action.val == .save || $0.action.val == .restore)
        }
}

private func parseSnapshotAction(i: PosArgParserInput) -> ParsedCliArgs<LayoutSnapshotCmdArgs.Action> {
    .init(parseEnum(i.arg, LayoutSnapshotCmdArgs.Action.self), advanceBy: 1)
}

/// Same as `newMandatoryPosArgParser`, but the argument may be omitted.
/// `parseSpecificCmdArgs` treats a positional parser without a placeholder as optional
private func newOptionalPosArgParser<Root, Value>(
    _ keyPath: SendableWritableKeyPath<Root, Value?>,
    _ parse: @escaping @Sendable (PosArgParserInput) -> ParsedCliArgs<Value>,
) -> PosArgParser<Root, Value?> {
    ArgParser(keyPath, upcastArgParserFun(parse), argPlaceholderIfMandatory: nil)
}
