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
/// Dark in both appearances, deliberately (§49). The tray is a persistent
/// object with its own identity, not a panel that inverts with the system —
/// and a dark surface is what keeps file thumbnails reading as the content.
struct TraySurfaceStyle: ViewModifier {
    var cornerRadius: CGFloat
    /// Slightly stronger blur while a drag is over the target (§14, step 5).
    var isEmphasised: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: TraySurface { TraySurface(cornerRadius: cornerRadius) }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(baseFill)
                    .background {
                        // Skipped entirely under reduced transparency, where a
                        // solid surface is both the accessible answer and the
                        // cheaper one.
                        if !reduceTransparency {
                            shape.fill(.ultraThinMaterial)
                        }
                    }
            }
            .overlay {
                // An edge highlight, not a stroke (§48). Brightest along the
                // top where light would catch a real object, gone by the
                // bottom. It exists so the tray still has an edge against a
                // white wallpaper.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isEmphasised ? 0.16 : 0.10),
                            .white.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .compositingGroup()
            // Soft and wide rather than dark and tight: a tight shadow reads
            // as a black halo, which §47 rules out.
            .shadow(color: .black.opacity(0.30), radius: 22, x: 0, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)
    }

    private var baseFill: Color {
        // Almost-black graphite rather than pure black, so the surface still
        // reads as a material when it happens to sit over black content.
        let opacity = reduceTransparency ? 1.0 : 0.78
        return Color(red: 0.055, green: 0.058, blue: 0.065).opacity(opacity)
    }
}

extension View {
    func traySurface(cornerRadius: CGFloat, isEmphasised: Bool = false) -> some View {
        modifier(TraySurfaceStyle(cornerRadius: cornerRadius, isEmphasised: isEmphasised))
    }
}
