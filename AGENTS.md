# Kilele

A free, native macOS notch app written from scratch (2026-10-26) after Notchy went paid. "Kilele" is a working name (Swahili for "peak"). No code, assets or name from Notchy; nothing reverse-engineered.

## Build and run

- `./scripts/build.sh` builds `build/Kilele.app` (ad-hoc signed). `./scripts/build.sh --install` also copies it to `/Applications` and opens it.
- Built with the command-line tools only (Swift 6.4, macOS 27 SDK), no Xcode. In this SDK SwiftUI's `@State` is a macro whose plugin ships only with Xcode, so **don't use `@State`** (or other SwiftUI macros): keep view state in the `ObservableObject` models (`NotchModel.dropping`, `NotchModel.openAtLogin`, `Shelf.hovered`).
- Language mode Swift 5 (tools 5.9). Models aren't `@MainActor`; they're updated on the main queue via GCD.
- Rebuilding changes the ad-hoc signature, so macOS may ask again for Calendar, Reminders and Automation access.
- Quit Notchy before running Kilele, otherwise the two overlap in the notch.

## How it works

- `NotchController.swift`: a borderless, non-activating `NSPanel` above the menu bar (`.mainMenu + 3`, on all Spaces and over full-screen apps), the size of the expanded notch and centred at the top of the notched screen (or the main screen). The notch size comes from `safeAreaInsets.top` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. While collapsed the panel ignores the mouse, so clicks pass through. Global and local monitors for mouse moved, dragged and up decide when to expand (0.12 s hover, or 0.05 s when dragging files) and collapse (0.35 s after leaving; never while a mouse button is held or a menu is open).
- `NotchView.swift`: the black shape (rounded bottom corners) sized collapsed, collapsed with wings (music artwork and equaliser, or a notice), or expanded with the **Now** tab (now playing plus agenda) and **Shelf** tab, and a settings menu (Open at login via `SMAppService`, show music beside the notch, Quit).
- `NowPlaying.swift`: follows Music and Spotify through their public distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`), so no permission is needed to see what's playing. Artwork and play/pause/next/previous use AppleScript (Automation permission, asked once per app). At launch it asks only players that are already running, so none get launched. Browser audio isn't covered yet; the open-source mediaremote-adapter (github.com/ungive/mediaremote-adapter, BSD-3) would add it.
- `Shelf.swift`: dropped files are kept as bookmarks in UserDefaults; drag tiles back out, double-click to open, right-click for Show in Finder or Remove.
- `Agenda.swift`: EventKit full access (asked the first time the notch opens), the next 4 events today or tomorrow (including one under way), and up to 4 reminders due by the end of today, which can be ticked off.
- `HUD.swift`: volume and mute (CoreAudio virtual main volume, following the default output device), power (IOKit power-source notifications: plug/unplug, dropping to 20% or 10%), and Bluetooth connect/disconnect (IOBluetooth; devices already connected in the first 3 s are ignored). macOS still shows its own volume pop-up; brightness isn't shown (it needs a private API).

## Wider notch (2026-10-26)

- Expanded size is `max(720, notch + 540)` wide (760 on the user's 1800-wide screen) by notch + 170 tall, at the user's request ("wider, like Notchy"). The now-playing card is 300 wide.

## Tsuzuri link (2026-10-26)

- `Notes.swift` connects Kilele to the user's Tsuzuri workspace, `~/Documents/notes` (override with `KILELE_NOTES` for testing). The **Notes** tab appears only if `Inbox.md` exists there. Reading or writing it makes macOS ask once for access to Documents.
- **Capture:** the field plus Enter adds `- text` to Inbox.md, filling the empty `- ` bullet Inbox keeps, otherwise going after the last item.
- **Due today:** unticked `- [ ]` to-dos with an `@YYYY-MM-DD` of today or earlier (overdue shown in orange), from every note except Templates, skipping fenced code; this matches Tsuzuri's `core.todoRe` and due dates. Ticking re-reads the note and finds the same unticked text, even if the line moved (e.g. after a phone sync), before writing `[x]`; if it's gone, nothing is written.
- **In progress:** cards under `## In progress` in the ```board block of Tasks.md, each opening its first `[[link]]` (or Tasks).
- **Shelf into notes:** hover button or right-click "Add to notes" copies the file into `notes/assets/` (`name-2.ext` on a clash) and adds a link to Inbox in Tsuzuri's own format (`![stem](…)` for images, `[▶ stem](…)` video, `[♪ stem](…)` audio, `[📎 file](…)` otherwise; target in `<…>` when it has spaces or parentheses). Files over 25 MB are refused, since notes sync to the phone through GitHub.
- **Open in Tsuzuri:** Today, Home and Inbox buttons, and each to-do's note name, open a new iTerm window (Terminal if iTerm is missing) and type `tsuzuri …` into the user's shell, so `~/bin` and `TSUZURI_WORKSPACE` from .zshrc apply. Needs Automation permission for iTerm.
- **Sync:** after any write, `~/bin/notes-sync <root>` runs 15 s after the last change, with Homebrew and ~/bin on PATH.
- Collapsing the notch calls `panel.resignKey()`, so the capture field never keeps the keyboard once the notch folds away.
- Tested with a compiled harness against a copy of the notes (no .git, no Private): due-today selection, In progress cards, ticking, Inbox capture, and attaching with name clashes all matched Tsuzuri's formats.

## Pill mode (2026-10-26)

- On by default (`NotchModel.pillMode`, gear menu "Pill mode (icons beside the notch)"). Collapsed, the black extends 84 pt either side of the notch with quick-access icons: left Shelf (badge = items) and quick note (opens Notes with the cursor in the Inbox box; only once the notes folder is reachable); right music (play/pause when a player is loaded, bouncing bars while it plays, otherwise opens Now) and the next timed event today as `HH:mm` (otherwise a calendar icon; opens Now). Notices (volume, battery, Bluetooth) take over the wings for 1.8 s as before. With pill mode off, music wings work as before ("Show music beside the notch").
- Hover: in pill mode only the notch itself (±4 pt) opens the panel; over the wings the panel takes clicks (`ignoresMouseEvents` toggled by pointer position) without expanding. Dragging files over any part opens the Shelf. A 10 Hz timer also calls `track`, because mouse-moved events don't reliably reach a non-key panel; a held mouse button counts as dragging, so dragging windows past the notch doesn't open it.
- `FirstClickHostingView` accepts the first mouse click, so pill icons work on a single click on the never-active panel.
- `Agenda.startIfAllowed()` loads events at launch only if Calendar access was already granted (no prompt at launch), and reloads every 5 minutes, so the pill's next-event time stays current.

## Lessons (2026-10-26)

- **Never call something that can wait on a privacy prompt on the main thread.** `IOBluetoothDevice.register(forConnectNotifications:)` blocks on a semaphore until the Bluetooth prompt is answered, which left the notch blank (no window). It now runs on its own thread with a run loop, and callbacks hop to main. Likewise the first check of `~/Documents/notes` runs on the notes queue (`Notes.available` is published), and `reload()` re-checks it each time the notch opens, so allowing Documents access later just works.
- From the terminal, prompts are attributed to the terminal, which already has access, so such hangs only show when launched normally (`open` / Finder / login). Test with `./scripts/build.sh --install`, and use `sample Kilele 1` to see where the main thread is stuck.
- `withExtendedLifetime(delegate) { app.run() }`: NSApplication holds its delegate weakly.
- Every ad-hoc build is a new signature, so macOS asks again for Bluetooth, Calendar, Reminders, Documents and Automation. `scripts/make-signing-identity.sh` (run once by the user: Claude is blocked from changing the keychain) creates a self-signed "Kilele Local Signing" code-signing identity in the login keychain (not trusted; codesign allowed via `-T`). `build.sh` signs with it when present, otherwise ad-hoc, so permissions are asked once more after switching and then remembered.

## Browser and system-wide now playing (2026-10-26)

- Uses **mediaremote-adapter** v0.7.7 (github.com/ungive/mediaremote-adapter, BSD-3-Clause, commit e3ff502), downloaded with the user's OK and vendored in `Vendor/mediaremote-adapter` (no .git). Source reviewed: no network access or file writes; it launches a process only in its `test` command (its own test client). It's the same helper Notchy bundled, used as its README documents.
- `scripts/build-adapter.sh` builds it with cmake (Homebrew) and runs its `test`. `scripts/build.sh` then bundles `MediaRemoteAdapter.framework`, `mediaremote-adapter.pl` and its `LICENSE` (required by BSD-3) into `Contents/Resources/MediaRemoteAdapter/`, signing the framework ad-hoc before the app. Without the build, Kilele is Music/Spotify only.
- `MediaRemoteAdapter.swift`: runs `/usr/bin/perl mediaremote-adapter.pl <framework> stream --debounce=150` (only Apple's own binaries may read system Now Playing since macOS 15.4, hence perl). It parses one JSON line per change (`{type, diff, payload}`; diffs merge into the last full payload, `null` removes a key), decodes `artworkData` (base64) only when it changes, and names the source from `parentApplicationBundleIdentifier` (the browser for web players) or `bundleIdentifier`. Controls: `send 2` play/pause, `send 4` next, `send 5` previous. If the stream dies after working, it restarts (2 s, up to 5 times); if it never produced output, `NowPlaying` falls back to the Music/Spotify notifications plus AppleScript. The perl process is terminated on quit.
- `NowPlaying` now exposes `hasMedia` and `source` (app name), which the views use instead of `player`.
- Status: the user ran `scripts/build-adapter.sh` (self-test passed on macOS 27) and `build.sh --install` on 2026-10-26. Verified: the bundled perl `stream` runs under Kilele, and the pill's music icon picked up paused media (▶) that the Music/Spotify-only version couldn't see. Claude can't run the adapter build itself without a permission rule (downloaded code).

## Repository

- GitHub: `Kimina-Santuri/kilele` (private), branch `main`. The vendored adapter keeps its LICENSE; its build output is gitignored.
