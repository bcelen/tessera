public struct PlaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .place,
        help: place_help_generated,
        flags: [
            "--x": singleValueSubArgParser(\.x, "<x>", parsePlaceLength),
            "--y": singleValueSubArgParser(\.y, "<y>", parsePlaceLength),
            "--width": singleValueSubArgParser(\.width, "<width>", parsePlaceLength),
            "--height": singleValueSubArgParser(\.height, "<height>", parsePlaceLength),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [],
    )

    public var x: PlaceLength? = nil
    public var y: PlaceLength? = nil
    public var width: PlaceLength? = nil
    public var height: PlaceLength? = nil
}

/// A coordinate or a size, either in points or as a share of the monitor
public enum PlaceLength: Equatable, Sendable {
    case points(Double)
    /// In `0...1`. Written as a percentage on the command line
    case fraction(Double)

    public func resolve(against total: Double) -> Double {
        switch self {
            case .points(let value): value
            case .fraction(let value): value * total
        }
    }
}

public func parsePlaceLength(_ raw: String) -> ResOrStr<PlaceLength> {
    if raw.hasSuffix("%") {
        guard let percent = Double(raw.dropLast()), percent >= 0, percent <= 100 else {
            return .failure("Can't parse '\(raw)'. A percentage must be between 0% and 100%")
        }
        return .success(.fraction(percent / 100))
    }
    guard let points = Double(raw), points.isFinite, points >= 0 else {
        return .failure("Can't parse '\(raw)'. Expected a non-negative number of points, or a percentage like 50%")
    }
    return .success(.points(points))
}

func parsePlaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<PlaceCmdArgs> {
    parseSpecificCmdArgs(PlaceCmdArgs(rawArgs: args), args)
        .filter("--x and --y must be given together") { ($0.x == nil) == ($0.y == nil) }
        .filter("--width and --height must be given together") { ($0.width == nil) == ($0.height == nil) }
        .filter("Give a position (--x and --y), a size (--width and --height), or both") {
            $0.x != nil || $0.width != nil
        }
}
