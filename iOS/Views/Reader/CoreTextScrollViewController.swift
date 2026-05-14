import Combine
import UIKit

/// Renders CoreTextScrollEngine into a vertical UITableView.
final class CoreTextScrollViewController: UIViewController, UIEditMenuInteractionDelegate {

    // MARK: - Inputs

    private let engine: CoreTextScrollEngine
    private var horizontalInset: CGFloat
    private var verticalInset: CGFloat
    /// Progress callback: (chapter, charOffset, percentage) for the topmost visible chunk.
    var onProgressChange: ((Int, Int, Double) -> Void)?
    /// Tap callback: notifies the parent to toggle top/bottom bars.
    var onTap: (() -> Void)?

    // MARK: - State

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var cancellables: Set<AnyCancellable> = []
    private var pendingInitialScroll: (chapter: Int, charOffset: Int)?
    private var hasAppliedInitialScroll = false
    private var hasKickedOffEngine = false
    private var pendingInitialChapter: Int = 0
    private var pendingInitialCharOffset: Int = 0
    private var displayedCount: Int = 0

    // Text selection state
    private var selectionChapter: Int?
    private var anchorIndex: Int?
    private var focusIndex: Int?
    private var selectedText: String?

    // MARK: - Init

    init(engine: CoreTextScrollEngine,
         horizontalInset: CGFloat,
         verticalInset: CGFloat,
         backgroundColor: UIColor) {
        self.engine = engine
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = backgroundColor
        tableView.backgroundColor = backgroundColor
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var editMenuInteraction: UIEditMenuInteraction = {
        UIEditMenuInteraction(delegate: self)
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addInteraction(editMenuInteraction)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInsetAdjustmentBehavior = .never
        // Use precise heightForRowAt instead of self-sizing for exact layout control.
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.register(CoreTextChunkCell.self, forCellReuseIdentifier: CoreTextChunkCell.reuseIdentifier)
        tableView.contentInset = UIEdgeInsets(top: verticalInset, left: 0, bottom: verticalInset, right: 0)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.cancelsTouchesInView = false
        tableView.addGestureRecognizer(longPress)

        bindEngine()
    }

    override var canBecomeFirstResponder: Bool { true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(copy(_:)) && (selectedText?.isEmpty == false)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        nil
    }

    @objc override func copy(_ sender: Any?) {
        guard let text = selectedText, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    @objc private func handleTap() {
        if anchorIndex != nil || focusIndex != nil {
            clearSelection()
            return
        }
        onTap?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: tableView)
        switch gesture.state {
        case .began:
            guard let (cell, chunk, localPoint) = hitTestChunk(at: point) else {
                clearSelection()
                return
            }
            guard let idx = chunk.stringIndex(atLocalPoint: localPoint) else { return }
            selectionChapter = chunk.chapterIndex
            anchorIndex = idx
            focusIndex = idx
            refreshSelectionOverlays()
            _ = cell // suppress unused warning
        case .changed:
            guard let chapter = selectionChapter,
                  let (_, chunk, localPoint) = hitTestChunk(at: point),
                  chunk.chapterIndex == chapter,
                  let idx = chunk.stringIndex(atLocalPoint: localPoint) else { return }
            focusIndex = idx
            refreshSelectionOverlays()
        case .ended:
            updateSelectedText()
            guard let text = selectedText, !text.isEmpty else { clearSelection(); return }
            becomeFirstResponder()
            let menuRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
            let viewPoint = tableView.convert(menuRect.origin, to: view)
            editMenuInteraction.presentEditMenu(with: UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: viewPoint))
            _ = text
        case .cancelled, .failed:
            clearSelection()
        default:
            break
        }
    }

    private func hitTestChunk(at pointInTableView: CGPoint) -> (cell: CoreTextChunkCell, chunk: CoreTextChunk, localPoint: CGPoint)? {
        guard let path = tableView.indexPathForRow(at: pointInTableView),
              let cell = tableView.cellForRow(at: path) as? CoreTextChunkCell,
              let chunk = cell.currentChunk else { return nil }
        let local = tableView.convert(pointInTableView, to: cell.drawView)
        return (cell, chunk, local)
    }

    private var currentSelectionRange: NSRange? {
        guard let a = anchorIndex, let f = focusIndex else { return nil }
        let start = min(a, f)
        let end = max(a, f)
        return NSRange(location: start, length: end - start + 1)
    }

    private func refreshSelectionOverlays() {
        let chapter = selectionChapter
        let range = currentSelectionRange
        for cell in tableView.visibleCells.compactMap({ $0 as? CoreTextChunkCell }) {
            if let chapter = chapter {
                cell.applySelection(chapterIndex: chapter, chapterRange: range)
            } else {
                cell.applySelection(chapterIndex: -1, chapterRange: nil)
            }
        }
    }

    private func updateSelectedText() {
        guard let chapter = selectionChapter,
              let range = currentSelectionRange,
              range.length > 0 else { selectedText = nil; return }
        // The chapter-level attributedString is shared across all chunks of the same chapter.
        if let chunk = engine.chunks.first(where: { $0.chapterIndex == chapter }) {
            let s = chunk.attributedString
            guard range.location + range.length <= s.length else { selectedText = nil; return }
            selectedText = (s.string as NSString).substring(with: range)
        } else {
            selectedText = nil
        }
    }

    private func clearSelection() {
        selectionChapter = nil
        anchorIndex = nil
        focusIndex = nil
        selectedText = nil
        refreshSelectionOverlays()
        editMenuInteraction.dismissMenu()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        kickoffEngineIfNeeded()
    }

    private func kickoffEngineIfNeeded() {
        guard !hasKickedOffEngine else { return }
        let width = view.bounds.width - 2 * horizontalInset
        guard width > 0 else { return }
        hasKickedOffEngine = true
        let chapter = pendingInitialChapter
        print("[ScrollEngine] kickoff(VC) width=\(width) chapter=\(chapter)")
        Task { [weak self] in
            guard let self = self else { return }
            await self.engine.start(initialChapter: chapter, contentWidth: width)
        }
    }

    // MARK: - Engine binding

    private func bindEngine() {
        engine.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                self?.handle(event: event)
            }
            .store(in: &cancellables)

        // If chunks already exist (e.g., reused engine), sync immediately.
        displayedCount = engine.chunks.count
        if !engine.chunks.isEmpty {
            tableView.reloadData()
        }
    }

    private func handle(event: CoreTextScrollEngine.Event) {
        switch event {
        case .reset:
            displayedCount = engine.chunks.count
            tableView.reloadData()
        case .insertedAtBottom(let count, _):
            let total = engine.chunks.count
            let expectedOld = max(0, total - count)
            // Calculate delta from actual displayedCount vs chunks.count to avoid races.
            let actualOld = displayedCount
            guard actualOld == expectedOld else {
                // Mismatch: reload as a safety net.
                displayedCount = total
                tableView.reloadData()
                applyPendingInitialScrollIfPossible()
                return
            }
            let paths = (actualOld..<total).map { IndexPath(row: $0, section: 0) }
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                displayedCount = total
                tableView.insertRows(at: paths, with: .none)
                tableView.endUpdates()
            }
        case .insertedAtTop(let count, let addedHeight, _):
            let total = engine.chunks.count
            let actualOld = displayedCount
            guard actualOld + count == total else {
                displayedCount = total
                tableView.reloadData()
                applyPendingInitialScrollIfPossible()
                return
            }
            let beforeOffset = tableView.contentOffset
            let paths = (0..<count).map { IndexPath(row: $0, section: 0) }
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                displayedCount = total
                tableView.insertRows(at: paths, with: .none)
                tableView.endUpdates()
                tableView.setContentOffset(
                    CGPoint(x: beforeOffset.x, y: beforeOffset.y + addedHeight),
                    animated: false
                )
            }
        }

        applyPendingInitialScrollIfPossible()
    }

    // MARK: - Public

    /// Sets the initial scroll position (chapter + char offset). Takes effect once the engine has sliced the target chapter.
    func setInitialPosition(chapter: Int, charOffset: Int) {
        pendingInitialScroll = (chapter, charOffset)
        pendingInitialChapter = chapter
        applyPendingInitialScrollIfPossible()
    }

    /// Updates horizontal/vertical insets, triggers a reslice if the width changed.
    func updateInsets(horizontal: CGFloat, vertical: CGFloat) {
        let widthChanged = abs(horizontal - horizontalInset) > 0.5
        horizontalInset = horizontal
        verticalInset = vertical
        tableView.contentInset = UIEdgeInsets(top: vertical, left: 0, bottom: vertical, right: 0)
        if widthChanged {
            requestReslice(at: visibleTopChapter())
        } else {
            displayedCount = engine.chunks.count
            tableView.reloadData()
        }
    }

    /// Reslices text when font size, line height, spacing, paragraph spacing, or theme changes.
    func requestReslice(at chapter: Int) {
        let width = view.bounds.width - 2 * horizontalInset
        guard width > 0 else { return }
        Task { [weak self] in
            guard let self = self else { return }
            self.hasAppliedInitialScroll = false
            self.pendingInitialScroll = (chapter, 0)
            await self.engine.reslice(restoreAt: chapter, contentWidth: width)
        }
    }

    private func visibleTopChapter() -> Int {
        let chunks = engine.chunks
        guard !chunks.isEmpty else { return pendingInitialChapter }
        let y = max(0, tableView.contentOffset.y + tableView.adjustedContentInset.top)
        if let path = tableView.indexPathForRow(at: CGPoint(x: 0, y: y)),
           path.row < chunks.count {
            return chunks[path.row].chapterIndex
        }
        return chunks.first?.chapterIndex ?? 0
    }

    func updateBackgroundColor(_ color: UIColor) {
        view.backgroundColor = color
        tableView.backgroundColor = color
    }

    private func applyPendingInitialScrollIfPossible() {
        guard !hasAppliedInitialScroll, let target = pendingInitialScroll else { return }
        guard let row = engine.chunkIndex(forChapter: target.chapter, charOffset: target.charOffset) else { return }
        guard row < engine.chunks.count else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
            self.hasAppliedInitialScroll = true
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension CoreTextScrollViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayedCount
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < engine.chunks.count else { return 0 }
        let chunk = engine.chunks[indexPath.row]
        return chunk.height + chapterTopSpacing(for: indexPath.row)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CoreTextChunkCell.reuseIdentifier, for: indexPath)
        if let chunkCell = cell as? CoreTextChunkCell, indexPath.row < engine.chunks.count {
            chunkCell.bind(
                chunk: engine.chunks[indexPath.row],
                horizontalInset: horizontalInset,
                topSpacing: chapterTopSpacing(for: indexPath.row)
            )
        }
        return cell
    }

    /// Returns the visual gap (in points) between chapters. The first chunk and consecutive same-chapter chunks get 0.
    private func chapterTopSpacing(for row: Int) -> CGFloat {
        guard row > 0, row < engine.chunks.count else { return 0 }
        let curr = engine.chunks[row].chapterIndex
        let prev = engine.chunks[row - 1].chapterIndex
        return curr != prev ? CoreTextScrollViewController.chapterGap : 0
    }

    static let chapterGap: CGFloat = 56

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard indexPath.row < engine.chunks.count else { return }
        engine.chunks[indexPath.row].materializeFrameIfNeeded()
        // Restore selection highlight when scrolling to a new cell.
        if let chunkCell = cell as? CoreTextChunkCell, let chapter = selectionChapter {
            chunkCell.applySelection(chapterIndex: chapter, chapterRange: currentSelectionRange)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let chunks = engine.chunks
        guard !chunks.isEmpty else { return }

        // Prefetch: when remaining content is less than 1.5 screen heights, load the next chapter.
        let remaining = scrollView.contentSize.height - (scrollView.contentOffset.y + scrollView.bounds.height)
        if remaining < scrollView.bounds.height * 1.5,
           let lastChapter = chunks.last?.chapterIndex {
            engine.ensureChapterAhead(of: lastChapter)
        }
        if scrollView.contentOffset.y < scrollView.bounds.height * 1.5,
           let firstChapter = chunks.first?.chapterIndex {
            engine.ensureChapterBehind(of: firstChapter)
        }

        // Progress: report based on the topmost visible chunk.
        let visibleY = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        if let topPath = tableView.indexPathForRow(at: CGPoint(x: 0, y: max(0, visibleY))),
           topPath.row < chunks.count {
            let chunk = chunks[topPath.row]
            let total = max(1, engine.chapterCount)
            let pct = Double(chunk.chapterIndex) / Double(total - 1 == 0 ? 1 : total - 1)
            onProgressChange?(chunk.chapterIndex, chunk.charRange.location, min(1, max(0, pct)))
        }
    }
}
