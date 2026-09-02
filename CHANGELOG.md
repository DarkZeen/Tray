# Changelog

All notable changes to Tray are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- *Open after a drop*, which decides whether the shelf stays up for a moment to
  show what landed or closes as soon as the drop is done.
- A slider for how far inside the tray's edge the dashed drop outline sits.
- A new app icon and menu bar glyph: something living in the tray, peering out.
  Two shapes and nothing else, with the corner radii uneven on every corner and
  the eyes deliberately mismatched, which is the difference between a creature
  and a rounded rectangle with dots on it.
- *Icon size*, which sets how large each file is drawn on the shelf. Thumbnails
  are re-rendered at the chosen size rather than scaled up, and the shelf grows
  to fit them.
- *Height*, which sets how tall the open shelf is. It is a floor rather than a
  fixed size: icons large enough to need more room still get it, because a
  shelf shorter than what it is holding would clip it.
- *Width*, which sets how much of the screen the open shelf spans. Stored as a
  share of the display rather than a number of points, so one setting means the
  same thing on a laptop screen and a 5K display.
- *Outline the drop area*, a dashed border marking where a dropped file will
  land. Rounded on all four corners, faint enough to stay a hint rather than a
  frame, and starting below the camera housing so the whole border is visible.
- Three surfaces, chosen in Settings. Graphite is the default; Light flips the
  ink so it stays legible; Pitch black is fully opaque and the same black as
  the camera housing, so on a notched Mac the shelf reads as the notch growing
  rather than as something hanging below it.
- *Stay open after a click*, which turns off the rule that a tray you have
  clicked into waits to be dismissed. With it off, the pointer leaving always
  closes the shelf.
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

- The shelf closes faster than it opens. Closing used to be the slowest motion
  in the app, sitting on the exit of the most-seen element — which was fine
  when a grace period ran before it, and reads as lag now that it starts the
  moment the pointer leaves.
- Items arrive from below rather than growing from nothing in place, and at a
  gentler scale. Files travel upward into the tray, so that is the direction an
  arriving one comes from.
- The open shelf's walls flare outwards where they meet the top edge of the
  screen, instead of stopping at a square corner. The closed tray keeps its
  square silhouette, because on a notched Mac it *is* the camera housing and
  has to match it exactly.
- The shelf now closes as the pointer leaves rather than after a grace period.
  *Close after* in Settings still goes up to three seconds for anyone who wants
  the old behaviour, and a tray you have clicked into stays open regardless —
  otherwise reaching for the keyboard would close it.

### Fixed

- Reduce Motion had no effect until the app was relaunched. The preference was
  read straight from `NSWorkspace` inside view bodies, so nothing invalidated
  when it changed. It now travels through the environment, the way the
  reduced-transparency preference already did.
- The tray gave no feedback at all until a drag was directly over the drop
  area. The anticipation step had a value defined for it and no call site.
- A drop landed with no acknowledgement. The shelf now gives a little as
  something lands and springs back — two values and an underdamped spring
  rather than three hand-written keyframes.
- The shelf could stick open after the pointer left. Two separate causes, both
  of which stopped anything from ever telling the tray the pointer had gone.
  The hover tracking area was sized to the tray and rebuilt every time the tray
  changed shape; a rebuild makes AppKit re-emit enter and exit events that
  match no pointer movement, and once an *enter* was missed that way the
  matching exit never arrived either. The tracking area is now constant and
  where the pointer is gets decided from its actual position. Separately, a
  drag session that ended without a `draggingExited` — cancelled with Escape,
  or finished elsewhere — left the tray believing a drag was still overhead,
  and a tray that thinks a drag is overhead refuses to close.
- Settings recorded preferences nobody chose. SwiftUI's binding setters fire
  during view updates as well as on input, so merely opening the settings
  window wrote every value on the page to disk — and a slider wrote a *clamped*
  value, which is how a setting nobody touched ended up pinned to the end of
  its range. Every write is now guarded on the value actually changing.
- The open shelf's contents sat under the camera housing on a notched Mac,
  where nothing is visible, cutting the top off every thumbnail in the middle
  of the shelf.
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
