import Carbon.HIToolbox

/// Single source for the global hotkeys: registration and every on-screen hint read from here.
enum GlobalShortcut: UInt32, CaseIterable {
    case toggleRecording = 1
    case recordArea
    case toggleMeeting

    var keyCode: UInt32 {
        switch self {
        case .toggleRecording: UInt32(kVK_ANSI_R)
        case .recordArea: UInt32(kVK_ANSI_A)
        case .toggleMeeting: UInt32(kVK_ANSI_M)
        }
    }

    static let modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)

    var keyCaps: [String] {
        let letter = switch self {
        case .toggleRecording: "R"
        case .recordArea: "A"
        case .toggleMeeting: "M"
        }
        return ["⌃", "⌥", "⌘", letter]
    }

    var spoken: String { keyCaps.joined() }
}
