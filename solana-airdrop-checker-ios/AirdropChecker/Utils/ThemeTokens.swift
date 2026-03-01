import SwiftUI

enum ThemeTokens {
    enum Layout {
        static let unit8: CGFloat = 8
        static let cardRadius: CGFloat = 24
    }

    enum Background {
        static let base = Color(hex: "#0C1117")
        static let top = Color(hex: "#121A25")
        static let bottom = Color(hex: "#090D14")
        static let vignette = Color.black.opacity(0.46)
    }

    enum Card {
        static let top = Color(hex: "#111823")
        static let bottom = Color(hex: "#111823")
        static let innerSurface = Color(hex: "#0E141D")
        static let border = Color.white.opacity(0.06)
        static let innerHighlight = Color.white.opacity(0.06)
        static let iconBubble = Color(hex: "#0E141D")
        static let shadow = Color.black.opacity(0.56)
        static let shadowSecondary = Color.black.opacity(0.30)
    }

    enum Dock {
        static let top = Color(hex: "#111823")
        static let bottom = Color(hex: "#0F1620")
        static let border = Color.white.opacity(0.07)
        static let shadow = Color.black.opacity(0.56)
    }

    enum Text {
        static let primary = Color(hex: "#F2F5F8")
        static let secondary = Color(hex: "#9AA6B2")
        static let muted = Color(hex: "#7F8A95")
    }

    enum Accent {
        static let intelligenceBlue = Color(hex: "#4DA3FF")
        static let green = Color(hex: "#2ED47A")
        static let orange = Color(hex: "#FFB020")
        static let critical = Color(hex: "#FF5A5F")
        static let criticalMutedBackground = Color(hex: "#2A1518")
    }

    enum Shadow {
        static let softRadius: CGFloat = 22
        static let softY: CGFloat = 10
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
