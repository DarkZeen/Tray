import Foundation

/// What the tray is currently doing (§43).
///
/// Deliberately not a pile of booleans: `isOpen && !isDragging && !isHovering`
/// is where animation bugs are born. Every visible configuration of the tray
/// is exactly one case here.
///
/// The spec's sketch included `expanding` and `collapsing`. They are absent on
/// purpose. Springs are continuous and interruptible — a state that exists
/// only while an animation runs has to be exited by a timer, and a UI that
/// waits for a timer cannot be grabbed and reversed mid-flight. Instead the
/// *scheduled* collapse is modelled as `isCollapseScheduled` on the presenter,
/// which is a fact about intent rather than about animation progress.
enum TrayPresentationState: Equatable, Sendable {
    /// Resting. A pill, or the notch itself.
    case collapsed

    /// Open because the pointer is on it, or because something just landed.
    case expanded

    /// An external drag is inside the drop area. The target is lit and a
    /// release would stash (§13).
    case dragOver

    /// One of the tray's own items has been picked up and is being carried
    /// somewhere (§21, §22).
    case draggingItem(TrayItem.ID)

    /// Is the shelf showing its contents?
    var isOpen: Bool {
        switch self {
        case .collapsed: false
        case .expanded, .dragOver, .draggingItem: true
        }
    }

    /// Is an external drag currently hovering over the drop area?
    var isDropTargetActive: Bool {
        self == .dragOver
    }

    var draggedItemID: TrayItem.ID? {
        if case .draggingItem(let id) = self { return id }
        return nil
    }
}
