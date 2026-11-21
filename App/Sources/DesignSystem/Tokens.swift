// ORIX Clean — App/Sources/DesignSystem/Tokens.swift
// Description: ORIX design tokens for ORIX Clean: colour roles, spacing, radii, type, density, storage palettes.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import AppKit
import ORIXCleanCore
import SwiftUI

/// The core measurement type; Foundation also defines a generic `Measurement`.
typealias Measurement = ORIXCleanCore.Measurement

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) })
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum ORIX {
    enum Palette {
        /// Window background behind grouped content (shared ORIX family values).
        static let canvas = Color(light: 0xF4F5FA, dark: 0x0A0D18)
        static let surface = Color(light: 0xFFFFFF, dark: 0x141828)
        static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x1B2034)
        static let hairline = Color(light: 0xE3E6EF, dark: 0x262C44)
        static let textSecondary = Color(light: 0x5A6072, dark: 0x9AA2B8)
        static let textTertiary = Color(light: 0x8A90A2, dark: 0x6B738C)
        /// ORIX Clean accent pair: "clear water" teal with the family indigo.
        static let accent = Color(light: 0x0A9E96, dark: 0x2DD4BF)
        static let accentSecondary = Color(light: 0x5B5BF0, dark: 0x8484FF)
        static let low = Color(light: 0x16A34A, dark: 0x4ADE80)
        static let review = Color(light: 0xD97706, dark: 0xFBBF24)
        static let high = Color(light: 0xDC2626, dark: 0xF87171)
        static var brandGradient: LinearGradient {
            LinearGradient(colors: [Color(hex: 0x2DD4BF), Color(hex: 0x06B6D4), Color(hex: 0x5B5BF0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 6, m: CGFloat = 10, l: CGFloat = 14
    }
}

extension Risk {
    var color: Color {
        switch self {
        case .low: return ORIX.Palette.low
        case .review: return ORIX.Palette.review
        case .high: return ORIX.Palette.high
        }
    }

    /// Shape differs per level so the meaning never depends on colour alone.
    var symbol: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .review: return "eye.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
}

enum Density: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: String { rawValue }
    var rowPadding: CGFloat { self == .compact ? 3 : 7 }
    var title: String { self == .compact ? L("Compact") : L("Comfortable") }
}

enum MapPalette: String, CaseIterable, Identifiable {
    case orix, colorblind
    var id: String { rawValue }
    var title: String { self == .orix ? L("ORIX") : L("Colour-blind friendly") }

    /// Base colour of a file category. The colour-blind set is the Okabe–Ito palette.
    func color(_ c: FileCategory) -> (r: Double, g: Double, b: Double) {
        let hex: UInt32
        switch (self, c) {
        case (.orix, .video): hex = 0x8B5CF6
        case (.orix, .audio): hex = 0xEC4899
        case (.orix, .image): hex = 0xF59E0B
        case (.orix, .archive): hex = 0x64748B
        case (.orix, .diskImage): hex = 0x0EA5E9
        case (.orix, .installer): hex = 0xEF4444
        case (.orix, .document): hex = 0x22C55E
        case (.orix, .code): hex = 0x06B6D4
        case (.orix, .application): hex = 0x6366F1
        case (.orix, .other): hex = 0x94A3B8
        case (.colorblind, .video): hex = 0xCC79A7
        case (.colorblind, .audio): hex = 0xD55E00
        case (.colorblind, .image): hex = 0xE69F00
        case (.colorblind, .archive): hex = 0x7F7F7F
        case (.colorblind, .diskImage): hex = 0x56B4E9
        case (.colorblind, .installer): hex = 0xB34700
        case (.colorblind, .document): hex = 0x009E73
        case (.colorblind, .code): hex = 0x0072B2
        case (.colorblind, .application): hex = 0xF0E442
        case (.colorblind, .other): hex = 0xA9A9A9
        }
        return (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    func swiftUIColor(_ c: FileCategory) -> Color {
        let v = color(c)
        return Color(.sRGB, red: v.r, green: v.g, blue: v.b, opacity: 1)
    }
}

extension FileCategory {
    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        case .archive: return "archivebox"
        case .diskImage: return "externaldrive"
        case .installer: return "shippingbox"
        case .document: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .application: return "app.badge"
        case .other: return "doc"
        }
    }
}
