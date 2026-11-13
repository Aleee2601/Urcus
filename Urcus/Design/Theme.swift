import SwiftUI
import CoreText

/// Paleta „Amurg alpin”: fundal verde-noapte, accent piersică, mov pentru urcare, salvie pentru „făcut”.
enum Theme {
    static let bg = Color(hex: 0x0E1512)
    static let sidebar = Color(hex: 0x111A16)
    static let surface = Color(hex: 0x16201C)
    static let surface2 = Color(hex: 0x1E2A25)
    static let inset = Color(hex: 0x1A2420)
    static let track = Color(hex: 0x24312B)
    static let line = Color(hex: 0xEEF1EC, opacity: 0.07)
    static let lineStrong = Color(hex: 0xEEF1EC, opacity: 0.12)
    static let mutedDot = Color(hex: 0x3A4842)

    static let text = Color(hex: 0xEEF1EC)
    static let muted = Color(hex: 0x9AA8A1)

    static let peach = Color(hex: 0xF2B48C)
    static let onPeach = Color(hex: 0x1A1410)
    static let plum = Color(hex: 0xA996D6)
    static let plumLight = Color(hex: 0xC4B5EA)
    static let sage = Color(hex: 0x7FCBA4)
    static let sky = Color(hex: 0x8CB8F2)
    static let sand = Color(hex: 0xD9C27A)
    static let coral = Color(hex: 0xF29A8C)
    static let teal = Color(hex: 0x7CC6C9)

    static let radiusL: CGFloat = 28
    static let radiusM: CGFloat = 24
    static let radiusS: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Font (Manrope, inclus în aplicație; dacă lipsește, cade pe fontul de sistem rotunjit)

enum AppFont {
    private static var registered = false
    private static var available = false

    static func register() {
        guard !registered else { return }
        registered = true
        var urls: [URL] = []
        for sub in [nil, "Fonts", "Resources/Fonts"] as [String?] {
            urls += Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: sub) ?? []
        }
        for url in Set(urls) where url.lastPathComponent.hasPrefix("Manrope") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        available = !urls.filter { $0.lastPathComponent.hasPrefix("Manrope") }.isEmpty
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard available else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        let name: String
        if weight == .heavy || weight == .black {
            name = "Manrope-ExtraBold"
        } else if weight == .bold {
            name = "Manrope-Bold"
        } else if weight == .semibold {
            name = "Manrope-SemiBold"
        } else if weight == .medium {
            name = "Manrope-Medium"
        } else {
            name = "Manrope-Regular"
        }
        return .custom(name, size: size)
    }
}

extension View {
    /// Text în fontul aplicației. `.heavy` = ExtraBold (titluri și cifre mari).
    func appFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(AppFont.font(size, weight))
    }
}
