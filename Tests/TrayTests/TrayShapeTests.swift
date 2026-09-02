import CoreGraphics
import Foundation
import Testing

@testable import Tray

/// The shelf's geometry: how wide it opens, how it clears the notch, and where
/// its corners flare (§8, §20).
@MainActor
struct TrayShapeTests {
    private let screenWidth: CGFloat = 1470
    private let notchHeight: CGFloat = 32

    // MARK: - Width

    @Test func `the shelf opens to its share of the screen`() {
        let shape = TrayShape.expanded(
            screenWidth: screenWidth,
            widthFraction: 0.32,
            notchHeight: 0
        )

        #expect(shape.width == screenWidth * 0.32)
    }

    @Test func `a wider setting gives a wider shelf`() {
        let narrow = TrayShape.expanded(screenWidth: screenWidth, widthFraction: 0.2, notchHeight: 0)
        let wide = TrayShape.expanded(screenWidth: screenWidth, widthFraction: 0.8, notchHeight: 0)

        #expect(wide.width > narrow.width)
    }

    @Test func `the shelf never spans the whole display`() {
        // It has to read as an object on the screen rather than as a second
        // menu bar (§20).
        let shape = TrayShape.expanded(
            screenWidth: screenWidth,
            widthFraction: SettingsStore.widthFractionRange.upperBound,
            notchHeight: 0
        )

        #expect(shape.width < screenWidth)
    }

    @Test func `a tiny share still leaves a usable shelf`() {
        let shape = TrayShape.expanded(screenWidth: 400, widthFraction: 0.05, notchHeight: 0)

        #expect(shape.width >= TrayMetrics.minimumWidth)
    }

    @Test func `the same share is proportional on any display`() {
        let laptop = TrayShape.expanded(screenWidth: 1470, widthFraction: 0.4, notchHeight: 0)
        let bigScreen = TrayShape.expanded(screenWidth: 5120, widthFraction: 0.4, notchHeight: 0)

        #expect(bigScreen.width > laptop.width)
        #expect(abs(bigScreen.width / 5120 - laptop.width / 1470) < 0.001)
    }

    // MARK: - Notch clearance

    @Test func `a notched display gets its contents pushed clear of the housing`() {
        // Nothing drawn under the notch is visible; it is a hole in the display.
        let shape = TrayShape.expanded(
            screenWidth: screenWidth,
            widthFraction: 0.32,
            notchHeight: notchHeight
        )

        #expect(shape.notchInset == notchHeight)
        #expect(shape.height == TrayMetrics.expandedHeight + notchHeight)
    }

    @Test func `a display without a notch loses no height to one`() {
        let shape = TrayShape.expanded(
            screenWidth: screenWidth,
            widthFraction: 0.32,
            notchHeight: 0
        )

        #expect(shape.notchInset == 0)
        #expect(shape.height == TrayMetrics.expandedHeight)
    }

    // MARK: - Flare

    @Test func `the open shelf flares where it meets the top of the screen`() {
        let shape = TrayShape.expanded(screenWidth: screenWidth, widthFraction: 0.32, notchHeight: 0)

        #expect(shape.topFlare > 0)
    }

    @Test func `the closed tray has no flare`() {
        // Closed on a notched Mac, the tray *is* the camera housing, and the
        // housing has no flare — anything extra would show beside it.
        let onNotch = TrayShape.collapsed(
            notchSize: CGSize(width: 179, height: notchHeight),
            isEmpty: false
        )
        let onPlainScreen = TrayShape.collapsed(notchSize: nil, isEmpty: false)
        let handle = TrayShape.collapsed(notchSize: nil, isEmpty: true)

        #expect(onNotch.topFlare == 0)
        #expect(onPlainScreen.topFlare == 0)
        #expect(handle.topFlare == 0)
    }

    @Test func `the closed tray on a notched Mac matches the housing exactly`() {
        let notch = CGSize(width: 179, height: notchHeight)
        let shape = TrayShape.collapsed(notchSize: notch, isEmpty: false)

        #expect(shape.width == notch.width)
        #expect(shape.height == notch.height)
    }

    // MARK: - Scrolling

    @Test func `items scroll once they outgrow the chosen width`() {
        #expect(TrayShape.fits(itemCount: 3, screenWidth: screenWidth, widthFraction: 0.32))
        #expect(!TrayShape.fits(itemCount: 40, screenWidth: screenWidth, widthFraction: 0.32))
    }

    @Test func `a wider shelf fits more before it scrolls`() {
        #expect(!TrayShape.fits(itemCount: 12, screenWidth: screenWidth, widthFraction: 0.2))
        #expect(TrayShape.fits(itemCount: 12, screenWidth: screenWidth, widthFraction: 0.8))
    }

    // MARK: - Settings

    @Test func `width and outline settings survive a relaunch`() {
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!

        let first = SettingsStore(defaults: defaults)
        #expect(first.showsDropOutline == false)
        first.trayWidthFraction = 0.6
        first.showsDropOutline = true

        let second = SettingsStore(defaults: defaults)
        #expect(second.trayWidthFraction == 0.6)
        #expect(second.showsDropOutline)
    }

    @Test func `a stored width outside the range is clamped on the way in`() {
        // An older build, or a hand-edited plist, must not produce a shelf
        // wider than the display.
        let defaults = UserDefaults(suiteName: "TrayTests-\(UUID().uuidString)")!
        defaults.set(4.0, forKey: "trayWidthFraction")

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.trayWidthFraction == SettingsStore.widthFractionRange.upperBound)
    }
}

/// Settings must only ever record a *choice*.
@MainActor
struct SettingsPersistenceTests {
    /// Runs `body` against a settings store backed by a throwaway domain, then
    /// hands back whatever that domain actually contains on disk.
    private func writtenKeys(
        _ body: (SettingsStore) -> Void
    ) -> [String] {
        let name = "TrayTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        body(SettingsStore(defaults: defaults))

        return (defaults.persistentDomain(forName: name) ?? [:]).keys.sorted()
    }

    @Test func `reading every setting writes nothing`() {
        // Opening the settings window reads all of these. If reading persisted
        // them, a fresh install would immediately claim a full set of
        // preferences the user never chose.
        let written = writtenKeys { settings in
            _ = settings.appearance
            _ = settings.trayWidthFraction
            _ = settings.showsDropOutline
            _ = settings.staysOpenAfterClick
            _ = settings.autoCollapseDelay
            _ = settings.showsFileNames
            _ = settings.showsMenuBarIcon
            _ = settings.activation
            _ = settings.launchAtLoginIntent
        }

        #expect(written.isEmpty)
    }

    @Test func `assigning a value that has not changed writes nothing`() {
        // This is the real one. SwiftUI's `Binding(get:set:)` setters fire
        // during view updates, not only on user input, so every control on the
        // page assigns its current value back on layout. A slider does it with
        // a clamped value, which is how a setting nobody touched ends up
        // pinned to the end of its range.
        let written = writtenKeys { settings in
            settings.appearance = settings.appearance
            settings.trayWidthFraction = settings.trayWidthFraction
            settings.showsDropOutline = settings.showsDropOutline
            settings.staysOpenAfterClick = settings.staysOpenAfterClick
            settings.autoCollapseDelay = settings.autoCollapseDelay
            settings.showsFileNames = settings.showsFileNames
            settings.activation = settings.activation
        }

        #expect(written.isEmpty)
    }

    @Test func `an actual change is written`() {
        let written = writtenKeys { settings in
            settings.appearance = .black
            settings.trayWidthFraction = 0.5
        }

        #expect(written == ["appearance", "trayWidthFraction"])
    }
}
