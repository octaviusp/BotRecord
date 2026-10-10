import Foundation

/// What the menu-bar item shows; the icon is the app's only permanent surface, so it always reflects state.
enum StatusDisplay: Equatable {
    case idle
    case selecting
    case countdown(Int)
    case recording(String)
    case paused(String)
    /// Spinner with an optional word, e.g. "Saving".
    case busy(String?)
    case error
    case copied

    var hint: String {
        switch self {
        case .idle: "Rec: click to open, \(GlobalShortcut.toggleRecording.spoken) to start"
        case .selecting: "Choose an area, Esc to cancel"
        case .countdown: "Starting soon, Esc to cancel"
        case .recording: "Recording: click to stop"
        case .paused: "Paused: click to resume"
        case .busy: "Finishing the file"
        case .error: "Something went wrong: click to open Rec"
        case .copied: "Copied to clipboard"
        }
    }
}

extension RecordingCoordinator {
    var statusDisplay: StatusDisplay {
        switch phase {
        case .idle: showsCopiedConfirmation ? .copied : .idle
        case .selectingArea: .selecting
        case .countdown: .countdown(countdownRemaining)
        case .starting: .recording(Formatters.duration(0))
        case .recording: .recording(Formatters.duration(TimeInterval(elapsedSeconds)))
        case .paused: .paused(Formatters.duration(TimeInterval(elapsedSeconds)))
        case .saving: .busy("Saving")
        case .discarding: .busy(nil)
        case .failed: .error
        }
    }
}
