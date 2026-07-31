import AppKit
import SwiftUI

struct WindowHint: Identifiable, Equatable {
    let key: String
    let windowId: UInt32
    let appName: String
    let workspace: String
    let title: String

    var id: UInt32 { windowId }
}

private let panelWidth: CGFloat = 620
private let rowHeight: CGFloat = 26
private let verticalPadding: CGFloat = 16

@MainActor
final class WindowHintsPanel: NSPanelHud {
    static var shared: WindowHintsPanel = WindowHintsPanel()

    override private init() {
        super.init()
    }

    func show(_ hints: [WindowHint]) {
        let height = CGFloat(hints.count) * rowHeight + verticalPadding * 2
        contentView?.subviews.removeAll()
        let hostingView = NSHostingView(rootView: WindowHintsView(hints: hints))
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        contentView?.addSubview(hostingView)

        // AppKit screen coordinates, not AeroSpace's top-left normalized ones
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: panelWidth, height: height)
        let origin = CGPoint(
            x: screen.origin.x + (screen.width - panelWidth) / 2,
            y: screen.origin.y + (screen.height - height) / 2,
        )
        setFrame(NSRect(origin: origin, size: CGSize(width: panelWidth, height: height)), display: true)
        orderFrontRegardless()
    }

    func hide() {
        contentView?.subviews.removeAll()
        close()
    }
}

struct WindowHintsView: View {
    let hints: [WindowHint]

    @Environment(\.colorScheme) var colorScheme: ColorScheme
    private var fontColor: Color { colorScheme == .dark ? Color.white : Color.black }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.9))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hints) { hint in
                    HStack(spacing: 8) {
                        Text(hint.key.uppercased())
                            .font(.system(.body, design: .monospaced).bold())
                            .frame(width: 22, alignment: .center)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.55)))
                        Text(hint.appName)
                            .font(.system(.body).bold())
                            .frame(width: 150, alignment: .leading)
                            .lineLimit(1)
                        Text(hint.title)
                            .font(.system(.body))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(hint.workspace)
                            .font(.system(.caption, design: .monospaced))
                            .opacity(0.75)
                    }
                    .frame(height: rowHeight)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
        }
        .foregroundStyle(fontColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: panelWidth)
    }
}
