import AtlasCore
import SwiftUI

/// Where saved sketches live: one vector file per sketch, beside the library.
enum SketchFiles {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Atlas/Sketches", directoryHint: .isDirectory)
    }

    static func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString.lowercased()).json")
    }
}

/// A saved sketch drawn inside a note, framed around the ink.
struct SketchEmbedView: View {
    let id: UUID
    @Environment(\.atlasPalette) private var theme
    @State private var loaded: Result<SketchDocument, Error>?

    private static let maximumHeight: CGFloat = 420

    var body: some View {
        Group {
            switch loaded {
            case nil:
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            case let .success(document):
                if let bounds = document.page.inkBounds(padding: 24) {
                    drawing(document.page, bounds: bounds)
                } else {
                    placeholder("This sketch is empty.")
                }
            case let .failure(error):
                placeholder(error.localizedDescription)
            }
        }
        .task(id: id) {
            loaded = Result { try SketchDocumentFile.readSaved(from: SketchFiles.url(for: id)) }
        }
    }

    private func drawing(_ page: SketchPage, bounds: SketchRect) -> some View {
        Canvas { context, size in
            let scale = min(Double(size.width) / bounds.width, Double(size.height) / bounds.height)
            let inset = CGPoint(
                x: (Double(size.width) - bounds.width * scale) / 2,
                y: (Double(size.height) - bounds.height * scale) / 2
            )
            let map = { (point: SketchPoint) in
                CGPoint(x: inset.x + (point.x - bounds.minX) * scale, y: inset.y + (point.y - bounds.minY) * scale)
            }
            page.strokes.forEach {
                SketchCanvasRenderer.drawStroke($0, in: context, scale: scale, color: theme.textPrimary, map: map)
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: Self.maximumHeight)
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.divider, lineWidth: 1)
        }
        .accessibilityLabel("Sketch")
    }

    private func placeholder(_ message: String) -> some View {
        Label(message, systemImage: "hand.draw")
            .font(AtlasType.mono(10.5))
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
