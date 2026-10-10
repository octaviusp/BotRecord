import Foundation

/// One row of the Recent list: screen recordings and meetings share it, newest first.
enum RecentItem: Identifiable {
    case screen(RecentRecording)
    case meeting(MeetingEntry)

    var id: URL {
        switch self {
        case let .screen(recording): recording.id
        case let .meeting(meeting): meeting.id
        }
    }

    var createdAt: Date {
        switch self {
        case let .screen(recording): recording.createdAt
        case let .meeting(meeting): meeting.startedAt
        }
    }
}
