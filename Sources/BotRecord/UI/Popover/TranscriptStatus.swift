/// A recording's transcript as the Recent list shows it.
enum TranscriptStatus {
    case done
    /// Still being finalized after Stop (normally under a second).
    case transcribing
    case off

    var label: String {
        switch self {
        case .done: "transcript ✓"
        case .transcribing: "transcribing…"
        case .off: "transcript off"
        }
    }
}
