import AVFoundation
import Combine
import Foundation
import MediaPlayer
import os.log
import UIKit

// MARK: - Audiobook sleep timer option

enum AudiobookSleepOption: Equatable {
    case off
    case minutes(Int)
    case endOfChapter
}

// MARK: - Audiobook playback coordinator
//
// The single brain for audiobook (有聲書) playback. It is a long-lived singleton
// so that audio keeps playing — with lock-screen / Control-Center controls — after
// the player page is dismissed, exactly like the EPUB inline-video manager and TTS.
//
// Responsibilities: hold the current book's chapter context, ask a
// `ChapterAudioProvider` for a playable chapter audio asset, drive an `AVQueuePlayer`,
// move on at the end of a chapter, expose prev/next/seek/rate/sleep, publish
// NowPlaying info + handle remote commands, and persist `(audioChapterIndex,
// audioTimeSeconds)`.
//
// Chapter changes are where playback used to die with the screen locked. iOS keeps a
// background-audio app running only while it is producing audio; the old player
// started resolving the next chapter's link when the current one ended, so there was
// no audio exactly while that request ran, the app was suspended mid-request, and the
// listener came back to a spinner that ended in a timeout. The transition now follows
// what Apple and long-form players do, in three layers:
//
// 1. Look-ahead (legado `ResourceUrlPreloader`): as soon as a chapter's link is ready,
//    the links of the chapters on either side are resolved (`AudiobookResourcePreloader`).
// 2. Play queue (AVFoundation's own tool for this, WWDC16 "Advances in AVFoundation
//    Playback"): the resolved next chapter goes into the `AVQueuePlayer` queue, so
//    AVFoundation prerolls it before the current chapter ends and switches to it
//    without the app doing anything — the audio never stops, so the app is never
//    suspended.
// 3. Background task (Apple "Extending your app's background execution time"; Pocket
//    Casts does the same at every episode change): any switch the app has to drive
//    itself — a jump, a look-ahead that failed, a link that had to be resolved again —
//    holds a background task until the new chapter is audibly playing.
//
// A link that fails to play is resolved again once, silently, before an error is
// shown (legado `AudioPlaySession.onPlayerError`): most links are time-signed, and a
// look-ahead makes a link older by the time it plays.

@MainActor
final class AudiobookPlayer: NSObject, ObservableObject {

    static let shared = AudiobookPlayer()

    private struct CoverFallback {
        let urlString: String
        let sourceBaseURL: String?
        let sourceHeaders: [String: String]
    }

    /// One chapter's item in the play queue.
    private final class QueueEntry {
        var chapterIndex: Int
        var audio: ChapterAudio
        let item: AVPlayerItem
        /// Start playing once the item is ready. Items the queue advances to inherit the
        /// player's rate instead.
        let autoPlay: Bool
        var observers: Set<AnyCancellable> = []

        init(chapterIndex: Int, audio: ChapterAudio, item: AVPlayerItem, autoPlay: Bool) {
            self.chapterIndex = chapterIndex
            self.audio = audio
            self.item = item
            self.autoPlay = autoPlay
        }
    }

    // MARK: - Published State (bound to AudiobookReaderView)

    @Published private(set) var bookId: UUID?
    @Published private(set) var bookTitle: String = ""
    @Published private(set) var coverImage: UIImage?
    @Published private(set) var chapters: [OnlineChapterRef] = []
    @Published private(set) var chapterIndex: Int = 0
    @Published private(set) var currentChapterTitle: String = ""

    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var error: String? = nil
    @Published var playbackRate: Float = 1.0
    @Published var sleepOption: AudiobookSleepOption = .off

    // MARK: - Context

    private weak var store: BookStore?
    private var activeBook: ReadingBook?
    private var persistsPositionInStore = true
    private var coverFallbacks: [UUID: CoverFallback] = [:]
    private let onlineChapterAudioProvider: ChapterAudioProvider
    private let localChapterAudioProvider: ChapterAudioProvider
    private let preloader = AudiobookResourcePreloader()

    // MARK: - Engine

    private var player: AVQueuePlayer?
    private var playerObservers: Set<AnyCancellable> = []
    private var timeObserverToken: Any?
    private var boundaryObserverToken: Any?
    /// The chapter the player is on.
    private var currentEntry: QueueEntry?
    /// The next chapter, handed to AVFoundation ahead of time.
    private var queuedEntry: QueueEntry?
    /// The look-ahead's result for the chapter after `currentEntry`, kept so the queue can
    /// be refilled when the sleep timer stops holding it back.
    private var resolvedNext: (chapterIndex: Int, audio: ChapterAudio)?
    private var loadToken = UUID()
    private var pendingResumeTime: TimeInterval = 0
    private var didSeekForResume = false
    private var lastPersist: Date = .distantPast
    private var loadedRuntimeVariables: [String: String]?
    private var chapterStartSeconds: TimeInterval = 0
    private var chapterDurationOverride: TimeInterval?
    private var chapterFinishHandled = false
    /// legado `hasRefreshedOnPlayError`: one silent re-resolve per failure, re-armed
    /// whenever an item becomes ready.
    private var hasRefreshedOnPlayError = false
    private var transitionBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Sleep timer

    private var sleepTimer: Timer?
    private var stopAtChapterEnd = false

    // MARK: - Remote commands

    private var remoteCommandsConfigured = false

    private override init() {
        self.onlineChapterAudioProvider = OnlineChapterAudioProvider()
        self.localChapterAudioProvider = LocalChapterAudioProvider()
        super.init()
    }

    // MARK: - Public lifecycle

    /// Whether a given book is the one currently loaded into the coordinator.
    func isActive(bookId id: UUID) -> Bool { bookId == id }

    func prepareCoverFallback(
        bookId: UUID,
        coverUrl: String,
        sourceBaseURL: String?,
        sourceHeaders: [String: String]
    ) {
        let trimmed = coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fallback = CoverFallback(
            urlString: trimmed,
            sourceBaseURL: sourceBaseURL,
            sourceHeaders: sourceHeaders
        )
        coverFallbacks[bookId] = fallback
        if self.bookId == bookId, coverImage == nil {
            loadRemoteCoverIfNeeded(for: bookId, fallback: fallback)
        }
    }

    /// Attach to (or start) playback for a book. If the same book is already
    /// loaded, keep the live session unless the stored chapters/runtime changed.
    func start(book: ReadingBook, store: BookStore) {
        start(book: book, store: store, persistsPositionInStore: true)
    }

    /// Start playback from a detail-page book that has not been added to the bookshelf.
    /// Progress is intentionally kept in-memory so this path does not create or mutate
    /// a `BookStore.books` entry.
    func startTransient(book: ReadingBook, store: BookStore) {
        start(book: book, store: store, persistsPositionInStore: false)
    }

    private func start(
        book: ReadingBook,
        store: BookStore,
        persistsPositionInStore: Bool
    ) {
        self.store = store
        self.activeBook = book
        self.persistsPositionInStore = persistsPositionInStore
        if bookId == book.id, player != nil {
            refreshActiveBookIfNeeded(book)
            NowPlayingHub.shared.attachAudiobook(self)
            audiobookLog("start: already active book=\(book.title) — attaching to live session")
            return
        }

        // Take over the audio session from any active TTS narration (audiobook only
        // displaces TTS, never another audiobook).
        NowPlayingHub.shared.stopTTSIfActive()

        stopInternal()
        error = nil

        bookId = book.id
        bookTitle = book.title
        coverImage = Self.loadCover(book.coverImagePath)
        if coverImage == nil, let fallback = coverFallbacks[book.id] {
            loadRemoteCoverIfNeeded(for: book.id, fallback: fallback)
        }
        loadedRuntimeVariables = book.runtimeVariables

        chapters = book.onlineChapters ?? []
        let restoredIndex = min(max(0, book.audioChapterIndex), max(0, chapters.count - 1))
        chapterIndex = restoredIndex
        pendingResumeTime = max(0, book.audioTimeSeconds)

        configureRemoteCommandsIfNeeded()
        activateAudioSession()

        NowPlayingHub.shared.attachAudiobook(self)
        audiobookLog("start: book=\(book.title) chapters=\(chapters.count) restoreCh=\(restoredIndex) resumeT=\(pendingResumeTime)")
        loadCurrentChapter(autoPlay: true)
    }

    private func refreshActiveBookIfNeeded(_ book: ReadingBook) {
        let updatedChapters = book.onlineChapters ?? []
        guard activeBookNeedsRefresh(updatedChapters: updatedChapters, runtimeVariables: book.runtimeVariables) else {
            return
        }

        let shouldAutoplay = isPlaying || error != nil
        chapters = updatedChapters
        loadedRuntimeVariables = book.runtimeVariables
        if !chapters.indices.contains(chapterIndex) {
            chapterIndex = min(max(0, book.audioChapterIndex), max(0, chapters.count - 1))
        }
        pendingResumeTime = max(0, book.audioTimeSeconds)
        currentTime = 0
        duration = 0
        audiobookLog("start: refreshed active book=\(book.title) chapters=\(chapters.count)")
        loadCurrentChapter(autoPlay: shouldAutoplay)
    }

    private func activeBookNeedsRefresh(
        updatedChapters: [OnlineChapterRef],
        runtimeVariables: [String: String]?
    ) -> Bool {
        guard !updatedChapters.isEmpty else { return false }
        if loadedRuntimeVariables != runtimeVariables { return true }
        if chapters.count != updatedChapters.count { return true }
        return zip(chapters, updatedChapters).contains { old, new in
            old.index != new.index
                || old.title != new.title
                || old.url != new.url
                || old.runtimeVariables != new.runtimeVariables
                || old.audioStartSeconds != new.audioStartSeconds
                || old.audioDurationSeconds != new.audioDurationSeconds
        }
    }

    func play() {
        guard player != nil else { return }
        catchUpWithQueue()
        player?.rate = playbackRate
        isPlaying = true
        startSleepTimerIfNeeded()
        updateNowPlaying()
    }

    func pause() {
        catchUpWithQueue()
        player?.pause()
        isPlaying = false
        endTransitionBackgroundTask(reason: "paused")
        persistPosition(force: true)
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isLoading { return }
        if isPlaying { pause() } else { play() }
    }

    func stop() {
        persistPosition(force: true)
        stopInternal()
        deactivateAudioSession()
        bookId = nil
        chapters = []
        currentChapterTitle = ""
        bookTitle = ""
        coverImage = nil
        activeBook = nil
        persistsPositionInStore = true
        loadedRuntimeVariables = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        isLoading = false
        cancelSleepTimer()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Seeking

    /// - Parameter chapter: the chapter `time` was read from — the slider passes the one it
    ///   was scrubbing. A position on one chapter's timeline means nothing on the next one's:
    ///   a slider released at the end finishes the chapter, and a request arriving after the
    ///   queue has moved on would otherwise land on the new chapter and finish that one too.
    func seek(to time: TimeInterval, inChapter chapter: Int? = nil) {
        audiobookLog("seek request t=\(time) for=\(chapter.map(String.init) ?? "-") ch=\(chapterIndex) current=\(currentTime) duration=\(duration)")
        catchUpWithQueue()
        if let chapter, chapter != chapterIndex {
            audiobookLog("seek dropped: made for ch=\(chapter), now on ch=\(chapterIndex)")
            return
        }
        let clamped = max(0, min(time, duration > 0 ? duration : time))
        seekWithinCurrentChapter(to: clamped)
        persistPosition(force: true)
        updateNowPlaying()
    }

    func skipForward(_ seconds: Double = 15) {
        catchUpWithQueue()
        seek(to: currentTime + seconds)
    }

    func skipBackward(_ seconds: Double = 15) {
        catchUpWithQueue()
        seek(to: currentTime - seconds)
    }

    // MARK: - Rate

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player?.rate = rate }
        updateNowPlaying()
    }

    // MARK: - Chapter navigation

    func selectChapter(_ index: Int) {
        catchUpWithQueue()
        guard chapters.indices.contains(index), index != chapterIndex else { return }
        // Already queued and prerolled: let AVFoundation switch, as it does at a chapter
        // end, instead of resolving and loading the chapter a second time.
        if let queued = queuedEntry, queued.chapterIndex == index,
           queued.item.status != .failed, let player {
            player.advanceToNextItem()
            adoptQueuedEntry(queued, reason: "select")
            player.rate = playbackRate
            isPlaying = true
            updateNowPlaying()
            return
        }
        chapterIndex = index
        pendingResumeTime = 0
        loadCurrentChapter(autoPlay: true)
    }

    func nextChapter() {
        catchUpWithQueue()
        guard chapterIndex + 1 < chapters.count else { return }
        selectChapter(chapterIndex + 1)
    }

    func previousChapter() {
        catchUpWithQueue()
        guard chapterIndex - 1 >= 0 else { return }
        selectChapter(chapterIndex - 1)
    }

    /// The error card's 重試: resolve the current chapter's link afresh and play it from
    /// where it stopped. (It used to call `selectChapter(chapterIndex)`, which returns at
    /// once for the chapter that is already selected — the button did nothing.)
    func retryCurrentChapter() {
        catchUpWithQueue()
        guard chapters.indices.contains(chapterIndex) else { return }
        if let book = currentBook(), let store {
            chapterAudioProvider(for: book).discardResolvedAudio(
                for: book, chapterIndex: chapterIndex, store: store)
        }
        hasRefreshedOnPlayError = false
        pendingResumeTime = resumePositionForReload()
        loadCurrentChapter(autoPlay: true)
    }

    var hasNextChapter: Bool { chapterIndex + 1 < chapters.count }
    var hasPreviousChapter: Bool { chapterIndex - 1 >= 0 }

    // MARK: - Sleep timer

    func setSleepOption(_ option: AudiobookSleepOption) {
        catchUpWithQueue()
        sleepOption = option
        cancelSleepTimer()
        stopAtChapterEnd = false
        switch option {
        case .off:
            break
        case .endOfChapter:
            stopAtChapterEnd = true
        case .minutes(let m) where m > 0:
            sleepTimer = Timer.scheduledTimer(
                withTimeInterval: TimeInterval(m * 60), repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSleepFired() }
            }
        default:
            break
        }
        // A queued chapter would play on by itself at the chapter end.
        if stopAtChapterEnd {
            dequeueNext(reason: "sleep at chapter end")
        } else {
            enqueueNextIfReady()
        }
        audiobookLog("sleep option=\(option)")
    }

    private func startSleepTimerIfNeeded() {
        // Minute-based timers are absolute from when they were set; nothing to do
        // on resume. End-of-chapter is handled when the item finishes.
    }

    private func handleSleepFired() {
        pause()
        sleepOption = .off
    }

    private func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
    }

    // MARK: - Chapter loading

    /// Resolves the current chapter and plays it: the path for everything the queue does
    /// not cover — opening a book, a jump, a chapter end with nothing queued, a retry.
    private func loadCurrentChapter(autoPlay: Bool) {
        guard let store, chapters.indices.contains(chapterIndex) else {
            error = localized("未找到音訊")
            return
        }
        guard let book = currentBook() else { return }

        let index = chapterIndex
        // legado `loadPlayUrl`: a volume heading has no audio; move on to the next chapter.
        if chapters[index].shouldRenderAsVolumeSeparator, hasNextChapter {
            audiobookLog("loadChapter ch=\(index) is a volume heading — skipping")
            chapterIndex = index + 1
            pendingResumeTime = 0
            loadCurrentChapter(autoPlay: autoPlay)
            return
        }

        currentChapterTitle = chapters[index].title
        isLoading = true
        error = nil
        let token = UUID()
        loadToken = token
        didSeekForResume = false
        if autoPlay {
            // Held until the chapter is audibly playing; see the type comment.
            beginTransitionBackgroundTask(reason: "load ch=\(index)")
        }
        // legado cancels its look-ahead before resolving the chapter the listener asked
        // for: both use the same source, and running them side by side slows this one.
        preloader.cancel()
        resolvedNext = nil
        dequeueNext(reason: "load ch=\(index)")
        if book.isOnline, let player, player.timeControlStatus != .paused {
            // legado `stopPlay()`: an online chapter is a separate stream, so the chapter
            // being left stops now rather than playing on under the new chapter's title
            // (and being saved as its position) while the new link resolves. Local books
            // keep playing: another chapter of the same file continues from this item.
            player.pause()
            currentTime = pendingResumeTime
            duration = 0
        }
        updateNowPlaying()

        let provider = chapterAudioProvider(for: book)
        Task { [weak self] in
            guard let self else { return }
            if book.isOnline {
                await ChapterFetchManager.shared.cancelLowPriority(for: book.id, keepPriority: .immediate)
            }
            do {
                let audio = try await provider.audio(
                    for: book,
                    chapterIndex: index,
                    priority: .immediate,
                    store: store
                )
                guard self.loadToken == token else { return }
                audiobookLog("loadChapter ch=\(index) audioURL=\(audio.url.absoluteString)")
                self.play(audio: audio, chapterIndex: index, autoPlay: autoPlay)
                // legado: once the current chapter is ready, look at its neighbours.
                self.preloadNeighbors(of: index, book: book, store: store)
            } catch {
                guard self.loadToken == token else { return }
                self.handleLoadFailure(error, chapterIndex: index, book: book, store: store)
            }
        }
    }

    private func handleLoadFailure(
        _ loadError: Error,
        chapterIndex index: Int,
        book: ReadingBook,
        store: BookStore
    ) {
        if case let .missingAudio(contentLength, preview)? = loadError as? ChapterAudioProviderError {
            audiobookLog("loadChapter ch=\(index) NO AUDIO URL contentLen=\(contentLength) head=\(preview)")
            AppLogger.network(
                "[Audiobook] chapter content is not a playable link",
                context: ["chapter": index, "length": contentLength, "head": String(preview.prefix(120))],
                level: .warning
            )
            // What was fetched is not a link (a quota notice, a login wall, a stale cached
            // answer): legado would hand it to the player, fail, and resolve once more.
            if refreshOnceAfterFailure(chapterIndex: index, book: book, store: store, reason: "not a link") {
                return
            }
        } else {
            audiobookLog("loadChapter ch=\(index) ERROR \(loadError.localizedDescription)")
            AppLogger.network(
                "[Audiobook] could not resolve chapter link",
                error: loadError,
                context: ["chapter": index],
                level: .warning
            )
        }
        isLoading = false
        isPlaying = false
        error = loadError.localizedDescription
        endTransitionBackgroundTask(reason: "load failed")
        updateNowPlaying()
    }

    /// legado `AudioPlaySession.onPlayerError`: the first failure after an item was ready
    /// forgets the chapter's link and resolves it again without telling the listener.
    /// Returns `false` once that chance is used, and the caller reports the failure.
    private func refreshOnceAfterFailure(
        chapterIndex index: Int,
        book: ReadingBook,
        store: BookStore,
        reason: String
    ) -> Bool {
        guard !hasRefreshedOnPlayError, index == chapterIndex else { return false }
        hasRefreshedOnPlayError = true
        AppLogger.info(
            "[Audiobook] re-resolving the chapter link once after a failure",
            context: ["chapter": index, "reason": reason],
            level: .notice
        )
        chapterAudioProvider(for: book).discardResolvedAudio(for: book, chapterIndex: index, store: store)
        pendingResumeTime = resumePositionForReload()
        loadCurrentChapter(autoPlay: true)
        return true
    }

    /// Where a reload of the current chapter should resume: the playhead once the item had
    /// been positioned, otherwise the position it was still waiting to seek to.
    private func resumePositionForReload() -> TimeInterval {
        didSeekForResume ? currentTime : pendingResumeTime
    }

    private func play(audio: ChapterAudio, chapterIndex index: Int, autoPlay: Bool) {
        let startSeconds = max(0, audio.chapterStartSeconds ?? 0)
        let durationOverride = audio.chapterDurationSeconds.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let resumeTime = max(0, pendingResumeTime)

        // Another chapter of the file the player is already on (a local book cut into
        // chapters by time): move within the item instead of reloading it.
        if let entry = currentEntry, entry.audio.url == audio.url,
           let currentPlayer = player,
           entry.item.status == .readyToPlay {
            entry.chapterIndex = index
            entry.audio = audio
            chapterStartSeconds = startSeconds
            chapterDurationOverride = durationOverride
            chapterFinishHandled = false
            didSeekForResume = true
            pendingResumeTime = 0
            isLoading = false
            teardownBoundaryObserver()
            updateDuration()
            installBoundaryObserverIfNeeded(on: currentPlayer)
            seekWithinCurrentChapter(to: resumeTime)
            if autoPlay {
                currentPlayer.rate = playbackRate
                isPlaying = true
            }
            // No item change follows, so nothing else will end the switch's background task.
            endTransitionBackgroundTask(reason: "same file")
            updateNowPlaying()
            audiobookLog("reuse current audio item ch=\(index) start=\(startSeconds) duration=\(durationOverride ?? -1)")
            enqueueNextIfReady()
            return
        }

        let queuePlayer = ensurePlayer()
        dequeueNext(reason: "replace current")
        teardownBoundaryObserver()
        currentEntry?.observers.removeAll()

        let entry = makeEntry(chapterIndex: index, audio: audio, autoPlay: autoPlay)
        // Set before the item goes in, so the `currentItem` observer recognises it.
        currentEntry = entry
        queuePlayer.removeAllItems()
        queuePlayer.actionAtItemEnd = .pause
        queuePlayer.insert(entry.item, after: nil)
        queuePlayer.rate = 0

        chapterStartSeconds = startSeconds
        chapterDurationOverride = durationOverride
        chapterFinishHandled = false
        currentTime = 0
        duration = 0
        observe(entry)
    }

    private func makeEntry(chapterIndex index: Int, audio: ChapterAudio, autoPlay: Bool) -> QueueEntry {
        // 番茄畅听-style URLs have no audio file extension and the CDN's Content-Type
        // is not one AVFoundation recognizes, so a plain AVURLAsset fails with
        // "無法打開". Route those through a resource loader that declares the MIME type
        // out-of-band. Ordinary .mp3/.m4a links keep the plain fast path.
        let asset: AVURLAsset
        if AudioStreamResourceLoader.requiresLoader(for: audio.url),
           let loaderAsset = AudioStreamResourceLoader.makeAsset(url: audio.url, headers: audio.headers) {
            asset = loaderAsset
        } else {
            let options: [String: Any] = audio.headers.isEmpty
                ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": audio.headers]
            asset = AVURLAsset(url: audio.url, options: options)
        }
        return QueueEntry(
            chapterIndex: index,
            audio: audio,
            item: AVPlayerItem(asset: asset),
            autoPlay: autoPlay
        )
    }

    private func ensurePlayer() -> AVQueuePlayer {
        if let player { return player }
        let queuePlayer = AVQueuePlayer()
        queuePlayer.actionAtItemEnd = .pause
        player = queuePlayer

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = queuePlayer.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self, self.isPlaying, !self.isLoading,
                      self.player?.currentItem === self.currentEntry?.item else { return }
                self.updateDuration()
                let relative = max(0, time.seconds - self.chapterStartSeconds)
                self.currentTime = min(relative, self.duration > 0 ? self.duration : relative)
                if let limit = self.chapterDurationOverride, relative > limit + 0.75 {
                    self.finishCurrentChapterIfNeeded()
                    return
                }
                self.persistPosition(force: false)
            }
        }

        // The queue moving on by itself at a chapter end.
        queuePlayer.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in self?.playerCurrentItemChanged(item) }
            .store(in: &playerObservers)

        // A switch is over once audio is actually coming out.
        queuePlayer.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .playing {
                    self?.endTransitionBackgroundTask(reason: "audio playing")
                }
            }
            .store(in: &playerObservers)

        return queuePlayer
    }

    private func observe(_ entry: QueueEntry) {
        entry.item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak entry] status in
                guard let self, let entry else { return }
                self.itemStatusChanged(entry, status: status)
            }
            .store(in: &entry.observers)

        NotificationCenter.default.publisher(
            for: AVPlayerItem.didPlayToEndTimeNotification, object: entry.item
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak entry] _ in
            guard let self, let entry else { return }
            self.itemDidPlayToEnd(entry)
        }
        .store(in: &entry.observers)

        // A stream that breaks off mid-chapter (legado's iOS host listens for the same
        // notification). Nothing observed it before, so such a chapter just went silent.
        NotificationCenter.default.publisher(
            for: AVPlayerItem.failedToPlayToEndTimeNotification, object: entry.item
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self, weak entry] note in
            guard let self, let entry else { return }
            let failure = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.itemFailed(entry, error: failure)
        }
        .store(in: &entry.observers)
    }

    private func itemStatusChanged(_ entry: QueueEntry, status: AVPlayerItem.Status) {
        if entry === currentEntry {
            switch status {
            case .readyToPlay:
                currentItemBecameReady(entry)
            case .failed:
                itemFailed(entry, error: entry.item.error)
            default:
                break
            }
        } else if entry === queuedEntry {
            switch status {
            case .readyToPlay:
                audiobookLog("queued ch=\(entry.chapterIndex) ready")
            case .failed:
                // Don't let the queue play into a broken item. The chapter end then takes
                // the loading path, which resolves the chapter again.
                AppLogger.network(
                    "[Audiobook] queued next chapter failed to load",
                    error: entry.item.error,
                    context: ["chapter": entry.chapterIndex, "host": entry.audio.url.host ?? "-"],
                    level: .warning
                )
                let failedIndex = entry.chapterIndex
                dequeueNext(reason: "queued item failed")
                resolvedNext = nil
                if let book = currentBook(), let store {
                    chapterAudioProvider(for: book).discardResolvedAudio(
                        for: book, chapterIndex: failedIndex, store: store)
                }
            default:
                break
            }
        }
    }

    private func currentItemBecameReady(_ entry: QueueEntry) {
        isLoading = false
        hasRefreshedOnPlayError = false
        updateDuration()
        teardownBoundaryObserver()
        if let player { installBoundaryObserverIfNeeded(on: player) }
        if !didSeekForResume {
            didSeekForResume = true
            let t = max(0, pendingResumeTime)
            pendingResumeTime = 0
            seekWithinCurrentChapter(to: t)
        }
        if entry.autoPlay {
            player?.rate = playbackRate
            isPlaying = true
        } else if player?.timeControlStatus != .playing {
            endTransitionBackgroundTask(reason: "ready without autoplay")
        }
        updateNowPlaying()
        enqueueNextIfReady()
    }

    private func itemFailed(_ entry: QueueEntry, error failure: Error?) {
        guard entry === currentEntry else {
            if entry === queuedEntry { itemStatusChanged(entry, status: .failed) }
            return
        }
        let message = failure?.localizedDescription ?? localized("未找到音訊")
        audiobookLog("item failed ch=\(entry.chapterIndex): \(message)")
        AppLogger.network(
            "[Audiobook] chapter audio failed to play",
            error: failure,
            context: ["chapter": entry.chapterIndex, "host": entry.audio.url.host ?? "-"],
            level: .warning
        )
        if let book = currentBook(), let store,
           refreshOnceAfterFailure(chapterIndex: entry.chapterIndex, book: book, store: store, reason: "playback") {
            return
        }
        isLoading = false
        isPlaying = false
        error = message
        endTransitionBackgroundTask(reason: "playback failed")
        updateNowPlaying()
    }

    private func itemDidPlayToEnd(_ entry: QueueEntry) {
        audiobookLog("item ended ch=\(entry.chapterIndex) at=\(entry.item.currentTime().seconds) duration=\(entry.item.duration.seconds) current=\(entry === currentEntry)")
        // An item the queue has already moved past.
        guard entry === currentEntry else { return }
        // The queue moves on to the next chapter by itself; `currentItem` reports it.
        if let queued = queuedEntry, player?.items().contains(where: { $0 === queued.item }) == true {
            return
        }
        finishCurrentChapterIfNeeded()
    }

    private func playerCurrentItemChanged(_ item: AVPlayerItem?) {
        guard let item, let queued = queuedEntry, item === queued.item else { return }
        adoptQueuedEntry(queued, reason: "chapter end")
    }

    /// The queue has moved on to the chapter it was holding: bring the coordinator's state
    /// along. Nothing was resolved or loaded here — the item was prerolled while the
    /// previous chapter was still playing.
    private func adoptQueuedEntry(_ entry: QueueEntry, reason: String) {
        queuedEntry = nil
        currentEntry?.observers.removeAll()
        currentEntry = entry
        player?.actionAtItemEnd = .pause
        teardownBoundaryObserver()
        resolvedNext = nil

        chapterIndex = entry.chapterIndex
        currentChapterTitle = chapters.indices.contains(entry.chapterIndex)
            ? chapters[entry.chapterIndex].title : ""
        chapterStartSeconds = max(0, entry.audio.chapterStartSeconds ?? 0)
        chapterDurationOverride = entry.audio.chapterDurationSeconds.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        chapterFinishHandled = false
        pendingResumeTime = 0
        didSeekForResume = true
        currentTime = 0
        duration = 0
        error = nil
        isPlaying = true
        persistPosition(force: true)

        let prerolled = entry.item.status == .readyToPlay
        audiobookLog("advance to queued ch=\(entry.chapterIndex) reason=\(reason) prerolled=\(prerolled)")
        AppLogger.info(
            "[Audiobook] moved to the next chapter from the play queue",
            context: ["chapter": entry.chapterIndex, "reason": reason, "prerolled": prerolled],
            level: .notice
        )
        if player?.timeControlStatus != .playing {
            beginTransitionBackgroundTask(reason: "advance ch=\(entry.chapterIndex)")
        }
        if prerolled {
            currentItemBecameReady(entry)
        } else {
            isLoading = true
            updateNowPlaying()
        }
        if let book = currentBook(), let store {
            preloadNeighbors(of: entry.chapterIndex, book: book, store: store)
        }
    }

    // MARK: - Look-ahead and play queue

    private func preloadNeighbors(of center: Int, book: ReadingBook, store: BookStore) {
        guard center == chapterIndex else { return }
        let indices = AudiobookResourcePreloader.neighborIndices(around: center, chapterCount: chapters.count)
            // legado skips volume headings: they have no audio of their own.
            .filter { !chapters[$0].shouldRenderAsVolumeSeparator }
        let provider = chapterAudioProvider(for: book)
        preloader.preload(
            indices: indices,
            resolve: { index in
                try await provider.audio(for: book, chapterIndex: index, priority: .prefetch, store: store)
            },
            onResolved: { [weak self] index, audio in
                self?.neighborResolved(index, audio: audio, center: center)
            },
            onFailure: { [weak self] index, failure in
                self?.neighborFailed(index, error: failure, book: book, store: store)
            }
        )
    }

    private func neighborResolved(_ index: Int, audio: ChapterAudio, center: Int) {
        guard center == chapterIndex else { return }
        audiobookLog("preload ch=\(index) resolved around ch=\(center)")
        guard index == center + 1 else { return }
        resolvedNext = (index, audio)
        enqueueNextIfReady()
    }

    private func neighborFailed(_ index: Int, error failure: Error, book: ReadingBook, store: BookStore) {
        // legado: a failed look-ahead is logged, never silent, and playback resolves the
        // chapter again when it gets there.
        AppLogger.network(
            "[Audiobook] look-ahead could not resolve chapter link",
            error: failure,
            context: ["chapter": index],
            level: .warning
        )
        if case .missingAudio? = failure as? ChapterAudioProviderError {
            // The answer is cached as the chapter's link; left there, playback would replay
            // it instead of asking the source again.
            chapterAudioProvider(for: book).discardResolvedAudio(for: book, chapterIndex: index, store: store)
        }
    }

    /// Hands the resolved next chapter to AVFoundation, which prerolls it while the current
    /// chapter plays and switches to it at the end.
    private func enqueueNextIfReady() {
        guard let player, let current = currentEntry, let next = resolvedNext,
              next.chapterIndex == current.chapterIndex + 1,
              current.chapterIndex == chapterIndex,
              !stopAtChapterEnd,
              current.item.status != .failed,
              queuedEntry?.chapterIndex != next.chapterIndex,
              // Another chapter of the same file continues from the current item.
              next.audio.url != current.audio.url,
              (next.audio.chapterStartSeconds ?? 0) <= 0
        else { return }

        dequeueNext(reason: "replace queued")
        let entry = makeEntry(chapterIndex: next.chapterIndex, audio: next.audio, autoPlay: false)
        guard player.canInsert(entry.item, after: current.item) else {
            audiobookLog("enqueue ch=\(next.chapterIndex) refused by the queue")
            return
        }
        player.insert(entry.item, after: current.item)
        queuedEntry = entry
        observe(entry)
        player.actionAtItemEnd = .advance
        audiobookLog("queued ch=\(next.chapterIndex) after ch=\(current.chapterIndex)")
    }

    private func dequeueNext(reason: String) {
        guard let queued = queuedEntry else { return }
        queuedEntry = nil
        queued.observers.removeAll()
        player?.remove(queued.item)
        player?.actionAtItemEnd = .pause
        audiobookLog("dequeued ch=\(queued.chapterIndex) reason=\(reason)")
    }

    private func chapterAudioProvider(for book: ReadingBook) -> ChapterAudioProvider {
        book.isOnline ? onlineChapterAudioProvider : localChapterAudioProvider
    }

    private func currentBook() -> ReadingBook? {
        guard let id = bookId else { return nil }
        return store?.books.first(where: { $0.id == id })
            ?? (activeBook?.id == id ? activeBook : nil)
    }

    private func seekWithinCurrentChapter(to relativeTime: TimeInterval) {
        let upperBound = duration > 0 ? duration : relativeTime
        let clamped = max(0, min(relativeTime, upperBound))
        currentTime = clamped
        guard let item = currentEntry?.item else { return }
        guard item.status == .readyToPlay else {
            // An item can't take a seek before it is ready; `currentItemBecameReady` applies it.
            pendingResumeTime = clamped
            didSeekForResume = false
            return
        }
        // Seek the chapter's own item. `AVPlayer.seek` acts on whichever item is current when
        // the seek runs (Apple: "for the current player item"): a seek to a chapter's end let
        // the queue move on first, then landed on the next chapter at the old chapter's end
        // time, and that chapter ended at once — a whole chapter skipped.
        item.seek(
            to: CMTime(seconds: chapterStartSeconds + clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: nil
        )
    }

    /// The queue can move on to the next chapter before its `currentItem` change reaches the
    /// main queue. Anything that acts on "the current chapter" catches up first, so it never
    /// applies the finished chapter's state — its index, its position — to the new one.
    private func catchUpWithQueue() {
        if let queued = queuedEntry, player?.currentItem === queued.item {
            adoptQueuedEntry(queued, reason: "chapter end")
        }
    }

    private func installBoundaryObserverIfNeeded(on player: AVPlayer) {
        guard let chapterDurationOverride, chapterDurationOverride > 0 else { return }
        let boundary = chapterStartSeconds + chapterDurationOverride
        guard boundary.isFinite, boundary > 0 else { return }
        boundaryObserverToken = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: boundary, preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in
                self?.finishCurrentChapterIfNeeded()
            }
        }
    }

    private func finishCurrentChapterIfNeeded() {
        guard !chapterFinishHandled else { return }
        chapterFinishHandled = true
        handleChapterFinished()
    }

    private func handleChapterFinished() {
        currentTime = duration
        persistPosition(force: true)
        if stopAtChapterEnd {
            stopAtChapterEnd = false
            sleepOption = .off
            isPlaying = false
            player?.pause()
            endTransitionBackgroundTask(reason: "sleep at chapter end")
            updateNowPlaying()
            return
        }
        if hasNextChapter {
            audiobookLog("chapter finished → load \(chapterIndex + 1) (nothing queued)")
            AppLogger.info(
                "[Audiobook] chapter ended with nothing queued; loading the next chapter",
                context: ["chapter": chapterIndex + 1],
                level: .notice
            )
            selectChapter(chapterIndex + 1)
        } else {
            isPlaying = false
            player?.pause()
            endTransitionBackgroundTask(reason: "end of book")
            updateNowPlaying()
        }
    }

    // MARK: - Background time across chapter switches

    /// The app is producing no audio from the moment one chapter ends until the next one
    /// plays, and iOS suspends a background-audio app that is not playing. This keeps it
    /// running across that gap — the resolve and the preroll — and no longer.
    private func beginTransitionBackgroundTask(reason: String) {
        guard transitionBackgroundTask == .invalid else { return }
        transitionBackgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Audiobook chapter switch"
        ) { [weak self] in
            self?.transitionBackgroundTimeExpired()
        }
        audiobookLog("background task begin (\(reason)) id=\(transitionBackgroundTask.rawValue)")
    }

    private func endTransitionBackgroundTask(reason: String) {
        guard transitionBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transitionBackgroundTask)
        audiobookLog("background task end (\(reason)) id=\(transitionBackgroundTask.rawValue)")
        transitionBackgroundTask = .invalid
    }

    private func transitionBackgroundTimeExpired() {
        AppLogger.network(
            "[Audiobook] background time ran out before the chapter started playing",
            context: ["chapter": chapterIndex, "loading": isLoading],
            level: .warning
        )
        endTransitionBackgroundTask(reason: "expired")
    }

    // MARK: - Persistence

    private func persistPosition(force: Bool) {
        guard persistsPositionInStore else { return }
        guard let id = bookId else { return }
        if !force, Date().timeIntervalSince(lastPersist) < 10 { return }
        lastPersist = Date()
        store?.updateAudioPosition(
            bookId: id,
            chapter: chapterIndex,
            time: currentTime,
            totalChapters: chapters.count,
            forceSave: force
        )
    }

    // MARK: - Duration

    private func updateDuration() {
        guard let item = currentEntry?.item, item.status == .readyToPlay else { return }
        if let chapterDurationOverride, chapterDurationOverride > 0 {
            duration = chapterDurationOverride
            return
        }
        let d = item.duration.seconds
        if d.isFinite, d > 0 {
            duration = max(0, d - chapterStartSeconds)
        }
    }

    // MARK: - Teardown

    private func teardownBoundaryObserver() {
        if let token = boundaryObserverToken {
            player?.removeTimeObserver(token)
            boundaryObserverToken = nil
        }
    }

    private func teardownPlayerObservers() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        teardownBoundaryObserver()
        playerObservers.removeAll()
        currentEntry?.observers.removeAll()
        queuedEntry?.observers.removeAll()
    }

    private func stopInternal() {
        loadToken = UUID()
        preloader.cancel()
        resolvedNext = nil
        dequeueNext(reason: "stop")
        player?.pause()
        teardownPlayerObservers()
        player?.removeAllItems()
        player = nil
        currentEntry = nil
        chapterStartSeconds = 0
        chapterDurationOverride = nil
        chapterFinishHandled = false
        hasRefreshedOnPlayError = false
        endTransitionBackgroundTask(reason: "stop")
    }

    // MARK: - Audio session

    private func activateAudioSession() {
        UIApplication.shared.beginReceivingRemoteControlEvents()
        // Blocking AVAudioSession calls run off-main (see AudioSessionActivator).
        AudioSessionActivator.activate(category: .playback, mode: .default)
    }

    private func deactivateAudioSession() {
        UIApplication.shared.endReceivingRemoteControlEvents()
        AudioSessionActivator.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Now Playing + Remote commands

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let c = MPRemoteCommandCenter.shared()

        c.playCommand.isEnabled = true
        c.pauseCommand.isEnabled = true
        c.togglePlayPauseCommand.isEnabled = true
        c.nextTrackCommand.isEnabled = true
        c.previousTrackCommand.isEnabled = true
        c.skipForwardCommand.isEnabled = true
        c.skipBackwardCommand.isEnabled = true
        c.skipForwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.preferredIntervals = [15]
        c.changePlaybackPositionCommand.isEnabled = true

        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextChapter() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousChapter() }
            return .success
        }
        c.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward() }
            return .success
        }
        c.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            audiobookLog("remote seek t=\(event.positionTime)")
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = currentChapterTitle.isEmpty ? bookTitle : currentChapterTitle
        info[MPMediaItemPropertyArtist] = bookTitle
        info[MPMediaItemPropertyAlbumTitle] = bookTitle
        if let coverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: coverImage.size) { _ in coverImage }
        }
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = max(duration, 1)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(playbackRate)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    // MARK: - Cover

    private static func loadCover(_ filename: String?) -> UIImage? {
        BookCoverLoader.localImage(filename: filename)
    }

    private func loadRemoteCoverIfNeeded(for id: UUID, fallback: CoverFallback) {
        let headers = BookCoverLoader.headers(
            sourceBaseURL: fallback.sourceBaseURL,
            sourceHeaders: fallback.sourceHeaders
        )
        Task { [weak self] in
            guard let image = await BookCoverLoader.loadImage(
                urlString: fallback.urlString,
                headers: headers
            ) else { return }
            await MainActor.run {
                guard let self, self.bookId == id, self.coverImage == nil else { return }
                self.coverImage = image
            }
        }
    }
}

// MARK: - Logging

/// On-device audiobook playback diagnostics (Console.app, category `audiobook`).
/// Must NOT be `#if DEBUG`-gated: audiobook open failures ("未找到音訊" / AVPlayer
/// "無法打開") only reproduce against live sources on Release/TestFlight builds, and
/// the `item failed:` / `NO AUDIO URL contentLen=… head=…` lines are the only signal
/// for why a specific book (e.g. a VIP 番茄有聲 title) won't play. os_log surfaces in
/// Release; `print` behind `#if DEBUG` is invisible in the field.
/// Decisions that explain a stop — a failed look-ahead, a re-resolve, running out of
/// background time — also go to `AppLogger`, so they reach 設定 → 診斷與回報; those
/// lines carry hosts, never full links (links can carry tokens).
private let audiobookOSLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.yuedu.app", category: "audiobook")

func audiobookLog(_ message: @autoclosure () -> String) {
    let text = message()
    audiobookOSLog.notice("[Audiobook] \(text, privacy: .public)")
}
