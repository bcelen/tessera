import Common
import Foundation
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @Environment(\.colorScheme) var menuColorScheme: ColorScheme
    @EnvironmentObject var viewModel: TrayMenuModel
    let color: Color?
    let style: MenuBarStyle?

    let hStackSpacing = CGFloat(6)
    let itemSize = CGFloat(40)
    let itemBorderSize = CGFloat(3)
    let itemCornerRadius = CGFloat(6)

    private var finalColor: Color {
        return color ?? (menuColorScheme == .dark ? Color.white : Color.black)
    }

    init(style: MenuBarStyle? = nil, color: Color? = nil) {
        self.style = style
        self.color = color
    }

    var body: some View {
        if #available(macOS 14, *) { // https://github.com/nikitabobko/AeroSpace/issues/1122
            let renderer = ImageRenderer(content: menuBarContent)
            switch renderer.cgImage {
                // Using scale: 1 results in a blurry image for unknown reasons
                case let cgImage?: Image(cgImage, scale: 2, label: Text(viewModel.trayText))

                // In case image can't be rendered fallback to plain text
                case nil: Text(viewModel.trayText)
            }
        } else { // macOS 13 and lower
            Text(viewModel.trayText)
        }
    }

    var menuBarContent: some View {
        return HStack(spacing: hStackSpacing) {
            let style = style ?? viewModel.experimentalUISettings.displayStyle
            switch style {
                case .monospacedText: getText(for: .monospaced)
                case .systemText: getText(for: .default)
                case .squares: squares
                case .i3:
                    squares
                    let workspaces = viewModel.workspaces.filter { !$0.isEffectivelyEmpty && !$0.isVisible }
                    if !workspaces.isEmpty {
                        otherWorkspaces(with: workspaces)
                    }
                case .i3Ordered:
                    let modeItem = viewModel.trayItems.first { $0.type == .mode }
                    if let modeItem {
                        itemView(for: modeItem)
                        modeSeparator(with: .monospaced)
                    }
                    let orderedWorkspaces = viewModel.workspaces.filter { !$0.isEffectivelyEmpty || $0.isVisible }
                    ForEach(orderedWorkspaces, id: \.name) { item in
                        let trayItem = TrayItem(
                            type: .workspace,
                            name: item.name,
                            isActive: item.isFocused,
                            hasFullscreenWindows: item.hasFullscreenWindows,
                        )
                        itemView(for: trayItem)
                            .opacity(item.isVisible ? 1 : 0.5)
                    }
                case .tessera:
                    if let modeItem = viewModel.trayItems.first(where: { $0.type == .mode }) {
                        itemView(for: modeItem)
                        modeSeparator(with: .monospaced)
                    }
                    tesseraGlyph
            }
        }
    }

    /// The app icon in miniature: a large tile carrying the focused workspace's name, and a column of
    /// smaller tiles ending in the icon's red one. Drawn at the same 40-unit height as the squares,
    /// which the menu bar renders at half size
    private var tesseraGlyph: some View {
        let workspaces = viewModel.trayItems.filter { $0.type == .workspace }
        let name = (workspaces.first(where: \.isActive) ?? workspaces.first)?.name ?? ""
        let gap = CGFloat(3)
        let tile = (itemSize - gap) / 2
        let mini = (tile - gap) / 2
        let label = Text(name)
            .font(.system(size: 26, weight: .bold))
            .padding(.horizontal, 6)
            .frame(minWidth: tile * 1.6)
            .frame(height: itemSize)
        return HStack(alignment: .top, spacing: gap) {
            ZStack {
                label.background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                }
                label.blendMode(.destinationOut)
            }
            .compositingGroup()
            VStack(alignment: .trailing, spacing: gap) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .frame(width: tile, height: tile)
                HStack(alignment: .bottom, spacing: gap) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .frame(width: mini, height: tile)
                    VStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .frame(width: mini, height: mini)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(tesseraRed)
                            .frame(width: mini, height: mini)
                    }
                }
            }
        }
        .foregroundStyle(finalColor)
        .frame(height: itemSize)
    }

    private func getText(for design: Font.Design) -> some View {
        Text(viewModel.trayText)
            .font(.system(.largeTitle, design: design))
            .foregroundStyle(finalColor)
    }

    private var squares: some View {
        ForEach(viewModel.trayItems, id: \.id) { item in
            itemView(for: item)
            if item.type == .mode {
                modeSeparator(with: .monospaced)
            }
        }
    }

    private func otherWorkspaces(with otherWorkspaces: [WorkspaceViewModel]) -> some View {
        Group {
            Text("|")
                .font(.system(.largeTitle))
                .foregroundStyle(finalColor)
                .bold()
                .padding(.bottom, 6)
            ForEach(otherWorkspaces, id: \.name) { item in
                itemView(for: TrayItem(type: .workspace, name: item.name, isActive: false, hasFullscreenWindows: item.hasFullscreenWindows))
            }
        }
        .opacity(0.6)
    }

    private func modeSeparator(with design: Font.Design) -> some View {
        Text(":")
            .font(.system(.largeTitle, design: design))
            .foregroundStyle(finalColor)
            .bold()
    }

    @ViewBuilder
    fileprivate func itemView(for item: TrayItem) -> some View {
        let view = itemSubView(for: item)
        if item.hasFullscreenWindows {
            let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter, miterLimit: 10, dash: [10, 5], dashPhase: 3)
            view
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                        .strokeBorder(finalColor, style: strokeStyle)
                }
        } else {
            view
        }
    }

    @ViewBuilder
    fileprivate func itemSubView(for item: TrayItem) -> some View {
        // If workspace name contains emojis we use the plain emoji in text to avoid visibility issues scaling the emoji to fit the squares
        if item.name.containsEmoji() {
            Text(item.name)
                .font(.system(.largeTitle))
                .foregroundStyle(finalColor)
                .frame(height: itemSize)
        } else {
            if let imageName = item.systemImageName {
                Image(systemName: imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(finalColor)
                    .frame(width: itemSize, height: itemSize)
            } else {
                let text = Text(item.name)
                    .font(.system(.largeTitle))
                    .bold()
                    .padding(.horizontal, itemBorderSize * 2)
                    .frame(height: itemSize)
                if item.isActive {
                    ZStack {
                        text.background {
                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .circular)
                        }
                        text.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .foregroundStyle(finalColor)
                    .frame(height: itemSize)
                } else {
                    text.background {
                        RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                            .strokeBorder(lineWidth: itemBorderSize)
                    }
                    .foregroundStyle(finalColor)
                    .frame(height: itemSize)
                }
            }
        }
    }
}

extension String {
    fileprivate func containsEmoji() -> Bool {
        unicodeScalars.contains { $0.properties.isEmoji && $0.properties.isEmojiPresentation }
    }
}

/// The red tile from the app icon
private let tesseraRed = Color(red: 0.91, green: 0.20, blue: 0.11)
