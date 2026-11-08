# Kilele

A free, native macOS app for the MacBook notch. Kilele (Swahili for "peak") is written from scratch in SwiftUI.

- **Pill**: the notch extends either side with quick icons: shelf, quick note, play/pause and your next event.
- **Now playing**: anything playing on the Mac (browsers, Music, Spotify) with artwork and controls, through the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3).
- **Shelf**: drop files on the notch, drag them out later.
- **Calendar and reminders**: next events, and reminders due today you can tick off.
- **Notices**: volume, battery and Bluetooth devices.
- **Tsuzuri notes**: quick capture to Inbox, to-dos due today, Tasks in progress, open notes in Tsuzuri.

## Build

Needs macOS 14+, the Xcode command-line tools and cmake (no Xcode).

```sh
scripts/build-adapter.sh           # once: builds the bundled mediaremote-adapter
scripts/make-signing-identity.sh   # once, optional: stable signature so permissions aren't asked again on rebuild
scripts/build.sh --install         # builds Kilele.app, copies it to /Applications and opens it
```

See AGENTS.md for how it works.

## Licence

MIT (see LICENSE). The bundled mediaremote-adapter keeps its own BSD-3 licence (`Vendor/mediaremote-adapter/LICENSE`).
