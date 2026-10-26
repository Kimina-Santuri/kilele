import AppKit
import AVFoundation

/// A focus countdown shown in the pill. A finished session (or one stopped after 5+ minutes) is logged to today's
/// Tsuzuri journal, so it shows up in the weekly review.
final class FocusTimer: ObservableObject {
    @Published private(set) var startedAt: Date?
    @Published private(set) var endsAt: Date?
    @Published private(set) var label = ""

    /// Called with start, end and label when a session should be logged.
    var onLog: (Date, Date, String) -> Void = { _, _, _ in }
    /// Called when the time is up (for the notice in the notch).
    var onFinish: (String) -> Void = { _ in }
    private var timer: Timer?

    var running: Bool { endsAt != nil }

    func remaining(at date: Date = Date()) -> TimeInterval { max(0, (endsAt ?? date).timeIntervalSince(date)) }

    func start(minutes: Int, label: String) {
        let now = Date()
        startedAt = now
        endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        self.label = label
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in self?.finish() }
    }

    func stop() {
        guard let start = startedAt else { return }
        if Date().timeIntervalSince(start) >= 300 { onLog(start, Date(), label + (label.isEmpty ? "stopped early" : " (stopped early)")) }
        reset()
    }

    private func finish() {
        guard let start = startedAt, let end = endsAt else { return }
        onLog(start, end, label)
        onFinish(label)
        NSSound(named: "Glass")?.play()
        reset()
    }

    private func reset() {
        timer?.invalidate(); timer = nil
        startedAt = nil; endsAt = nil; label = ""
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Voice memos: AAC, mono, 64 kbps (about half a megabyte a minute, light enough to sync to the phone).
/// The finished file is handed over to be filed in the notes.
final class VoiceMemo: ObservableObject {
    @Published private(set) var startedAt: Date?
    @Published private(set) var denied = false
    var onFinished: (URL) -> Void = { _ in }
    private var recorder: AVAudioRecorder?

    var recording: Bool { startedAt != nil }

    func toggle() { recording ? stop() : start() }

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.denied = !granted
                guard granted else { return }
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd HHmm"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Voice memo \(stamp.string(from: Date())).m4a")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]
                guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else { return }
                self.recorder = recorder
                self.startedAt = Date()
            }
        }
    }

    func stop() {
        guard let recorder else { return }
        recorder.stop()
        self.recorder = nil
        startedAt = nil
        onFinished(recorder.url)
    }
}
