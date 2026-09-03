import AppKit
import SwiftUI

/// The tray itself (§5, §6, §14, §16, §19, §76, §77).
///
/// One surface, hanging from the top edge of the display, changing shape.
/// There is no branch here that swaps one view for another when the tray
/// opens — the container's width, height and corner radius animate, and the
/// contents cross-fade inside it. That is what makes the open and close read
/// as a single object rather than two views trading places (§16).
struct TrayContentView: View {
    let store: TrayStore
    let presenter: TrayPresenter
    let selection: TraySelection
    let thumbnails: ThumbnailProvider
    let settings: SettingsStore
    let geometry: ScreenGeometry

    let onRemove: (TrayItem) -> Void
    let onCopy: ([TrayItem]) -> Void
    let onClick: (TrayItem, NSEvent.ModifierFlags) -> Void
    let onReveal: (TrayItem) -> Void
    let onQuickLook: (TrayItem) -> Void
    let onItemDragBegan: ([TrayItem]) -> Void
    let onItemDragEnded: ([TrayItem], Bool) -> Void

    /// Reported upward so the AppKit layer can keep its hit regions exactly on
    /// the pixels the user can see (§74).
    let onShapeChange: (TrayShape) -> Void

    /// The viewer's motion preference, read here rather than from a static, so
    /// that switching Reduce Motion takes effect immediately (§50).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            tray
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The tray keeps its own appearance rather than following the system's
        // (§49). Which one it keeps is now the user's choice.
        .environment(\.trayPalette, palette)
        .environment(\.trayMotion, motion)
        .environment(\.colorScheme, palette.colorScheme)
    }

    // MARK: - The surface

    private var tray: some View {
        ZStack {
            // Each layer is pinned to the tray's exact size. Without this the
            // ZStack takes the size of its *largest* child — the open shelf —
            // and the closed layer's `maxHeight: .infinity` then resolves
            // against that instead of against the closed height, which lands
            // the item dots below the tray entirely.
            collapsedContents
                .frame(width: shape.width, height: shape.height)
                .opacity(isOpen ? 0 : 1)

            expandedContents
                .frame(width: shape.width, height: shape.height - shape.notchInset)
                // Everything the shelf shows sits below the camera housing.
                // Nothing drawn under the notch is visible — it is a hole in
                // the display, not a dark rectangle — so without this the top
                // of every thumbnail in the middle of the shelf is missing.
                .padding(.top, shape.notchInset)
                .opacity(isOpen ? 1 : 0)
        }
        .frame(width: shape.width, height: shape.height)
        // Nothing escapes the surface. As well as being correct at rest, this
        // is what makes the collapse read as the shelf closing over its
        // contents rather than the contents sliding out of a shrinking box.
        .clipShape(TraySurface(cornerRadius: shape.cornerRadius))
        .traySurface(
            cornerRadius: shape.cornerRadius,
            topFlare: shape.topFlare,
            isEmphasised: presenter.state.isDropTargetActive,
            showsDropOutline: settings.showsDropOutline && isOpen,
            dropOutlineInset: settings.dropOutlineInset,
            notchInset: shape.notchInset
        )
        // Scaled from the top, because that is where the object is attached.
        // Scaling from the centre would lift it off the edge of the screen.
        .scaleEffect(presenter.containerScale, anchor: .top)
        .animation(containerAnimation, value: shape)
        .animation(motion.appearance, value: palette)
        .animation(motion.hover, value: presenter.state)
        // Anticipation as a drag approaches (§13), and the give as one lands
        // (§46). Both are scale changes on the same property, so they get their
        // own springs rather than borrowing the pointer's.
        .animation(motion.hover, value: presenter.isDragApproaching)
        .animation(motion.dropImpact, value: presenter.isAbsorbingDrop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: shape, initial: true) { _, new in onShapeChange(new) }
    }

    private var palette: TrayPalette { settings.appearance.palette }

    private var motion: TrayMotion { TrayMotion(reduceMotion: reduceMotion) }

    private var isOpen: Bool { presenter.state.isOpen }

    private var shape: TrayShape {
        if isOpen {
            return .expanded(
                screenWidth: geometry.frame.width,
                widthFraction: settings.trayWidthFraction,
                notchHeight: geometry.notchSize?.height ?? 0,
                item: settings.itemMetrics,
                height: settings.trayHeight
            )
        }
        return .collapsed(notchSize: geometry.notchSize, isEmpty: store.isEmpty)
    }

    /// Opening and closing get different springs: leaving should feel calmer
    /// than arriving (§45).
    private var containerAnimation: Animation {
        isOpen ? motion.expand : motion.collapse
    }

    // MARK: - Closed

    /// Closed, the tray says only whether it is holding anything (§76, §77).
    @ViewBuilder
    private var collapsedContents: some View {
        if !store.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<min(store.count, 3), id: \.self) { _ in
                    Circle()
                        .fill(palette.ink(0.55))
                        .frame(width: 4, height: 4)
                }
                if store.count > 3 {
                    Text("\(store.count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.ink(0.55))
                        .padding(.leading, 1)
                }
            }
            .padding(.bottom, geometry.hasNotch ? 4 : 0)
            .frame(maxHeight: .infinity, alignment: geometry.hasNotch ? .bottom : .center)
        }
    }

    // MARK: - Open

    @ViewBuilder
    private var expandedContents: some View {
        if store.isEmpty {
            emptyPrompt
        } else {
            shelf
        }
    }

    /// No permanent onboarding screen (§5). The prompt exists only while the
    /// tray is open and empty, and it changes to an instruction only once a
    /// drag is actually overhead.
    private var emptyPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: presenter.state.isDropTargetActive
                ? "arrow.down.circle.fill"
                : "tray")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(palette.ink(presenter.state.isDropTargetActive ? 0.85 : 0.4))
                .contentTransition(.symbolEffect(.replace))

            Text(presenter.state.isDropTargetActive ? "Release to stash" : "Drop files here")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.ink(presenter.state.isDropTargetActive ? 0.8 : 0.42))
        }
        .animation(motion.hover, value: presenter.state)
    }

    /// A horizontal shelf, never a grid (§19).
    ///
    /// The scroll view appears only once the items stop fitting (§20). While
    /// everything fits — which is nearly always — the row is laid out plainly,
    /// so there is no scroll offset to end up in the wrong place and no chance
    /// of a stray trackpad gesture nudging the shelf sideways.
    @ViewBuilder
    private var shelf: some View {
        if TrayShape.fits(
            itemCount: store.count,
            screenWidth: geometry.frame.width,
            widthFraction: settings.trayWidthFraction,
            item: settings.itemMetrics
        ) {
            itemRow
        } else {
            ScrollView(.horizontal) {
                itemRow
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            // Content dissolves at the edges instead of being cut off mid-icon.
            // A hard edge reads as a rendering mistake; a fade reads as "there
            // is more this way".
            .mask(scrollEdgeMask)
        }
    }

    private var itemRow: some View {
        HStack(spacing: TrayMetrics.itemSpacing) {
            ForEach(store.items) { item in
                TrayItemView(
                    item: item,
                    thumbnails: thumbnails,
                    metrics: settings.itemMetrics,
                    isBeingDragged: presenter.state.draggedItemIDs.contains(item.id),
                    isSelected: selection.contains(item.id),
                    dragTargets: { selectionTargets(for: item) },
                    onDragBegan: onItemDragBegan,
                    onDragEnded: onItemDragEnded,
                    onRemove: { onRemove(item) },
                    onReveal: { onReveal(item) },
                    onQuickLook: { onQuickLook(item) },
                    onClick: { onClick(item, $0) },
                    onCopy: { onCopy(selectionTargets(for: item)) }
                )
                .transition(motion.itemTransition)
            }
        }
        .padding(.horizontal, TrayMetrics.horizontalPadding)
        .padding(.vertical, TrayMetrics.verticalPadding)
        .animation(motion.itemShift, value: store.items.map(\.id))
    }

    private var scrollEdgeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: TrayMetrics.scrollFade / shape.width),
                .init(color: .black, location: 1 - TrayMetrics.scrollFade / shape.width),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Which items an action on `item` applies to.
    ///
    /// The whole selection when this item is part of it, just this one when it
    /// is not — the same rule Finder uses, so acting on an item never silently
    /// narrows or widens what you picked. Copy and drag share it: a selection
    /// of five that copies five but drags one is the kind of inconsistency
    /// nobody can predict.
    private func selectionTargets(for item: TrayItem) -> [TrayItem] {
        guard selection.contains(item.id) else { return [item] }
        return selection.items(from: store.items)
    }

    private var accessibilityLabel: String {
        store.isEmpty
            ? "Tray, empty"
            : "Tray containing \(store.count) item\(store.count == 1 ? "" : "s")"
    }
}
