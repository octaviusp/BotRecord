import AVFoundation
import CoreGraphics
import Foundation

/// Reasons a recording cannot start or continue, written for the person using the app.
enum CaptureError: LocalizedError {
    case screenRecordingPermissionMissing
    case displayNotFound(CGDirectDisplayID)
    case invalidCaptureRegion
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            "Screen recording permission is missing. Allow Rec in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .displayNotFound:
            "The display to record is no longer available."
        case .invalidCaptureRegion:
            "The selected area is outside the display."
        case .alreadyRecording:
            "A recording is already in progress."
        case .notRecording:
            "There is no recording in progress."
        }
    }
}

enum FailureMessage {
    /// One sentence for the failure banner, naming the cause when it is one the user can fix.
    static func describe(_ error: Error) -> String {
        if isDiskFull(error) {
            return "Recording stopped — disk almost full"
        }
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return "Recording stopped — \(reason)"
    }

    private static func isDiskFull(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            switch (nsError.domain, nsError.code) {
            case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
                 (AVFoundationErrorDomain, AVError.diskFull.rawValue),
                 (NSPOSIXErrorDomain, Int(ENOSPC)):
                return true
            default:
                current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            }
        }
        return false
    }
}
