import Foundation

/// Feedback state of a copy button: it turns green the moment the file is on the clipboard.
enum CopyState: Equatable {
    case idle
    case working
    case copied
    case failed(String)
}
