import SwiftUI
import UIKit

// MARK: - 資源庫 paper look
//
// 資源庫's own visual language (maintainer's reference, 2026-11-04): a warm off-white page,
// a serif title, ink-green accents and cards that sit on the page like sheets rather than
// panels. Deliberately scoped here: every other page keeps `DSColor` / `DSFont`, so this
// cannot leak into 書架, 探索 or the reader.
//
// Colours are resolved per `colorScheme` instead of going through `DSColor`, so an imported
// appearance pack cannot turn the page into something else while this look is on.

enum PaperPalette {
    static func page(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x15160F) : hex(0xF7F4EC)
    }

    static func pageTop(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x1A1B13) : hex(0xFCFAF4)
    }

    static func pageBottom(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x121309) : hex(0xF2EEE1)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x21221A) : hex(0xFFFFFF)
    }

    /// 墨綠: the accent this page is built around.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x9DBBA4) : hex(0x2F4A3A)
    }

    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0xEFEDE4) : hex(0x23281E)
    }

    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0xA9AA9E) : hex(0x73776A)
    }

    static func textTertiary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x7C7D71) : hex(0x9B9E91)
    }

    /// The square behind a card's symbol: warm paper, not the theme's tinted fill.
    static func iconTile(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x2C2D25) : hex(0xF1EDE0)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? hex(0x32332B) : hex(0xE8E3D5)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.34 : 0.055)
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Type

enum PaperFont {
    /// A serif title. 宋體 when the system has it (it does on every iOS the app supports),
    /// SwiftUI's serif otherwise: a name `UIFont` cannot resolve would draw as 黑體, which is
    /// the one thing this page must not look like.
    ///
    /// Main-actor: `UIFont(name:size:)` is, and only views ask for this.
    @MainActor
    static func serif(_ size: CGFloat, bold: Bool = true) -> Font {
        let names = bold
            ? ["SongtiSC-Bold", "STSongti-SC-Bold", "Songti SC"]
            : ["SongtiSC-Regular", "STSongti-SC-Regular", "Songti SC"]
        for name in names where UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
    }
}

// MARK: - Background

/// The page: a warm gradient with a faint sprig of leaves at the top trailing corner, the
/// way the reference draws its paper.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [
                    PaperPalette.pageTop(scheme),
                    PaperPalette.page(scheme),
                    PaperPalette.pageBottom(scheme),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            PaperLeafSprig()
                .stroke(PaperPalette.ink(scheme).opacity(scheme == .dark ? 0.10 : 0.075), lineWidth: 1)
                .frame(width: 190, height: 280)
                .rotationEffect(.degrees(6))
                .offset(x: 62, y: -46)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}

/// One stem with five leaves, drawn rather than shipped as an asset: it has to tint with the
/// scheme and cost nothing in the bundle.
private struct PaperLeafSprig: Shape {
    private struct Leaf {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let angle: Double
    }

    private static let leaves: [Leaf] = [
        Leaf(x: 96, y: 232, width: 62, height: 26, angle: -34),
        Leaf(x: 104, y: 186, width: 70, height: 28, angle: 26),
        Leaf(x: 92, y: 140, width: 64, height: 26, angle: -30),
        Leaf(x: 100, y: 94, width: 58, height: 24, angle: 30),
        Leaf(x: 90, y: 52, width: 48, height: 20, angle: -22),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // The stem, curving up from the page's edge.
        path.move(to: CGPoint(x: 118, y: 272))
        path.addQuadCurve(to: CGPoint(x: 84, y: 18), control: CGPoint(x: 70, y: 150))

        for leaf in Self.leaves {
            let box = CGRect(x: leaf.x, y: leaf.y, width: leaf.width, height: leaf.height)
            let outline = Path { p in
                p.move(to: CGPoint(x: box.minX, y: box.midY))
                p.addQuadCurve(
                    to: CGPoint(x: box.maxX, y: box.midY),
                    control: CGPoint(x: box.midX, y: box.minY)
                )
                p.addQuadCurve(
                    to: CGPoint(x: box.minX, y: box.midY),
                    control: CGPoint(x: box.midX, y: box.maxY)
                )
                p.closeSubpath()
            }
            let rotation = CGAffineTransform(translationX: box.midX, y: box.midY)
                .rotated(by: leaf.angle * .pi / 180)
                .translatedBy(x: -box.midX, y: -box.midY)
            path.addPath(outline.applying(rotation))

            // The leaf's midrib, so it reads as a leaf and not a lozenge.
            var rib = Path()
            rib.move(to: CGPoint(x: box.minX, y: box.midY))
            rib.addQuadCurve(
                to: CGPoint(x: box.maxX, y: box.midY),
                control: CGPoint(x: box.midX, y: box.midY - 1.5)
            )
            path.addPath(rib.applying(rotation))
        }

        return path
    }
}

// MARK: - Surfaces

extension View {
    /// A sheet of paper on the page: white, generously rounded, with a hairline and a shadow
    /// soft enough that cards read as stacked rather than floating.
    func paperCard(radius: CGFloat = 22) -> some View {
        modifier(PaperCardSurface(radius: radius))
    }
}

private struct PaperCardSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape
                    .fill(PaperPalette.card(scheme))
                    .shadow(color: PaperPalette.shadow(scheme), radius: 14, x: 0, y: 6)
            }
            .overlay {
                shape.strokeBorder(PaperPalette.hairline(scheme).opacity(0.85), lineWidth: 0.8)
            }
    }
}

// MARK: - Header

/// 資源庫's masthead: the page's name in 宋體, a quiet line under it, and the page's menu.
struct PaperPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(PaperFont.serif(32))
                    .foregroundStyle(PaperPalette.textPrimary(scheme))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PaperPalette.textSecondary(scheme))
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, DSSpacing.sm)
    }
}

/// A section's name: a small ink-green symbol, the name in spaced small caps, and whatever
/// manages the section on the trailing edge.
struct PaperSectionHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var accessory: () -> Accessory
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, symbol: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.symbol = symbol
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PaperPalette.ink(scheme).opacity(0.85))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(PaperPalette.ink(scheme).opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            accessory()
                .font(.system(size: 12))
                .foregroundStyle(PaperPalette.textTertiary(scheme))
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Search

/// The page's search: a capsule of paper rather than the system's field in the bar, so the
/// masthead stays the first thing read.
struct PaperSearchField: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.colorScheme) private var scheme
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PaperPalette.textTertiary(scheme))

            TextField(prompt, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(PaperPalette.textPrimary(scheme))
                .tint(PaperPalette.ink(scheme))
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(PaperPalette.textTertiary(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("清除"))
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .frame(height: 44)
        .background {
            Capsule(style: .continuous)
                .fill(PaperPalette.card(scheme).opacity(scheme == .dark ? 0.9 : 0.92))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(PaperPalette.hairline(scheme), lineWidth: 0.8)
        }
        .shadow(color: PaperPalette.shadow(scheme), radius: isFocused ? 10 : 6, x: 0, y: 3)
    }
}

// MARK: - No-trailing / no-accessory forms

extension PaperPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension PaperSectionHeader where Accessory == EmptyView {
    init(_ title: String, symbol: String) {
        self.init(title, symbol: symbol) { EmptyView() }
    }
}
