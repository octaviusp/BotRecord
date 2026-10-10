import Foundation

/// A finished recording ready to be shown.
struct SavedRecording {
    let result: RecordingResult
    /// e.g. "1080p 60"
    let qualityLabel: String
    /// True when auto-copy already put the file on the clipboard.
    let alreadyCopied: Bool
}

struct FailurePresentation {
    let title: String
    let message: String
    /// A usable clip saved before things went wrong, offered through "Copy <duration> clip".
    let partialResult: RecordingResult?
}

/// Where the coordinator reports outcomes; implemented by the toast layer.
@MainActor
protocol RecordingOutcomePresenting: AnyObject {
    func presentSaved(_ recording: SavedRecording)
    func presentFailure(_ failure: FailurePresentation, onDismiss: @escaping @MainActor () -> Void)
    func dismissAll()
}

@MainActor
protocol PermissionPresenting: AnyObject {
    func presentPermissionRequest()
}

/// A finished meeting, announced as "Meeting saved · 42:10".
struct SavedMeeting {
    let folder: URL
    let duration: TimeInterval
}

@MainActor
protocol MeetingOutcomePresenting: AnyObject {
    func presentMeetingSaved(_ meeting: SavedMeeting)
    func presentFailure(_ failure: FailurePresentation, onDismiss: @escaping @MainActor () -> Void)
    func dismissAll()
}
