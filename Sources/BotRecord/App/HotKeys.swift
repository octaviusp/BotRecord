import Carbon.HIToolbox

/// System-wide hotkeys through Carbon `RegisterEventHotKey`: no Accessibility permission needed.
@MainActor
final class HotKeys {
    enum RegistrationError: LocalizedError {
        case shortcutUnavailable(GlobalShortcut, OSStatus)
        case handlerInstallFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .shortcutUnavailable(shortcut, status):
                "\(shortcut.spoken) is already used by another app (error \(status))."
            case let .handlerInstallFailed(status):
                "Global shortcuts could not be enabled (error \(status))."
            }
        }
    }

    private static let signature: OSType = 0x5245_4320 // 'REC '

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var registeredKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        try installEventHandlerIfNeeded()
        var keyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, GlobalShortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &keyRef)
        guard status == noErr, let keyRef else { throw RegistrationError.shortcutUnavailable(shortcut, status) }
        registeredKeys.append(keyRef)
        handlers[shortcut.rawValue] = handler
    }

    fileprivate func fire(id: UInt32) {
        handlers[id]?()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            throw RegistrationError.handlerInstallFailed(status)
        }
    }
}

/// C callback: Carbon delivers hotkey events on the main thread.
private let hotKeyEventCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let hotKeys = Unmanaged<HotKeys>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKeys.fire(id: hotKeyID.id) }
    return noErr
}
