import CoreMedia
import os

/// Maps host-clock timestamps onto recording time: zero at the first video frame (or `startTimeline`),
/// with paused spans removed. Shared between the main actor (pause/resume/elapsed) and the capture queue.
final class RecordingClock: @unchecked Sendable {
    private struct State {
        var origin: CMTime?
        var pausedTotal = CMTime.zero
        var pauseStart: CMTime?
        /// Most recent finished pause. Frames captured during it can still be delivered after resume.
        var lastPausedSpan: (start: CMTime, end: CMTime)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    static var hostNow: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    var isPaused: Bool { state.withLock { $0.pauseStart != nil } }

    /// Fixes time zero explicitly, for recordings whose timeline starts before any video frame
    /// (meetings start with audio). No effect once a frame already set it.
    func startTimeline(at now: CMTime) {
        state.withLock { state in
            if state.origin == nil { state.origin = now }
        }
    }

    func pause(at now: CMTime) {
        state.withLock { state in
            if state.pauseStart == nil { state.pauseStart = now }
        }
    }

    func resume(at now: CMTime) {
        state.withLock { state in
            guard let start = state.pauseStart else { return }
            state.pauseStart = nil
            state.lastPausedSpan = (start, now)
            // A pause before the first frame must not shift the origin, which is not set yet.
            if state.origin != nil { state.pausedTotal = state.pausedTotal + (now - start) }
        }
    }

    /// Recording time for a video frame; the first accepted frame defines time zero. Nil while paused.
    func videoTime(for timestamp: CMTime) -> CMTime? {
        state.withLock { state in
            guard !Self.isPaused(timestamp, in: state) else { return nil }
            if state.origin == nil { state.origin = timestamp }
            return Self.rebase(timestamp, in: state)
        }
    }

    /// Recording time for an audio buffer. Nil while paused and before the first video frame.
    func audioTime(for timestamp: CMTime) -> CMTime? {
        state.withLock { state in
            guard !Self.isPaused(timestamp, in: state), state.origin != nil else { return nil }
            let time = Self.rebase(timestamp, in: state)
            return time >= .zero ? time : nil
        }
    }

    /// Recorded time at `now`, frozen while paused.
    func elapsedTime(at now: CMTime) -> CMTime {
        state.withLock { state in
            guard let origin = state.origin else { return .zero }
            let end = state.pauseStart ?? now
            return CMTimeMaximum(.zero, end - origin - state.pausedTotal)
        }
    }

    private static func isPaused(_ timestamp: CMTime, in state: State) -> Bool {
        if let start = state.pauseStart, timestamp >= start { return true }
        if let span = state.lastPausedSpan, timestamp >= span.start, timestamp < span.end { return true }
        return false
    }

    private static func rebase(_ timestamp: CMTime, in state: State) -> CMTime {
        timestamp - (state.origin ?? timestamp) - state.pausedTotal
    }
}
