import AppKit
import SwiftUI

/// The neutral sparkle shown next to "Claude", loaded from the bundled SVG (AppKit renders SVG natively)
/// as a template so it takes the surrounding color. `swift run` has no app bundle, hence the SF Symbol fallback.
struct ClaudeGlyph: View {
    var size: CGFloat = 12

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "claude-glyph", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "sparkle").font(.system(size: size * 0.9, weight: .semibold))
        }
    }
}
