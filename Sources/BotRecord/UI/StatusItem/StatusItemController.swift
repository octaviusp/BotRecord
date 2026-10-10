import AppKit
import Observation
import SwiftUI

/// Menu-bar item built on `NSStatusItem`, not `MenuBarExtra`: while recording, a click must stop the
/// recording, and `MenuBarExtra(.window)` always opens its window instead of delivering the click.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let labelView = PassthroughHostingView(rootView: StatusLabelView(display: .idle))
    private let display: () -> StatusDisplay
    private let onClick: () -> Void

    private static let horizontalInset: CGFloat = 6

    var button: NSStatusBarButton? { statusItem.button }

    /// `display` reads observable state, so any change it depends on re-renders the item.
    init(display: @escaping () -> StatusDisplay, onClick: @escaping () -> Void) {
        self.display = display
        self.onClick = onClick
        super.init()
        installLabel()
        trackState()
    }

    @objc private func buttonClicked(_ sender: Any?) {
        onClick()
    }

    private func installLabel() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            labelView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
    }

    /// Re-renders whenever the displayed state changes.
    private func trackState() {
        withObservationTracking {
            apply(display())
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackState() }
        }
    }

    private func apply(_ display: StatusDisplay) {
        labelView.rootView = StatusLabelView(display: display)
        statusItem.length = ceil(labelView.fittingSize.width) + 2 * Self.horizontalInset
        statusItem.button?.toolTip = display.hint
        statusItem.button?.setAccessibilityLabel(display.hint)
    }
}

/// Lets clicks fall through to the status button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
