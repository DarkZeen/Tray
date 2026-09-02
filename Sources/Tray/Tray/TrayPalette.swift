import SwiftUI

/// How the tray is painted.
///
/// The default stays the dark graphite surface §6 describes. The other two are
/// choices, not modes: Tray does not follow the system appearance, because the
/// shelf is a persistent object with its own identity rather than a panel that
/// inverts underneath you (§49).
enum TrayAppearance: String, CaseIterable, Sendable {
    /// Almost-black, translucent, blurred. The house style.
    case graphite
    /// A light translucent surface, for anyone who wants the shelf to sit with
    /// a light desktop rather than against it.
    case light
    /// True black and fully opaque — the colour of the camera housing itself.
    /// On a notched Mac this makes the shelf read as the notch growing rather
    /// than as something hanging below it.
    case black

    var title: String {
        switch self {
        case .graphite: "Graphite"
        case .light: "Light"
        case .black: "Pitch black"
        }
    }

    var note: String {
        switch self {
        case .graphite: "Dark and slightly translucent."
        case .light: "Light and slightly translucent."
        case .black: "The same black as the notch, with nothing showing through."
        }
    }

    var palette: TrayPalette { TrayPalette(appearance: self) }
}

/// Every colour the tray draws, derived from one appearance.
///
/// Gathered into a struct rather than scattered as `.white.opacity(0.6)` across
/// the views, because "make the tray light" has to be one change, not thirty —
/// and because a foreground that does not flip with its background is how a
/// light theme ends up unreadable.
struct TrayPalette: Equatable, Sendable {
    let appearance: TrayAppearance

    init(appearance: TrayAppearance) {
        self.appearance = appearance
    }

    /// Whether content on this surface should be drawn light or dark.
    var colorScheme: ColorScheme {
        appearance == .light ? .light : .dark
    }

    /// The blur behind the surface. Pitch black has none: the notch does not
    /// let anything through, and neither should this.
    var usesMaterial: Bool {
        appearance != .black
    }

    func surfaceFill(reduceTransparency: Bool) -> Color {
        switch appearance {
        case .graphite:
            // Almost-black rather than black, so the surface still reads as a
            // material when it happens to sit over black content.
            Color(red: 0.055, green: 0.058, blue: 0.065)
                .opacity(reduceTransparency ? 1 : 0.78)
        case .light:
            Color(red: 0.93, green: 0.93, blue: 0.945)
                .opacity(reduceTransparency ? 1 : 0.76)
        case .black:
            .black
        }
    }

    /// The edge highlight (§48) — brightest at the top, where light would catch
    /// a real object.
    func edgeHighlight(isEmphasised: Bool) -> (top: Color, bottom: Color) {
        switch appearance {
        case .graphite:
            (.white.opacity(isEmphasised ? 0.16 : 0.10), .white.opacity(0.02))
        case .light:
            // A light surface needs a dark edge to hold its shape against a
            // pale wallpaper; a white one would vanish.
            (.black.opacity(isEmphasised ? 0.14 : 0.09), .black.opacity(0.03))
        case .black:
            // Almost nothing. A real notch has no highlight, and the whole
            // point of this option is that you cannot tell where it ends.
            (.white.opacity(isEmphasised ? 0.10 : 0.03), .clear)
        }
    }

    /// Foreground ink at full strength — filenames, the drop prompt when lit.
    var primaryInk: Color {
        appearance == .light ? .black : .white
    }

    func ink(_ opacity: Double) -> Color {
        primaryInk.opacity(opacity)
    }

    /// Fill behind an item under the pointer.
    func hoverFill(_ isHovering: Bool) -> Color {
        guard isHovering else { return .clear }
        return appearance == .light ? .black.opacity(0.07) : .white.opacity(0.09)
    }

    /// The shadow under the tray. Kept soft and wide — a tight one reads as a
    /// black halo, which §47 rules out.
    var shadow: (colour: Color, radius: CGFloat, y: CGFloat) {
        switch appearance {
        case .graphite: (.black.opacity(0.30), 22, 6)
        case .light: (.black.opacity(0.22), 20, 5)
        // Slightly stronger, because a black surface has no edge of its own to
        // separate it from dark content behind.
        case .black: (.black.opacity(0.40), 24, 7)
        }
    }
}

private struct TrayPaletteKey: EnvironmentKey {
    static let defaultValue = TrayPalette(appearance: .graphite)
}

extension EnvironmentValues {
    var trayPalette: TrayPalette {
        get { self[TrayPaletteKey.self] }
        set { self[TrayPaletteKey.self] = newValue }
    }
}
