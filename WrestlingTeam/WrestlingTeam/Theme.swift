import SwiftUI

/// Team colors. Change red / gold (and ink) to your school colors; everything else follows.
enum Theme {
    // Every color has a light and a dark value and follows the phone's appearance.
    static let red = dyn(0xC8102E, 0xE23A50)
    static let redDark = Color(hex: 0x8E0B20)
    /// Main text color (near-black in light mode, near-white in dark mode).
    static let ink = dyn(0x111214, 0xF2F2F4)
    /// Fixed dark charcoal for the hero cards and anything on gold; stays dark in both modes.
    static let heroInk = Color(hex: 0x111214)
    static let ink2 = Color(hex: 0x1D1F23)
    static let gray = dyn(0x5D6168, 0xA3A7AE)
    static let line = dyn(0xE3E4E8, 0x34363C)
    /// Screen background.
    static let soft = dyn(0xF4F4F6, 0x0B0C0E)
    /// Card / tile background.
    static let card = dyn(0xFFFFFF, 0x1A1B1F)
    static let gold = Color(hex: 0xF9B91A)
    static let goldText = dyn(0x9A6A00, 0xF9B91A)   // gold that reads on the card color (after-practice labels)
    static let okBG = dyn(0xE3F4EA, 0x15331F)
    static let ok = dyn(0x1E7B45, 0x4CC27F)
    static let noBG = dyn(0xFBE5E8, 0x3D161C)
    static let lightText = Color(hex: 0xC9CCD3)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// Oswald-like condensed headline type.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Matches the portal's stCls(): green for Ironman / on track, red for off track / lost.
enum StatusTone {
    case good, bad, neutral
    init(_ status: String) {
        let s = status.uppercased()
        if s.contains("NOT") && !s.contains("STARTED") { self = .bad; return }
        if ["IRONMAN", "ON TRACK", "YES"].contains(where: s.contains) { self = .good; return }
        if s.contains("OFF") || s.contains("LOST") || s.contains("MISSED") || s.range(of: #"\bNO\b"#, options: .regularExpression) != nil { self = .bad; return }
        self = .neutral
    }
}
