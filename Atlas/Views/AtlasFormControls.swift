import SwiftUI

/// Shared chrome for Atlas's input sheets.
///
/// The app's own surfaces are warm, rounded, and card-based; a stock grouped
/// `Form` reads as a different application bolted on. These pieces give every
/// sheet the same header, fields, and footer so creating a note looks like it
/// belongs to the same product as reading one.
struct AtlasSheetShell<Content: View>: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let confirmTitle: String
    let isConfirmEnabled: Bool
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(theme.heroGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [theme.tintSurface, theme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) { Rectangle().fill(theme.divider).frame(height: 1) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(AtlasQuietButtonStyle())
                .keyboardShortcut(.cancelAction)
            if let secondaryTitle, let onSecondary {
                Button(secondaryTitle, action: onSecondary)
                    .buttonStyle(AtlasQuietButtonStyle())
                    .disabled(!isConfirmEnabled)
                    .opacity(isConfirmEnabled ? 1 : 0.45)
            }
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(AtlasCompactPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isConfirmEnabled)
                .opacity(isConfirmEnabled ? 1 : 0.45)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(theme.surface.opacity(0.8))
        .overlay(alignment: .top) { Rectangle().fill(theme.divider).frame(height: 1) }
    }
}

/// A labelled field. The label sits above the control in the same small-caps
/// style the sidebar uses, so a value like "Notes" can never be mistaken for a
/// static label the way a trailing-aligned form row can.
struct AtlasField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(theme.textSecondary)
                if let hint, !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textSecondary.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            content()
        }
    }
}

struct AtlasInputStyle: ViewModifier {
    var minHeight: CGFloat = 36
    @Environment(\.atlasPalette) private var theme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.divider, lineWidth: 1)
            }
    }
}

extension View {
    func atlasInput(minHeight: CGFloat = 36) -> some View {
        modifier(AtlasInputStyle(minHeight: minHeight))
    }
}

/// Tappable suggestions beside a free-text field, so the common answer is one
/// click and an unusual one is still typeable.
struct AtlasSuggestionChips: View {
    let options: [String]
    @Binding var selection: String
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.caseInsensitiveCompare(option) == .orderedSame
                    Button { selection = option } label: {
                        Text(option)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : theme.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(isSelected ? theme.primary : theme.surface, in: Capsule())
                            .overlay { Capsule().stroke(isSelected ? .clear : theme.divider, lineWidth: 1) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

struct AtlasCompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.atlasPalette) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 34)
            .background(theme.heroGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AtlasQuietButtonStyle: ButtonStyle {
    @Environment(\.atlasPalette) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.divider, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct AtlasDestructiveButtonStyle: ButtonStyle {
    @Environment(\.atlasPalette) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(theme.danger)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(theme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.danger, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
