# Changelog

All notable changes to Tray are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Keyboard control of the shelf. Click an item to select it, then Delete to
  remove it, Space to Quick Look it, ⌘C to copy it and ⌘V to paste files in.
  ⌘-click selects several, ⌘A selects everything, the arrow keys walk along the
  shelf, and Escape closes it. Copying writes file URLs, so pasting into Finder
  or a Save dialog lands the file itself and the original never moves.
- Copy in the item's secondary-click menu, so ⌘C is discoverable.
- Opening Tray while it is already running opens Settings. An app with no Dock
  icon and no windows would otherwise appear to do nothing when opened.
- A settings window with sidebar navigation and four pages: General, Tray,
  Privacy and About. The Privacy page states, permission by permission, what
  Tray does not ask for — no Accessibility, no Screen Recording, no Full Disk
  Access, no camera or microphone, and no network at all.

### Changed

- The shelf now closes as the pointer leaves rather than after a grace period.
  *Close after* in Settings still goes up to three seconds for anyone who wants
  the old behaviour, and a tray you have clicked into stays open regardless —
  otherwise reaching for the keyboard would close it.

### Fixed

- The *Close after* setting had no effect at all. The presenter read a constant
  instead of the stored value, so the slider moved and nothing happened.
- Tray no longer records a Launch at Login preference the user never expressed.
  `SMAppService` reports the app as enabled on a fresh install, and startup
  reconciliation treated an absent preference as "off" — so it read that as the
  user having switched it on elsewhere, adopted it, and wrote it down. "Never
  asked" is now a distinct state from "asked for off".
- The tray's closed item indicator drew below the tray instead of inside it.
  The open shelf was setting the height of the layer stack, so the closed
  layer's alignment resolved against the wrong bounds.
- A tray opened from the menu bar never closed on its own, because nothing
  schedules a collapse when there is no pointer to leave.
- The tray could open when nothing had gone near it: rebuilding a tracking area
  makes AppKit fire enter and exit events that do not correspond to any pointer
  movement, and only the exit was being verified.

## [0.1.0]

First release. The scope is deliberately locked: a shelf at the top of the
screen that files go into and come back out of, and nothing else.

### Added

- A tray anchored to the top centre of the screen, measured from the display's
  own safe area rather than hardcoded, so notched MacBooks, external monitors
  and scaling changes all place it correctly.
- Drag files and folders in from anywhere, several at once. The tray keeps a
  reference; the originals are never moved, copied or modified.
- Drag items back out into Finder, Save dialogs, upload fields, or any other
  destination that accepts a file, as a real macOS drag session.
- File icons immediately, replaced by Quick Look thumbnails as they arrive.
- One tray per connected display, following monitors as they come and go.
- Secondary click for Remove from Tray, Reveal in Finder and Quick Look.
- A menu bar item with Open Tray, Launch at Login, Settings and Quit.
- Settings for activation (hover, drag, or both), auto-collapse delay, file
  names, the menu bar icon and Launch at Login.
- Launch at Login through `SMAppService`, with the three states that actually
  fail — read-only location, approval revoked in System Settings, unstable
  signature — detected and explained instead of silently ignored.
- Full-screen and Spaces support, without ever taking focus from the app in
  front.
- Reduced motion and reduced transparency support, VoiceOver labels, and a
  dark surface that holds up in both light and dark appearance.
- A signed, notarized disk image built by a GitHub Actions workflow, and a
  three-tier local signing ladder that needs no Apple Developer account.

[Unreleased]: https://github.com/DarkZeen/Tray/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DarkZeen/Tray/releases/tag/v0.1.0
