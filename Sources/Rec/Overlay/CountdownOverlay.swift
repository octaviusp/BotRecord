import AppKit
import SwiftUI

/// 3-2-1 countdown over the recording target. Esc cancels, a click skips to the start.
@MainActor
final class CountdownOverlay: CountdownPresenting {
    private var isRunning = false

    init() {}

    func run(seconds: Int, target: CaptureTarget) async -> Bool {
        guard seconds > 0 else { return true }
        guard !isRunning else { return false }
        guard let screen = ScreenSpace.screen(forDisplayID: target.displayID) ?? NSScreen.main else { return false }
        isRunning = true
        defer { isRunning = false }
        return await CountdownSession(seconds: seconds, screen: screen, area: target.sourceRect).run()
    }
}

/// Window that turns key presses and clicks into countdown outcomes.
private final class CountdownContentView: NSView {
    var onCancel: () -> Void = {}
    var onSkip: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() }
    }

    override func mouseDown(with event: NSEvent) { onSkip() }
}

@MainActor
private final class CountdownSession {
    private let seconds: Int
    private let panel: OverlayPanel
    private let model: CountdownModel
    private let content = CountdownContentView()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var ticker: Task<Void, Never>?

    init(seconds: Int, screen: NSScreen, area: CGRect?) {
        self.seconds = seconds
        model = CountdownModel(remaining: seconds)
        panel = OverlayPanel(frame: screen.frame, level: .screenSaver, acceptsKeyboard: true)

        let host = NSHostingView(rootView: CountdownView(model: model, screenSize: screen.frame.size, area: area))
        host.frame = CGRect(origin: .zero, size: screen.frame.size)
        content.frame = host.frame
        content.addSubview(host)
        content.onCancel = { [weak self] in self?.finish(completed: false) }
        content.onSkip = { [weak self] in self?.finish(completed: true) }
        panel.contentView = content
    }

    func run() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(content)
            startTicking()
        }
    }

    private func startTicking() {
        ticker = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                model.remaining = remaining
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // cancelled by finish(completed:)
                }
            }
            finish(completed: true)
        }
    }

    private func finish(completed: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        ticker?.cancel()
        // The overlay must be off screen before capture begins.
        panel.orderOut(nil)
        panel.close()
        continuation.resume(returning: completed)
    }
}
