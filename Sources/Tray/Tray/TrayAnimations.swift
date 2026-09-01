import AppKit
import SwiftUI

/// The tray's motion, in one place (§44).
///
/// Three layers move differently on purpose (§15, §45). The container is the
/// heaviest thing on screen and settles softly; items arriving carry a little
/// more energy because the user just threw them; removal is quick because a
/// departure should not be dwelt on; hover is barely there. Applying one
/// global spring to everything is what makes an interface read as "SwiftUI
/// with `.animation()` everywhere" rather than as a designed object.
///
/// Every value here is a starting point to be judged by eye on real hardware.
enum TrayAnimation {
    // MARK: Response — how quickly a spring reaches its target, in seconds.

    static let hoverResponse = 0.24
    static let expandResponse = 0.32
    static let collapseResponse = 0.38
    static let itemEntranceResponse = 0.34
    static let itemRemovalResponse = 0.20
    static let itemShiftResponse = 0.30

    // MARK: Damping — 1.0 settles without overshoot, lower bounces.

    /// The container never overshoots. A shelf that wobbles reads as cheap.
    static let expandDamping = 0.86
    static let collapseDamping = 0.92
    static let hoverDamping = 0.90
    /// Items get the only real bounce in the product, and only a hint of one,
    /// because the gesture that delivered them carried momentum.
    static let itemEntranceDamping = 0.74
    static let itemRemovalDamping = 1.0
    static let itemShiftDamping = 0.88

    // MARK: Timings

    /// Long enough that crossing the menu bar does not open the tray; short
    /// enough that deliberately going there feels immediate (§12).
    static let hoverActivationDelay: TimeInterval = 0.10

    /// The grace period after the pointer leaves. Covers the gap between
    /// dropping one file and going to fetch the next (§17).
    static let collapseDelay: TimeInterval = 0.65

    /// A drag leaving the drop area gets longer rope — a drag that clips the
    /// edge of the target should not slam the shelf shut mid-gesture.
    static let dragExitGrace: TimeInterval = 0.35

    // MARK: Built animations

    /// True when the system asks for less movement (§50). Functionality never
    /// changes; only the way it arrives does.
    static var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Reduced motion is not *no* motion — it is a short, non-vestibular
    /// equivalent. Springs and overshoot go; a brief fade stays, because
    /// removing all feedback loses information.
    private static var reducedSubstitute: Animation {
        .easeOut(duration: 0.14)
    }

    private static func spring(_ response: Double, _ damping: Double) -> Animation {
        if prefersReducedMotion { return reducedSubstitute }
        return .spring(response: response, dampingFraction: damping, blendDuration: 0.05)
    }

    /// Closed pill growing into the open shelf.
    static var expand: Animation { spring(expandResponse, expandDamping) }

    /// Open shelf easing back down. Slightly slower than opening: leaving
    /// should feel calmer than arriving.
    static var collapse: Animation { spring(collapseResponse, collapseDamping) }

    /// The near-imperceptible acknowledgement that the pointer is near.
    static var hover: Animation { spring(hoverResponse, hoverDamping) }

    /// An item joining the shelf.
    static var itemEntrance: Animation { spring(itemEntranceResponse, itemEntranceDamping) }

    /// An item leaving. Quick, and out of the way.
    static var itemRemoval: Animation {
        if prefersReducedMotion { return reducedSubstitute }
        return .spring(response: itemRemovalResponse, dampingFraction: itemRemovalDamping)
    }

    /// Neighbours closing a gap or opening one.
    static var itemShift: Animation { spring(itemShiftResponse, itemShiftDamping) }
}

/// Scale values for interaction feedback (§13, §46).
///
/// The amplitudes are tiny on purpose. Everything here is meant to be felt
/// rather than watched.
enum TrayScale {
    static let resting: CGFloat = 1.0
    /// A drag is approaching but has not entered the drop area.
    static let dragApproaching: CGFloat = 1.03
    /// The pointer is inside and a drop would land.
    static let dropTargetActive: CGFloat = 1.04
    /// Pointer resting on a single item.
    static let itemHover: CGFloat = 1.025
    /// An item picked up and being carried out.
    static let itemLifted: CGFloat = 1.04
    /// The compression at the instant of a drop, before it settles back.
    static let dropImpact: CGFloat = 0.97
    /// An item on its way out.
    static let itemDeparting: CGFloat = 0.86
}
