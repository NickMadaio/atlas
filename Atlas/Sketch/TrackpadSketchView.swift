#if os(macOS)
import AtlasCore
import SwiftUI

/// The sketch pad window: the trackpad as an absolute-position writing surface.
struct TrackpadSketchView: View {
    @ObservedObject var appModel: AtlasAppModel
    @StateObject private var model = TrackpadSketchModel()
    @Environment(\.atlasPalette) private var theme
    @State private var isSaving = false
    @State private var filedNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            controls
            ZStack(alignment: .bottomLeading) {
                canvas
                SketchMinimap(document: model.document)
                    .padding(16)
            }
        }
        .background(theme.canvas)
        .frame(minWidth: 820, minHeight: 560)
        .sheet(isPresented: $isSaving) {
            if let library = appModel.library {
                SketchSaveSheet(library: library, sketch: model) { title in
                    filedNotice = "Saved to “\(title)”"
                }
            }
        }
    }

    private func beginSave() {
        model.isWriting = false
        filedNotice = nil
        isSaving = true
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                model.isWriting.toggle()
            } label: {
                Label(model.isWriting ? "Stop writing" : "Start writing",
                      systemImage: model.isWriting ? "stop.fill" : "pencil.tip")
            }
            .buttonStyle(AtlasCompactPrimaryButtonStyle())
            .keyboardShortcut(.return, modifiers: .command)

            HStack(spacing: 8) {
                AtlasMicroLabel(text: "pen", size: 9)
                Slider(
                    value: Binding(get: { model.document.penSize }, set: { model.setPenSize($0) }),
                    in: SketchDocument.penSizeRange
                )
                .frame(width: 120)
                Text("\(Int(model.document.penSize))")
                    .font(AtlasType.mono(10))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 20, alignment: .leading)
            }

            Button("Undo", action: model.undo)
                .buttonStyle(AtlasQuietButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button("Clear", action: model.clear)
                .buttonStyle(AtlasQuietButtonStyle())
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.document.page.strokes.isEmpty)

            Button("Save…", action: beginSave)
                .buttonStyle(AtlasQuietButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
                .disabled(model.document.page.strokes.isEmpty || appModel.library == nil)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                if let filedNotice {
                    Text(filedNotice)
                        .font(AtlasType.mono(9.5))
                        .foregroundStyle(theme.primary)
                }
                Text(model.isWriting
                     ? "touch = pen down · WASD move · Q/E zoom · [ ] pen · esc to stop"
                     : "⌘↩ to write — the pointer is held until you stop")
                    .font(AtlasType.mono(9.5))
                    .foregroundStyle(model.isWriting ? theme.primary : theme.textSecondary)
                if let error = model.saveError {
                    Text(error)
                        .font(AtlasType.mono(9.5))
                        .foregroundStyle(theme.danger)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .overlay { TrackpadCaptureView(model: model) }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let document = model.document
        let camera = SketchCamera(viewport: document.viewport, viewSize: size)
        let pageRect = camera.view(SketchRect(minX: 0, minY: 0, width: document.page.size.width, height: document.page.size.height))
        context.fill(Path(pageRect), with: .color(theme.surface))
        SketchCanvasRenderer.drawRules(page: document.page.size, camera: camera, in: context, viewSize: size, color: theme.divider.opacity(0.6))

        let strokes = document.page.strokes + (model.liveStroke.map { [$0.smoothed()] } ?? [])
        strokes.forEach {
            SketchCanvasRenderer.drawStroke($0, in: context, scale: camera.scale, color: theme.textPrimary, map: camera.view)
        }

        let frame = camera.view(document.viewport.rect)
        context.stroke(
            Path(roundedRect: frame, cornerRadius: 10),
            with: .color(theme.primary.opacity(model.isWriting ? 0.9 : 0.45)),
            style: StrokeStyle(lineWidth: model.isWriting ? 2 : 1.5, dash: model.isWriting ? [] : [6, 5])
        )

        if let pen = model.penLocation {
            let point = camera.view(pen)
            let radius = max(document.viewport.pageLineWidth(forPenSize: document.penSize) * camera.scale / 2 + 3, 4)
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(theme.primary),
                lineWidth: 1.5
            )
        }
    }
}

/// The whole page, small, with the trackpad frame on it.
private struct SketchMinimap: View {
    let document: SketchDocument
    @Environment(\.atlasPalette) private var theme
    private let width: CGFloat = 180

    var body: some View {
        let page = document.page.size
        let scale = Double(width) / page.width
        Canvas { context, _ in
            let map = { (p: SketchPoint) in CGPoint(x: p.x * scale, y: p.y * scale) }
            document.page.strokes.forEach {
                SketchCanvasRenderer.drawStroke($0, in: context, scale: scale, color: theme.textPrimary.opacity(0.8), map: map)
            }
            let frame = document.viewport.rect
            context.stroke(
                Path(CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)),
                with: .color(theme.primary),
                lineWidth: 1.5
            )
        }
        .frame(width: width, height: CGFloat(page.height * scale))
        .background(theme.surface.opacity(0.92))
        .overlay { Rectangle().stroke(theme.divider, lineWidth: 1) }
        .allowsHitTesting(false)
    }
}
#endif
