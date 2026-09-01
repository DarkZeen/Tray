import AppKit

/// Decides what a drop means (§38).
///
/// Separated from the view that receives it so the rule that matters most —
/// **a drop stores a reference and never copies, moves or modifies the
/// original file** (§3, §38) — lives in one readable place instead of being
/// implied by the absence of code in a view controller.
struct FileDropHandler {
    let store: TrayStore

    /// The operation advertised back to the drag source.
    ///
    /// `.copy` is the honest answer to macOS's question "what will you do with
    /// this?" — it tells the source that its file stays where it is. The tray
    /// does not even copy; it remembers a URL. There is no drag operation that
    /// means "reference", and `.copy` is the one that leaves the original
    /// untouched.
    static let advertisedOperation: NSDragOperation = .copy

    func canAccept(_ info: any NSDraggingInfo) -> Bool {
        PasteboardFileReader.containsFileURLs(info.draggingPasteboard)
    }

    /// Stashes whatever the drag was carrying.
    ///
    /// Returns the ids of items that actually joined the shelf, so the view can
    /// animate exactly those in and leave the rest alone.
    @discardableResult
    func accept(_ info: any NSDraggingInfo) -> [TrayItem.ID] {
        let urls = PasteboardFileReader.fileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }

        switch store.add(urls) {
        case .added(let ids): return ids
        case .allDuplicates, .rejectedAtCapacity, .nothingUsable: return []
        }
    }
}
