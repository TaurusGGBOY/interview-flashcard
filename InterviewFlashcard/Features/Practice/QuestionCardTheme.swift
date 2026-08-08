import SwiftUI

/// A deterministic visual theme for a question card.
///
/// The palette is derived from the question's UUID bytes instead of Swift's
/// process-randomized `hashValue`, so the same question keeps its identity
/// across launches, devices, and previews.
struct QuestionCardTheme {
    enum ForegroundKind: String, CaseIterable, Equatable, Sendable {
        case light
        case dark
    }

    let paletteIndex: Int
    let foregroundKind: ForegroundKind
    /// The lowest WCAG contrast ratio among the light-mode gradient stops.
    let contrastRatio: Double

    private let lightGradientStops: [Color]
    private let darkGradientStops: [Color]
    private let foregroundColor: Color
    private let accentColor: Color

    static var paletteCount: Int { palettes.count }

    static func theme(for questionID: UUID) -> QuestionCardTheme {
        let hash = stableHash(questionID)
        let index = Int(hash % UInt64(palettes.count))
        let palette = palettes[index]

        return QuestionCardTheme(
            paletteIndex: index,
            foregroundKind: palette.foregroundKind,
            contrastRatio: palette.contrastRatio,
            lightGradientStops: palette.lightGradient.map(\.color),
            darkGradientStops: palette.darkGradient.map(\.color),
            foregroundColor: palette.foreground.color,
            accentColor: palette.accent.color
        )
    }

    func gradient(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark ? darkGradientStops : lightGradientStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var foreground: Color { foregroundColor }
    var accent: Color { accentColor }

    private init(
        paletteIndex: Int,
        foregroundKind: ForegroundKind,
        contrastRatio: Double,
        lightGradientStops: [Color],
        darkGradientStops: [Color],
        foregroundColor: Color,
        accentColor: Color
    ) {
        self.paletteIndex = paletteIndex
        self.foregroundKind = foregroundKind
        self.contrastRatio = contrastRatio
        self.lightGradientStops = lightGradientStops
        self.darkGradientStops = darkGradientStops
        self.foregroundColor = foregroundColor
        self.accentColor = accentColor
    }
}

private extension QuestionCardTheme {
    struct RGBColor: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func darkened(by factor: Double) -> RGBColor {
            RGBColor(red: red * factor, green: green * factor, blue: blue * factor)
        }
    }

    struct PaletteDefinition {
        let lightGradient: [RGBColor]
        let darkGradient: [RGBColor]
        let foreground: RGBColor
        let accent: RGBColor
        let foregroundKind: ForegroundKind
        let contrastRatio: Double

        init(
            first: RGBColor,
            second: RGBColor,
            foreground: RGBColor = RGBColor(red: 1, green: 1, blue: 1),
            accent: RGBColor = RGBColor(red: 1, green: 1, blue: 1)
        ) {
            self.lightGradient = [first, second]
            self.darkGradient = [first.darkened(by: 0.72), second.darkened(by: 0.72)]
            self.foreground = foreground
            self.accent = accent
            self.foregroundKind = foreground == RGBColor(red: 1, green: 1, blue: 1) ? .light : .dark
            self.contrastRatio = min(
                QuestionCardTheme.contrastRatio(foreground: foreground, background: first),
                QuestionCardTheme.contrastRatio(foreground: foreground, background: second)
            )
        }
    }

    static let palettes: [PaletteDefinition] = [
        PaletteDefinition(
            first: RGBColor(red: 11.0 / 255.0, green: 58.0 / 255.0, blue: 83.0 / 255.0),
            second: RGBColor(red: 11.0 / 255.0, green: 111.0 / 255.0, blue: 122.0 / 255.0)
        ),
        PaletteDefinition(
            first: RGBColor(red: 45.0 / 255.0, green: 32.0 / 255.0, blue: 93.0 / 255.0),
            second: RGBColor(red: 107.0 / 255.0, green: 61.0 / 255.0, blue: 167.0 / 255.0)
        ),
        PaletteDefinition(
            first: RGBColor(red: 74.0 / 255.0, green: 20.0 / 255.0, blue: 56.0 / 255.0),
            second: RGBColor(red: 156.0 / 255.0, green: 44.0 / 255.0, blue: 99.0 / 255.0)
        ),
        PaletteDefinition(
            first: RGBColor(red: 16.0 / 255.0, green: 76.0 / 255.0, blue: 61.0 / 255.0),
            second: RGBColor(red: 15.0 / 255.0, green: 123.0 / 255.0, blue: 100.0 / 255.0)
        ),
        PaletteDefinition(
            first: RGBColor(red: 99.0 / 255.0, green: 42.0 / 255.0, blue: 22.0 / 255.0),
            second: RGBColor(red: 167.0 / 255.0, green: 76.0 / 255.0, blue: 30.0 / 255.0)
        ),
        PaletteDefinition(
            first: RGBColor(red: 52.0 / 255.0, green: 25.0 / 255.0, blue: 76.0 / 255.0),
            second: RGBColor(red: 107.0 / 255.0, green: 61.0 / 255.0, blue: 167.0 / 255.0)
        )
    ]

    static func stableHash(_ questionID: UUID) -> UInt64 {
        // FNV-1a over UUID's 16 raw bytes is intentionally boring and
        // portable. UUID.hashValue is randomized per process by Swift.
        let bytes = questionID.uuid
        return withUnsafeBytes(of: bytes) { rawBuffer in
            rawBuffer.reduce(UInt64(14695981039346656037)) { hash, byte in
                (hash ^ UInt64(byte)) &* 1099511628211
            }
        }
    }

    static func contrastRatio(foreground: RGBColor, background: RGBColor) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func relativeLuminance(_ color: RGBColor) -> Double {
        func linearized(_ value: Double) -> Double {
            value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearized(color.red)
            + 0.7152 * linearized(color.green)
            + 0.0722 * linearized(color.blue)
    }
}
