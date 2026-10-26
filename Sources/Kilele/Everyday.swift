import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

/// New downloads and screenshots go onto the shelf by themselves. Unfinished downloads (.crdownload, .download, .part)
/// light up the shelf icon until they finish. Folders are opened off the main thread: the first look at Downloads or
/// Desktop makes macOS ask for permission, and waiting on that while drawing would freeze the notch.
final class AutoShelf: ObservableObject {
    @Published private(set) var downloading = false
    @Published var enabled = UserDefaults.standard.object(forKey: "autoShelf") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "autoShelf") }
    }
    var onNewFile: (URL) -> Void = { _ in }

    private let queue = DispatchQueue(label: "kilele.autoshelf")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var known: Set<String> = []
    private static let partial = ["crdownload", "download", "part", "partial", "opdownload"]

    init() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let downloads = home.appendingPathComponent("Downloads")
        let shots = (UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"))
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? home.appendingPathComponent("Desktop")
        queue.async { [weak self] in
            guard let self else { return }
            for (dir, screenshotsOnly) in [(downloads, false), (shots, true)] {
                self.known.formUnion(self.list(dir).map(\.path)) // what's there already isn't new
                self.watch(dir, screenshotsOnly: screenshotsOnly)
            }
        }
    }

    private func list(_ dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
    }

    private func watch(_ dir: URL, screenshotsOnly: Bool) {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in self?.scan(dir, screenshotsOnly: screenshotsOnly) }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources.append(source)
    }

    private func scan(_ dir: URL, screenshotsOnly: Bool) {
        let files = list(dir)
        if !screenshotsOnly {
            let busy = files.contains { Self.partial.contains($0.pathExtension.lowercased()) }
            DispatchQueue.main.async { self.downloading = busy }
        }
        for file in files where !known.contains(file.path) && !Self.partial.contains(file.pathExtension.lowercased()) {
            let name = file.lastPathComponent
            if screenshotsOnly && !(name.hasPrefix("Screenshot") || name.hasPrefix("Screen Recording")) { continue }
            known.insert(file.path)
            // Wait until the file stops growing (screenshots and downloads are written in steps).
            settle(file, lastSize: -1, tries: 0)
        }
    }

    private func settle(_ file: URL, lastSize: Int, tries: Int) {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, FileManager.default.fileExists(atPath: file.path) else { return }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size == lastSize || tries > 30 {
                DispatchQueue.main.async { if self.enabled { self.onNewFile(file) } }
            } else {
                self.settle(file, lastSize: size, tries: tries + 1)
            }
        }
    }
}

/// System-wide shortcuts through Carbon's hot keys, which need no Accessibility permission.
final class HotKeys {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef?] = []

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let me = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { me.handlers[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func register(key: Int, modifiers: Int, action: @escaping () -> Void) {
        let id = UInt32(handlers.count + 1)
        handlers[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4B4C_4C45), id: id), GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

/// A quick look in the camera, shown in the open notch. The camera runs only while the mirror is showing.
final class Mirror: ObservableObject {
    @Published private(set) var showing = false
    @Published private(set) var denied = false
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "kilele.mirror")
    private var configured = false

    func toggle() { showing || denied ? hide() : show() }

    func show() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.denied = !granted
                guard granted else { return }
                self.showing = true
                self.queue.async {
                    if !self.configured, let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) {
                        self.session.sessionPreset = .medium
                        self.session.addInput(input)
                        self.configured = true
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                }
            }
        }
    }

    func hide() {
        denied = false
        guard showing else { return }
        showing = false
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
}

struct MirrorView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
