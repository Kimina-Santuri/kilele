import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The black shape hanging from the notch. Collapsed it's the pill (or the bare notch, with wings for music or a
/// notice); expanded it opens into a panel with the Now, Today, Notes and Shelf tabs.
struct NotchRoot: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying

    var body: some View {
        let size = model.visibleSize(playing: player.isPlaying)
        let radius: CGFloat = model.expanded ? 24 : model.peek != nil ? 18 : min(10, model.notchSize.height / 3)
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
        ZStack(alignment: .top) {
            // The pill is glass all over (the physical notch hides its middle); open, the top strip stays black.
            NotchBackground(glass: model.seeThrough, band: model.expanded || model.peek != nil ? model.notchSize.height : 0)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    Group {
                        if model.expanded {
                            ExpandedView(model: model, player: player, shelf: model.shelf, notes: model.notes, mirror: model.mirror)
                        } else {
                            VStack(spacing: 0) {
                                CollapsedView(model: model, player: player, shelf: model.shelf, notes: model.notes, mic: model.mic, memo: model.memo, autoShelf: model.autoShelf, alerts: model.alerts)
                                    .frame(width: model.barSize(playing: player.isPlaying).width, height: model.notchSize.height)
                                if let peek = model.peek {
                                    PeekView(alert: peek, alerts: model.alerts) { model.peek = nil }
                                        .transition(.opacity)
                                }
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .top)
                }
                .clipShape(shape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: size)
        .environment(\.colorScheme, .dark)
    }
}

/// Solid black, or (see-through on) dark frosted glass: the pill all over, and open with a black band at the top
/// where the physical notch and menu bar are, fading into the glass.
struct NotchBackground: View {
    var glass: Bool
    var band: CGFloat

    var body: some View {
        if glass {
            ZStack(alignment: .top) {
                GlassView()
                Color.black.opacity(0.3)
                if band > 0 {
                    VStack(spacing: 0) {
                        Color.black.frame(height: band)
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 16)
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            Color.black
        }
    }
}

/// The desktop behind, blurred (NSVisualEffectView, always active since the panel never becomes the main window).
struct GlassView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: Collapsed

struct CollapsedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var shelf: Shelf
    @ObservedObject var notes: Notes
    @ObservedObject var mic: MicWatcher
    @ObservedObject var memo: VoiceMemo
    @ObservedObject var autoShelf: AutoShelf
    @ObservedObject var alerts: Alerts

    var body: some View {
        if model.hud == nil && model.pillMode {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if alerts.unread > 0 { PillIcon(symbol: "bell.badge", badge: alerts.unread, help: "Notifications") { model.open(.alerts, false) } }
                    PillIcon(symbol: autoShelf.downloading ? "arrow.down.circle" : "tray", badge: shelf.items.count, help: autoShelf.downloading ? "Downloading… (Shelf)" : "Shelf") { model.open(.shelf, false) }
                    if notes.available { PillIcon(symbol: "square.and.pencil", help: "Quick note (⌃⌥N)") { model.open(.notes, true) } }
                    if memo.recording {
                        PillIcon(symbol: "record.circle.fill", tint: .red, help: "Stop recording the voice memo") { memo.stop() }
                    } else if mic.inUse || mic.muted {
                        PillIcon(symbol: mic.muted ? "mic.slash.fill" : "mic.fill", tint: mic.muted ? .white.opacity(0.6) : .orange, help: mic.muted ? "Microphone muted: click to unmute" : "Microphone in use: click to mute") { mic.toggleMute() }
                    }
                }
                .frame(width: model.wingWidth, height: model.notchSize.height)
                Spacer(minLength: model.notchSize.width)
                HStack(spacing: 10) {
                    MusicPillIcon(player: player) { model.open(.now, false) }
                    TimePill(agenda: model.agenda, focus: model.focus) { model.open(.today, false) }
                }
                .frame(width: model.wingWidth, height: model.notchSize.height)
            }
            .transition(.opacity)
        } else if model.hud != nil || (player.isPlaying && model.showMusicWings) {
            HStack(spacing: 0) {
                left.frame(width: model.wingWidth, height: model.notchSize.height)
                Spacer(minLength: model.notchSize.width)
                right.frame(width: model.wingWidth, height: model.notchSize.height)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder private var left: some View {
        if let hud = model.hud {
            Image(systemName: hud.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        } else {
            ArtworkView(image: player.artwork, size: max(16, model.notchSize.height - 12), corner: 5)
        }
    }

    @ViewBuilder private var right: some View {
        if let hud = model.hud {
            if let level = hud.level {
                LevelBar(level: level).frame(width: model.wingWidth - 18, height: 4)
            } else {
                Text(hud.text).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 8)
            }
        } else {
            EqualizerBars().frame(width: 16, height: 12)
        }
    }
}

struct PillIcon: View {
    var symbol: String
    var badge = 0
    var tint: Color = .white.opacity(0.85)
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .frame(width: 22, height: 22).contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 3).background(Capsule().fill(.white)).offset(x: 5, y: -3)
                    }
                }
        }
        .buttonStyle(.plain).help(help)
    }
}

/// Play/pause when something is loaded (bouncing bars while it plays); otherwise opens the Now tab.
struct MusicPillIcon: View {
    @ObservedObject var player: NowPlaying
    var openNow: () -> Void
    var body: some View {
        Button { player.hasMedia ? player.playPause() : openNow() } label: {
            Group {
                if player.isPlaying { EqualizerBars().frame(width: 16, height: 12) }
                else { Image(systemName: player.hasMedia ? "play.fill" : "music.note").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85)) }
            }
            .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(player.hasMedia ? "Play or pause \(player.title)" : "Now playing")
    }
}

/// The pill's clock: a running focus timer, else time left in the event you're in, else the countdown (pinned event
/// or the next one, within a week), else a calendar icon.
struct TimePill: View {
    @ObservedObject var agenda: Agenda
    @ObservedObject var focus: FocusTimer
    var open: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: open) { label(at: context.date).frame(minWidth: 22, minHeight: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func label(at now: Date) -> some View {
        let text = Font.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
        if focus.running {
            HStack(spacing: 3) { Image(systemName: "timer").font(.system(size: 10)); Text(FocusTimer.clock(focus.remaining(at: now))).font(text) }
                .foregroundStyle(.orange).help("Focus")
        } else if let session = agenda.session(at: now) {
            Text("\(Agenda.span(session.endDate.timeIntervalSince(now))) left").font(text).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.7).help(session.title ?? "Now")
        } else if let next = agenda.countdownTarget(at: now), next.startDate.timeIntervalSince(now) < 7 * 86_400 {
            Text(Agenda.span(next.startDate.timeIntervalSince(now))).font(text).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).minimumScaleFactor(0.7).help("\(next.title ?? "Next event")")
        } else {
            Image(systemName: "calendar").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct LevelBar: View {
    var level: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: g.size.width * min(1, max(0, level)))
            }
        }
    }
}

/// Little bouncing bars while music plays.
struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(.white).frame(width: 2.5, height: 3 + 9 * abs(sin(t * 3.2 + Double(i) * 0.9)))
                }
            }
        }
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat = 8
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: Expanded

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying
    @ObservedObject var shelf: Shelf
    @ObservedObject var notes: Notes
    @ObservedObject var mirror: Mirror

    var body: some View {
        VStack(spacing: 0) {
            // The strip either side of the camera: Now, Today and Alerts on the left; Notes, Shelf, mirror, do not disturb
            // and settings on the right. Each side gets exactly the space beside the notch, so nothing slides under it.
            let side = (model.expandedSize.width - model.notchSize.width) / 2 - 32
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    TabButton(title: "Now", selected: model.tab == .now) { model.tab = .now }
                    TabButton(title: "Today", selected: model.tab == .today) { model.tab = .today }
                    AlertsTabButton(model: model, alerts: model.alerts)
                }
                .frame(width: side, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    if notes.available { TabButton(title: "Notes", selected: model.tab == .notes) { model.tab = .notes } }
                    TabButton(title: shelf.items.isEmpty ? "Shelf" : "Shelf \(shelf.items.count)", selected: model.tab == .shelf) { model.tab = .shelf }
                    Spacer(minLength: 6)
                    Button { mirror.toggle() } label: {
                        Image(systemName: mirror.showing ? "video.fill" : "video").font(.system(size: 12)).foregroundStyle(.white.opacity(mirror.showing ? 1 : 0.6))
                    }
                    .buttonStyle(.plain).help("Camera mirror")
                    QuietButton(alerts: model.alerts).padding(.leading, 6)
                    SettingsMenu(model: model, lyrics: model.lyrics, autoShelf: model.autoShelf, updater: model.updater, alerts: model.alerts).padding(.leading, 8)
                }
                .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(height: model.notchSize.height)

            Group {
                if mirror.showing {
                    MirrorView(session: mirror.session)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if mirror.denied {
                    Text("Camera access is off. Turn it on in System Settings › Privacy & Security › Camera.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                } else {
                    switch model.tab {
                    case .now: NowTab(player: player, lyrics: model.lyrics, outputs: model.outputs, tempo: model.tempo)
                    case .today: TodayTab(agenda: model.agenda, slots: model.slots, focus: model.focus)
                    case .alerts: AlertsTab(alerts: model.alerts)
                    case .notes: NotesTab(notes: notes, focus: model.focus, memo: model.memo)
                    case .shelf: ShelfTab(shelf: shelf, notes: notes, autoShelf: model.autoShelf, dropping: model.dropping)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { model.dropping }, set: { model.dropping = $0 })) { providers in
            model.tab = .shelf
            shelf.accept(providers)
            return true
        }
        .onChange(of: model.dropping) { _, now in if now { model.tab = .shelf } }
    }
}

struct TabButton: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0)))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMenu: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var autoShelf: AutoShelf
    @ObservedObject var updater: Updater
    @ObservedObject var alerts: Alerts

    var body: some View {
        Menu {
            Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                model.openAtLogin = SMAppService.mainApp.status == .enabled
            }))
            Toggle("Pill mode (icons beside the notch)", isOn: $model.pillMode)
            Toggle("See-through (frosted glass)", isOn: $model.seeThrough)
            Toggle("Show music beside the notch", isOn: $model.showMusicWings).disabled(model.pillMode)
            Toggle("Lyrics (from lrclib.net)", isOn: $lyrics.enabled)
            Toggle("New downloads and screenshots to the shelf", isOn: $autoShelf.enabled)
            Toggle("Show new notifications from the notch", isOn: $alerts.peeks)
            Divider()
            Text("⌃⌥Space  open or close the notch")
            Text("⌃⌥N  quick note")
            Divider()
            if let version = updater.available {
                Button("Update to Kilele \(version)") { updater.install() }
            } else {
                Button("Check for updates") { updater.check() }
            }
            Text(updater.status.isEmpty ? "Kilele \(updater.current)" : updater.status)
            Divider()
            Button("Quit Kilele") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: updater.available == nil ? "gearshape.fill" : "arrow.down.circle.fill")
                .font(.system(size: 12)).foregroundStyle(updater.available == nil ? .white.opacity(0.6) : .orange)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: Now tab (music)

struct NowTab: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var outputs: AudioOutputs
    @ObservedObject var tempo: TapTempo

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            NowPlayingCard(player: player).frame(width: 330, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 8) {
                LyricsView(player: player, lyrics: lyrics).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 10) {
                    Menu {
                        ForEach(outputs.devices) { device in
                            Button { outputs.select(device) } label: {
                                if device.id == outputs.current { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                            }
                        }
                    } label: {
                        Label(outputs.currentName, systemImage: "hifispeaker.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Sound output")
                    Spacer()
                    Button { tempo.tap() } label: {
                        HStack(spacing: 6) {
                            Text("TAP").font(.system(size: 10, weight: .bold))
                            Text(tempo.bpm.map { "\($0) BPM" } ?? "– BPM").font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain).help("Tap along to the beat")
                }
            }
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        if player.hasMedia {
            HStack(alignment: .top, spacing: 12) {
                ArtworkView(image: player.artwork, size: 76, corner: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    HStack(spacing: 18) {
                        control("backward.fill", player.previous)
                        control(player.isPlaying ? "pause.fill" : "play.fill", player.playPause)
                        control("forward.fill", player.next)
                        Spacer()
                        if !player.source.isEmpty { Text(player.source).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).lineLimit(1) }
                    }
                    .padding(.top, 6)
                    if player.duration > 0 { Scrubber(player: player).padding(.top, 4) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5))
                Text("Nothing playing").font(.system(size: 13, weight: .semibold))
                Text("Play something: Music, Spotify, or a video or song in your browser.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func control(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15)) }.buttonStyle(.plain)
    }
}

/// Position in the track; drag to seek (sent when you let go).
struct Scrubber: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let position = player.scrubbing ?? player.position(at: context.date)
            VStack(spacing: 1) {
                Slider(value: Binding(get: { position }, set: { player.scrubbing = $0 }), in: 0...max(1, player.duration)) { editing in
                    if !editing, let target = player.scrubbing { player.seek(to: target); player.scrubbing = nil }
                }
                .controlSize(.mini).tint(.white)
                HStack {
                    Text(Self.time(position)); Spacer(); Text("-" + Self.time(max(0, player.duration - position)))
                }
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func time(_ s: Double) -> String {
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct LyricsView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: Lyrics

    var body: some View {
        if !lyrics.enabled {
            DailyCard()
        } else if !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let line = lyrics.current(at: player.position(at: context.date))
                VStack(alignment: .leading, spacing: 5) {
                    Text(line.now.isEmpty ? "♪" : line.now).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(line.next).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                .animation(.easeOut(duration: 0.2), value: line.now)
            }
        } else if lyrics.searching {
            Text("Looking for lyrics…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        } else {
            // No lyrics to follow: the proverb and animation of the day instead.
            DailyCard()
        }
    }
}

// MARK: Today tab (calendar, countdown, studio)

struct TodayTab: View {
    @ObservedObject var agenda: Agenda
    @ObservedObject var slots: StudioSlots
    @ObservedObject var focus: FocusTimer

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            AgendaView(agenda: agenda).frame(width: 330, alignment: .topLeading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in countdown(at: context.date) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPEN NEXT AT SANTURI").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    if slots.slots.isEmpty {
                        Text(slots.failed ? "Couldn't reach the bookings site." : "Checking the studio…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    ForEach(slots.slots) { slot in
                        Button { slots.book(slot) } label: {
                            HStack {
                                Text(slot.name).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                Text(Self.when(slot.start) + " ↗").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        .buttonStyle(.plain).help("Book \(slot.name)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func countdown(at now: Date) -> some View {
        if let session = agenda.session(at: now) {
            let total = session.endDate.timeIntervalSince(session.startDate), done = now.timeIntervalSince(session.startDate)
            VStack(alignment: .leading, spacing: 3) {
                Text("NOW").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                HStack { Text(session.title ?? "Event").font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text("\(Agenda.span(session.endDate.timeIntervalSince(now))) left").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
                LevelBar(level: total > 0 ? done / total : 0).frame(height: 3)
            }
        } else if let next = agenda.countdownTarget(at: now) {
            VStack(alignment: .leading, spacing: 3) {
                Text(agenda.pinned == next ? "COUNTING DOWN TO" : "NEXT").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                HStack { Text(next.title ?? "Event").font(.system(size: 13, weight: .semibold)).lineLimit(1); Spacer(); Text("in \(Agenda.span(next.startDate.timeIntervalSince(now)))").font(.system(size: 12, weight: .semibold).monospacedDigit()) }
            }
        } else {
            Text("Pin an event (📌) to count down to it.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
    }

    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if Calendar.current.isDateInToday(date) { return "Today " + f.string(from: date) }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow " + f.string(from: date) }
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }
}

struct AgendaView: View {
    @ObservedObject var agenda: Agenda

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !agenda.calendarAllowed {
                Text("Calendar access is off").font(.system(size: 13, weight: .semibold))
                Text("Turn it on in System Settings › Privacy & Security › Calendars.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                HStack {
                    Text("COMING UP").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    CalendarsMenu(agenda: agenda)
                }
                DayTimeline(agenda: agenda).frame(height: 30)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        if agenda.events.isEmpty && agenda.reminders.isEmpty {
                            Text("Nothing in the next week on the calendars you've chosen.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        }
                        ForEach(agenda.events, id: \.self) { event in
                            EventPill(event: event, pinned: agenda.pinned == event) { agenda.pin(agenda.pinned == event ? nil : event) }
                        }
                        ForEach(agenda.reminders, id: \.self) { reminder in
                            HStack(spacing: 6) {
                                Button { agenda.complete(reminder) } label: { Image(systemName: "circle").font(.system(size: 10)) }.buttonStyle(.plain).help("Tick off")
                                Text(reminder.title ?? "Reminder").font(.system(size: 11.5)).lineLimit(1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.07)))
                        }
                    }
                }
            }
        }
    }
}

/// An event as a capsule in its calendar's colour: time, title, and a pin to count down to it.
struct EventPill: View {
    let event: EKEvent
    let pinned: Bool
    let pin: () -> Void

    var body: some View {
        let color = Color(cgColor: event.calendar.cgColor)
        let now = !event.isAllDay && event.startDate <= Date() && event.endDate > Date()
        HStack(spacing: 7) {
            Text(now ? "NOW" : Self.when(event)).font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            Text(event.title ?? "Event").font(.system(size: 11.5, weight: now ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 4)
            if !event.isAllDay {
                Button(action: pin) {
                    Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 9)).foregroundStyle(.white.opacity(pinned ? 0.95 : 0.35))
                }
                .buttonStyle(.plain).help(pinned ? "Stop counting down" : "Count down to this")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(now ? 0.45 : 0.22)))
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
        .help("\(event.title ?? "Event") · \(event.calendar.title)")
    }

    static func when(_ event: EKEvent) -> String {
        let f = DateFormatter()
        let calendar = Calendar.current
        if event.isAllDay { return calendar.isDateInToday(event.startDate) ? "TODAY" : (calendar.isDateInTomorrow(event.startDate) ? "TMRW" : { f.dateFormat = "EEE"; return f.string(from: event.startDate).uppercased() }()) }
        if calendar.isDateInToday(event.startDate) { f.dateFormat = "HH:mm" }
        else if calendar.isDateInTomorrow(event.startDate) { f.dateFormat = "'TMRW' HH:mm" }
        else { f.dateFormat = "EEE HH:mm" }
        return f.string(from: event.startDate).uppercased()
    }
}

/// The next 12 hours (from an hour ago): events as coloured pills on a track, with a marker for now.
struct DayTimeline: View {
    @ObservedObject var agenda: Agenda

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let start = context.date.addingTimeInterval(-3600), span: TimeInterval = 12 * 3600
            GeometryReader { g in
                let w = g.size.width
                let x = { (d: Date) in CGFloat(min(span, max(0, d.timeIntervalSince(start))) / span) * w }
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.white.opacity(0.08)).frame(width: w, height: 12).offset(y: 4)
                    ForEach(agenda.upcoming.filter { $0.endDate > start && $0.startDate < start.addingTimeInterval(span) }, id: \.self) { event in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(cgColor: event.calendar.cgColor).opacity(0.9))
                            .frame(width: max(6, x(event.endDate) - x(event.startDate)), height: 12)
                            .offset(x: x(event.startDate), y: 4)
                            .help("\(EventPill.when(event)) \(event.title ?? "")")
                    }
                    ForEach(Self.hours(from: start, span: span), id: \.self) { hour in
                        Text(Self.label(hour)).font(.system(size: 8, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                            .position(x: x(hour), y: 24)
                    }
                    Rectangle().fill(Color.orange).frame(width: 1.5, height: 18).offset(x: x(context.date), y: 1)
                }
            }
        }
    }

    /// Every third full hour in the window.
    static func hours(from start: Date, span: TimeInterval) -> [Date] {
        let calendar = Calendar.current
        guard var hour = calendar.nextDate(after: start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) else { return [] }
        var out: [Date] = []
        while hour < start.addingTimeInterval(span - 1800) {
            if calendar.component(.hour, from: hour) % 3 == 0 { out.append(hour) }
            hour = hour.addingTimeInterval(3600)
        }
        return out
    }

    static func label(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH"; return f.string(from: d)
    }
}

/// Choose which calendars Kilele uses, grouped by account (Google, iCloud, …).
struct CalendarsMenu: View {
    @ObservedObject var agenda: Agenda

    var body: some View {
        Menu {
            ForEach(Array(Set(agenda.calendars.map(Agenda.account))).sorted(), id: \.self) { account in
                Section(account) {
                    ForEach(agenda.calendars.filter { Agenda.account($0) == account }, id: \.calendarIdentifier) { calendar in
                        Button { agenda.toggle(calendar) } label: {
                            if agenda.isShown(calendar) { Label(calendar.title, systemImage: "checkmark") } else { Text(calendar.title) }
                        }
                    }
                }
            }
        } label: {
            Label("Calendars", systemImage: "calendar").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose which calendars to show")
    }
}

// MARK: Alerts tab (other apps' notifications)

/// Do not disturb: a moon, lit while Kilele's quiet mode or a macOS Focus is on.
struct QuietButton: View {
    @ObservedObject var alerts: Alerts
    var body: some View {
        Button { alerts.toggleQuiet() } label: {
            Image(systemName: alerts.silenced ? "moon.fill" : "moon").font(.system(size: 12))
                .foregroundStyle(alerts.silenced ? Color(red: 0.62, green: 0.55, blue: 1) : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help(alerts.quiet ? "Do not disturb is on: notifications wait in Alerts. Click to turn off."
              : alerts.systemFocus.map { "\($0) Focus is on in macOS. Click for Kilele's do not disturb too." } ?? "Do not disturb: hold notifications in Alerts")
    }
}

/// "Alerts", with the number that came in since you last looked; looking marks them read.
struct AlertsTabButton: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var alerts: Alerts
    var body: some View {
        TabButton(title: alerts.unread > 0 ? "Alerts \(alerts.unread)" : "Alerts", selected: model.tab == .alerts) { model.tab = .alerts }
            .onChange(of: model.tab) { _, tab in if tab == .alerts { alerts.markRead() } }
            .onAppear { if model.tab == .alerts { alerts.markRead() } }
    }
}

struct AlertsTab: View {
    @ObservedObject var alerts: Alerts

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("NOTIFICATIONS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                AlertAppsMenu(alerts: alerts)
                if !alerts.items.isEmpty {
                    Button("Clear") { alerts.clearAll() }.buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                }
            }
            if !alerts.allowed {
                Text("Kilele can't see notifications yet").font(.system(size: 13, weight: .semibold))
                Text("Turn on Kilele under Full Disk Access (it reads the list Notification Center keeps, on this Mac only).")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Button("Open Privacy & Security") { Alerts.openPrivacySettings() }.buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.12)))
            } else if alerts.replaceBanners && !alerts.accessibility {
                HStack(spacing: 8) {
                    Text("To replace macOS's banners, allow Kilele under Accessibility.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Button("Allow") { alerts.askForAccessibility() }.buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            if alerts.allowed && alerts.items.isEmpty {
                Text("No notifications in the last day.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else if alerts.allowed {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 6) {
                        ForEach(alerts.items) { alert in AlertRow(alert: alert, alerts: alerts) }
                    }
                }
            }
        }
    }
}

/// A notification as a card: app icon, sender or subject, the message, and how long ago. Click to open it.
struct AlertRow: View {
    let alert: Alert
    @ObservedObject var alerts: Alerts

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: alerts.icon(alert.app)).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(alert.title.isEmpty ? alerts.name(alert.app) : alert.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(Self.ago(alert.date)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                }
                Text([alert.subtitle, alert.body].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(alert.date > alerts.seenUntil ? 0.13 : 0.07)))
        .contentShape(Rectangle())
        .onTapGesture { alerts.open(alert) }
        .contextMenu {
            Button("Open") { alerts.open(alert) }
            Button("Dismiss") { alerts.dismiss(alert) }
            Divider()
            Button("Hide \(alerts.name(alert.app)) in Kilele") { alerts.toggleMute(alert.app) }
        }
        .help("\(alerts.name(alert.app)) · click to open, right-click to dismiss")
    }

    /// "now", "4m", "2h", "Mon".
    static func ago(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }
}

/// Which apps show in Kilele, and a shortcut to each app's macOS notification settings (to turn its banners off).
struct AlertAppsMenu: View {
    @ObservedObject var alerts: Alerts

    var body: some View {
        Menu {
            Section("Show in Kilele") {
                ForEach(alerts.apps, id: \.self) { app in
                    Button { alerts.toggleMute(app) } label: {
                        if alerts.isMuted(app) { Text(alerts.name(app)) } else { Label(alerts.name(app), systemImage: "checkmark") }
                    }
                }
            }
            Toggle("Replace macOS banners with the notch", isOn: $alerts.replaceBanners)
            Section("Hidden apps keep their macOS banners · settings per app") {
                ForEach(alerts.apps, id: \.self) { app in
                    Button("\(alerts.name(app)) settings…") { Alerts.openSystemSettings(for: app) }
                }
            }
        } label: {
            Label("Apps", systemImage: "app.badge").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Choose apps, or turn off their macOS banners")
    }
}

/// A new notification dropping down from the collapsed notch. Click to open it; it stays while the pointer is on it.
struct PeekView: View {
    let alert: Alert
    @ObservedObject var alerts: Alerts
    var close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: alerts.icon(alert.app)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title.isEmpty ? alerts.name(alert.app) : alert.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text([alert.subtitle, alert.body].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5)) }
                .buttonStyle(.plain).help("Hide")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 60)
        .contentShape(Rectangle())
        .onTapGesture { alerts.open(alert); close() }
    }
}

// MARK: Notes tab (Tsuzuri, focus, voice memos)

struct NotesTab: View {
    @ObservedObject var notes: Notes
    @ObservedObject var focus: FocusTimer
    @ObservedObject var memo: VoiceMemo

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(notes.target == .inbox ? "Capture to Inbox…" : "Add to today's journal…", text: Binding(get: { notes.draft }, set: { notes.draft = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
                    .onSubmit { notes.capture() }
                HStack(spacing: 6) {
                    Text("To").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    Chip(title: "Inbox", selected: notes.target == .inbox) { notes.target = .inbox }
                    Chip(title: "Today", selected: notes.target == .journal) { notes.target = .journal }
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button { memo.toggle() } label: {
                            Label(memo.recording ? Scrubber.time(context.date.timeIntervalSince(memo.startedAt ?? context.date)) : "Voice memo",
                                  systemImage: memo.recording ? "stop.circle.fill" : "mic.circle")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(memo.recording ? .red : .white.opacity(0.8))
                        }
                        .buttonStyle(.plain).help(memo.recording ? "Stop and file the memo" : "Record a voice memo into your notes")
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        if focus.running {
                            Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(.orange)
                            Text(FocusTimer.clock(focus.remaining(at: context.date)) + (focus.label.isEmpty ? "" : " · \(focus.label)"))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit()).lineLimit(1)
                            Spacer()
                            Chip(title: "Stop", selected: false) { focus.stop() }
                        } else {
                            Text("Focus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                            ForEach([25, 50, 90], id: \.self) { minutes in
                                Chip(title: "\(minutes)m", selected: false) {
                                    focus.start(minutes: minutes, label: notes.draft.trimmingCharacters(in: .whitespaces))
                                    notes.draft = ""
                                }
                                .help("Start a \(minutes)-minute focus session (the text above becomes its label); it's logged in today's journal")
                            }
                            Spacer()
                        }
                    }
                }
                HStack(spacing: 6) {
                    Pill(title: "Today", symbol: "calendar") { notes.openTsuzuri("today") }
                    Pill(title: "Home", symbol: "house") { notes.openTsuzuri() }
                    Pill(title: "Inbox", symbol: "tray") { notes.openTsuzuri("Inbox") }
                }
                Text(memo.denied ? "Microphone access is off (System Settings › Privacy & Security)." : notes.status)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .frame(width: 330, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DUE TODAY").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    if notes.todos.isEmpty {
                        Text("Nothing due. Add @\(Self.today) to a to-do to see it here.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(notes.todos) { todo in
                        HStack(spacing: 8) {
                            Button { notes.tick(todo) } label: { Image(systemName: "circle").font(.system(size: 11)) }.buttonStyle(.plain)
                            Text(todo.text).font(.system(size: 12)).lineLimit(1)
                                .foregroundStyle(todo.due.map { $0 < Calendar.current.startOfDay(for: Date()) } == true ? Color.orange : .white)
                            Spacer(minLength: 6)
                            Button(todo.note) { notes.openTsuzuri(todo.note) }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }
                    }
                    if !notes.inProgress.isEmpty {
                        Text("IN PROGRESS").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45)).padding(.top, 6)
                        ForEach(notes.inProgress) { card in
                            Button { notes.openTsuzuri(card.note ?? "Tasks") } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.stack").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                                    Text(card.title).font(.system(size: 12)).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}

struct Chip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(selected ? 0.3 : 0.1)))
        }
        .buttonStyle(.plain)
    }
}

struct Pill: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Shelf tab

struct ShelfTab: View {
    @ObservedObject var shelf: Shelf
    @ObservedObject var notes: Notes
    @ObservedObject var autoShelf: AutoShelf
    var dropping: Bool

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(dropping ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay(Label(autoShelf.downloading ? "Downloading… it'll land here" : "Drop files here to keep them handy", systemImage: "tray.and.arrow.down").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(shelf.items) { item in ShelfTile(shelf: shelf, notes: notes, item: item) }
                        }
                    }
                    Button("Clear") { shelf.clear() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                Text(autoShelf.downloading ? "Downloading… it'll land on the shelf when it's done." : notes.status)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
        }
    }
}

struct ShelfTile: View {
    @ObservedObject var shelf: Shelf
    var notes: Notes
    var item: Shelf.Item

    private var hovering: Bool { shelf.hovered == item.id }
    private func remove() { shelf.remove(item) }
    private func airDrop() { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.url]) }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 46, height: 46)
            Text(item.url.lastPathComponent).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(width: 76)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) { Image(systemName: "xmark.circle.fill").font(.system(size: 13)) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
            }
        }
        .overlay(alignment: .topLeading) {
            if hovering && notes.available {
                Button { notes.attach(item.url) } label: { Image(systemName: "note.text.badge.plus").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Add to notes (copied into notes/assets, linked in Inbox or today's journal)")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                Button(action: airDrop) { Image(systemName: "square.and.arrow.up.circle.fill").font(.system(size: 13)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("AirDrop")
                    .offset(y: -18)
            }
        }
        .onHover { inside in if inside { shelf.hovered = item.id } else if hovering { shelf.hovered = nil } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("AirDrop…", action: airDrop)
            if notes.available { Button("Add to notes") { notes.attach(item.url) } }
            Divider()
            Button("Remove from shelf", action: remove)
        }
        .help(item.url.path)
    }
}
