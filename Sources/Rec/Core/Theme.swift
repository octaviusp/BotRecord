import SwiftUI

/// Design tokens from design/screen-recorder.pen. Surfaces use the native Liquid Glass
/// (`.glassEffect`) instead of hand-made blur, so they follow system light/dark and accessibility.
enum Theme {
    static let record = Color(red: 1.0, green: 0.231, blue: 0.188)      // #FF3B30
    static let accent = Color(red: 0.039, green: 0.518, blue: 1.0)      // #0A84FF
    static let success = Color(red: 0.188, green: 0.820, blue: 0.345)   // #30D158
    static let warning = Color(red: 1.0, green: 0.702, blue: 0.251)     // #FFB340
    static let scrim = Color.black.opacity(0.5)

    static let popoverWidth: CGFloat = 340
    static let panelRadius: CGFloat = 26
    static let rowHeight: CGFloat = 36

    static let mono = Font.system(.body, design: .monospaced).weight(.semibold)
}
