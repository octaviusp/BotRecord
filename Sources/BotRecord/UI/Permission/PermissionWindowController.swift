import AppKit

/// Shows the permission card and watches for the grant, so the user never has to come back and click anything.
@MainActor
final class PermissionWindowController: PermissionPresenting {
    private var panel: FloatingPanel?
    private var pollTask: Task<Void, Never>?

    private static let pollInterval: Duration = .seconds(1)
    private static let successLinger: Duration = .milliseconds(1600)
    private static let edgeMargin: CGFloat = 40

    func presentPermissionRequest() {
        if let panel, panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        let model = PermissionModel()
        let panel = FloatingPanel(level: .floating, acceptsKeyFocus: true) {
            PermissionView(
                model: model,
                onOpenSettings: {
                    model.didOpenSettings = true
                    ScreenCapturePermission.openSystemSettings()
                },
                onRelaunch: { [weak self] in self?.relaunch(model) },
                onClose: { [weak self] in self?.close() }
            )
        }
        panel.isMovableByWindowBackground = true
        panel.onCancel = { [weak self] in self?.close() }
        self.panel = panel
        panel.present(at: origin(for: panel.frame.size))
        startPolling(model)
    }

    private func startPolling(_ model: PermissionModel) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if ScreenCapturePermission.isGranted {
                    model.phase = .granted
                    do { try await Task.sleep(for: Self.successLinger) } catch { return }
                    close()
                    return
                }
                do { try await Task.sleep(for: Self.pollInterval) } catch { return }
            }
        }
    }

    private func relaunch(_ model: PermissionModel) {
        do {
            try ScreenCapturePermission.relaunchApp()
        } catch {
            model.relaunchError = "Couldn't relaunch BotRecord (\(error.localizedDescription)). Quit it from the menu bar and open it again."
        }
    }

    private func close() {
        pollTask?.cancel()
        pollTask = nil
        panel?.dismissAnimated()
        panel = nil
    }

    /// Right side of the screen, so System Settings opens beside the card instead of under it.
    private func origin(for size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        return NSPoint(x: visible.maxX - size.width - Self.edgeMargin, y: visible.midY - size.height / 2)
    }
}
