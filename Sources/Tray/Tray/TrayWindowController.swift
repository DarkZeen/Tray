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
    let selection = TraySelection()

    private let store: TrayStore
    private let thumbnails: ThumbnailProvider
    private let settings: SettingsStore
    private let dropHandler: FileDropHandler

    private let panel: TrayPanel
    private let dropView: TrayDropView
    private var hostingView: NSHostingView<AnyView>!

    private var focusObserver: (any NSObjectProtocol)?

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

        presenter.collapseDelay = { [settings] in settings.autoCollapseDelay }
        presenter.holdsOpenWhenClicked = { [settings] in settings.staysOpenAfterClick }
        presenter.expandsAfterDrop = { [settings] in settings.expandsAfterDrop }

        configureContent()
        configureMouseHandling()
        configureFocusHandling()

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
        // Sized for the widest the shelf is ever allowed to be, plus room for
        // its flares and its shadow. The window never resizes — the shelf
        // animates inside it — so it has to be big enough for the largest
        // setting, not for the current one.
        let widest = TrayMetrics.expandedWidth(
            forScreenWidth: geometry.frame.width,
            fraction: SettingsStore.widthFractionRange.upperBound
        )
        let width = min(
            geometry.frame.width,
            widest + (TrayMetrics.panelPadding + TrayMetrics.topFlare) * 2
        )

        // The debug overlay hangs below the tray and would otherwise be clipped
        // by the window it lives in — a diagnostic you cannot read is not one.
        let height = TrayItemMetrics.maximumExpandedHeight
            + (geometry.notchSize?.height ?? 0)
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

    isolated deinit {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
    }

    // MARK: - Content

    private func configureContent() {
        let view = TrayContentView(
            store: store,
            presenter: presenter,
            selection: selection,
            thumbnails: thumbnails,
            settings: settings,
            geometry: geometry,
            onRemove: { [weak self] item in self?.remove([item]) },
            onCopy: { [weak self] items in self?.copy(items) },
            onClick: { [weak self] item, modifiers in self?.click(item, modifiers) },
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

        dropView.onDragSessionEnded = { [weak self] in
            self?.presenter.dragSessionEnded()
        }

        dropView.performDrop = { [weak self] info in
            guard let self else { return false }
            return self.accept(info)
        }

        presenter.onStateChange = { [weak self] state in
            guard let self else { return }
            self.dropView.isOpen = state.isOpen
            // A closed tray has nothing to have selected, and leaving a stale
            // selection behind means the next Delete acts on something the user
            // picked minutes ago.
            if !state.isOpen { self.clearSelection() }
        }

        configureKeyboard()
    }

    // MARK: - Focus

    /// Clicking away from the tray ends whatever was going on in it.
    ///
    /// Without this, a tray the user clicked into stays open forever: the
    /// interaction gate is holding it, and the pointer leaving no longer
    /// closes it.
    private func configureFocusHandling() {
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.selection.clear()
                self.presenter.endedInteracting()
            }
        }
    }

    // MARK: - Keyboard

    private func configureKeyboard() {
        dropView.onDelete = { [weak self] in
            guard let self else { return }
            self.remove(self.selection.items(from: self.store.items))
        }

        dropView.onCopy = { [weak self] in
            guard let self else { return }
            self.copy(self.selection.items(from: self.store.items))
        }

        dropView.onPaste = { [weak self] in self?.paste() }

        dropView.onSelectAll = { [weak self] in
            guard let self else { return }
            self.selection.selectAll(self.store.items.map(\.id))
        }

        dropView.onQuickLook = { [weak self] in
            guard let self,
                  let item = self.selection.items(from: self.store.items).first
            else { return }
            self.onQuickLookRequest?(item)
        }

        dropView.onEscape = { [weak self] in
            self?.clearSelection()
            self?.presenter.collapseNow()
        }

        dropView.onStepSelection = { [weak self] offset in
            guard let self else { return }
            self.selection.step(by: offset, within: self.store.items.map(\.id))
        }

        dropView.onClearSelection = { [weak self] in self?.clearSelection() }
    }

    private func click(_ item: TrayItem, _ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            selection.toggle(item.id)
        } else {
            selection.select(item.id)
        }
        presenter.beganInteracting()
    }

    private func clearSelection() {
        selection.clear()
        presenter.endedInteracting()
    }

    /// ⌘C. Writes file URLs, which is what Finder writes — so pasting lands
    /// the file itself, and the original never moves (§3).
    private func copy(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        let wrote = TrayPasteboard.copy(items)
        logger.debug("Copied \(items.count, privacy: .public) item(s): \(wrote, privacy: .public)")
    }

    /// ⌘V. The mirror of a drop, and it obeys the same rule: what lands on the
    /// shelf is a reference, not a copy of the bytes.
    private func paste() {
        let urls = TrayPasteboard.pasteableURLs()
        guard !urls.isEmpty else { return }

        store.refreshAvailability()
        if case .added(let ids) = store.add(urls) {
            // Select what just arrived, so a paste is visible rather than
            // merely successful.
            selection.selectAll(ids)
            presenter.beganInteracting()
        }
        presenter.dropCompleted()
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
            remove([item])
        }
    }

    private func remove(_ items: [TrayItem]) {
        guard !items.isEmpty else { return }
        for item in items {
            store.remove(id: item.id)
            thumbnails.forget(item)
        }
        selection.prune(to: store.items.map(\.id))
        if selection.isEmpty { presenter.endedInteracting() }
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
