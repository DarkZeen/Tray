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
    var inset: CGFloat = 0

    /// Lets the radius interpolate with the rest of the container, so the
    /// corner tightens and loosens as part of the same motion.
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func inset(by amount: CGFloat) -> TraySurface {
        TraySurface(cornerRadius: cornerRadius, inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        return Path(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
            .path(in: rect).cgPath
        )
    }
}

/// The material treatment applied to `TraySurface`.
///
/// Every colour comes from the palette, so switching appearance is one change
/// rather than thirty (§49).
struct TraySurfaceStyle: ViewModifier {
    var cornerRadius: CGFloat
    /// Slightly stronger blur while a drag is over the target (§14, step 5).
    var isEmphasised: Bool

    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: TraySurface { TraySurface(cornerRadius: cornerRadius) }

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
            .compositingGroup()
            .shadow(color: shadow.colour, radius: shadow.radius, x: 0, y: shadow.y)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func traySurface(cornerRadius: CGFloat, isEmphasised: Bool = false) -> some View {
        modifier(TraySurfaceStyle(cornerRadius: cornerRadius, isEmphasised: isEmphasised))
    }
}
