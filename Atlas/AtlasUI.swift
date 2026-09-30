import SwiftUI

/*
 Atlas's visual language.

 What this replaces: every element sat inside a filled, rounded card, columns
 were equal-width grids, and the default palette was cream. Boxes were doing
 the work that spacing, type and alignment should be doing, and the result read
 as a settings form rather than as something you want to open.

 Four rules, and the rest follows:

   1. NOTHING IS IN A BOX. Grouping comes from proximity and from a hairline
      that separates without enclosing. A fill is reserved for a genuinely
      primary action or a text field you are meant to type into.

   2. TYPE CARRIES THE HIERARCHY. One idea per block: a tracked micro-label,
      the thing itself at size, its detail smaller and dimmer. If a section
      needs a border to look important, it is not important.

   3. LINE ART, NOT FILLED CHROME. Meters are thin strokes. Actions are
      hairline underlines.

   5. AN ACCENT IS NEVER FADED. Colour always renders at full strength.
      Hover and selection change weight, size, or the wash behind an element —
      never its opacity. A half-opacity accent does not read as "inactive", it
      reads as a washed-out version of the colour, which is worse than no
      colour at all.

   4. OFFSET, NOT GRID. Deliberately unequal widths, deliberately staggered
      starts. A row of three identical cards is the thing being replaced.

 Detail is reached by expanding in place rather than by navigating away, so a
 list stays scannable and nothing is hidden behind a click you have to guess at.
 Numbers are monospaced: proportional digits shift column widths as values
 change, and a page whose numbers jitter reads as unstable even when correct.
*/

/// One spacing scale, so separation is a decision made once rather than a
/// number guessed at each call site.
///
/// The sizes come from what actually reads well on a page of notes: a gap has
/// to be clearly larger than the one below it in the hierarchy, or the reader
/// cannot tell which things belong together. Steps of roughly 1.5x do that;
/// 12 and 14 sitting next to each other do not.
enum AtlasSpace {
    /// Between a label and the thing it labels.
    static let hair: CGFloat = 6
    /// Between lines inside one idea.
    static let tight: CGFloat = 12
    /// Between two ideas.
    static let step: CGFloat = 20
    /// Between two blocks.
    static let block: CGFloat = 32
    /// Between two sections of a document.
    static let section: CGFloat = 46
    /// The page gutter.
    static let gutter: CGFloat = 38
}

enum AtlasType {
    /// The reading size. Notes are read, not skimmed, and 13pt body text was
    /// the single biggest thing making this app feel cramped.
    static func body(_ size: CGFloat = 15.5, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Labels, counts, timecodes, every number.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Headlines and figures.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Structure

/// A hairline that fades out rather than stopping.
///
/// A rule with two hard ends draws a boundary, which is a quiet way of drawing
/// the box this design is avoiding. One that dissolves separates without
/// enclosing.
struct AtlasFadingRule: View {
    var tint: Color?
    var height: CGFloat = 1
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        let colour = tint ?? theme.textSecondary
        LinearGradient(
            colors: [colour.opacity(0.28), colour.opacity(0.10), colour.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: height)
    }
}

/// A tracked micro-label. The smallest voice in the type scale.
struct AtlasMicroLabel: View {
    let text: String
    var tint: Color?
    var size: CGFloat = 10.5
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(AtlasType.mono(size, .semibold))
            .tracking(1.9)
            .foregroundStyle(tint ?? theme.textSecondary)
    }
}

/// A section marker: tracked label with the rule running off to the right.
struct AtlasSectionRule: View {
    let title: String
    var trailing: String?
    var tint: Color?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AtlasMicroLabel(text: title, tint: tint).fixedSize()
            AtlasFadingRule(tint: tint)
            if let trailing {
                AtlasMicroLabel(text: trailing, size: 9.5).fixedSize()
            }
        }
    }
}

// MARK: - Figures

/// One number, set large, its unit kept small so the value dominates.
struct AtlasBigStat: View {
    let value: String
    var unit: String?
    var caption: String?
    var tint: Color?
    var size: CGFloat = 44
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let caption {
                AtlasMicroLabel(text: caption)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(AtlasType.display(size))
                    .foregroundStyle(tint ?? theme.textPrimary)
                if let unit {
                    Text(unit)
                        .font(AtlasType.mono(12))
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }
}

/// A value read at a glance. Thin enough to be an instrument rather than a
/// filled donut competing for attention.
struct AtlasRingMeter: View {
    let progress: Double
    let value: String
    var caption: String?
    var tint: Color?
    var diameter: CGFloat = 92
    @Environment(\.atlasPalette) private var theme

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        let colour = tint ?? theme.primary
        ZStack {
            Circle().stroke(theme.divider, lineWidth: 4)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(colour, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(value)
                    .font(AtlasType.display(diameter * 0.27))
                    .foregroundStyle(theme.textPrimary)
                if let caption {
                    AtlasMicroLabel(text: caption, size: 9)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.45), value: clamped)
    }
}

// MARK: - Actions

/// A hairline underline that brightens on hover. The default action shape.
struct AtlasInlineAction: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    var isDestructive = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        let colour = tint ?? (isDestructive ? theme.danger : theme.primary)
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(AtlasType.mono(11.5, .semibold))
                    .tracking(0.8)
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 10.5, weight: .bold))
                }
            }
            .foregroundStyle(colour)
            // Weight, not opacity: the underline thickens instead of the
            // colour arriving.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(colour)
                    .frame(height: hovering ? 1.5 : 1)
                    .offset(y: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// The one filled shape on a screen, for the single primary action.
struct AtlasSolidAction: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        let colour = tint ?? theme.primary
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 11.5, weight: .bold))
                }
                Text(title)
                    .font(AtlasType.mono(11.5, .bold))
                    .tracking(0.9)
            }
            .foregroundStyle(theme.canvas)
            .padding(.horizontal, 20)
            .frame(height: 38)
            .background(colour, in: Capsule())
            .overlay {
                // Hover lightens the fill rather than un-fading it.
                Capsule().fill(.white.opacity(hovering ? 0.16 : 0))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

// MARK: - Expanding detail

/// A row that shows its headline always and its detail on demand.
///
/// This is how depth is reached everywhere in Atlas: in place, with the short
/// form still saying enough that nothing is hidden behind the disclosure. A
/// list of these stays scannable in a way a list of expanded blocks does not.
struct AtlasExpandingRow<Detail: View>: View {
    let title: String
    var caption: String?
    var accent: Color?
    var trailing: String?
    @Binding var isExpanded: Bool
    @ViewBuilder var detail: () -> Detail

    @State private var hovering = false
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 13) {
                    Capsule()
                        .fill(accent ?? theme.primary)
                        .frame(width: 3, height: isExpanded ? 26 : (hovering ? 21 : 17))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let caption {
                            Text(caption)
                                .font(AtlasType.mono(11))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let trailing {
                        AtlasMicroLabel(text: trailing, size: 9.5)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .black))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, AtlasSpace.tight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }

            if isExpanded {
                detail()
                    .padding(.leading, 16)
                    .padding(.bottom, AtlasSpace.step)
                    .transition(.opacity)
            }

            AtlasFadingRule()
        }
    }
}

/// A label-and-body pair used inside expanded detail.
struct AtlasDetailLine: View {
    let label: String
    let text: String
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AtlasSpace.hair) {
            AtlasMicroLabel(text: label, size: 9.5)
            Text(text)
                .font(AtlasType.body(14))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small status word. The only pill in the design, because a state needs to
/// be findable at a glance in a list.
struct AtlasStateTag: View {
    let text: String
    var tint: Color?
    var showsSpinner = false
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        let colour = tint ?? theme.primary
        HStack(spacing: 5) {
            if showsSpinner {
                ProgressView().controlSize(.mini)
            } else {
                Circle().fill(colour).frame(width: 5, height: 5)
            }
            Text(text.uppercased())
                .font(AtlasType.mono(10, .bold))
                .tracking(1.1)
                .foregroundStyle(colour)
        }
    }
}


/// A block of content with room around it.
///
/// The one place this design does use an enclosure, and it earns it: a page of
/// lecture notes is a run of separate ideas, and the reader has to be able to
/// see where one ends. The enclosure stays quiet — a wash and a hairline, no
/// shadow, no heavy border — so it separates without competing with the words.
struct AtlasPanel<Content: View>: View {
    var accent: Color?
    @ViewBuilder var content: () -> Content
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 28)
            .padding(.trailing, 26)
            .padding(.vertical, 24)
            .background(theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .leading) {
                // A colour stripe rather than a full border: it marks where the
                // block starts without drawing a box around the words.
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent ?? theme.primary)
                    .frame(width: 3)
                    .padding(.vertical, 22)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.divider.opacity(0.5), lineWidth: 1)
            }
    }
}

/// A section heading inside a document: big, coloured, unmistakably the start
/// of something new.
struct AtlasContentHeading: View {
    let title: String
    var tint: Color?
    @Environment(\.atlasPalette) private var theme

    var body: some View {
        Text(title)
            .font(AtlasType.display(21, .bold))
            .foregroundStyle(tint ?? theme.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
