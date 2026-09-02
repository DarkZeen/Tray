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

    static let collapsedWidth: CGFloat = 108
    static let minimumWidth: CGFloat = 116

    /// The open-but-empty tray. Wide enough to give the prompt margins rather
    /// than having it press against both edges.
    static let emptyWidth: CGFloat = 190

    /// The empty, resting tray: a handle, not a panel (§77). Present enough to
    /// be found, quiet enough to be forgotten.
    static let handleWidth: CGFloat = 56
    static let handleHeight: CGFloat = 5

    /// How tall the open shelf is, in points.
    ///
    /// Points rather than a share of the screen, unlike the width: the shelf
    /// hangs from the top edge and is small next to the display, so a fraction
    /// of the screen height would be a strange thing to reason about.
    static let trayHeightRange: ClosedRange<Double> = 80...320

    /// How wide the open shelf is, as a share of the display it is on.
    ///
    /// A fraction rather than a number of points, so one setting behaves
    /// sensibly on a laptop screen and a 5K display at once.
    static func expandedWidth(forScreenWidth screenWidth: CGFloat, fraction: Double) -> CGFloat {
        let requested = screenWidth * fraction
        // Never the full span: the shelf has to read as an object on the
        // screen rather than as a second menu bar (§20).
        return min(max(requested, minimumWidth), screenWidth - 48)
    }

    // MARK: Corners

    /// Corner radii are stated as a pair because the closed pill and the open
    /// shelf are the *same surface* changing shape (§16) — the radius is
    /// interpolated between them, never cut.
    static let collapsedCornerRadius: CGFloat = 14
    static let expandedCornerRadius: CGFloat = 22

    /// How far the open shelf flares outwards where its walls meet the top edge
    /// of the screen.
    ///
    /// A concave fillet rather than a square corner, so the shelf reads as
    /// carved out of the display's edge rather than taped to it — the same
    /// trick the hardware plays where the notch meets the bezel. Zero while
    /// closed, because a closed tray on a notched Mac *is* the housing and must
    /// match its silhouette exactly.
    static let topFlare: CGFloat = 11

    /// The dashed outline some people want around the drop area, inset from the
    /// surface edge.
    static let defaultDropOutlineInset: CGFloat = 7
    static let dropOutlineInsetRange: ClosedRange<Double> = 0...30
    static let dropOutlineDash: CGFloat = 5
    static let dropOutlineGap: CGFloat = 4

    // MARK: Items

    /// How large a file is drawn. Adjustable, because how much of the shelf a
    /// file should occupy depends on what you keep in it — a row of photographs
    /// wants a different size from a row of documents.
    static let defaultThumbnailSize: CGFloat = 52
    static let thumbnailSizeRange: ClosedRange<Double> = 32...88

    static let itemSpacing: CGFloat = 9
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12

    /// How much wider than its thumbnail an item is, so that filenames get
    /// somewhere to live without every one of them ending in an ellipsis.
    static let itemLabelMargin: CGFloat = 14

    /// The gap between a thumbnail and the name beneath it.
    static let labelSpacing: CGFloat = 5
    static let labelHeight: CGFloat = 13

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

/// How big one item on the shelf is.
///
/// Derived from the two settings that change it, and passed down as one value
/// so that the layout, the views and the thumbnail cache cannot disagree about
/// how large a file is meant to be.
struct TrayItemMetrics: Equatable, Sendable {
    var thumbnailSize: CGFloat
    var showsFilename: Bool

    static let `default` = TrayItemMetrics(
        thumbnailSize: TrayMetrics.defaultThumbnailSize,
        showsFilename: true
    )

    var itemWidth: CGFloat { thumbnailSize + TrayMetrics.itemLabelMargin }

    var itemHeight: CGFloat {
        thumbnailSize + (showsFilename ? TrayMetrics.labelSpacing + TrayMetrics.labelHeight : 0)
    }

    /// The open shelf's height, before any allowance for the notch.
    var expandedHeight: CGFloat {
        itemHeight + TrayMetrics.verticalPadding * 2
    }

    /// The tallest the shelf can get, used to size the window once rather than
    /// resizing it whenever a setting moves.
    static var maximumExpandedHeight: CGFloat {
        let byContent = TrayItemMetrics(
            thumbnailSize: TrayMetrics.thumbnailSizeRange.upperBound,
            showsFilename: true
        ).expandedHeight
        return max(byContent, TrayMetrics.trayHeightRange.upperBound)
    }

    /// The shelf's height for a requested value.
    ///
    /// The request is a floor, not a ceiling. Content that needs more room gets
    /// it — a shelf shorter than the icons it is holding would clip them, and
    /// no setting should be able to ask for that.
    func expandedHeight(requesting requested: Double) -> CGFloat {
        max(requested, expandedHeight)
    }
}

/// The size of the tray surface for a given state and item count.
struct TrayShape: Equatable {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var topFlare: CGFloat = 0

    /// Space kept clear at the top of the open shelf so the camera housing does
    /// not sit over the contents.
    ///
    /// Nothing drawn under the notch is visible — it is a hole in the display,
    /// not a dark rectangle — so without this the top third of every thumbnail
    /// in the middle of the shelf is simply missing.
    var notchInset: CGFloat = 0

    static func collapsed(notchSize: CGSize?, isEmpty: Bool) -> TrayShape {
        // No flare while closed: on a notched Mac the closed tray is the
        // housing, and the housing has no flare.
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
    static func contentWidth(itemCount: Int, item: TrayItemMetrics) -> CGFloat {
        guard itemCount > 0 else { return TrayMetrics.emptyWidth }
        return CGFloat(itemCount) * item.itemWidth
            + CGFloat(itemCount - 1) * TrayMetrics.itemSpacing
            + TrayMetrics.horizontalPadding * 2
    }

    /// Whether the items fit, or whether the shelf has to start scrolling (§20).
    static func fits(
        itemCount: Int,
        screenWidth: CGFloat,
        widthFraction: Double,
        item: TrayItemMetrics
    ) -> Bool {
        contentWidth(itemCount: itemCount, item: item)
            <= TrayMetrics.expandedWidth(forScreenWidth: screenWidth, fraction: widthFraction)
    }

    static func expanded(
        screenWidth: CGFloat,
        widthFraction: Double,
        notchHeight: CGFloat,
        item: TrayItemMetrics = .default,
        height requestedHeight: Double = 0
    ) -> TrayShape {
        TrayShape(
            width: TrayMetrics.expandedWidth(
                forScreenWidth: screenWidth,
                fraction: widthFraction
            ),
            height: item.expandedHeight(requesting: requestedHeight) + notchHeight,
            cornerRadius: TrayMetrics.expandedCornerRadius,
            topFlare: TrayMetrics.topFlare,
            notchInset: notchHeight
        )
    }

    var size: CGSize { CGSize(width: width, height: height) }
}
