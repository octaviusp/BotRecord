import CoreAudio
import Foundation

/// Where the Mac's sound is playing right now, from the CoreAudio default output device.
enum AudioOutputRoute: Equatable {
    case builtInSpeakers
    /// Built-in headphone jack, AirPods and other Bluetooth or USB headsets.
    case headphones
    /// Displays, audio interfaces, AirPlay: away from the built-in mic, so Auto leaves voice processing off.
    case external

    var label: String {
        switch self {
        case .builtInSpeakers: "built-in speakers"
        case .headphones: "headphones"
        case .external: "external output"
        }
    }

    /// Only the built-in speakers sit next to the built-in microphone.
    var leaksIntoMicrophone: Bool { self == .builtInSpeakers }

    // Data source codes of the built-in output: 'ispk' internal speakers, 'hdpn' headphone jack.
    private static let headphonesDataSource: UInt32 = 0x6864_706E // 'hdpn'

    static func current() -> AudioOutputRoute {
        do {
            let device: AudioObjectID = try property(AudioObjectID(kAudioObjectSystemObject),
                                                     kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            let transport: UInt32 = try property(device, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
            switch transport {
            case kAudioDeviceTransportTypeBuiltIn:
                return builtInRoute(device)
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeUSB:
                return .headphones
            default:
                return .external
            }
        } catch {
            // Unknown route: assume speakers, where a missing echo canceller would hurt most.
            captureLog.error("Could not read the audio output route: \(error.localizedDescription)")
            return .builtInSpeakers
        }
    }

    /// Macs without a headphone data source (or that don't report it) are on speakers.
    private static func builtInRoute(_ device: AudioObjectID) -> AudioOutputRoute {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return .builtInSpeakers }
        do {
            let source: UInt32 = try property(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
            return source == headphonesDataSource ? .headphones : .builtInSpeakers
        } catch {
            captureLog.error("Could not read the built-in output's data source: \(error.localizedDescription)")
            return .builtInSpeakers
        }
    }

    private static func property<Value>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                        scope: AudioObjectPropertyScope) throws -> Value where Value: FixedWidthInteger {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return value
    }
}

extension EchoCancellationMode {
    func isEnabled(for route: AudioOutputRoute) -> Bool {
        switch self {
        case .auto: route.leaksIntoMicrophone
        case .on: true
        case .off: false
        }
    }
}
