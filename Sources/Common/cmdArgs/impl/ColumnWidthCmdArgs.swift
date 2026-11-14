public struct ColumnWidthCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .columnWidth,
        help: column_width_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.widths, parseWidths, placeholder: "<width>")],
    )

    public var widths: Lateinit<[Width]> = .uninitialized

    public init(rawArgs: [String], widths: [Width]) {
        self.commonState = .init(rawArgs.slice)
        self.widths = .initialized(widths)
    }

    /// In percent of the screen
    public enum Width: Equatable, Sendable {
        case set(UInt)
        case add(UInt)
        case subtract(UInt)
    }
}

func parseColumnWidthCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ColumnWidthCmdArgs> {
    parseSpecificCmdArgs(ColumnWidthCmdArgs(rawArgs: args), args)
        .filter("A relative width (+N% or -N%) must be the only <width>") { args in
            args.widths.val.count == 1 || args.widths.val.allSatisfy {
                if case .set = $0 { true } else { false }
            }
        }
}

private func parseWidths(input: PosArgParserInput) -> ParsedCliArgs<[ColumnWidthCmdArgs.Width]> {
    var result: [ColumnWidthCmdArgs.Width] = []
    var i = input.index
    // Not nonFlagArgs(), since '-10%' looks like a flag
    while input.args.indices.contains(i) && (!input.args[i].isCliDashFlag || input.args[i].isNegativeColumnWidth) {
        let arg = input.args[i]
        let digits = arg.removePrefix("+").removePrefix("-")
        guard let number = UInt(digits.hasSuffix("%") ? String(digits.dropLast()) : digits) else {
            return .fail("Can't parse '\(arg)'. <width> must be a percentage like 50%, +10% or -10%", advanceBy: i - input.index + 1)
        }
        result.append(arg.starts(with: "+") ? .add(number) : arg.starts(with: "-") ? .subtract(number) : .set(number))
        i += 1
    }
    return .succ(result, advanceBy: i - input.index)
}

extension String {
    fileprivate var isNegativeColumnWidth: Bool {
        var iter = makeIterator()
        return iter.next() == "-" && iter.next()?.isNumber == true
    }
}
