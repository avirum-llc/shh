import SwiftUI

/// Design tokens from `shh-plan.md` §4. Single source of truth for colors,
/// typography, and layout constants. Views reference `Tokens.X` rather than
/// hard-coding values so a theme change is one file.
enum Tokens {
    // MARK: - Colors

    /// Warm off-white app window background.
    static let surfaceBase = Color(red: 0xFA/255.0, green: 0xFA/255.0, blue: 0xF8/255.0)

    /// System dark menubar dropdown background (mirrors Apple's menubar chrome).
    static let surfaceMenubar = Color(red: 28/255.0, green: 28/255.0, blue: 30/255.0).opacity(0.96)

    /// Inset cards inside light windows.
    static let surfaceCard = Color.white

    /// Primary text on light surfaces.
    static let ink = Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x1A/255.0)

    /// Secondary text on light surfaces.
    static let inkMuted = Color.black.opacity(0.55)

    /// Labels and hints.
    static let inkFaint = Color.black.opacity(0.4)

    /// Primary brand colour / filled buttons (dark teal).
    static let accent = Color(red: 0x08/255.0, green: 0x2D/255.0, blue: 0x35/255.0)

    /// Active / success / "request in flight".
    static let stateActive = Color(red: 0x1D/255.0, green: 0x9E/255.0, blue: 0x75/255.0)

    /// Approaching budget cap.
    static let stateWarn = Color(red: 0xBD/255.0, green: 0x8F/255.0, blue: 0x1E/255.0)

    /// Proxy down / hard failure.
    static let stateError = Color(red: 0xFF/255.0, green: 0x5A/255.0, blue: 0x5A/255.0)

    /// Default hairline border.
    static let borderHairline = Color.black.opacity(0.08)

    // MARK: - Typography

    static let fontHero       = Font.system(size: 32, weight: .ultraLight).monospacedDigit()
    static let fontHeroLarge  = Font.system(size: 44, weight: .ultraLight).monospacedDigit()
    static let fontSectionTitle = Font.system(size: 15, weight: .medium)
    static let fontBody       = Font.system(size: 13, weight: .regular)
    static let fontLabel      = Font.system(size: 11, weight: .medium)
    static let fontMono       = Font.system(size: 12, weight: .regular, design: .monospaced)

    // MARK: - Layout

    static let hairlineWidth: CGFloat = 0.5
    static let dropdownWidth: CGFloat = 320
    static let dropdownHeight: CGFloat = 420
    static let dashboardWidth: CGFloat = 640
}
