import AppKit

/// Full-screen area picker: hover or click a window, or drag a rectangle, then adjust and confirm.
@MainActor
final class AreaSelector: AreaSelecting {
    private var isSelecting = false

    init() {}

    func selectArea(_ request: AreaSelectionRequest) async -> CaptureTarget? {
        // A second picker on top of the first would fight over the keyboard; the re-entrant call just loses.
        guard !isSelecting else { return nil }
        isSelecting = true
        defer { isSelecting = false }
        return await AreaSelectionSession(request: request).run()
    }
}
