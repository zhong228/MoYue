import CoreGraphics
import Foundation

struct FixedPageReaderConfiguration: Equatable, Codable {
    enum Layout: String, Codable {
        case paged
        case continuousVerticalScroll
    }

    enum NavigationAxis: String, Codable {
        case horizontal
        case vertical
    }

    enum Progression: String, Codable {
        case rightToLeft
        case leftToRight
        case topToBottom
        case verticalScroll
    }

    enum FitMode: String, Codable {
        case fitPage
        case fitWidth
    }

    let mode: FixedPageReadingMode
    let layout: Layout
    let navigationAxis: NavigationAxis
    let progression: Progression
    let fitMode: FitMode
    let pageSpacing: CGFloat
    let isZoomEnabled: Bool

    static func recommendedDefault(for mode: FixedPageReadingMode) -> FixedPageReaderConfiguration {
        mode.recommendedConfiguration
    }
}

extension FixedPageReadingMode {
    var recommendedConfiguration: FixedPageReaderConfiguration {
        switch self {
        case .rtl:
            return FixedPageReaderConfiguration(
                mode: self,
                layout: .paged,
                navigationAxis: .horizontal,
                progression: .rightToLeft,
                fitMode: .fitPage,
                pageSpacing: 8,
                isZoomEnabled: true
            )
        case .ltr:
            return FixedPageReaderConfiguration(
                mode: self,
                layout: .paged,
                navigationAxis: .horizontal,
                progression: .leftToRight,
                fitMode: .fitPage,
                pageSpacing: 8,
                isZoomEnabled: true
            )
        case .vertical:
            return FixedPageReaderConfiguration(
                mode: self,
                layout: .paged,
                navigationAxis: .vertical,
                progression: .topToBottom,
                fitMode: .fitPage,
                pageSpacing: 8,
                isZoomEnabled: true
            )
        case .webtoon:
            return FixedPageReaderConfiguration(
                mode: self,
                layout: .continuousVerticalScroll,
                navigationAxis: .vertical,
                progression: .verticalScroll,
                fitMode: .fitWidth,
                pageSpacing: 0,
                isZoomEnabled: false
            )
        }
    }

    static func savedConfiguration(
        for bookId: UUID,
        defaults: UserDefaults = .standard
    ) -> FixedPageReaderConfiguration {
        saved(for: bookId, defaults: defaults).recommendedConfiguration
    }
}
