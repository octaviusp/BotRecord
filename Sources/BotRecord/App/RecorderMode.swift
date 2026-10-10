/// The popover's three tiles: two screen capture modes and meeting notes.
enum RecorderMode: Hashable, CaseIterable {
    case fullScreen, area, meeting

    init(_ captureMode: CaptureMode) {
        switch captureMode {
        case .fullScreen: self = .fullScreen
        case .area: self = .area
        }
    }

    /// Nil for meetings, which have no screen target to pick.
    var captureMode: CaptureMode? {
        switch self {
        case .fullScreen: .fullScreen
        case .area: .area
        case .meeting: nil
        }
    }
}
