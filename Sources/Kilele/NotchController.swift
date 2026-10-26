import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// What the notch is showing. Updated on the main thread only.
final class NotchModel: ObservableObject {
    enum Tab { case now, today, notes, shelf }

    @Published var expanded = false
    @Published var tab: Tab = .now
    @Published var hud: HUDEvent?
    @Published var notchSize = CGSize(width: 185, height: 32)
    // Small bits of view state live here: SwiftUI's @State needs Xcode's macro plugin, which the command-line tools lack.
    @Published var dropping = false
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled
    @Published var showMusicWings = UserDefaults.standard.object(forKey: "showMusicWings") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMusicWings, forKey: "showMusicWings") }
    }
    /// Collapsed, the notch is a pill with quick-access icons either side.
    @Published var pillMode = UserDefaults.standard.object(forKey: "pillMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pillMode, forKey: "pillMode") }
    }
    /// Set by the controller: open the notch on a tab (and put the cursor in the Inbox box).
    var open: (Tab, Bool) -> Void = { _, _ in }

    let nowPlaying = NowPlaying()
    let shelf = Shelf()
    let agenda = Agenda()
    let notes = Notes()
    let outputs = AudioOutputs()
    let mic = MicWatcher()
    let tempo = TapTempo()
    let lyrics = Lyrics()
    let slots = StudioSlots()
    let focus = FocusTimer()
    let memo = VoiceMemo()
    let autoShelf = AutoShelf()
    let mirror = Mirror()
    let updater = Updater()
    private var hideHUD: DispatchWorkItem?

    /// Wings beside the notch: wider when a notice has text (a device name, a percentage).
    var wingWidth: CGFloat {
        if pillMode { return 104 }
        if let hud, hud.level == nil { return 96 }
        return notchSize.height + 14
    }

    var expandedSize: CGSize {
        CGSize(width: max(720, notchSize.width + 540), height: notchSize.height + 190)
    }

    func visibleSize(playing: Bool) -> CGSize {
        if expanded { return expandedSize }
        let wings = hud != nil || pillMode || (playing && showMusicWings)
        return CGSize(width: notchSize.width + (wings ? 2 * wingWidth : 0), height: notchSize.height)
    }

    func flash(_ event: HUDEvent) {
        hud = event
        hideHUD?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hideHUD = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

/// A borderless panel above the menu bar, the size of the expanded notch. While collapsed it lets clicks through.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}

/// Lets the first click on the (never-active) panel press a button instead of only bringing the window forward.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    private let model = NotchModel()
    private let panel = NotchPanel()
    private var screenFrame = NSRect.zero
    private var monitors: [Any] = []
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var menuOpen = false
    private var volume: VolumeWatcher?
    private var power: PowerWatcher?
    private var bluetooth: BluetoothWatcher?
    private var poll: Timer?
    private let hotKeys = HotKeys()
    /// Opened from the keyboard (or a shortcut) with the pointer elsewhere: stay open until the pointer has been in
    /// and left again, Esc is pressed, or the shortcut is pressed again.
    private var heldOpen = false

    init() {
        let host = FirstClickHostingView(rootView: NotchRoot(model: model, player: model.nowPlaying))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.layout() }
        // A settings menu can hang below the notch; don't fold the notch away while it's open.
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuOpen = true }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = false
            self?.track(.mouseMoved)
        }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] e in self?.track(e.type) }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in self?.track(e.type); return e }) { monitors.append(local) }

        // Mouse-moved events don't always reach a panel that isn't key, so also check the pointer ten times a second.
        poll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.track(.mouseMoved) }
        model.open = { [weak self] tab, focusCapture in self?.open(tab, focusCapture: focusCapture) }
        wire()
        model.agenda.startIfAllowed()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.model.agenda.reload() }

        volume = VolumeWatcher { [weak self] level, muted in self?.model.flash(.volume(level, muted: muted)) }
        power = PowerWatcher { [weak self] percent, onAC in self?.model.flash(.battery(percent, onAC: onAC)) }
        bluetooth = BluetoothWatcher { [weak self] name, connected in self?.model.flash(.bluetooth(name, connected: connected)) }
    }

    private func wire() {
        let m = model
        m.nowPlaying.onTrackChange = { [weak m] title, artist, duration in m?.lyrics.load(title: title, artist: artist, duration: duration) }
        m.focus.onLog = { [weak m] start, end, label in m?.notes.logFocus(start: start, end: end, label: label) }
        m.focus.onFinish = { [weak m] label in m?.flash(HUDEvent(symbol: "checkmark.circle.fill", text: label.isEmpty ? "Focus done" : "Done: \(label)")) }
        m.memo.onFinished = { [weak m] url in m?.notes.attach(url, moving: true) }
        m.autoShelf.onNewFile = { [weak m] url in
            m?.shelf.add(url)
            m?.flash(HUDEvent(symbol: "tray.and.arrow.down.fill", text: url.lastPathComponent))
        }
        m.agenda.onEndingSoon = { [weak m] _ in
            NSSound(named: "Tink")?.play()
            m?.flash(HUDEvent(symbol: "clock.fill", text: "10 min left"))
        }
        // ⌃⌥Space opens or closes the notch; ⌃⌥N opens quick capture.
        hotKeys.register(key: kVK_Space, modifiers: controlKey | optionKey) { [weak self] in
            guard let self else { return }
            if self.model.expanded { self.heldOpen = false; self.setExpanded(false) } else { self.heldOpen = true; self.open(self.model.tab == .shelf ? .now : self.model.tab, focusCapture: false) }
        }
        hotKeys.register(key: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
            self?.heldOpen = true
            self?.open(.notes, focusCapture: true)
        }
        // Esc closes the notch while it's open.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.expanded, event.keyCode == UInt16(kVK_Escape) else { return event }
            self.heldOpen = false
            self.setExpanded(false)
            return nil
        }
    }

    /// The screen with a notch, or the main screen (where Kilele sits in the middle of the menu bar).
    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layout() {
        let s = screen, frame = s.frame
        var height = s.safeAreaInsets.top
        if height <= 0 { height = max(24, frame.maxY - s.visibleFrame.maxY) }
        var width: CGFloat = 185
        if let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea { width = frame.width - left.width - right.width }
        model.notchSize = CGSize(width: width, height: height)
        screenFrame = frame
        panel.setFrame(rect(for: model.expandedSize), display: true)
    }

    /// A rect of this size hanging from the top centre of the screen.
    private func rect(for size: CGSize) -> NSRect {
        NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    private func draggingFiles() -> Bool {
        NSPasteboard(name: .drag).types?.contains(.fileURL) ?? false
    }

    private func track(_ type: NSEvent.EventType) {
        let point = NSEvent.mouseLocation
        // A held button counts as dragging (the 10 Hz check reports mouse moves even mid-drag); only files open the notch.
        let dragging = type == .leftMouseDragged || NSEvent.pressedMouseButtons & 1 != 0
        if !model.expanded {
            // The visible notch (and its wings), with a little slack, up to the very top edge of the screen.
            var visible = rect(for: model.visibleSize(playing: model.nowPlaying.isPlaying)).insetBy(dx: -6, dy: 0)
            visible.size.height += 2
            // In pill mode only the notch itself opens the panel on hover; the icons either side take clicks instead.
            var hot = model.pillMode && model.hud == nil ? rect(for: model.notchSize).insetBy(dx: -4, dy: 0) : visible
            hot.size.height += 2
            if dragging && draggingFiles() { hot = visible }
            panel.ignoresMouseEvents = !(model.pillMode && visible.contains(point))
            guard hot.contains(point), !dragging || draggingFiles() else {
                expandWork?.cancel(); expandWork = nil
                return
            }
            guard expandWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.expandWork = nil
                self?.setExpanded(true, forShelf: dragging)
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (dragging ? 0.05 : 0.12), execute: work)
        } else {
            if insideExpanded(point) { heldOpen = false; collapseWork?.cancel(); collapseWork = nil; return }
            if heldOpen { return }
            // Mid-drag (a file out of the shelf, or one that wandered off): wait until the button is released.
            if NSEvent.pressedMouseButtons & 1 != 0 { return }
            guard collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !self.menuOpen && !self.insideExpanded(NSEvent.mouseLocation) { self.setExpanded(false) }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func insideExpanded(_ point: NSPoint) -> Bool {
        var r = rect(for: model.expandedSize).insetBy(dx: -12, dy: -12)
        r.size.height += 2
        return r.contains(point)
    }

    private func open(_ tab: NotchModel.Tab, focusCapture: Bool) {
        expandWork?.cancel(); expandWork = nil
        model.tab = tab
        setExpanded(true)
        guard focusCapture else { return }
        // Put the cursor in the Inbox box once the Notes tab is on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let field = Self.firstTextField(in: self.panel.contentView) else { return }
            self.panel.makeKey()
            self.panel.makeFirstResponder(field)
        }
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let found = firstTextField(in: sub) { return found } }
        return nil
    }

    private func setExpanded(_ expanded: Bool, forShelf: Bool = false) {
        if forShelf { model.tab = .shelf }
        model.expanded = expanded
        panel.ignoresMouseEvents = !expanded
        if expanded {
            model.agenda.start()
            model.notes.reload()
            model.slots.reload()
        } else {
            heldOpen = false
            model.mirror.hide()
        }
        if !expanded && panel.isKeyWindow {
            // Typing in the Inbox box made the panel key; hand the keyboard back once the notch folds away.
            panel.resignKey()
        }
    }
}
