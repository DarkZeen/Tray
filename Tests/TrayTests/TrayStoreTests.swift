import Foundation
import Testing

@testable import Tray

/// Shelf behaviour (§70).
///
/// Each test builds its own files in a temporary directory, so nothing here
/// depends on what happens to be on the developer's disk.
@MainActor
struct TrayStoreTests {
    // MARK: - Fixtures

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrayTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("contents".utf8).write(to: url)
        return url
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Adding

    @Test func `an added file lands on the shelf`() throws {
        let store = TrayStore()
        let file = try makeFile("photo.jpg")

        #expect(store.add(file) == .added(store.items.map(\.id)))
        #expect(store.count == 1)
        #expect(store.items.first?.filename == "photo.jpg")
        #expect(store.items.first?.kind == .file)
    }

    @Test func `a folder is recognised as a folder`() throws {
        let store = TrayStore()
        store.add(try makeFolder("Assets"))

        #expect(store.items.first?.kind == .folder)
    }

    @Test func `newest additions enter on the right`() throws {
        let store = TrayStore()
        store.add(try makeFile("first.txt"))
        store.add(try makeFile("second.txt"))
        store.add(try makeFile("third.txt"))

        #expect(store.items.map(\.filename) == ["first.txt", "second.txt", "third.txt"])
    }

    @Test func `a multi file drop keeps the order it arrived in`() throws {
        let store = TrayStore()
        let urls = try ["a.txt", "b.txt", "c.txt"].map(makeFile)

        store.add(urls)

        #expect(store.items.map(\.filename) == ["a.txt", "b.txt", "c.txt"])
    }

    // MARK: - Duplicates (§52)

    @Test func `dropping the same file twice keeps one entry`() throws {
        let store = TrayStore()
        let file = try makeFile("invoice.pdf")

        store.add(file)
        let second = store.add(file)

        #expect(second == .allDuplicates)
        #expect(store.count == 1)
    }

    @Test func `paths that resolve to the same file count as duplicates`() throws {
        let store = TrayStore()
        let file = try makeFile("report.pdf")
        let roundabout = directory
            .appendingPathComponent("sub")
            .appendingPathComponent("..")
            .appendingPathComponent("report.pdf")

        store.add(file)
        store.add(roundabout)

        #expect(store.count == 1)
    }

    @Test func `the same filename from two places stays two entries`() throws {
        let store = TrayStore()
        let here = try makeFolder("Desktop")
        let there = try makeFolder("Documents")

        let first = here.appendingPathComponent("report.pdf")
        let second = there.appendingPathComponent("report.pdf")
        try Data().write(to: first)
        try Data().write(to: second)

        store.add([first, second])

        #expect(store.count == 2)
    }

    @Test func `a partly duplicate drop adds only what is new`() throws {
        let store = TrayStore()
        let existing = try makeFile("old.txt")
        let fresh = try makeFile("new.txt")

        store.add(existing)
        let outcome = store.add([existing, fresh])

        #expect(store.count == 2)
        if case .added(let ids) = outcome {
            #expect(ids.count == 1)
        } else {
            Issue.record("expected one item to be added, got \(outcome)")
        }
    }

    // MARK: - Removing and reordering

    @Test func `removing takes out exactly one item`() throws {
        let store = TrayStore()
        store.add(try [makeFile("a.txt"), makeFile("b.txt")])
        let target = try #require(store.items.first)

        store.remove(id: target.id)

        #expect(store.items.map(\.filename) == ["b.txt"])
    }

    @Test func `moving an item reorders the shelf`() throws {
        let store = TrayStore()
        store.add(try ["a.txt", "b.txt", "c.txt"].map(makeFile))
        let last = try #require(store.items.last)

        store.move(id: last.id, to: 0)

        #expect(store.items.map(\.filename) == ["c.txt", "a.txt", "b.txt"])
    }

    @Test func `moving past the end clamps instead of crashing`() throws {
        let store = TrayStore()
        store.add(try ["a.txt", "b.txt"].map(makeFile))
        let first = try #require(store.items.first)

        store.move(id: first.id, to: 99)

        #expect(store.items.map(\.filename) == ["b.txt", "a.txt"])
    }

    // MARK: - Invalid input (§80)

    @Test func `a non file URL is refused`() {
        let store = TrayStore()

        #expect(store.add(URL(string: "https://example.com/x.pdf")!) == .nothingUsable)
        #expect(store.isEmpty)
    }

    @Test func `an empty drop is refused`() {
        let store = TrayStore()

        #expect(store.add([]) == .nothingUsable)
    }

    @Test func `the shelf refuses to grow past its capacity`() throws {
        let store = TrayStore()
        let urls = try (0..<TrayStore.capacity).map { try makeFile("file-\($0).txt") }
        store.add(urls)

        #expect(store.count == TrayStore.capacity)
        #expect(store.add(try makeFile("one-too-many.txt")) == .rejectedAtCapacity)
    }

    // MARK: - Files that go away (§52)

    @Test func `a deleted file becomes unavailable rather than vanishing`() throws {
        let store = TrayStore()
        let file = try makeFile("temporary.txt")
        store.add(file)

        try FileManager.default.removeItem(at: file)
        store.refreshAvailability()

        #expect(store.count == 1)
        #expect(store.items.first?.isAvailable == false)
        #expect(store.items.first?.accessibilityLabel.contains("unavailable") == true)
    }

    @Test func `a file that comes back is available again`() throws {
        let store = TrayStore()
        let file = try makeFile("flaky.txt")
        store.add(file)

        try FileManager.default.removeItem(at: file)
        store.refreshAvailability()
        try Data("back".utf8).write(to: file)
        store.refreshAvailability()

        #expect(store.items.first?.isAvailable == true)
    }

    @Test func `contains answers for a URL that was never added`() throws {
        let store = TrayStore()
        store.add(try makeFile("present.txt"))

        #expect(store.contains(url: directory.appendingPathComponent("absent.txt")) == false)
    }
}
