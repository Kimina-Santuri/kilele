import AppKit
import CoreAudio

/// Small CoreAudio helpers shared by the output switcher and the mic watcher.
enum CoreAudioHelp {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func device(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var addr = address(selector), id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func setDevice(_ selector: AudioObjectPropertySelector, _ id: AudioObjectID) {
        var addr = address(selector), value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &value)
    }

    static func allDevices() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices), size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    static func name(_ id: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName), ref: Unmanaged<CFString>?, size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ref) == noErr, let ref else { return "Audio device" }
        return ref.takeRetainedValue() as String
    }

    static func hasStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope), size = UInt32(0)
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }
}

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
}

/// The Mac's sound outputs (speakers, headphones, AirPods, interfaces) and which one is in use. Switching sets both the
/// default output and the alert-sound output, like choosing it in Control Centre.
final class AudioOutputs: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var current = AudioObjectID(kAudioObjectUnknown)
    private lazy var changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }

    init() {
        refresh()
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = CoreAudioHelp.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, changed)
        }
    }

    var currentName: String { devices.first { $0.id == current }?.name ?? "Output" }

    func refresh() {
        devices = CoreAudioHelp.allDevices().filter { CoreAudioHelp.hasStreams($0, scope: kAudioDevicePropertyScopeOutput) }
            .map { AudioDevice(id: $0, name: CoreAudioHelp.name($0)) }
        current = CoreAudioHelp.device(kAudioHardwarePropertyDefaultOutputDevice)
    }

    func select(_ device: AudioDevice) {
        CoreAudioHelp.setDevice(kAudioHardwarePropertyDefaultOutputDevice, device.id)
        CoreAudioHelp.setDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, device.id)
        refresh()
    }
}

/// Whether any app is using the microphone (CoreAudio's "running somewhere", no permission needed), and mute.
/// Mute uses the input's mute switch where it has one, otherwise sets its volume to zero and back.
final class MicWatcher: ObservableObject {
    @Published private(set) var inUse = false
    @Published private(set) var muted = false

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var savedVolume: Float32 = 1
    private lazy var changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.read() }
    private lazy var deviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }
    private let watched: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput),
        (kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput),
    ]

    init() {
        var addr = CoreAudioHelp.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, deviceChanged)
        attach()
    }

    private func attach() {
        if device != kAudioObjectUnknown {
            for (selector, scope) in watched { var a = CoreAudioHelp.address(selector, scope); AudioObjectRemovePropertyListenerBlock(device, &a, .main, changed) }
        }
        device = CoreAudioHelp.device(kAudioHardwarePropertyDefaultInputDevice)
        for (selector, scope) in watched { var a = CoreAudioHelp.address(selector, scope); AudioObjectAddPropertyListenerBlock(device, &a, .main, changed) }
        read()
    }

    private func read() {
        var running = UInt32(0), size = UInt32(4), addr = CoreAudioHelp.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        inUse = running != 0
        muted = muteSwitch() == true || (muteSwitch() == nil && volume() == 0)
    }

    func toggleMute() {
        if muteSwitch() != nil {
            var addr = CoreAudioHelp.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput), value = UInt32(muted ? 0 : 1)
            AudioObjectSetPropertyData(device, &addr, 0, nil, 4, &value)
        } else {
            if !muted { savedVolume = max(volume() ?? 1, 0.1) }
            var addr = CoreAudioHelp.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput), value: Float32 = muted ? savedVolume : 0
            AudioObjectSetPropertyData(device, &addr, 0, nil, 4, &value)
        }
        read()
    }

    /// nil when the input has no settable mute switch.
    private func muteSwitch() -> Bool? {
        var addr = CoreAudioHelp.address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput), settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr), AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return nil }
        var value = UInt32(0), size = UInt32(4)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return value != 0
    }

    private func volume() -> Float32? {
        var addr = CoreAudioHelp.address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput), value: Float32 = 0, size = UInt32(4)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

/// Tap along to get a tempo: the average of the last eight taps; a pause of over two seconds starts again.
final class TapTempo: ObservableObject {
    @Published private(set) var bpm: Int?
    private var taps: [Date] = []

    func tap() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps = [] }
        taps = Array((taps + [now]).suffix(8))
        guard taps.count >= 2, let first = taps.first else { bpm = nil; return }
        bpm = Int((60 / (now.timeIntervalSince(first) / Double(taps.count - 1))).rounded())
    }
}
