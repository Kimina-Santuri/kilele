import EventKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The black shape hanging from the notch. Collapsed it matches the notch (plus wings for music or a notice);
/// expanded it opens into a panel with the Now and Shelf tabs.
struct NotchRoot: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying

    var body: some View {
        let size = model.visibleSize(playing: player.isPlaying)
        let radius: CGFloat = model.expanded ? 24 : min(10, model.notchSize.height / 3)
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    Group {
                        if model.expanded {
                            ExpandedView(model: model, player: player, shelf: model.shelf, agenda: model.agenda)
                        } else {
                            CollapsedView(model: model, player: player)
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

// MARK: Collapsed

struct CollapsedView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var player: NowPlaying

    var body: some View {
        if model.hud == nil && model.pillMode {
            HStack(spacing: 0) {
                HStack(spacing: 14) {
                    PillIcon(symbol: "tray", badge: model.shelf.items.count, help: "Shelf") { model.open(.shelf, false) }
                    if model.notes.available { PillIcon(symbol: "square.and.pencil", help: "Quick note to Inbox") { model.open(.notes, true) } }
                }
                .frame(width: model.wingWidth, height: model.notchSize.height)
                Spacer(minLength: model.notchSize.width)
                HStack(spacing: 14) {
                    MusicPillIcon(player: player) { model.open(.now, false) }
                    NextEventIcon(agenda: model.agenda) { model.open(.now, false) }
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
    @ObservedObject var agenda: Agenda

    var body: some View {
        VStack(spacing: 0) {
            // The strip either side of the camera: tabs on the left, settings on the right.
            HStack(spacing: 6) {
                TabButton(title: "Now", selected: model.tab == .now) { model.tab = .now }
                if model.notes.available { TabButton(title: "Notes", selected: model.tab == .notes) { model.tab = .notes } }
                TabButton(title: shelf.items.isEmpty ? "Shelf" : "Shelf \(shelf.items.count)", selected: model.tab == .shelf) { model.tab = .shelf }
                Spacer(minLength: model.notchSize.width + 24)
                SettingsMenu(model: model)
            }
            .padding(.horizontal, 20)
            .frame(height: model.notchSize.height)

            Group {
                switch model.tab {
                case .now: NowTab(player: player, agenda: agenda)
                case .notes: NotesTab(notes: model.notes)
                case .shelf: ShelfTab(shelf: shelf, notes: model.notes, dropping: model.dropping)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
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
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0)))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsMenu: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        Menu {
            Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch {}
                model.openAtLogin = SMAppService.mainApp.status == .enabled
            }))
            Toggle("Pill mode (icons beside the notch)", isOn: $model.pillMode)
            Toggle("Show music beside the notch", isOn: $model.showMusicWings).disabled(model.pillMode)
            Divider()
            Button("Quit Kilele") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: Now tab

struct NowTab: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var agenda: Agenda

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            NowPlayingCard(player: player).frame(width: 300, alignment: .leading)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
            AgendaView(agenda: agenda)
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var player: NowPlaying

    var body: some View {
        if player.hasMedia {
            HStack(spacing: 12) {
                ArtworkView(image: player.artwork, size: 76, corner: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    HStack(spacing: 18) {
                        control("backward.fill", player.previous)
                        control(player.isPlaying ? "pause.fill" : "play.fill", player.playPause)
                        control("forward.fill", player.next)
                    }
                    .padding(.top, 8)
                    if !player.source.isEmpty { Text(player.source).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)).padding(.top, 4) }
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

struct AgendaView: View {
    @ObservedObject var agenda: Agenda

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !agenda.calendarAllowed {
                Text("Calendar access is off").font(.system(size: 13, weight: .semibold))
                Text("Turn it on in System Settings › Privacy & Security › Calendars.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else if agenda.events.isEmpty && agenda.reminders.isEmpty {
                Text("Nothing else today").font(.system(size: 13, weight: .semibold))
                Text("Your next events and today's reminders show here.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(agenda.events, id: \.self) { event in
                    HStack(spacing: 8) {
                        Circle().fill(Color(cgColor: event.calendar.cgColor)).frame(width: 6, height: 6)
                        Text(when(event)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).frame(width: 64, alignment: .leading)
                        Text(event.title ?? "Event").font(.system(size: 12)).lineLimit(1)
                    }
                }
                ForEach(agenda.reminders, id: \.self) { reminder in
                    HStack(spacing: 8) {
                        Button { agenda.complete(reminder) } label: { Image(systemName: "circle").font(.system(size: 11)) }.buttonStyle(.plain)
                        Text(reminder.title ?? "Reminder").font(.system(size: 12)).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func when(_ event: EKEvent) -> String {
        if event.isAllDay { return "All day" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(event.startDate) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: event.startDate)
    }
}

// MARK: Shelf tab

struct ShelfTab: View {
    @ObservedObject var shelf: Shelf
    @ObservedObject var notes: Notes
    var dropping: Bool

    var body: some View {
        if shelf.items.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(dropping ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .overlay(Label("Drop files here to keep them handy", systemImage: "tray.and.arrow.down").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)))
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
                if notes.available && !notes.status.isEmpty {
                    Text(notes.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
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
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Add to notes (copied into notes/assets, linked in Inbox)")
            }
        }
        .onHover { inside in if inside { shelf.hovered = item.id } else if hovering { shelf.hovered = nil } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            if notes.available { Button("Add to notes") { notes.attach(item.url) } }
            Divider()
            Button("Remove from shelf", action: remove)
        }
        .help(item.url.path)
    }
}

// MARK: Notes tab (Tsuzuri)

struct NotesTab: View {
    @ObservedObject var notes: Notes

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Capture to Inbox…", text: Binding(get: { notes.draft }, set: { notes.draft = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
                    .onSubmit { notes.capture() }
                HStack(spacing: 6) {
                    Pill(title: "Today", symbol: "calendar") { notes.openTsuzuri("today") }
                    Pill(title: "Home", symbol: "house") { notes.openTsuzuri() }
                    Pill(title: "Inbox", symbol: "tray") { notes.openTsuzuri("Inbox") }
                }
                Text(notes.status.isEmpty ? "Press Enter to add it to Inbox. It syncs to your phone." : notes.status)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }
            .frame(width: 300, alignment: .leading)
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

// MARK: Pill icons

struct PillIcon: View {
    var symbol: String
    var badge = 0
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
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

/// Play/pause when a player is loaded (bouncing bars while it plays); otherwise opens the Now tab.
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

/// The next event's start time today (or a calendar icon), opening the Now tab.
struct NextEventIcon: View {
    @ObservedObject var agenda: Agenda
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if let next = agenda.events.first(where: { !$0.isAllDay && $0.startDate > Date() && Calendar.current.isDateInToday($0.startDate) }) {
                    Text(Self.time.string(from: next.startDate)).font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(systemName: "calendar").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help("Calendar")
    }

    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
}

