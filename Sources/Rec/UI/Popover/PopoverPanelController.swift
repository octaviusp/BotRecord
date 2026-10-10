import AppKit
import SwiftUI

/// Presents the recorder popover as a glass panel hanging under the status item.
/// A custom panel (not `NSPopover`) so the surface is the app's own Liquid Glass, not a system arrow bubble.
@MainActor
final class PopoverPanelController {
    private let panel: FloatingPanel
    private let recents: RecentRecordingsStore
    private let settings: AppSettings
    private weak var anchorButton: NSStatusBarButton?
    /// Top edge under the menu bar; content height changes keep it fixed.
    private var anchorTop: CGFloat?
    private var outsideClickMonitor: Any?
    private var lastClosedAt = Date.distantPast

    private static let gapBelowMenuBar: CGFloat = 6
    private static let screenMargin: CGFloat = 8
    /// A click on the status item first dismisses the panel (focus loss), then fires its action;
    /// without this guard that click would immediately reopen it.
    private static let reopenGuardInterval: TimeInterval = 0.25

    var isVisible: Bool { panel.isVisible }

    init(
        settings: AppSettings,
        sessions: CaptureSessions,
        recents: RecentRecordingsStore,
        onOpenSettings: @escaping () -> Void
    ) {
        self.recents = recents
        self.settings = settings
        // Wired after `panel` exists: the view needs to close the panel, and `self` can't be captured before init finishes.
        var closeAndRecord: () -> Void = {}
        var closeAndOpenSettings: () -> Void = {}
        var refit: () -> Void = {}
        panel = FloatingPanel(level: .popUpMenu, acceptsKeyFocus: true) {
            PopoverView(
                settings: settings,
                sessions: sessions,
                recents: recents,
                onRecord: { closeAndRecord() },
                onOpenSettings: { closeAndOpenSettings() },
                onContentSizeChange: { refit() }
            )
        }
        closeAndRecord = { [weak self] in
            // Close first so the popover is never in the shot.
            self?.close()
            sessions.start(settings.recorderMode)
        }
        refit = { [weak self] in
            DispatchQueue.main.async { self?.refitIfContentChanged() }
        }
        closeAndOpenSettings = { [weak self] in
            self?.close()
            onOpenSettings()
        }
        panel.onCancel = { [weak self] in self?.close() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func toggle(below button: NSStatusBarButton) {
        if panel.isVisible {
            close()
        } else if Date().timeIntervalSince(lastClosedAt) > Self.reopenGuardInterval {
            show(below: button)
        }
    }

    func close() {
        guard panel.isVisible else { return }
        lastClosedAt = Date()
        panel.orderOut(nil)
        anchorButton?.highlight(false)
        removeOutsideClickMonitor()
    }

    private func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        anchorButton = button
        recents.reload()
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = fittedSize()
        let origin = origin(for: size, below: buttonFrame)
        anchorTop = origin.y + size.height
        panel.present(at: origin, slidingFrom: 6)
        panel.makeKey()
        button.highlight(true)
        installOutsideClickMonitor()
        // SwiftUI may still be applying the reloaded recents; refit once layout settles.
        DispatchQueue.main.async { [weak self] in self?.refitIfContentChanged() }
    }

    private func fittedSize() -> NSSize {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        return size
    }

    private func origin(for size: NSSize, below buttonFrame: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(buttonFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let idealX = buttonFrame.midX - size.width / 2
        let x = min(max(idealX, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        return NSPoint(x: x, y: buttonFrame.minY - Self.gapBelowMenuBar - size.height)
    }

    /// Keeps the top edge under the menu bar when the content height changes after showing
    /// (reloaded recents, switching mode, the summary card changing state).
    private func refitIfContentChanged() {
        guard panel.isVisible, let anchorTop else { return }
        let oldFrame = panel.frame
        let size = fittedSize()
        guard abs(size.height - oldFrame.height) > 0.5 else { return }
        panel.setFrame(
            NSRect(x: oldFrame.minX, y: anchorTop - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
