import AppKit
import SwiftUI
import Testing

@testable import Tray

/// Renders the tray in each of its states to PNGs so the visual design can be
/// judged by eye rather than by reading numbers (§70 — "automated screenshot
/// tests are optional"; §84's build-run-look-fix loop needs *something* to
/// look at).
///
/// Off unless asked for, because it writes files:
///
///     ./Scripts/test.sh --previews
///
/// Rendered through a real `NSHostingView` in an offscreen window rather than
/// through `ImageRenderer`, which silently substitutes a placeholder for
/// `Image(nsImage:)` and skips `ScrollView` contents — it would have shown a
/// shelf full of yellow "prohibited" tiles for a tray that draws file icons
/// perfectly well.
///
/// One caveat remains: `.ultraThinMaterial` samples the window server's
/// backdrop, which an offscreen window has none of, so translucency renders as
/// its opaque fallback. Layout, type, icons, contrast and proportion are
/// faithful; the exact vibrancy has to be confirmed on screen.
@MainActor
struct TrayAppearanceTests {
    /// `nonisolated` because the trait is evaluated outside the test's
    /// isolation, before it runs.
    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TRAY_RENDER_PREVIEWS"] == "1"
    }

    private let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("build/previews")

    @Test(.enabled(if: TrayAppearanceTests.isEnabled))
    func `render every tray state`() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let notchless = ScreenGeometry(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: nil,
            topInset: 0,
            menuBarHeight: 24
        )

        // The development Mac: an M2 Air reporting safeAreaInsets.top == 32 (§8).
        let notched = ScreenGeometry(
            id: 2,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: CGSize(width: 200, height: 32),
            topInset: 32,
            menuBarHeight: 32
        )

        try render("01-collapsed-empty", geometry: notchless, items: 0, state: .collapsed)
        try render("02-collapsed-with-items", geometry: notchless, items: 3, state: .collapsed)
        try render("03-collapsed-notched", geometry: notched, items: 3, state: .collapsed)
        try render("04-expanded-empty", geometry: notchless, items: 0, state: .expanded)
        try render("05-drop-target", geometry: notchless, items: 0, state: .dragOver)
        try render("06-expanded-four", geometry: notchless, items: 4, state: .expanded)
        try render("07-expanded-many", geometry: notchless, items: 12, state: .expanded)
        try render("08-expanded-notched", geometry: notched, items: 4, state: .expanded)

        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count >= 8)
    }

    /// The images the README shows.
    ///
    /// Rendered through the same path as everything else, so they are the real
    /// interface rather than a mockup — composited over a backdrop instead of
    /// over a desktop, which is the one thing about them that is not literal.
    @Test(.enabled(if: TrayAppearanceTests.isEnabled))
    func `render the readme images`() throws {
        let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets/readme")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let screen = ScreenGeometry(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            notchSize: CGSize(width: 179, height: 32),
            topInset: 32,
            menuBarHeight: 32
        )

        try renderAsset("shelf", into: assets, geometry: screen, items: 5, state: .expanded)
        try renderAsset("closed", into: assets, geometry: screen, items: 3, state: .collapsed)
        try renderAsset("drop", into: assets, geometry: screen, items: 0, state: .dragOver)
    }

    private func renderAsset(
        _ name: String,
        into directory: URL,
        geometry: ScreenGeometry,
        items: Int,
        state: TrayPresentationState
    ) throws {
        let store = TrayStore()
        store.add(Self.sampleURLs(count: items))

        let presenter = TrayPresenter()
        switch state {
        case .collapsed: presenter.collapseNow()
        case .expanded: presenter.open()
        case .dragOver: presenter.dragEntered()
        case .draggingItem: break
        }

        let view = TrayContentView(
            store: store,
            presenter: presenter,
            thumbnails: ThumbnailProvider(),
            settings: SettingsStore(defaults: Self.emptyDefaults()),
            geometry: geometry,
            onRemove: { _ in }, onReveal: { _ in }, onQuickLook: { _ in },
            onItemDragBegan: { _ in }, onItemDragEnded: { _, _ in },
            onShapeChange: { _ in }
        )
        .background(Self.wallpaper)

        guard let png = Self.rasterize(view, size: CGSize(width: 900, height: 220)) else {
            Issue.record("could not render \(name)")
            return
        }
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    // MARK: - Machinery

    private func render(
        _ name: String,
        geometry: ScreenGeometry,
        items: Int,
        state: TrayPresentationState
    ) throws {
        let store = TrayStore()
        store.add(Self.sampleURLs(count: items))

        let presenter = TrayPresenter()
        switch state {
        case .collapsed: presenter.collapseNow()
        case .expanded: presenter.open()
        case .dragOver: presenter.dragEntered()
        case .draggingItem: break
        }

        let view = TrayContentView(
            store: store,
            presenter: presenter,
            thumbnails: ThumbnailProvider(),
            settings: SettingsStore(defaults: Self.emptyDefaults()),
            geometry: geometry,
            onRemove: { _ in }, onReveal: { _ in }, onQuickLook: { _ in },
            onItemDragBegan: { _ in }, onItemDragEnded: { _, _ in },
            onShapeChange: { _ in }
        )
        // A busy, bright backdrop is the hard case: it is where a dark surface
        // with no border disappears, and where the edge highlight earns its
        // keep (§48, §49).
        .background(Self.wallpaper)

        guard let png = Self.rasterize(view, size: CGSize(width: 820, height: 160)) else {
            Issue.record("could not render \(name)")
            return
        }

        try png.write(to: output.appendingPathComponent("\(name).png"))
    }

    /// Draws a view the way the app draws it: hosted in a real window, then
    /// captured from the layer tree.
    private static func rasterize(_ view: some View, size: CGSize) -> Data? {
        let frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear

        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        window.contentView = hosting

        // Let SwiftUI lay out and the icons resolve before the snapshot.
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: frame)
        else { return nil }
        representation.size = size
        hosting.cacheDisplay(in: frame, to: representation)

        return representation.representation(using: .png, properties: [:])
    }

    private static var wallpaper: some View {
        LinearGradient(
            colors: [
                Color(red: 0.36, green: 0.62, blue: 0.86),
                Color(red: 0.93, green: 0.90, blue: 0.83),
                Color(red: 0.85, green: 0.45, blue: 0.36),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Real files, so thumbnails and icons are the ones the tray would actually
    /// show. `/System/Applications` is present on every Mac.
    private static func sampleURLs(count: Int) -> [URL] {
        guard count > 0 else { return [] }
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/System/Applications"),
            includingPropertiesForKeys: nil
        )) ?? []
        return Array(candidates.prefix(count))
    }

    private static func emptyDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TrayPreviews-\(UUID().uuidString)") ?? .standard
    }
}
