import SwiftUI

/// Modal confirmation box with a row of buttons at the bottom, as used for "Close the software?".
public struct ConsoleDialog: View {
    let message: String
    let detail: String?
    let buttons: [String]
    let destructiveIndex: Int?
    let focusedIndex: Int
    let onSelect: (Int) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(
        message: String,
        detail: String?,
        buttons: [String],
        destructiveIndex: Int?,
        focusedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) {
        self.message = message
        self.detail = detail
        self.buttons = buttons
        self.destructiveIndex = destructiveIndex
        self.focusedIndex = focusedIndex
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: ui(12)) {
                    Text(message)
                        .font(ui.font(23, .medium))
                        .foregroundStyle(theme.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(ui.font(17))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(ui(40))
                .frame(maxWidth: .infinity, minHeight: ui(160))

                Rectangle().fill(theme.divider).frame(height: 1)

                HStack(spacing: 0) {
                    ForEach(buttons.indices, id: \.self) { index in
                        Button { onSelect(index) } label: {
                            Text(buttons[index])
                                .font(ui.font(21, .medium))
                                .foregroundStyle(index == destructiveIndex ? theme.destructive : theme.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: ui(70))
                                .contentShape(Rectangle())
                                .selectionFrame(index == focusedIndex, cornerRadius: ui(6))
                        }
                        .buttonStyle(.plain)
                        if index < buttons.count - 1 {
                            Rectangle().fill(theme.divider).frame(width: 1, height: ui(70))
                        }
                    }
                }
            }
            .frame(width: ui(640))
            .background(RoundedRectangle(cornerRadius: ui(14), style: .continuous).fill(theme.surface))
            .shadow(color: .black.opacity(0.35), radius: ui(30), y: ui(10))
        }
    }
}

/// Small notification bubble shown at the top of the screen.
public struct ToastView: View {
    let message: String
    let symbol: String

    @Environment(\.theme) private var theme
    @Environment(\.ui) private var ui

    public init(message: String, symbol: String = "info.circle.fill") {
        self.message = message
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: ui(12)) {
            Image(systemName: symbol)
                .font(.system(size: ui(20), weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(message)
                .font(ui.font(18, .medium))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, ui(26))
        .padding(.vertical, ui(14))
        .background(Capsule().fill(theme.surface))
        .shadow(color: .black.opacity(0.25), radius: ui(14), y: ui(4))
    }
}
