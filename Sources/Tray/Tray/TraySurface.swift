import AppKit
import SwiftUI

/// The tray's physical surface (§6, §47, §48).
///
/// One shape, one material, from closed pill to open shelf. The whole point of
/// §16 is that this surface never fades out and back in — it changes shape
/// continuously, so it reads as a single object rather than two views
/// cross-dissolving.
///
/// The top corners are square and the bottom ones are round, because the tray
/// hangs from the edge of the display. On a notched Mac that is literally the
/// housing's silhouette; on any other display it produces the same "grown out
/// of the top of the screen" reading rather than a rectangle parked near it.
struct TraySurface: InsettableShape {
    var cornerRadius: CGFloat

    /// How far the top corners flare outwards to meet the edge of the screen.
    /// Zero gives a plain square-topped shape.
    var topFlare: CGFloat = 0

    var inset: CGFloat = 0

    /// Both curves interpolate, so the corner tightens and the flare grows as
    /// part of the same motion rather than snapping when the state changes.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, topFlare) }
        set {
            cornerRadius = newValue.first
            topFlare = newValue.second
        }
    }

    func inset(by amount: CGFloat) -> TraySurface {
        TraySurface(cornerRadius: cornerRadius, topFlare: topFlare, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let body = rect.insetBy(dx: inset, dy: inset)
        guard body.width > 0, body.height > 0 else { return Path() }

        let corner = min(cornerRadius, min(body.width, body.height) / 2)
        let flare = max(topFlare, 0)

        var path = Path()

        // The flares deliberately extend past `rect` on both sides. The shelf's
        // walls meet the top edge of the display with a concave fillet — the
        // same move the hardware makes where the notch meets the bezel — and a
        // fillet that curves outwards has to have somewhere to go.
        path.move(to: CGPoint(x: body.minX - flare, y: body.minY))

        if flare > 0 {
            path.addArc(
                tangent1End: CGPoint(x: body.minX, y: body.minY),
                tangent2End: CGPoint(x: body.minX, y: body.minY + flare),
                radius: flare
            )
        }

        // Down the left wall and round the bottom-left corner.
        path.addArc(
            tangent1End: CGPoint(x: body.minX, y: body.maxY),
            tangent2End: CGPoint(x: body.maxX, y: body.maxY),
            radius: corner
        )

        // Along the bottom and round the bottom-right corner.
        path.addArc(
            tangent1End: CGPoint(x: body.maxX, y: body.maxY),
            tangent2End: CGPoint(x: body.maxX, y: body.minY),
            radius: corner
        )

        // Up the right wall, flaring out to the top edge.
        if flare > 0 {
            path.addArc(
                tangent1End: CGPoint(x: body.maxX, y: body.minY),
                tangent2End: CGPoint(x: body.maxX + flare, y: body.minY),
                radius: flare
            )
        } else {
            path.addLine(to: CGPoint(x: body.maxX, y: body.minY))
        }

        path.closeSubpath()
        return path
    }
}

/// The material treatment applied to `TraySurface`.
///
/// Every colour comes from the palette, so switching appearance is one change
/// rather than thirty (§49).
struct TraySurfaceStyle: ViewModifier {
    var cornerRadius: CGFloat
    var topFlare: CGFloat
    /// Slightly stronger blur while a drag is over the target (§14, step 5).
    var isEmphasised: Bool
    /// The optional dashed outline marking the drop area, and how far inside
    /// the surface edge it sits.
    var showsDropOutline: Bool
    var dropOutlineInset: CGFloat = TrayMetrics.defaultDropOutlineInset
    /// Space at the top the camera housing covers. The outline starts below it,
    /// so the whole border is visible rather than having its top run disappear
    /// into the notch.
    var notchInset: CGFloat = 0

    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: TraySurface {
        TraySurface(cornerRadius: cornerRadius, topFlare: topFlare)
    }

    /// The dashed outline is a plain rounded rectangle — rounded on all four
    /// corners, not just the two the surface rounds.
    ///
    /// The surface has square shoulders because it hangs off the top edge of
    /// the display and has nowhere else to go. The outline sits *inside* it,
    /// where nothing is holding its top corners square, so squaring them only
    /// made it look unfinished.
    private var outlineShape: RoundedRectangle {
        RoundedRectangle(
            // The radius shrinks with the inset so the outline stays concentric
            // with the surface rather than getting rounder as it moves inwards.
            cornerRadius: max(cornerRadius - dropOutlineInset, 6),
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        let highlight = palette.edgeHighlight(isEmphasised: isEmphasised)
        let shadow = palette.shadow

        return content
            .background {
                shape
                    .fill(palette.surfaceFill(reduceTransparency: reduceTransparency))
                    .background {
                        // Skipped under reduced transparency, where a solid
                        // surface is both the accessible answer and the cheaper
                        // one — and skipped for pitch black, which is opaque by
                        // definition.
                        if palette.usesMaterial && !reduceTransparency {
                            shape.fill(.ultraThinMaterial)
                        }
                    }
            }
            .overlay {
                // An edge highlight, not a stroke (§48). It exists so the tray
                // still has an edge against a wallpaper the same colour as it.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [highlight.top, highlight.bottom],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .overlay {
                if showsDropOutline {
                    outlineShape
                        .stroke(
                            palette.dropOutlineInk,
                            style: StrokeStyle(
                                lineWidth: 1.2,
                                dash: [TrayMetrics.dropOutlineDash, TrayMetrics.dropOutlineGap]
                            )
                        )
                        .padding(dropOutlineInset)
                        .padding(.top, notchInset)
                }
            }
            .compositingGroup()
            .shadow(color: shadow.colour, radius: shadow.radius, x: 0, y: shadow.y)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func traySurface(
        cornerRadius: CGFloat,
        topFlare: CGFloat = 0,
        isEmphasised: Bool = false,
        showsDropOutline: Bool = false,
        dropOutlineInset: CGFloat = TrayMetrics.defaultDropOutlineInset,
        notchInset: CGFloat = 0
    ) -> some View {
        modifier(
            TraySurfaceStyle(
                cornerRadius: cornerRadius,
                topFlare: topFlare,
                isEmphasised: isEmphasised,
                showsDropOutline: showsDropOutline,
                dropOutlineInset: dropOutlineInset,
                notchInset: notchInset
            )
        )
    }
}
