import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Saturated system-style hues, tuned to stay bright on the dark violet backdrop.
enum Palette {
    static let cyan = Color(hex: 0x4CD7FF)
    static let blue = Color(hex: 0x2F7BFF)
    static let indigo = Color(hex: 0x6A5CFF)
    static let violet = Color(hex: 0xB15CFF)
    static let pink = Color(hex: 0xFF4F9E)
    static let orange = Color(hex: 0xFF9B3D)
    static let amber = Color(hex: 0xFFD340)
    static let mint = Color(hex: 0x3CF0B4)
    static let green = Color(hex: 0x2FD158)
    static let red = Color(hex: 0xFF453A)
    static let teal = Color(hex: 0x30E3E3)

    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.38)
}

/// A two-stop gradient used for every colored mark, so charts, bars and badges match.
struct Tint {
    let top: Color
    let bottom: Color

    var diagonal: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing) }
    var horizontal: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .leading, endPoint: .trailing) }
    var vertical: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
    /// For chart areas: strong at the top, fading to almost nothing at the baseline.
    var areaFill: LinearGradient {
        LinearGradient(colors: [top.opacity(0.75), bottom.opacity(0.35), bottom.opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
    }

    static let user = Tint(top: Palette.cyan, bottom: Palette.blue)
    static let system = Tint(top: Palette.pink, bottom: Palette.orange)
    static let accent = Tint(top: Palette.blue, bottom: Palette.violet)
    static let good = Tint(top: Palette.mint, bottom: Palette.green)
    static let warn = Tint(top: Palette.amber, bottom: Palette.orange)
    static let bad = Tint(top: Palette.pink, bottom: Palette.red)
    static let wired = Tint(top: Palette.violet, bottom: Palette.indigo)
    static let storage = Tint(top: Palette.teal, bottom: Palette.blue)
    static let network = Tint(top: Palette.pink, bottom: Palette.violet)
    static let neutral = Tint(top: .white.opacity(0.45), bottom: .white.opacity(0.25))

    /// good under 50 %, warning under 75 %, bad above.
    static func load(_ fraction: Double) -> Tint {
        switch fraction {
        case ..<0.5: good
        case ..<0.75: warn
        default: bad
        }
    }
}

/// Smoked glass tinted deep ocean: graphite, petrol and midnight blue with teal and blue light.
/// It is partly transparent, so the panel's own frosted window material and the desktop show through.
/// Static, so it costs nothing per frame.
struct Backdrop: View {
    private static func point(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x, y) }

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    Self.point(0, 0), Self.point(0.5, 0), Self.point(1, 0),
                    Self.point(0, 0.5), Self.point(0.45, 0.55), Self.point(1, 0.5),
                    Self.point(0, 1), Self.point(0.5, 1), Self.point(1, 1),
                ],
                colors: [
                    Color(hex: 0x10202E), Color(hex: 0x123544), Color(hex: 0x16294C),
                    Color(hex: 0x0C1C28), Color(hex: 0x0E3640), Color(hex: 0x132544),
                    Color(hex: 0x0A141E), Color(hex: 0x0B2A30), Color(hex: 0x101B30),
                ]
            )
            .opacity(0.72)

            // Light passing through the glass.
            Circle()
                .fill(Palette.teal.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 150, y: -230)
            Circle()
                .fill(Palette.blue.opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 100)
                .offset(x: -150, y: 260)

            // Glass sheen: a soft highlight across the top that fades out.
            LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.0)],
                           startPoint: .top, endPoint: .center)
        }
        .clipped()
    }
}

/// Frosted glass panel: a faint white fill with a light-catching top edge.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(.white.opacity(0.07), in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

/// Small rounded square with a gradient and a white symbol, like System Settings icons.
struct IconTile: View {
    let symbol: String
    let tint: Tint
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.diagonal, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: tint.bottom.opacity(0.45), radius: 4, y: 1)
    }
}

/// Capsule button used for "Завершити" and the confirm row.
struct PillButton: View {
    enum Style { case glass, accent, danger }

    let title: String
    var style: Style = .glass
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(style == .glass ? Palette.cyan : .white)
                .background {
                    switch style {
                    case .glass: Capsule().fill(.white.opacity(hovering ? 0.17 : 0.09))
                    case .accent: Capsule().fill(Tint.accent.horizontal)
                    case .danger: Capsule().fill(Tint.bad.horizontal)
                    }
                }
                .brightness(hovering && style != .glass ? 0.08 : 0)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering = $0 }
    }
}

/// Instant press feedback, released with a critically damped spring.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(configuration.isPressed ? nil : .spring(duration: 0.3, bounce: 0), value: configuration.isPressed)
    }
}

/// Thin horizontal meter with a gradient fill.
struct UsageBar: View {
    let fraction: Double
    let tint: Tint

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(tint.horizontal)
                    .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                    .shadow(color: tint.top.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 4)
        .animation(.spring(duration: 0.5, bounce: 0), value: fraction)
    }
}

/// Section header: title on the left, a muted detail on the right.
struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            if let detail { Text(detail) }
        }
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundStyle(Palette.textTertiary)
    }
}
