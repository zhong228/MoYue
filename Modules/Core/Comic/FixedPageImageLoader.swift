import UIKit
import Nuke

// MARK: - Fixed page image loading
//
// Dispatches fixed-page render sources. Image archive pages use Nuke's shared
// pipeline; fixed-layout EPUB pages are rasterized on demand by their provider.

enum FixedPageImageLoader {

    /// Build a Nuke request for a page: headered URLRequest + resize-to-width.
    static func request(for page: FixedPage, targetWidth: CGFloat) -> ImageRequest {
        let resolved = page.localURL ?? URL(string: page.imageURL)
        var urlRequest = URLRequest(url: resolved ?? URL(fileURLWithPath: "/dev/null"))
        if page.localURL == nil {
            for (key, value) in page.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        }
        var processors: [any ImageProcessing] = []
        if targetWidth > 0 {
            processors.append(ImageProcessors.Resize(width: targetWidth, unit: .points, upscale: false))
        }
        return ImageRequest(urlRequest: urlRequest, processors: processors)
    }

    @MainActor
    static func loadImage(for page: FixedPage, targetWidth: CGFloat) async -> UIImage? {
        if case .fixedLayoutEPUB(let sourceFilename, let chapterIndex) = page.renderSource {
            let sourceURL = LocalMangaArchive.archiveURL(for: sourceFilename)
            return try? await FixedLayoutEPUBPageProvider.renderPageImage(
                from: sourceURL,
                chapterIndex: chapterIndex
            )
        }
        return try? await ImagePipeline.shared.image(for: request(for: page, targetWidth: targetWidth))
    }

    @MainActor
    static func prefetch(_ pages: [FixedPage], targetWidth: CGFloat, using prefetcher: ImagePrefetcher) {
        prefetcher.startPrefetching(with: pages.map { request(for: $0, targetWidth: targetWidth) })
    }
}
