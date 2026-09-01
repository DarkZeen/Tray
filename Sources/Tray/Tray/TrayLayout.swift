import CoreGraphics
import Foundation

/// Every dimension the tray has, in one place (§7).
///
/// These are starting points chosen to sit mid-range in the spec's brackets.
/// They are meant to be tuned by looking at the thing on a real screen, which
/// is exactly why they live here instead of being scattered through the views.
enum TrayMetrics {
    // MARK: Container

    /// Height of the resting pill on a display with no notch to borrow.
    static let collapsedHeight: CGFloat = 30
    static let expandedHeight: CGFloat = 98

    static let collapsedWidth: CGFloat = 108
    static let minimumWidth: CGFloat = 116

    /// The open-but-empty tray. Wide enough to give the prompt margins rather
    /// than having it press against both edges.
    static let emptyWidth: CGFloat = 190

    /// The empty, resting tray: a handle, not a panel (§77). Present enough to
    /// be found, quiet enough to be forgotten.
    static let handleWidth: CGFloat = 56
    static let handleHeight: CGFloat = 5

    /// The shelf never spans the screen (§20).
    static func maximumWidth(forScreenWidth screenWidth: CGFloat) -> CGFloat {
        min(720, screenWidth * 0.60)
    }

    // MARK: Corners

    /// Corner radii are stated as a pair because the closed pill and the open
    /// shelf are the *same surface* changing shape (§16) — the radius is
    /// interpolated between them, never cut.
    static let collapsedCornerRadius: CGFloat = 14
    static let expandedCornerRadius: CGFloat = 22

    // MARK: Items

    static let thumbnailSize: CGFloat = 52
    static let itemSpacing: CGFloat = 9
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12

    /// Width one item occupies including its label column. Wider than the
    /// thumbnail so that filenames get somewhere to live without every one of
    /// them ending in an ellipsis.
    static let itemWidth: CGFloat = 66

    /// How far the shelf's contents fade out at a scrolling edge (§20).
    static let scrollFade: CGFloat = 18

    // MARK: Hit regions (§74)

    /// How far outside the visible shape the pointer still counts as "on" the
    /// tray. Stops the shelf collapsing out from under a pointer that drifted
    /// a pixel past the edge.
    static let hoverSlop: CGFloat = 8

    /// The resting hover target: narrow, so ordinary mouse travel across the
    /// menu bar does not keep tripping it (§12, §75).
    static let hoverActivationWidth: CGFloat = 148

    /// The drag target is deliberately wider — throwing a file at the top of
    /// the screen should not demand precision (§75).
    static let dragActivationWidth: CGFloat = 320
    static let dragActivationHeight: CGFloat = 46

    /// The panel is a fixed-size window; the tray is drawn inside it and the
    /// window never resizes. Resizing an `NSWindow` per frame is the classic
    /// source of the jitter §16 warns about, so the surface animates in the
    /// view layer and the window just stays big enough to contain the largest
    /// state.
    static let panelPadding: CGFloat = 44
}

/// The size of the tray surface for a given state and item count.
struct TrayShape: Equatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    static func collapsed(notchSize: CGSize?, isEmpty: Bool) -> TrayShape {
        // On a notched display the closed tray *is* the notch: same width, same
        // height, so it reads as part of the hardware rather than a widget
        // parked underneath it (§9).
        if let notchSize {
            return TrayShape(
                width: notchSize.width,
                height: notchSize.height,
                cornerRadius: TrayMetrics.collapsedCornerRadius
            )
        }
        // Empty and closed, the surface contracts all the way down to a
        // handle rather than sitting there as a small black slab (§77).
        if isEmpty {
            return TrayShape(
                width: TrayMetrics.handleWidth,
                height: TrayMetrics.handleHeight,
                cornerRadius: TrayMetrics.handleHeight / 2
            )
        }

        return TrayShape(
            width: TrayMetrics.collapsedWidth,
            height: TrayMetrics.collapsedHeight,
            cornerRadius: TrayMetrics.collapsedCornerRadius
        )
    }

    /// Width the shelf's items want, before any clamping.
    static func contentWidth(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return TrayMetrics.emptyWidth }
        return CGFloat(itemCount) * TrayMetrics.itemWidth
            + CGFloat(itemCount - 1) * TrayMetrics.itemSpacing
            + TrayMetrics.horizontalPadding * 2
    }

    /// Whether the items fit, or whether the shelf has to start scrolling (§20).
    static func fits(itemCount: Int, screenWidth: CGFloat) -> Bool {
        contentWidth(itemCount: itemCount)
            <= TrayMetrics.maximumWidth(forScreenWidth: screenWidth)
    }

    static func expanded(itemCount: Int, screenWidth: CGFloat) -> TrayShape {
        let width = min(
            max(contentWidth(itemCount: itemCount), TrayMetrics.minimumWidth),
            TrayMetrics.maximumWidth(forScreenWidth: screenWidth)
        )

        return TrayShape(
            width: width,
            height: TrayMetrics.expandedHeight,
            cornerRadius: TrayMetrics.expandedCornerRadius
        )
    }

    var size: CGSize { CGSize(width: width, height: height) }
}
