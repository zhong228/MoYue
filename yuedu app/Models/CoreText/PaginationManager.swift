import UIKit

struct PaginationRequest {
    let spineIndex: Int
    let attributedString: NSAttributedString
    let imagePage: HTMLAttributedStringBuilder.ImagePage?
    let pageBackgroundImage: UIImage?
    let anchorOffsets: [String: Int]
    let renderSize: CGSize
    let fontSize: CGFloat
    let contentInsets: UIEdgeInsets
}

struct PaginationResult {
    let layout: CoreTextPaginator.ChapterLayout
}

@MainActor
final class PaginationManager {
    private let paginator: CoreTextPaginator

    init(paginator: CoreTextPaginator = CoreTextPaginator()) {
        self.paginator = paginator
    }

    func paginate(_ request: PaginationRequest) async -> PaginationResult {
        let layout = await paginator.paginate(
            spineIndex: request.spineIndex,
            attrStr: request.attributedString,
            imagePage: request.imagePage,
            pageBackgroundImage: request.pageBackgroundImage,
            anchorOffsets: request.anchorOffsets,
            renderSize: request.renderSize,
            fontSize: request.fontSize,
            contentInsets: request.contentInsets
        )
        return PaginationResult(layout: layout)
    }

    func invalidate(reason: CoreTextPaginator.InvalidationReason) {
        paginator.invalidate(reason: reason)
    }
}