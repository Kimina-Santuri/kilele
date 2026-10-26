import AppKit
import ServiceManagement
import SwiftUI

/// What the notch is showing. Updated on the main thread only.
final class NotchModel: ObservableObject {
    enum Tab { case now, notes, shelf }

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
    private var hideHUD: DispatchWorkItem?

    /// Wings beside the notch: wider when a notice has text (a device name, a percentage).
    var wingWidth: CGFloat {
        if let hud, hud.level == nil { return 96 }
        if pillMode { return 84 }
        return notchSize.height + 14
    }

    var expandedSize: CGSize {
        CGSize(width: max(720, notchSize.width + 540), height: notchSize.height + 170)
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
        model.agenda.startIfAllowed()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.model.agenda.reload() }

        volume = VolumeWatcher { [weak self] level, muted in self?.model.flash(.volume(level, muted: muted)) }
        power = PowerWatcher { [weak self] percent, onAC in self?.model.flash(.battery(percent, onAC: onAC)) }
        bluetooth = BluetoothWatcher { [weak self] name, connected in self?.model.flash(.bluetooth(name, connected: connected)) }
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
            if insideExpanded(point) { collapseWork?.cancel(); collapseWork = nil; return }
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
        } else if panel.isKeyWindow {
            // Typing in the Inbox box made the panel key; hand the keyboard back once the notch folds away.
            panel.resignKey()
        }
    }
}
