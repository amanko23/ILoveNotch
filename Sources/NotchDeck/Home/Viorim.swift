// SPDX-License-Identifier: MIT
import SwiftUI

/// The Viorim OS design kit's dark theme (Gunmetal), as NotchDeck draws on its glass: role colours,
/// radii, type roles and the two springs. Values are the kit's `tokens.json`; fonts are the
/// system's in the kit's roles (thin numbers, monospaced capital labels) until its typefaces are
/// licensed for this project.
enum Viorim {
    // MARK: Colour (dark)

    static let surface = rgb(0x1B1F23)
    static let surfaceRaised = rgb(0x252A30)
    static let surfaceSunken = rgb(0x0C0E10)
    static let ink = rgb(0xE9EDF0)
    static let ink2 = rgb(0xB3BCC5)
    static let ink3 = rgb(0x8E98A2)
    static let separator = rgb(0x2E353C)
    /// The one interactive accent: progress, selection, the working dot.
    static let accent = rgb(0x9DB2CB)
    /// The Frost capsule of the one primary action.
    static let action = rgb(0xE2E8EC)
    static let onAction = rgb(0x22272B)
    static let highlight = rgb(0x2C3E55)
    static let danger = rgb(0xFF8B7E)
    static let dangerSoft = rgb(0x3B1D1A)
    static let warning = rgb(0xF2B25C)
    static let warningSoft = rgb(0x3A2A12)
    static let success = rgb(0x6FCF97)
    static let successSoft = rgb(0x16301F)
    static let info = rgb(0x8FB6E0)
    static let infoSoft = rgb(0x1A2938)
    static let glassRim = rgb(0xE9EDF0).opacity(0.1)
    static let heroTint = rgb(0x7FA2C9).opacity(0.2)
    static let heroRim = rgb(0x9DB2CB).opacity(0.28)
    static let glowSteel = rgb(0x7FA2C9).opacity(0.38)

    // MARK: Shape: concentric inside the notch's 26 pt corners

    static let radiusTile: CGFloat = 14  // radius-md
    static let radiusWell: CGFloat = 10  // radius-sm

    // MARK: Type roles

    /// `label`: capitals in the monospaced face, for tile titles and group labels.
    static func label(_ size: CGFloat = 9.5) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
    /// `metric`: thin numbers read precise.
    static func metric(_ size: CGFloat) -> Font { .system(size: size, weight: .light) }
    static let body = Font.system(size: 12, weight: .medium)
    static let footnote = Font.system(size: 11)

    // MARK: Motion

    /// Large things: peeks, panels. Apple's smooth spring, no bounce.
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 1)
    /// Small things: presses, toggles, digits. Apple's snappy spring, a slight settle.
    static let snappy = Animation.spring(duration: 0.33, bounce: 0.15)
    /// Reduce Motion: every move becomes this fade.
    static let reduced = Animation.easeInOut(duration: 0.15)

    static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// A state as a word on its soft ground: status is never colour alone.
struct StatusChip: View {
    enum Tone { case neutral, info, warning, success, danger }

    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colors.ink)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(colors.ground, in: Capsule())
            .fixedSize()
    }

    private var colors: (ink: Color, ground: Color) {
        switch tone {
        case .neutral: (Viorim.ink2, Viorim.surfaceRaised)
        case .info: (Viorim.info, Viorim.infoSoft)
        case .warning: (Viorim.warning, Viorim.warningSoft)
        case .success: (Viorim.success, Viorim.successSoft)
        case .danger: (Viorim.danger, Viorim.dangerSoft)
        }
    }
}

/// The working dot: one slow breath (1.6 s) while Claude works, the kit's only repeating motion.
/// Still with Reduce Motion; the words beside it say the same.
struct WorkingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inhale = false

    var body: some View {
        Circle()
            .fill(Viorim.accent)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion ? 1 : inhale ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: inhale)
            .onAppear { inhale = true }
            .accessibilityHidden(true)
    }
}

/// Presses scale to 0.97 at once and spring back, as the kit's buttons do.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.1) : Viorim.snappy, value: configuration.isPressed)
    }
}

/// A well inside a tile or peek: the kit's grouping ground (never a card inside a card).
struct Well<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Viorim.surfaceSunken.opacity(0.55), in: RoundedRectangle(cornerRadius: Viorim.radiusWell))
    }
}
