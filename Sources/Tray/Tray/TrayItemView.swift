import AppKit
import SwiftUI

/// One item on the shelf (§18, §19, §46).
///
/// A tile, not a row in a file browser. The tray shows what a thing *is* and
/// lets you pick it up; anything more belongs in Finder.
struct TrayItemView: View {
    let item: TrayItem
    let thumbnails: ThumbnailProvider
    let showsFilename: Bool
    let isBeingDragged: Bool

    let onDragBegan: () -> Void
    let onDragEnded: (Bool) -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    let onQuickLook: () -> Void

    @State private var image: NSImage?
    @State private var isHovering = false

    private var displayImage: NSImage {
        image ?? thumbnails.immediateImage(for: item)
    }

    var body: some View {
        VStack(spacing: 5) {
            thumbnail

            if showsFilename {
                Text(item.filename)
                    .font(.system(size: 9.5, weight: .medium))
                    // Slight positive tracking: small type over a translucent
                    // surface needs the extra air to stay legible.
                    .tracking(0.1)
                    .foregroundStyle(.white.opacity(item.isAvailable ? 0.62 : 0.34))
                    .lineLimit(1)
                    // Middle truncation keeps the extension visible, which is
                    // usually the most identifying part of a filename.
                    .truncationMode(.middle)
                    .frame(width: TrayMetrics.itemWidth)
            }
        }
        .frame(width: TrayMetrics.itemWidth)
        .scaleEffect(scale)
        .opacity(isBeingDragged ? 0.32 : 1)
        .animation(TrayAnimation.hover, value: isHovering)
        .animation(TrayAnimation.itemShift, value: isBeingDragged)
        .overlay { interactionLayer }
        .help(item.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .task(id: item.identity) {
            image = await thumbnails.previewImage(
                for: item,
                size: CGSize(width: TrayMetrics.thumbnailSize, height: TrayMetrics.thumbnailSize)
            )
        }
    }

    // MARK: - Pieces

    private var thumbnail: some View {
        Image(nsImage: displayImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: TrayMetrics.thumbnailSize, height: TrayMetrics.thumbnailSize)
            .opacity(item.isAvailable ? 1 : 0.4)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(isHovering ? 0.09 : 0))
                    .padding(-3)
            }
            .overlay(alignment: .bottomTrailing) {
                if !item.isAvailable { unavailableBadge }
            }
            .shadow(color: .black.opacity(isHovering ? 0.28 : 0.18), radius: isHovering ? 6 : 3, y: 2)
    }

    /// The file went away behind our back (§52). Say so quietly; do not remove
    /// the item out from under the user, and do not crash.
    private var unavailableBadge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(red: 0.85, green: 0.4, blue: 0.3))
            .offset(x: 2, y: 2)
    }

    private var scale: CGFloat {
        if isBeingDragged { return TrayScale.itemLifted }
        return isHovering ? TrayScale.itemHover : TrayScale.resting
    }

    private var interactionLayer: some View {
        ItemInteractionLayer(
            item: item,
            onHoverChanged: { isHovering = $0 },
            onDragBegan: onDragBegan,
            onDragEnded: onDragEnded,
            onOpenQuickLook: onQuickLook,
            menuBuilder: buildMenu,
            dragImage: { displayImage }
        )
    }

    /// Three items, and no more (§23). The tray is not Finder.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addAction(title: "Remove from Tray", handler: onRemove)
        menu.addAction(title: "Reveal in Finder", isEnabled: item.isAvailable, handler: onReveal)
        menu.addAction(title: "Quick Look", isEnabled: item.isAvailable, handler: onQuickLook)
        return menu
    }
}
