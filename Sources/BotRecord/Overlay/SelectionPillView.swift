import AppKit

/// Small rounded label used for size, coordinates and status badges next to the selection.
/// Plain AppKit (not SwiftUI) so it can follow the pointer on every mouse event without a render pass.
@MainActor
final class SelectionPillView: NSView {
    enum Style {
        case dark, accent, danger, warning

        var background: NSColor {
            switch self {
            case .dark: NSColor.black.withAlphaComponent(0.78)
            case .accent: NSColor(Theme.accent)
            case .danger: NSColor(Theme.record)
            case .warning: NSColor(Theme.warning)
            }
        }

        var foreground: NSColor { self == .warning ? NSColor.black.withAlphaComponent(0.85) : .white }
    }

    struct Segment {
        let text: String
        var isSecondary = false
    }

    private static let height: CGFloat = 24
    private static let horizontalPadding: CGFloat = 9
    private static let iconSize: CGFloat = 12
    private static let iconSpacing: CGFloat = 5

    private let iconView = NSImageView()
    private let textField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Self.height / 2
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        addSubview(textField)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Never intercepts clicks: labels are decoration over the canvas.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ segments: [Segment], symbol: String? = nil, style: Style) {
        let text = NSMutableAttributedString()
        for segment in segments {
            let font = segment.isSecondary
                ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                : NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            let color = segment.isSecondary ? style.foreground.withAlphaComponent(0.65) : style.foreground
            text.append(NSAttributedString(string: segment.text, attributes: [.font: font, .foregroundColor: color]))
        }
        textField.attributedStringValue = text
        let textSize = text.size()
        // NSTextField needs a little slack beyond the measured width or it truncates the last glyphs.
        let textWidth = ceil(textSize.width) + 4

        var x = Self.horizontalPadding
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iconView.image = image.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            iconView.contentTintColor = style.foreground
            iconView.frame = CGRect(x: x, y: (Self.height - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
            iconView.isHidden = false
            x += Self.iconSize + Self.iconSpacing
        } else {
            iconView.isHidden = true
        }
        textField.frame = CGRect(x: x, y: (Self.height - ceil(textSize.height)) / 2, width: textWidth, height: ceil(textSize.height))
        setFrameSize(CGSize(width: x + textWidth + Self.horizontalPadding, height: Self.height))
        layer?.backgroundColor = style.background.cgColor
        isHidden = false
    }

    func hide() { isHidden = true }
}
