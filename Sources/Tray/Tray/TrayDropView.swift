import AppKit

/// The panel's content view: the tray's entire relationship with the mouse
/// (§13, §74, §75).
///
/// Three regions, kept deliberately distinct:
///
/// * **content region** — the visible tray. Clicks, hover and item drags.
/// * **hover activation region** — the content region plus a little slop, and
///   when closed, a narrow strip. Narrow on purpose: ordinary pointer travel
///   across the top of the screen must not keep springing the shelf open.
/// * **drag activation region** — much wider, and live only while a mouse
///   button is down. Throwing a file at the top of the screen should not
///   demand aim.
///
/// Every point outside the region that currently applies returns `nil` from
/// `hitTest`, so the window is genuinely transparent to the app underneath.
/// The alternative — a permanently live strip across the top of the display —
/// is the "giant invisible mouse trap" §74 forbids.
final class TrayDropView: NSView {
    /// The visible tray, in this view's coordinates. Set by the controller
    /// whenever the shape changes.
    var contentRect: CGRect = .zero {
        didSet {
            guard contentRect != oldValue else { return }
            needsLayout = true
            window?.invalidateCursorRects(for: self)
            updateTrackingAreas()
        }
    }

    /// Whether the tray is currently open, which decides how generous the
    /// hover region is allowed to be.
    var isOpen = false {
        didSet {
            guard isOpen != oldValue else { return }
            updateTrackingAreas()
        }
    }

    var onPointerEnter: () -> Void = {}
    var onPointerExit: () -> Void = {}
    var onDragEnter: () -> Void = {}
    var onDragExit: () -> Void = {}
    var onDragApproach: () -> Void = {}
    var canAcceptDrag: (any NSDraggingInfo) -> Bool = { _ in false }
    var performDrop: (any NSDraggingInfo) -> Bool = { _ in false }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Regions

    /// Where the pointer counts as "on the tray".
    ///
    /// When open this is the shelf plus a few points of slop, so the tray does
    /// not collapse out from under a pointer that drifted a pixel past the
    /// edge. When closed it is a narrow strip at the top centre (§75).
    var hoverActivationRect: CGRect {
        if isOpen {
            return contentRect.insetBy(
                dx: -TrayMetrics.hoverSlop,
                dy: -TrayMetrics.hoverSlop
            )
        }
        let width = max(TrayMetrics.hoverActivationWidth, contentRect.width)
        let height = max(TrayMetrics.collapsedHeight, contentRect.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    /// The wider catchment for an incoming drag (§75). Live only while a
    /// button is held, so it costs ordinary mouse use nothing.
    var dragActivationRect: CGRect {
        let width = max(TrayMetrics.dragActivationWidth, contentRect.width + 40)
        let height = max(TrayMetrics.dragActivationHeight, contentRect.height)
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - height,
            width: width,
            height: height
        )
    }

    /// A drag is under way somewhere on the system.
    ///
    /// Reading the button state is a single cheap query at hit-test time, not
    /// a monitor and not a poll (§26). Every file drag has the button down,
    /// which is exactly the condition that should widen the target.
    private var pointerButtonIsDown: Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let region = pointerButtonIsDown
            ? dragActivationRect.union(hoverActivationRect)
            : hoverActivationRect

        guard region.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: hoverActivationRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // Rebuilding a tracking area — which happens every time the tray changes
    // shape — makes AppKit re-evaluate containment and fire enter/exit events
    // that do not correspond to the pointer having moved anywhere. Both are
    // confirmed against the live region before being believed. Without this,
    // the tray opens by itself when nothing went near it, which is precisely
    // the accidental activation §12 warns about.

    override func mouseEntered(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard hoverActivationRect.contains(local) else { return }
        onPointerEnter()
    }

    override func mouseExited(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard !hoverActivationRect.contains(local) else { return }
        onPointerExit()
    }

    // MARK: - Drag destination (§13, §14, §38)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else { return [] }
        updateDragPhase(for: sender)
        return FileDropHandler.advertisedOperation
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrag(sender) else { return [] }
        updateDragPhase(for: sender)
        return FileDropHandler.advertisedOperation
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExit()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        canAcceptDrag(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        performDrop(sender)
    }

    /// Distinguishes "a drag is nearby and the tray should lean toward it"
    /// from "a drag is over the target and releasing would stash" (§13).
    private func updateDragPhase(for sender: any NSDraggingInfo) {
        let local = convert(sender.draggingLocation, from: nil)
        if contentRect.insetBy(dx: -TrayMetrics.hoverSlop, dy: -TrayMetrics.hoverSlop).contains(local) {
            onDragEnter()
        } else {
            onDragApproach()
        }
    }
}
