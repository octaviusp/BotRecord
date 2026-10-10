import AppKit
import Observation

/// State behind "Generar resumen detallado": one summary at a time, cancellable, tied to a meeting by its stable id.
@MainActor @Observable
final class SummaryController {
    enum State: Equatable {
        case idle
        case running(meetingID: String)
        case done(meetingID: String, summaryURL: URL)
        case failed(meetingID: String, message: String)

        var meetingID: String? {
            switch self {
            case .idle: nil
            case let .running(id), let .done(id, _), let .failed(id, _): id
            }
        }
    }

    private(set) var state: State = .idle
    /// Brief "Copiado" confirmation after copying the summary.
    private(set) var didCopy = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let recents: RecentRecordingsStore
    @ObservationIgnored private let summarizer: MeetingSummarizing
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var copyResetTask: Task<Void, Never>?

    init(settings: AppSettings, recents: RecentRecordingsStore, summarizer: MeetingSummarizing) {
        self.settings = settings
        self.recents = recents
        self.summarizer = summarizer
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// The card shows while this meeting's summary is in flight or finished, or when it is ready to be made.
    func offersSummary(for meeting: MeetingEntry) -> Bool {
        state.meetingID == meeting.stableID || (meeting.hasTranscript && !meeting.hasSummary)
    }

    /// The state to draw for `meeting`; another meeting's leftover state reads as idle.
    func state(for meeting: MeetingEntry) -> State {
        state.meetingID == meeting.stableID ? state : .idle
    }

    func generate(for meeting: MeetingEntry) {
        guard !isRunning else { return }
        let meetingID = meeting.stableID
        let pipeline = MeetingSummaryPipeline(library: settings.library, summarizer: summarizer)
        state = .running(meetingID: meetingID)
        task = Task {
            do {
                let outcome = try await pipeline.run(meetingFolder: meeting.folder)
                state = .done(meetingID: meetingID, summaryURL: outcome.summaryURL)
            } catch {
                // A cancelled run can also surface as the terminated process's own error.
                state = Task.isCancelled || error is CancellationError
                    ? .idle
                    : .failed(meetingID: meetingID, message: error.localizedDescription)
            }
            // The folder may have been renamed and summary.md written either way.
            recents.reload()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func openSummary() {
        guard case let .done(_, url) = state else { return }
        NSWorkspace.shared.open(url)
    }

    func copySummary() {
        guard case let .done(meetingID, url) = state else { return }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            didCopy = true
            copyResetTask?.cancel()
            copyResetTask = Task {
                do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                didCopy = false
            }
        } catch {
            state = .failed(meetingID: meetingID, message: "No pude leer summary.md: \(error.localizedDescription)")
        }
    }
}
