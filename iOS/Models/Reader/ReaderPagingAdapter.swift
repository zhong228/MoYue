import UIKit

enum ReaderTapZone {
    case leading
    case center
    case trailing
}

@MainActor
protocol ReaderPagingAdapter: AnyObject {
    var style: ReaderPagingStyle { get }
    var viewController: UIViewController { get }

    func bind(
        provider: ReaderPageProvider,
        session: ReaderSessionStore,
        delegate: ReaderPagingAdapterDelegate
    )
    func apply(state: ReaderPresentationState, animated: Bool)
    func jump(to location: ReaderLocation, animated: Bool)
    func cancelInFlightTransition()
    func teardown()
}

@MainActor
protocol ReaderPagingAdapterDelegate: AnyObject {
    func pagingAdapter(
        _ adapter: ReaderPagingAdapter,
        didSettleAt location: ReaderLocation,
        pageIndex: Int
    )

    func pagingAdapter(
        _ adapter: ReaderPagingAdapter,
        didRequestTapZone zone: ReaderTapZone
    )
}

struct PageViewControllerPagingAdapterDescriptor: Equatable {
    let style: ReaderPagingStyle
    let transitionStyle: UIPageViewController.TransitionStyle
    let disablesBuiltInSwipe: Bool
    let usesCoverOverlay: Bool

    init(pageTurnStyle: PageTurnStyle) {
        style = ReaderPagingStyle(pageTurnStyle: pageTurnStyle)
        switch pageTurnStyle {
        case .curl:
            transitionStyle = .pageCurl
            disablesBuiltInSwipe = false
            usesCoverOverlay = false
        case .slide:
            transitionStyle = .scroll
            disablesBuiltInSwipe = false
            usesCoverOverlay = false
        case .cover:
            transitionStyle = .scroll
            disablesBuiltInSwipe = true
            usesCoverOverlay = true
        case .none:
            transitionStyle = .scroll
            disablesBuiltInSwipe = true
            usesCoverOverlay = false
        }
    }

    func spineLocation(isRTL: Bool) -> UIPageViewController.SpineLocation {
        isRTL && style == .curl ? .max : .min
    }
}
