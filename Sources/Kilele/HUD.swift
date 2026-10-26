import AppKit
import AudioToolbox
import CoreAudio
import IOBluetooth
import IOKit.ps

/// A short notice shown in the wings beside the notch.
struct HUDEvent: Equatable {
    var symbol: String
    var level: Double?   // shown as a bar (volume)
    var text = ""        // shown as text (battery percentage, device name)

    static func volume(_ level: Float, muted: Bool) -> HUDEvent {
        let symbol = muted || level == 0 ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        return HUDEvent(symbol: symbol, level: muted ? 0 : Double(level))
    }

    static func battery(_ percent: Int, onAC: Bool) -> HUDEvent {
        HUDEvent(symbol: onAC ? "battery.100percent.bolt" : percent <= 20 ? "battery.25percent" : "battery.75percent", text: "\(percent)%")
    }

    static func bluetooth(_ name: String, connected: Bool) -> HUDEvent {
        HUDEvent(symbol: name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones", text: connected ? name : "Disconnected")
    }
}

/// Output volume and mute on the current output device (it follows the device when that changes).
final class VolumeWatcher {
    private let onChange: (Float, Bool) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var volume = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var mute = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private var defaultOutput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private lazy var changed: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
    private lazy var deviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }

    init(onChange: @escaping (Float, Bool) -> Void) {
        self.onChange = onChange
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, .main, deviceChanged)
        attach()
    }

    private func attach() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &volume, .main, changed)
            AudioObjectRemovePropertyListenerBlock(device, &mute, .main, changed)
        }
        var id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultOutput, 0, nil, &size, &id)
        device = id
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, changed)
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, changed)
    }

    private func report() {
        var level = Float32(0), muted = UInt32(0), size = UInt32(4)
        guard AudioObjectGetPropertyData(device, &volume, 0, nil, &size, &level) == noErr else { return }
        size = 4
        AudioObjectGetPropertyData(device, &mute, 0, nil, &size, &muted)
        onChange(level, muted != 0)
    }
}

/// Plugging in, unplugging, and dropping to 20% or 10% on battery.
final class PowerWatcher {
    private let onChange: (Int, Bool) -> Void
    private var last: (percent: Int, onAC: Bool)?

    init(onChange: @escaping (Int, Bool) -> Void) {
        self.onChange = onChange
        last = read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerWatcher>.fromOpaque(context).takeUnretainedValue().check()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func check() {
        guard let now = read() else { return }
        defer { last = now }
        guard let last else { return }
        let crossedLow = !now.onAC && [20, 10].contains { last.percent > $0 && now.percent <= $0 }
        if now.onAC != last.onAC || crossedLow { onChange(now.percent, now.onAC) }
    }

    private func read() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Bluetooth devices connecting and disconnecting. macOS reports already-connected devices on start; those are skipped.
/// Registering waits until the Bluetooth permission prompt is answered, so it runs on its own thread (with a run loop
/// for the callbacks); on the main thread a pending prompt would freeze the notch.
final class BluetoothWatcher: NSObject {
    private let onChange: (String, Bool) -> Void
    private var started = Date()
    private var registration: IOBluetoothUserNotification?

    init(onChange: @escaping (String, Bool) -> Void) {
        self.onChange = onChange
        super.init()
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(self.connected(_:device:)))
            self.started = Date() // count the 3 s grace from when registration went through
            RunLoop.current.run()
        }
        thread.name = "kilele.bluetooth"
        thread.start()
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        guard Date().timeIntervalSince(started) > 3 else { return }
        let name = device.name ?? "Bluetooth device"
        DispatchQueue.main.async { self.onChange(name, true) }
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth device"
        DispatchQueue.main.async { self.onChange(name, false) }
    }
}
