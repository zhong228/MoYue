import AVFoundation
import Combine
import Foundation
import Testing
@testable import yuedu_app

// Chapter transitions of the audiobook player: legado's look-ahead
// (`ResourceUrlPreloader`) and AVFoundation's play queue.

@MainActor
private final class EventLog {
    var events: [String] = []
}

/// Holds a resolve open until the test lets it go.
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private func audio(_ index: Int) -> ChapterAudio {
    ChapterAudio(url: URL(string: "https://example.com/\(index).mp3")!)
}

@Suite("Audiobook look-ahead (legado ResourceUrlPreloader)")
@MainActor
struct AudiobookResourcePreloaderTests {

    @Test("the window is ±1, next chapter first")
    func neighborOrder() {
        #expect(AudiobookResourcePreloader.neighborIndices(around: 5, chapterCount: 10) == [6, 4])
        #expect(AudiobookResourcePreloader.neighborIndices(around: 0, chapterCount: 10) == [1])
        #expect(AudiobookResourcePreloader.neighborIndices(around: 9, chapterCount: 10) == [8])
        #expect(AudiobookResourcePreloader.neighborIndices(around: 0, chapterCount: 1) == [])
    }

    @Test("one chapter at a time, and a failed chapter does not end the round")
    func sequentialAndFailureTolerant() async {
        let preloader = AudiobookResourcePreloader()
        let log = EventLog()
        var inFlight = 0
        var maxInFlight = 0

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var remaining = 2
            func finishOne() {
                remaining -= 1
                if remaining == 0 { done.resume() }
            }
            preloader.preload(
                indices: [6, 4],
                resolve: { index in
                    inFlight += 1
                    maxInFlight = max(maxInFlight, inFlight)
                    defer { inFlight -= 1 }
                    await Task.yield()
                    if index == 6 { throw URLError(.timedOut) }
                    return audio(index)
                },
                onResolved: { index, _ in
                    log.events.append("resolved \(index)")
                    finishOne()
                },
                onFailure: { index, _ in
                    log.events.append("failed \(index)")
                    finishOne()
                }
            )
        }

        #expect(log.events == ["failed 6", "resolved 4"])
        #expect(maxInFlight == 1)
    }

    @Test("a new round supersedes the one in flight")
    func newRoundSupersedesOld() async {
        let preloader = AudiobookResourcePreloader()
        let log = EventLog()
        let gate = Gate()

        preloader.preload(
            indices: [2, 0],
            resolve: { index in
                log.events.append("old start \(index)")
                await gate.wait()
                return audio(index)
            },
            onResolved: { index, _ in log.events.append("old resolved \(index)") },
            onFailure: { index, _ in log.events.append("old failed \(index)") }
        )
        // Let the old round reach its first resolve.
        while !log.events.contains("old start 2") { await Task.yield() }

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            preloader.preload(
                indices: [3],
                resolve: { index in audio(index) },
                onResolved: { index, _ in
                    log.events.append("new resolved \(index)")
                    done.resume()
                },
                onFailure: { index, _ in
                    log.events.append("new failed \(index)")
                    done.resume()
                }
            )
        }

        // The old round's resolve now returns; it must neither report nor move on.
        gate.open()
        for _ in 0..<20 { await Task.yield() }

        #expect(log.events.contains("new resolved 3"))
        #expect(!log.events.contains("old resolved 2"))
        #expect(!log.events.contains("old start 0"))
    }
}

// MARK: - Play queue (real AVFoundation playback of short local files)

@Suite("Audiobook chapter transitions", .serialized)
@MainActor
struct AudiobookChapterTransitionTests {

    /// Chapter ends must be taken by the play queue: the next chapter is already in the
    /// `AVQueuePlayer`, so the player never goes back to "loading" between chapters. The
    /// old player started resolving the next chapter at the end of the current one — the
    /// silent window in which iOS suspends a locked phone's app.
    @Test("chapters advance through the play queue without reloading")
    func chaptersAdvanceWithoutReloading() async throws {
        let folder = "audiobook-transition-\(UUID().uuidString)"
        let folderURL = documentsURL(for: folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        var refs: [OnlineChapterRef] = []
        for index in 0..<3 {
            let relative = "\(folder)/\(index).wav"
            try silenceWAV(seconds: 1.2).write(to: documentsURL(for: relative))
            refs.append(OnlineChapterRef(index: index, title: "Chapter \(index)", url: relative))
        }
        var book = ReadingBook(title: "Transition", source: "local_audio", contentFilename: folder)
        book.contentPipelineKind = .audio
        book.onlineChapters = refs

        let player = AudiobookPlayer.shared
        let store = BookStore(metadataFileURL: tempMetadataURL())
        defer { player.stop() }

        var loadingStates: [Bool] = []
        var chapterIndices: [Int] = []
        var observers: Set<AnyCancellable> = []
        player.$isLoading.sink { loadingStates.append($0) }.store(in: &observers)
        player.$chapterIndex.sink { chapterIndices.append($0) }.store(in: &observers)

        player.startTransient(book: book, store: store)

        // First chapter plays.
        try await waitUntil(timeout: 10) { player.isPlaying && !player.isLoading && player.duration > 0 }
        let loadsBeforeTransitions = loadingStates.filter { $0 }.count

        // Both chapter ends pass.
        try await waitUntil(timeout: 20) { player.chapterIndex == 2 && player.duration > 0 && !player.isLoading }

        #expect(chapterIndices.contains(1))
        #expect(player.error == nil)
        // No chapter end went back through loading.
        #expect(loadingStates.filter { $0 }.count == loadsBeforeTransitions)
    }

    /// Dragging the slider to a chapter's end finishes that chapter, and the next one must
    /// start from its beginning. A seek issued through `AVPlayer` lands on whatever item is
    /// current when it runs: the queue moved on first, the seek hit the next chapter at the
    /// old chapter's end time, that chapter ended at once, and a whole chapter was skipped.
    @Test("seeking to a chapter's end plays the next chapter from its start")
    func seekToChapterEndDoesNotSkipAChapter() async throws {
        let folder = "audiobook-seek-end-\(UUID().uuidString)"
        let folderURL = documentsURL(for: folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        var refs: [OnlineChapterRef] = []
        // The second chapter is shorter than the first, as a seek to the first one's end
        // would be past the end of the second.
        for (index, seconds) in [(0, 6.0), (1, 3.0), (2, 3.0)] {
            let relative = "\(folder)/\(index).wav"
            try silenceWAV(seconds: seconds).write(to: documentsURL(for: relative))
            refs.append(OnlineChapterRef(index: index, title: "Chapter \(index)", url: relative))
        }
        var book = ReadingBook(title: "Seek", source: "local_audio", contentFilename: folder)
        book.contentPipelineKind = .audio
        book.onlineChapters = refs

        let player = AudiobookPlayer.shared
        let store = BookStore(metadataFileURL: tempMetadataURL())
        defer { player.stop() }

        player.startTransient(book: book, store: store)
        // Half a second in, the look-ahead (a local path) has long queued chapter 1.
        try await waitUntil(timeout: 10) {
            player.chapterIndex == 0 && player.isPlaying && player.duration > 0 && player.currentTime >= 0.5
        }

        // Only the changes from here on: the shared player still holds the previous test's
        // chapter when a new subscription starts.
        var chapterIndices: [Int] = []
        var observers: Set<AnyCancellable> = []
        player.$chapterIndex.dropFirst().sink { chapterIndices.append($0) }.store(in: &observers)

        player.seek(to: player.duration)

        try await waitUntil(timeout: 10) { player.chapterIndex == 1 && player.currentTime > 0.8 }
        #expect(player.chapterIndex == 1)
        #expect(!chapterIndices.contains(2))
    }

    /// A slider released at the far end reported "editing ended" again and again at its
    /// maximum; each report used to finish the chapter that was current by then. Requests
    /// made on chapter 0's timeline must not act on chapter 1.
    @Test("repeated end-of-chapter seeks finish only the chapter they were made for")
    func repeatedEndSeeksFinishOnlyTheirChapter() async throws {
        let folder = "audiobook-repeat-seek-\(UUID().uuidString)"
        let folderURL = documentsURL(for: folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        var refs: [OnlineChapterRef] = []
        for (index, seconds) in [(0, 4.0), (1, 4.0), (2, 4.0)] {
            let relative = "\(folder)/\(index).wav"
            try silenceWAV(seconds: seconds).write(to: documentsURL(for: relative))
            refs.append(OnlineChapterRef(index: index, title: "Chapter \(index)", url: relative))
        }
        var book = ReadingBook(title: "Repeat", source: "local_audio", contentFilename: folder)
        book.contentPipelineKind = .audio
        book.onlineChapters = refs

        let player = AudiobookPlayer.shared
        let store = BookStore(metadataFileURL: tempMetadataURL())
        defer { player.stop() }

        player.startTransient(book: book, store: store)
        try await waitUntil(timeout: 10) {
            player.chapterIndex == 0 && player.isPlaying && player.duration > 0 && player.currentTime >= 0.5
        }

        var chapterIndices: [Int] = []
        var observers: Set<AnyCancellable> = []
        player.$chapterIndex.dropFirst().sink { chapterIndices.append($0) }.store(in: &observers)

        let end = player.duration
        for _ in 0..<6 {
            player.seek(to: end, inChapter: 0)
            try await Task.sleep(nanoseconds: 40_000_000)
        }

        try await waitUntil(timeout: 10) { player.chapterIndex == 1 && player.currentTime > 1.0 }
        #expect(player.chapterIndex == 1)
        #expect(!chapterIndices.contains(2))
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("condition not met within \(timeout)s")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

/// PCM silence in a minimal WAV container.
private func silenceWAV(seconds: Double) -> Data {
    let sampleRate: UInt32 = 44_100
    let frames = UInt32(Double(sampleRate) * seconds)
    let dataSize = frames * 2
    var d = Data()
    func u32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
    u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(dataSize)
    d.append(Data(repeating: 0, count: Int(dataSize)))
    return d
}

private func documentsURL(for relativePath: String) -> URL {
    StorageLocations.bookFile(relativePath)
}

private func tempMetadataURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("books-\(UUID().uuidString).json")
}
