import AppKit
import SwiftUI

/// One display's tray: the panel, the mouse layer, and the SwiftUI content,
/// wired together (§11, §27).
///
/// The panel's frame never changes. It is created large enough to hold the
/// shelf at its widest and stays that way; the tray animates *inside* it. That
/// keeps window-server geometry out of the animation loop entirely, which is
/// what §16 is really asking for, and it means the hit regions the user is
/// aiming at never move out from under them mid-gesture (§74).
@MainActor
final class TrayWindowController {
    let geometry: ScreenGeometry
    let presenter = TrayPresenter()

    private let store: TrayStore
    private let thumbnails: ThumbnailProvider
    private let settings: SettingsStore
    private let dropHandler: FileDropHandler

    private let panel: TrayPanel
    private let dropView: TrayDropView
    private var hostingView: NSHostingView<AnyView>!

    private let logger = Diagnostics.logger("tray-window")

    /// Raised so the app can put a preview on screen without the tray needing
    /// to know what Quick Look is.
    var onQuickLookRequest: ((TrayItem) -> Void)?

    init(
        geometry: ScreenGeometry,
        store: TrayStore,
        thumbnails: ThumbnailProvider,
        settings: SettingsStore
    ) {
        self.geometry = geometry
        self.store = store
        self.thumbnails = thumbnails
        self.settings = settings
        self.dropHandler = FileDropHandler(store: store)

        let frame = Self.panelFrame(for: geometry)
        self.panel = TrayPanel(contentRect: frame)
        self.dropView = TrayDropView(frame: NSRect(origin: .zero, size: frame.size))

        configureContent()
        configureMouseHandling()

        // Notch geometry is nearly impossible to reason about and trivial to
        // check, so the numbers this display actually produced go in the log
        // (§8, §71).
        logger.notice(
            """
            Tray on display \(geometry.id, privacy: .public): \
            screen \(geometry.frame.debugDescription, privacy: .public), \
            notch \(geometry.notchSize?.debugDescription ?? "none", privacy: .public), \
            safeArea.top \(geometry.topInset, privacy: .public), \
            menuBar \(geometry.menuBarHeight, privacy: .public), \
            panel \(frame.debugDescription, privacy: .public)
            """
        )

        panel.contentView = dropView
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
    }

    // MARK: - Geometry

    /// The window is the largest the tray can ever be, plus room for its
    /// shadow, anchored to the top edge of this display (§9, §87).
    private static func panelFrame(for geometry: ScreenGeometry) -> NSRect {
        let width = TrayMetrics.maximumWidth(forScreenWidth: geometry.frame.width)
            + TrayMetrics.panelPadding * 2

        // The debug overlay hangs below the tray and would otherwise be clipped
        // by the window it lives in — a diagnostic you cannot read is not one.
        let height = TrayMetrics.expandedHeight
            + TrayMetrics.panelPadding
            + (Diagnostics.isDebugOverlayEnabled ? 140 : 0)

        return NSRect(
            x: geometry.anchorCenterX - width / 2,
            y: geometry.topEdgeY - height,
            width: width,
            height: height
        )
    }

    /// Re-reads this display's geometry after the arrangement changed (§11).
    func reposition(to geometry: ScreenGeometry) {
        let frame = Self.panelFrame(for: geometry)
        panel.setFrame(frame, display: true)
        dropView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.frame = dropView.bounds
    }

    func close() {
        panel.orderOut(nil)
    }

    // MARK: - Content

    private func configureContent() {
        let view = TrayContentView(
            store: store,
            presenter: presenter,
            thumbnails: thumbnails,
            settings: settings,
            geometry: geometry,
            onRemove: { [weak self] item in self?.remove(item) },
            onReveal: { item in
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            },
            onQuickLook: { [weak self] item in
                self?.onQuickLookRequest?(item)
            },
            onItemDragBegan: { [weak self] item in
                self?.presenter.beganDraggingItem(id: item.id)
            },
            onItemDragEnded: { [weak self] item, didLand in
                self?.finishItemDrag(item, didLand: didLand)
            },
            onShapeChange: { [weak self] shape in
                self?.updateHitRegions(for: shape)
            }
        )

        let root = AnyView(
            ZStack(alignment: .top) {
                view
                if Diagnostics.isDebugOverlayEnabled {
                    TrayDebugOverlay(presenter: presenter, store: store, geometry: geometry)
                }
            }
        )

        hostingView = NSHostingView(rootView: root)
        hostingView.frame = dropView.bounds
        hostingView.autoresizingMask = [.width, .height]
        // The window is mostly empty space; only the tray should ever paint.
        hostingView.layer?.backgroundColor = .clear
        dropView.addSubview(hostingView)
    }

    /// Keeps the interactive regions exactly on the visible pixels (§74).
    private func updateHitRegions(for shape: TrayShape) {
        let rect = CGRect(
            x: dropView.bounds.midX - shape.width / 2,
            y: dropView.bounds.maxY - shape.height,
            width: shape.width,
            height: shape.height
        )
        dropView.contentRect = rect
        dropView.isOpen = presenter.state.isOpen
    }

    // MARK: - Mouse and drags

    private func configureMouseHandling() {
        dropView.onPointerEnter = { [weak self] in
            guard let self, self.settings.activation.allowsHover else { return }
            self.presenter.pointerEntered()
        }

        dropView.onPointerExit = { [weak self] in
            self?.presenter.pointerExited()
        }

        dropView.canAcceptDrag = { [weak self] info in
            guard let self, self.settings.activation.allowsDrag else { return false }
            return self.dropHandler.canAccept(info)
        }

        dropView.onDragApproach = { [weak self] in
            self?.presenter.dragApproached()
        }

        dropView.onDragEnter = { [weak self] in
            self?.presenter.dragEntered()
        }

        dropView.onDragExit = { [weak self] in
            self?.presenter.dragExited()
        }

        dropView.performDrop = { [weak self] info in
            guard let self else { return false }
            return self.accept(info)
        }

        presenter.onStateChange = { [weak self] state in
            self?.dropView.isOpen = state.isOpen
        }
    }

    /// A drop stores references. It never copies, moves or modifies the
    /// original files (§3, §38).
    private func accept(_ info: any NSDraggingInfo) -> Bool {
        store.refreshAvailability()
        let landed = dropHandler.accept(info)
        presenter.dropCompleted()

        logger.debug("Drop accepted: \(landed.count, privacy: .public) new item(s).")
        // An all-duplicates drop is still a successful drop as far as the
        // source is concerned — the file the user aimed at is on the shelf.
        return true
    }

    private func finishItemDrag(_ item: TrayItem, didLand: Bool) {
        presenter.endedDraggingItem()

        // Landed somewhere: the item has done its job and leaves the shelf
        // (§22). Cancelled: it springs back, which is the absence of any
        // change here plus the scale animation unwinding.
        if didLand {
            store.remove(id: item.id)
            thumbnails.forget(item)
        }
    }

    private func remove(_ item: TrayItem) {
        store.remove(id: item.id)
        thumbnails.forget(item)
    }

    // MARK: - Commands

    func open() {
        store.refreshAvailability()
        presenter.open()
    }

    func collapse() {
        presenter.collapseNow()
    }

    func toggle() {
        if !presenter.state.isOpen { store.refreshAvailability() }
        presenter.toggle()
    }
}
