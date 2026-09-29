import SwiftUI

// MARK: - Metrics

enum ClipResolvedDesign {
    static let compactSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 32
    static let contentMaxWidth: CGFloat = 1_200
    static let readableWidth: CGFloat = 760
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 420
    static let inspectorMaxWidth: CGFloat = 600
    static let cornerRadius: CGFloat = 10
    static let smallRadius: CGFloat = 6
}

// MARK: - Palette

enum CRTheme: String, CaseIterable {
    case dark
    case light

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var toggleSymbol: String { self == .dark ? "sun.max" : "moon" }
    var toggleHelp: String { self == .dark ? "Switch to light theme" : "Switch to dark theme" }
    var toggled: CRTheme { self == .dark ? .light : .dark }
    var palette: CRPalette { self == .dark ? .dark : .light }
}

struct CRPalette {
    let background: Color
    let card: Color
    let bar: Color
    let surface: Color
    let surfaceAlt: Color
    let border: Color
    let borderStrong: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let accentSoft: Color
    let accentOn: Color
    let success: Color
    let successSoft: Color
    let warm: Color
    let warmSoft: Color
    let danger: Color
    let stripeLight: Color
    let stripeDark: Color

    static let dark = CRPalette(
        background: Color(hex: 0x0F0D0C),
        card: Color(hex: 0x1A1715),
        bar: Color(hex: 0x161311),
        surface: Color(hex: 0x211D1A),
        surfaceAlt: Color(hex: 0x2A2521),
        border: Color(hex: 0xEDE0D1, opacity: 0.10),
        borderStrong: Color(hex: 0xEDE0D1, opacity: 0.14),
        text: Color(hex: 0xF3ECE3),
        textSecondary: Color(hex: 0xA99E92),
        textTertiary: Color(hex: 0x766B60),
        accent: Color(hex: 0x5B8CFF),
        accentSoft: Color(hex: 0x5B8CFF, opacity: 0.14),
        accentOn: Color(hex: 0x0F0D0C),
        success: Color(hex: 0x7FC488),
        successSoft: Color(hex: 0x7FC488, opacity: 0.14),
        warm: Color(hex: 0xF0A860),
        warmSoft: Color(hex: 0xF0A860, opacity: 0.14),
        danger: Color(hex: 0xE2685F),
        stripeLight: Color(hex: 0x2A2521),
        stripeDark: Color(hex: 0x1E1B18)
    )

    static let light = CRPalette(
        background: Color(hex: 0xF5F1EA),
        card: Color(hex: 0xFFFFFF),
        bar: Color(hex: 0xF1EDE7),
        surface: Color(hex: 0xF7F4EF),
        surfaceAlt: Color(hex: 0xECE6DC),
        border: Color(hex: 0x1A1715, opacity: 0.10),
        borderStrong: Color(hex: 0x1A1715, opacity: 0.16),
        text: Color(hex: 0x1A1715),
        textSecondary: Color(hex: 0x5C5449),
        textTertiary: Color(hex: 0x8A8074),
        accent: Color(hex: 0x3D6FE0),
        accentSoft: Color(hex: 0x3D6FE0, opacity: 0.10),
        accentOn: Color(hex: 0xFFFFFF),
        success: Color(hex: 0x2F8A46),
        successSoft: Color(hex: 0x2F8A46, opacity: 0.10),
        warm: Color(hex: 0xB96B1F),
        warmSoft: Color(hex: 0xB96B1F, opacity: 0.10),
        danger: Color(hex: 0xC23B32),
        stripeLight: Color(hex: 0xECE6DC),
        stripeDark: Color(hex: 0xE0D8CB)
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

private struct CRPaletteKey: EnvironmentKey {
    static let defaultValue = CRPalette.dark
}

extension EnvironmentValues {
    var cr: CRPalette {
        get { self[CRPaletteKey.self] }
        set { self[CRPaletteKey.self] = newValue }
    }
}

// MARK: - Type

enum CRFont {
    /// Clip Resolved is operated at arm's length while cards, Resolve, and Finder
    /// are visible together. Keep its type materially larger than macOS's compact
    /// utility defaults instead of forcing every screen to tune tiny point sizes.
    private static let interfaceScale: CGFloat = 1.4

    static func display(_ size: CGFloat) -> Font { .system(size: size * interfaceScale, weight: .heavy) }
    static func title(_ size: CGFloat = 22) -> Font { .system(size: size * interfaceScale, weight: .heavy) }
    static func heading(_ size: CGFloat = 13.5) -> Font { .system(size: size * interfaceScale, weight: .semibold) }
    static func body(_ size: CGFloat = 13.5) -> Font { .system(size: size * interfaceScale, weight: .regular) }
    static func mono(_ size: CGFloat = 11.5, weight: Font.Weight = .regular) -> Font {
        .system(size: size * interfaceScale, weight: weight, design: .monospaced)
    }
}

struct CRLabelStyle: ViewModifier {
    @Environment(\.cr) private var cr
    let size: CGFloat
    func body(content: Content) -> some View {
        content
            .font(CRFont.mono(size, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(cr.textTertiary)
    }
}

extension View {
    func crEyebrow(size: CGFloat = 11) -> some View { modifier(CRLabelStyle(size: size)) }
}

// MARK: - Surfaces

struct CRCard<Content: View>: View {
    @Environment(\.cr) private var cr
    var padding: CGFloat = 16
    var dashed: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cr.surface, in: RoundedRectangle(cornerRadius: ClipResolvedDesign.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipResolvedDesign.cornerRadius)
                    .strokeBorder(
                        dashed ? cr.borderStrong : cr.border,
                        style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : [])
                    )
            }
    }
}

struct CRSection<Content: View>: View {
    @Environment(\.cr) private var cr
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).crEyebrow()
                Spacer()
                if let trailing { trailing }
            }
            CRCard { content }
        }
    }
}

// MARK: - Badges, chips, bars

enum CRTone {
    case neutral, accent, success, warm, danger

    func foreground(_ cr: CRPalette) -> Color {
        switch self {
        case .neutral: cr.textSecondary
        case .accent: cr.accent
        case .success: cr.success
        case .warm: cr.warm
        case .danger: cr.danger
        }
    }

    func background(_ cr: CRPalette) -> Color {
        switch self {
        case .neutral: cr.surfaceAlt
        case .accent: cr.accentSoft
        case .success: cr.successSoft
        case .warm: cr.warmSoft
        case .danger: cr.warmSoft
        }
    }
}

struct CRBadge: View {
    @Environment(\.cr) private var cr
    let text: String
    var tone: CRTone = .neutral

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tone.foreground(cr))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tone.background(cr), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
    }
}

struct CRChip: View {
    @Environment(\.cr) private var cr
    let text: String
    var active: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(active ? cr.accentOn : cr.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(active ? cr.accent : cr.surfaceAlt, in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}

struct CRProgressBar: View {
    @Environment(\.cr) private var cr
    let fraction: Double
    var tint: Color?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(cr.surfaceAlt)
                Capsule()
                    .fill(tint ?? (fraction >= 1 ? cr.success : cr.accent))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// The diagonal-stripe placeholder used wherever a thumbnail has not loaded yet.
struct CRStripe: View {
    @Environment(\.cr) private var cr
    var cornerRadius: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(cr.stripeDark))
            let step: CGFloat = 12
            var x = -size.height
            while x < size.width + size.height {
                var bar = Path()
                bar.move(to: CGPoint(x: x, y: size.height))
                bar.addLine(to: CGPoint(x: x + size.height, y: 0))
                bar.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                bar.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                bar.closeSubpath()
                context.fill(bar, with: .color(cr.stripeLight))
                x += step
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Controls

struct CRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.cr) private var cr
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .bold))
            .foregroundStyle(cr.accentOn)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(cr.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

struct CRSecondaryButtonStyle: ButtonStyle {
    @Environment(\.cr) private var cr
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(cr.text.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(configuration.isPressed ? cr.surfaceAlt : cr.surface,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(cr.borderStrong)
            }
            .contentShape(Rectangle())
    }
}

struct CRLinkButtonStyle: ButtonStyle {
    @Environment(\.cr) private var cr
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(cr.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

/// Square icon button used in the window chrome.
struct CRIconButton: View {
    @Environment(\.cr) private var cr
    let symbol: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(cr.textSecondary)
                .frame(width: 34, height: 34)
                .background(cr.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(cr.borderStrong) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help.isEmpty ? symbol : help)
        .help(help)
    }
}

struct CRFieldStyle: TextFieldStyle {
    @Environment(\.cr) private var cr

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 17))
            .foregroundStyle(cr.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(cr.bar, in: RoundedRectangle(cornerRadius: ClipResolvedDesign.smallRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClipResolvedDesign.smallRadius).strokeBorder(cr.borderStrong)
            }
    }
}

// MARK: - Page furniture

struct PageHeader: View {
    @Environment(\.cr) private var cr
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CRFont.display(26))
                .foregroundStyle(cr.text)
            Text(subtitle)
                .font(CRFont.body(14))
                .foregroundStyle(cr.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CRMetric: View {
    @Environment(\.cr) private var cr
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(cr.text)
            Text(label)
                .font(CRFont.mono(12))
                .foregroundStyle(cr.textTertiary)
        }
    }
}

struct CREmptyState: View {
    @Environment(\.cr) private var cr
    let title: String
    let message: String
    var symbol: String = "tray"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(cr.textTertiary)
            Text(title)
                .font(CRFont.title(18))
                .foregroundStyle(cr.text)
            Text(message)
                .font(CRFont.body(13))
                .foregroundStyle(cr.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ProjectPicker: View {
    @Environment(\.cr) private var cr
    @Bindable var store: AppStore

    var body: some View {
        Picker("Project", selection: $store.selectedProjectID) {
            ForEach(store.projects) { project in
                Text(project.name).tag(Optional(project.id))
            }
        }
        .labelsHidden()
        .controlSize(.large)
        .tint(cr.accent)
        .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
        .accessibilityLabel("Project")
    }
}
