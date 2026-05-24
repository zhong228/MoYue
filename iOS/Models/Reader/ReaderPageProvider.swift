import UIKit

struct ReaderResolvedPage {
    let pageIndex: Int
    let location: ReaderLocation
    let isPlaceholder: Bool
    let snapshot: UIImage?
}

enum ReaderInvalidationReason: Equatable {
    case viewportChanged(CGSize)
    case appearanceChanged(ReaderAppearance)
    case contentChanged(spineIndex: Int?)
    case directionChanged(ReaderReadingDirection)
}

@MainActor
protocol ReaderPageProvider: AnyObject {
    var totalPages: Int? { get }

    func prepare(viewportSize: CGSize, state: ReaderPresentationState) async
    func resolvePage(at index: Int) async -> ReaderResolvedPage?
    func resolvePage(at location: ReaderLocation) async -> ReaderResolvedPage?
    func adjacentLocation(from location: ReaderLocation, logicalForward: Bool) async -> ReaderLocation?
    func prefetch(around location: ReaderLocation, radius: Int) async
    func invalidateLayout(reason: ReaderInvalidationReason) async
}

@MainActor
final class LegacyCoreTextPageProvider: ReaderPageProvider {
    private let engine: any PageRenderingProvider
    private let bookId: String

    init(engine: any PageRenderingProvider, bookId: String) {
        self.engine = engine
        self.bookId = bookId
    }

    var totalPages: Int? {
        engine.totalPages
    }

    func prepare(viewportSize: CGSize, state: ReaderPresentationState) async {
        if engine.totalPages == 0 || engine.renderSize != viewportSize {
            await engine.start(renderSize: viewportSize, bookId: bookId)
        }
    }

    func resolvePage(at index: Int) async -> ReaderResolvedPage? {
        guard index >= 0, index < engine.totalPages else { return nil }
        let viewController = engine.pageViewController(at: index)
        let position = readingPosition(from: viewController)
            ?? engine.readingPosition(forPage: index)
            ?? CoreTextReadingPosition(
                spineIndex: engine.charOffset(forPage: index).spineIndex,
                charOffset: engine.charOffset(forPage: index).charOffset
            )
        return ReaderResolvedPage(
            pageIndex: index,
            location: ReaderLocation(position),
            isPlaceholder: viewController is PlaceholderPageViewController,
            snapshot: engine.renderSnapshot(forPage: index)
        )
    }

    func resolvePage(at location: ReaderLocation) async -> ReaderResolvedPage? {
        guard let index = engine.pageIndex(for: location.coreTextPosition) else { return nil }
        return await resolvePage(at: index)
    }

    func adjacentLocation(from location: ReaderLocation, logicalForward: Bool) async -> ReaderLocation? {
        guard let page = engine.pageIndex(for: location.coreTextPosition) else { return nil }
        let nextPage = logicalForward ? page + 1 : page - 1
        guard nextPage >= 0, nextPage < engine.totalPages else { return nil }
        guard let position = engine.readingPosition(forPage: nextPage) else { return nil }
        return ReaderLocation(position)
    }

    func prefetch(around location: ReaderLocation, radius: Int) async {
        guard radius > 0,
              let page = engine.pageIndex(for: location.coreTextPosition) else { return }
        engine.warmUpNext(currentGlobalPage: page)
    }

    func invalidateLayout(reason: ReaderInvalidationReason) async {
        switch reason {
        case .viewportChanged(let size):
            await engine.invalidateLayout(newSize: size)
        case .appearanceChanged, .directionChanged:
            await engine.invalidateLayout(newSize: engine.renderSize)
        case .contentChanged(let spineIndex):
            if let spineIndex {
                await engine.notifyChapterDataChanged(at: spineIndex)
            } else {
                await engine.invalidateLayout(newSize: engine.renderSize)
            }
        }
    }

    private func readingPosition(from viewController: UIViewController) -> CoreTextReadingPosition? {
        if let provider = viewController as? CoreTextReadingPositionProviding {
            return provider.coreTextReadingPosition
        }
        if let provider = viewController as? PageIndexProviding {
            return engine.readingPosition(forPage: provider.globalPageIndex)
        }
        return nil
    }
}
