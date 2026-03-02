import SwiftUI

enum ThemeTokens {
    static let buildSignature = "THEME_SIG_90A"

    enum Layout {
        static let unit8: CGFloat = 8
        static let cardRadius: CGFloat = 16
        static let cardInnerRadius: CGFloat = 12
        static let dockRadius: CGFloat = 18
    }

    // MARK: - Background
    enum Background {
        static let base = Color(hex: "#0A0E13")
        static let top = Color(hex: "#0B1016")
        static let bottom = Color(hex: "#070A0F")
        static let vignette = Color.black.opacity(0.18)
        static var gradient: LinearGradient {
            LinearGradient(
                colors: [top, base, bottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Card
    enum Card {
        static let surface = Color(hex: "#0F141B")
        static let surfaceAlt = Color(hex: "#111923")
        static let stroke = Color.white.opacity(0.08)
        static let divider = Color.white.opacity(0.06)
        static let highlightTop = Color.white.opacity(0.05)
        static let shadow = Color.black.opacity(0.28)
        static let shadowY: CGFloat = 6
        static let shadowRadius: CGFloat = 14

        // Backward-compatible aliases used by existing views.
        static let top = surface
        static let bottom = surface
        static let innerSurface = surfaceAlt
        static let border = stroke
        static let innerHighlight = highlightTop
        static let iconBubble = surfaceAlt
        static let shadowSecondary = Color.black.opacity(0.12)
        static var gradient: LinearGradient {
            LinearGradient(
                colors: [top, bottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Dock
    enum Dock {
        static let top = Card.surface
        static let bottom = Color(hex: "#0E141B")
        static let border = Card.divider
        static let shadow = Color.black.opacity(0.16)
    }

    // MARK: - Text
    enum Text {
        static let primary = Color(hex: "#E6EDF3")
        static let secondary = Color(hex: "#9AA7B2")
        static let muted = Color(hex: "#6B7785")
    }

    // MARK: - Accent
    enum Accent {
        static let actionBlue = Color(hex: "#3B82F6")
        static let intelligenceBlue = actionBlue
        static let success = Color(hex: "#22C55E")
        static let stable = success
        static let green = stable
        static let warning = Color(hex: "#F59E0B")
        static let elevated = warning
        static let danger = Color(hex: "#EF4444")
        static let critical = danger
        static let criticalMutedBackground = Color(hex: "#2A1416")
    }

    // MARK: - Shadow
    enum Shadow {
        static let softRadius: CGFloat = Card.shadowRadius
        static let softY: CGFloat = Card.shadowY
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
