import SwiftUI

extension Color {
    /// "#3D8B7D" → Color
    init(hex: String) {
        let (r, g, b) = Color.rgb(hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// White or near-black, whichever reads better on top of `hex`.
    static func ink(on hex: String) -> Color {
        let (r, g, b) = rgb(hex)
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let lum = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return 1.05 / (lum + 0.05) >= 2.8 ? .white : Color(.sRGB, red: 0.11, green: 0.11, blue: 0.12, opacity: 1)
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}
