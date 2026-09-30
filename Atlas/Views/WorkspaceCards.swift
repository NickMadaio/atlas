import AtlasCore
import SwiftUI

/// The repeated rows the workspace is built from. Nothing here draws a card:
/// separation is a fading hairline, and the accent is a 2pt capsule rather
/// than a border.

struct DocumentRow: View {
    let document: AtlasDocumentSnapshot
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    private var accent: Color { theme.collectionColor(document.accent) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Full colour always; width and inset say which row is live.
            Capsule()
                .fill(accent)
                .frame(width: isSelected ? 4 : 2.5)
                .padding(.vertical, isSelected ? 0 : (hovering ? 3 : 8))

            VStack(alignment: .leading, spacing: AtlasSpace.hair) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(document.title)
                        .font(AtlasType.body(16, isSelected ? .bold : .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if document.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.warmAccent)
                    }
                }

                if !document.summary.isEmpty {
                    Text(document.summary)
                        .font(AtlasType.body(13))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    AtlasMicroLabel(text: document.category, tint: accent, size: 9.5)
                    Text(document.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(AtlasType.mono(10))
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, AtlasSpace.tight + 2)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(alignment: .leading) {
            if isSelected {
                LinearGradient(
                    colors: [accent.opacity(0.17), accent.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// A subfolder shown inside its parent's note list, so opening a folder that
/// only contains folders does not look like opening an empty one.
struct FolderRow: View {
    let collection: AtlasCollectionSnapshot
    let noteCount: Int
    let childCount: Int
    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    private var accent: Color { theme.collectionColor(collection.accent) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(for: collection.icon))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(collection.title)
                    .font(AtlasType.body(15, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(AtlasType.mono(10.5))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(hovering ? accent : theme.textSecondary)
        }
        .padding(.vertical, AtlasSpace.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = ["\(noteCount) note\(noteCount == 1 ? "" : "s")"]
        if childCount > 0 { parts.append("\(childCount) folder\(childCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

func symbol(for icon: String) -> String {
    switch icon {
    case "briefcase": "briefcase"
    case "book": "book.closed"
    case "user": "person"
    case "lightbulb": "lightbulb"
    case "settings": "gearshape"
    default: "folder"
    }
}
