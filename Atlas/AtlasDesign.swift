import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AtlasColorTheme: String, CaseIterable, Identifiable {
    case orion, forest, ocean, violet, ember
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .orion: "Ink and instrument cyan"
        case .forest: "Pine on cool stone"
        case .ocean: "Deep blue and sea glass"
        case .violet: "Indigo and soft lavender"
        case .ember: "Terracotta and warm sand"
        }
    }

    /// Orion is a dark instrument panel. Rendering it light would not be the
    /// same theme with different numbers; it would be a different idea.
    var forcesDarkMode: Bool { self == .orion }
}

enum AtlasAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AtlasLogoStyle: String, CaseIterable, Identifiable {
    case meridian, compass, horizon, monogram
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meridian: "Meridian"
        case .compass: "Compass"
        case .horizon: "Horizon"
        case .monogram: "Orbit A"
        }
    }
    var subtitle: String {
        switch self {
        case .meridian: "A mapped world"
        case .compass: "Direction and discovery"
        case .horizon: "Layered terrain"
        case .monogram: "A simple signature"
        }
    }
}

@MainActor
final class AtlasAppearanceStore: ObservableObject {
    @Published var colorTheme: AtlasColorTheme {
        didSet { defaults.set(colorTheme.rawValue, forKey: Keys.colorTheme) }
    }
    @Published var mode: AtlasAppearanceMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    @Published var logoStyle: AtlasLogoStyle {
        didSet { defaults.set(logoStyle.rawValue, forKey: Keys.logoStyle) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colorTheme = AtlasColorTheme(rawValue: defaults.string(forKey: Keys.colorTheme) ?? "") ?? .orion
        mode = AtlasAppearanceMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .system
        logoStyle = AtlasLogoStyle(rawValue: defaults.string(forKey: Keys.logoStyle) ?? "") ?? .meridian
    }

    var palette: AtlasPalette { .palette(for: colorTheme) }

    /// The scheme actually applied, once a theme that insists on dark has had
    /// its say.
    var effectiveColorScheme: ColorScheme? {
        colorTheme.forcesDarkMode ? .dark : mode.colorScheme
    }

    private enum Keys {
        static let colorTheme = "atlas.appearance.colorTheme"
        static let mode = "atlas.appearance.mode"
        static let logoStyle = "atlas.appearance.logoStyle"
    }
}

struct AtlasPalette {
    let primary: Color
    let primaryStrong: Color
    let highlight: Color
    let warmAccent: Color
    let danger: Color
    let canvas: Color
    let sidebar: Color
    let surface: Color
    let surfaceRaised: Color
    let tintSurface: Color
    let textPrimary: Color
    let textSecondary: Color
    let divider: Color

    var heroGradient: LinearGradient {
        LinearGradient(colors: [primaryStrong, primary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func collectionColor(_ value: String) -> Color {
        switch value {
        case "forest": primary
        case "gold": warmAccent
        default: highlight
        }
    }

    static func palette(for theme: AtlasColorTheme) -> AtlasPalette {
        switch theme {
        case .orion:
            // Fixed rather than adaptive: this palette is the dark one.
            AtlasPalette(
                primary: Color(hex: 0x2ED4FF), primaryStrong: Color(hex: 0x0B6E93),
                highlight: Color(hex: 0xB38BFF), warmAccent: Color(hex: 0xFF9A3D), danger: Color(hex: 0xFF6B6B),
                canvas: Color(hex: 0x04060B), sidebar: Color(hex: 0x070A11),
                surface: Color(hex: 0x0C1119), surfaceRaised: Color(hex: 0x131A25),
                tintSurface: Color(hex: 0x0D2531), textPrimary: Color(hex: 0xF2F6FA),
                textSecondary: Color(hex: 0x8695A6), divider: Color(hex: 0x1A2330)
            )
        case .forest:
            AtlasPalette(
                primary: Color(hex: 0x16B486), primaryStrong: Color(hex: 0x0A6E55),
                highlight: Color(hex: 0x3D9AE0), warmAccent: Color(hex: 0xF7A81B), danger: Color(hex: 0xF05B45),
                canvas: adaptiveColor(light: 0xF3F6F5, dark: 0x0B100E), sidebar: adaptiveColor(light: 0xEAEFED, dark: 0x0E1412),
                surface: adaptiveColor(light: 0xFCFDFD, dark: 0x141C19), surfaceRaised: adaptiveColor(light: 0xFFFFFF, dark: 0x1B2521),
                tintSurface: adaptiveColor(light: 0xDCEDE6, dark: 0x153229), textPrimary: adaptiveColor(light: 0x141C19, dark: 0xF3F5F1),
                textSecondary: adaptiveColor(light: 0x5C6864, dark: 0xA3B1AB), divider: adaptiveColor(light: 0xDCE3E0, dark: 0x27332E)
            )
        case .ocean:
            AtlasPalette(
                primary: Color(hex: 0x1499D8), primaryStrong: Color(hex: 0x0B4E7A),
                highlight: Color(hex: 0x1FCBBF), warmAccent: Color(hex: 0xF7B23B), danger: Color(hex: 0xF05C5B),
                canvas: adaptiveColor(light: 0xF2F6F8, dark: 0x0D151B), sidebar: adaptiveColor(light: 0xE7EFF3, dark: 0x101C24),
                surface: adaptiveColor(light: 0xFCFEFF, dark: 0x17252E), surfaceRaised: adaptiveColor(light: 0xFFFFFF, dark: 0x1E303B),
                tintSurface: adaptiveColor(light: 0xDCEFF3, dark: 0x173A46), textPrimary: adaptiveColor(light: 0x16232B, dark: 0xF1F7F9),
                textSecondary: adaptiveColor(light: 0x5C6B73, dark: 0xA9BBC4), divider: adaptiveColor(light: 0xD4E0E5, dark: 0x2B414E)
            )
        case .violet:
            AtlasPalette(
                primary: Color(hex: 0x8A6BFF), primaryStrong: Color(hex: 0x4632A0),
                highlight: Color(hex: 0xE05FCB), warmAccent: Color(hex: 0xF5A63C), danger: Color(hex: 0xF0576B),
                canvas: adaptiveColor(light: 0xF6F3F9, dark: 0x141219), sidebar: adaptiveColor(light: 0xECE8F1, dark: 0x1A1621),
                surface: adaptiveColor(light: 0xFFFDFE, dark: 0x231E2A), surfaceRaised: adaptiveColor(light: 0xFFFFFF, dark: 0x2D2636),
                tintSurface: adaptiveColor(light: 0xE9E1F4, dark: 0x352A49), textPrimary: adaptiveColor(light: 0x241D2C, dark: 0xF7F2FA),
                textSecondary: adaptiveColor(light: 0x6B6172, dark: 0xBDB0C5), divider: adaptiveColor(light: 0xDED6E4, dark: 0x453B50)
            )
        case .ember:
            AtlasPalette(
                primary: Color(hex: 0xF0653F), primaryStrong: Color(hex: 0x8E3524),
                highlight: Color(hex: 0xE86E92), warmAccent: Color(hex: 0xF7A722), danger: Color(hex: 0xEE3944),
                canvas: adaptiveColor(light: 0xF8F2EA, dark: 0x181310), sidebar: adaptiveColor(light: 0xF0E7DC, dark: 0x211814),
                surface: adaptiveColor(light: 0xFFFCF8, dark: 0x2B201B), surfaceRaised: adaptiveColor(light: 0xFFFFFF, dark: 0x362821),
                tintSurface: adaptiveColor(light: 0xF4E1D4, dark: 0x4A2A22), textPrimary: adaptiveColor(light: 0x2B201B, dark: 0xFFF5ED),
                textSecondary: adaptiveColor(light: 0x71635A, dark: 0xC8B5AA), divider: adaptiveColor(light: 0xE4D7CB, dark: 0x533F35)
            )
        }
    }
}

private struct AtlasPaletteKey: EnvironmentKey { static let defaultValue = AtlasPalette.palette(for: .forest) }
private struct AtlasLogoStyleKey: EnvironmentKey { static let defaultValue = AtlasLogoStyle.meridian }

extension EnvironmentValues {
    var atlasPalette: AtlasPalette {
        get { self[AtlasPaletteKey.self] }
        set { self[AtlasPaletteKey.self] = newValue }
    }
    var atlasLogoStyle: AtlasLogoStyle {
        get { self[AtlasLogoStyleKey.self] }
        set { self[AtlasLogoStyleKey.self] = newValue }
    }
}

private func adaptiveColor(light: UInt, dark: UInt) -> Color {
    #if os(macOS)
    Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
    })
    #else
    Color(uiColor: UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
    #endif
}

#if os(macOS)
private extension NSColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

private extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct AtlasLogo: View {
    var size: CGFloat = 42
    var inverted = false
    @Environment(\.atlasPalette) private var theme
    @Environment(\.atlasLogoStyle) private var logoStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(inverted ? LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing) : theme.heroGradient)
            logoGlyph.foregroundStyle(.white).padding(size * 0.18)
        }
        .frame(width: size, height: size)
        .shadow(color: theme.primaryStrong.opacity(inverted ? 0.08 : 0.20), radius: size * 0.16, y: size * 0.08)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var logoGlyph: some View {
        switch logoStyle {
        case .meridian:
            ZStack {
                Circle().stroke(lineWidth: max(1.4, size * 0.045))
                Ellipse().stroke(lineWidth: max(1.1, size * 0.035)).frame(width: size * 0.30)
                Capsule().frame(height: max(1.1, size * 0.035)).padding(.horizontal, size * 0.04)
            }
        case .compass:
            ZStack {
                Circle().stroke(lineWidth: max(1.1, size * 0.035)).opacity(0.72)
                Image(systemName: "location.north.fill").font(.system(size: size * 0.43, weight: .medium)).rotationEffect(.degrees(31))
            }
        case .horizon:
            Canvas { context, canvasSize in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: canvasSize.height * 0.72))
                path.addLine(to: CGPoint(x: canvasSize.width * 0.27, y: canvasSize.height * 0.44))
                path.addLine(to: CGPoint(x: canvasSize.width * 0.43, y: canvasSize.height * 0.59))
                path.addLine(to: CGPoint(x: canvasSize.width * 0.66, y: canvasSize.height * 0.27))
                path.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height * 0.70))
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: max(1.5, size * 0.045), lineCap: .round, lineJoin: .round))
                for offset in [0.82, 0.98] {
                    var contour = Path()
                    contour.move(to: CGPoint(x: 0, y: canvasSize.height * offset))
                    contour.addCurve(to: CGPoint(x: canvasSize.width, y: canvasSize.height * (offset - 0.04)), control1: CGPoint(x: canvasSize.width * 0.30, y: canvasSize.height * (offset - 0.12)), control2: CGPoint(x: canvasSize.width * 0.66, y: canvasSize.height * (offset + 0.07)))
                    context.stroke(contour, with: .color(.white.opacity(0.76)), lineWidth: max(1, size * 0.032))
                }
            }
        case .monogram:
            ZStack {
                Text("A").font(.system(size: size * 0.50, weight: .black, design: .rounded))
                Ellipse().trim(from: 0.08, to: 0.82).stroke(style: StrokeStyle(lineWidth: max(1.2, size * 0.038), lineCap: .round)).frame(height: size * 0.34).rotationEffect(.degrees(-18))
            }
        }
    }
}

struct AtlasCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    @Environment(\.atlasPalette) private var theme
    func body(content: Content) -> some View {
        content.padding(padding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(theme.divider.opacity(0.70), lineWidth: 1) }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 7)
    }
}

extension View {
    func atlasCard(padding: CGFloat = 20, radius: CGFloat = 20) -> some View { modifier(AtlasCardModifier(padding: padding, radius: radius)) }
    @ViewBuilder func atlasSheetFrame(macWidth: CGFloat, minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: macWidth, minHeight: minHeight)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
    func atlasClickableArea<S: Shape>(_ shape: S) -> some View { frame(maxWidth: .infinity, alignment: .leading).contentShape(shape) }
}

struct AtlasPrimaryButtonStyle: ButtonStyle {
    @Environment(\.atlasPalette) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
            .background(LinearGradient(colors: [theme.primary, theme.primaryStrong], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1).opacity(configuration.isPressed ? 0.90 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AtlasAppearanceView: View {
    @ObservedObject var store: AtlasAppearanceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.atlasPalette) private var theme
    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    appearanceSection("Appearance", subtitle: "Choose how Atlas follows your environment.") {
                        Picker("Appearance", selection: $store.mode) {
                            ForEach(AtlasAppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.segmented)
                    }
                    appearanceSection("Color", subtitle: "The structure stays familiar while the atmosphere changes.") {
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(AtlasColorTheme.allCases) { themeChoice($0) } }
                    }
                    appearanceSection("Atlas mark", subtitle: "Four vector logo concepts. Pick one now and change it whenever you want.") {
                        LazyVGrid(columns: columns, spacing: 12) { ForEach(AtlasLogoStyle.allCases) { logoChoice($0) } }
                    }
                }.padding(24)
            }
            .background(theme.canvas).navigationTitle("Personalize Atlas")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .atlasSheetFrame(macWidth: 660, minHeight: 680).presentationBackground(theme.canvas)
    }

    private func appearanceSection<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()).foregroundStyle(theme.textPrimary)
                Text(subtitle).font(.subheadline).foregroundStyle(theme.textSecondary)
            }
            content()
        }
    }

    private func themeChoice(_ colorTheme: AtlasColorTheme) -> some View {
        let preview = AtlasPalette.palette(for: colorTheme)
        let selected = store.colorTheme == colorTheme
        return Button { store.colorTheme = colorTheme } label: {
            HStack(spacing: 13) {
                HStack(spacing: -8) {
                    Circle().fill(preview.primaryStrong).frame(width: 31, height: 31)
                    Circle().fill(preview.primary).frame(width: 31, height: 31)
                    Circle().fill(preview.warmAccent).frame(width: 31, height: 31)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(colorTheme.title).font(.headline).foregroundStyle(theme.textPrimary)
                    Text(colorTheme.subtitle).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? theme.primary : theme.textSecondary.opacity(0.55))
            }.padding(14).atlasClickableArea(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(selected ? theme.tintSurface : theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(selected ? theme.primary.opacity(0.58) : theme.divider, lineWidth: 1) }
        }.buttonStyle(.plain)
    }

    private func logoChoice(_ style: AtlasLogoStyle) -> some View {
        let selected = store.logoStyle == style
        return Button { store.logoStyle = style } label: {
            HStack(spacing: 13) {
                AtlasLogo(size: 54).environment(\.atlasLogoStyle, style)
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.title).font(.headline).foregroundStyle(theme.textPrimary)
                    Text(style.subtitle).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? theme.primary : theme.textSecondary.opacity(0.55))
            }.padding(14).atlasClickableArea(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .background(selected ? theme.tintSurface : theme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 17).stroke(selected ? theme.primary.opacity(0.58) : theme.divider, lineWidth: 1) }
        }.buttonStyle(.plain)
    }
}
