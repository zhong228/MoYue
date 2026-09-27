import UIKit

enum ReaderCoverTurnDirection: Equatable {
    case forward
    case backward
}

struct ReaderCoverPageMotion: Equatable {
    let direction: ReaderCoverTurnDirection
    let isRTL: Bool

    static func direction(for translationX: CGFloat, threshold: CGFloat, isRTL: Bool) -> ReaderCoverTurnDirection? {
        if isRTL {
            if translationX > threshold { return .forward }
            if translationX < -threshold { return .backward }
        } else {
            if translationX < -threshold { return .forward }
            if translationX > threshold { return .backward }
        }
        return nil
    }

    func initialX(width: CGFloat) -> CGFloat {
        switch direction {
        case .forward:
            return 0
        case .backward:
            return offscreenX(width: width)
        }
    }

    func interactiveX(progress: CGFloat, width: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 0.999)
        let offscreen = offscreenX(width: width)
        switch direction {
        case .forward:
            return offscreen * clamped
        case .backward:
            return offscreen * (1 - clamped)
        }
    }

    func settledX(width: CGFloat, shouldCommit: Bool) -> CGFloat {
        switch direction {
        case .forward:
            return shouldCommit ? offscreenX(width: width) : 0
        case .backward:
            return shouldCommit ? 0 : offscreenX(width: width)
        }
    }

    var movingEdgeCorners: CACornerMask {
        isRTL
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }

    var shadowOffset: CGSize {
        let ltrOffset: CGFloat = direction == .forward ? 10 : -10
        return CGSize(width: isRTL ? -ltrOffset : ltrOffset, height: 0)
    }

    private func offscreenX(width: CGFloat) -> CGFloat {
        (isRTL ? 1 : -1) * max(width, 1)
    }
}

struct PageViewControllerPagingAdapterDescriptor: Equatable {
    let style: ReaderPagingStyle
    let transitionStyle: UIPageViewController.TransitionStyle
    let disablesBuiltInSwipe: Bool
    let usesCoverOverlay: Bool
    let usesInstantPan: Bool
    let isDoubleSided: Bool

    init(pageTurnStyle: PageTurnStyle) {
        style = ReaderPagingStyle(pageTurnStyle: pageTurnStyle)
        isDoubleSided = pageTurnStyle == .curl
        switch pageTurnStyle {
        case .curl:
            transitionStyle = .pageCurl
            disablesBuiltInSwipe = false
            usesCoverOverlay = false
            usesInstantPan = false
        case .slide:
            transitionStyle = .scroll
            disablesBuiltInSwipe = false
            usesCoverOverlay = false
            usesInstantPan = false
        case .cover:
            transitionStyle = .scroll
            disablesBuiltInSwipe = true
            usesCoverOverlay = true
            usesInstantPan = false
        case .none:
            transitionStyle = .scroll
            disablesBuiltInSwipe = true
            usesCoverOverlay = false
            usesInstantPan = true
        }
    }

    func spineLocation(isRTL: Bool) -> UIPageViewController.SpineLocation {
        isRTL && (style == .curl || style == .cover) ? .max : .min
    }
}

/// Which animation engine plays a programmatic slide turn, and how.
///
/// Every tap, volume-key and queued slide turn runs as our own push transition;
/// only interactive swipes keep UIKit's `.scroll` transition. UIKit's programmatic
/// turn can be neither shortened nor cut short: `_UIQueuingScrollView` walks its
/// content offset on the main thread off a display link, which `layer.speed` does
/// not scale, so a second tap has to wait out the first turn in full. A push is a
/// render-server animation with a duration we own.
///
/// The push reproduces UIKit's own turn — duration and curve below — so a lone
/// tap still moves exactly like the page a swipe settles. It used to read as a
/// different, rougher animation because iPhone capped it at 60Hz while UIKit's
/// scrolling ran at 120Hz; `CADisableMinimumFrameDurationOnPhone` in Info.plist
/// plus `frameRateRange` lift that cap.
enum ReaderSlideTurnAnimation {
    /// UIKit's programmatic `.scroll` turn, sampled frame by frame (2026-09-26,
    /// iOS 27 simulator): 0.30s, progress (1 − cos πt) / 2.
    static let nativeDuration: CFTimeInterval = 0.3
    /// Apple's range for a fast, full-screen movement. On iPhone, Core Animation
    /// ignores anything above 60Hz unless Info.plist carries
    /// `CADisableMinimumFrameDurationOnPhone`.
    static let frameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

    static func runsTimedPush(pageTurnStyle: PageTurnStyle, animated: Bool) -> Bool {
        animated && pageTurnStyle == .slide
    }

    /// - Parameter speed: the tap-burst speed-up; 1 plays UIKit's own pace.
    static func pushTransition(
        direction: UIPageViewController.NavigationDirection,
        speed: Float
    ) -> CATransition {
        let transition = CATransition()
        transition.type = .push
        // `direction` already carries the RTL swap, so it maps straight to the
        // edge the incoming page enters from.
        transition.subtype = direction == .forward ? .fromRight : .fromLeft
        transition.duration = nativeDuration / Double(max(speed, 1))
        // Least-squares Bézier fit to UIKit's sine curve: within 0.08% of a page
        // at every sampled frame.
        transition.timingFunction = CAMediaTimingFunction(controlPoints: 0.365, 0, 0.635, 1)
        transition.preferredFrameRateRange = frameRateRange
        return transition
    }
}

enum ReaderCurlVirtualIndex {
    static func frontIndex(forGlobalPage page: Int, isRTL: Bool) -> Int {
        let base = max(0, page) * 2
        return isRTL ? base + 1 : base
    }

    static func backIndex(forLogicalPage page: Int, isRTL: Bool) -> Int {
        let base = max(0, page) * 2
        return isRTL ? base : base + 1
    }
}

enum ReaderCurlBackPageResolver {
    static func logicalPageIndex(targetPage: Int, visiblePage: Int) -> Int {
        targetPage >= visiblePage ? targetPage - 1 : targetPage
    }

    static func contentPageIndex(logicalPageIndex: Int, totalPages: Int) -> Int? {
        guard logicalPageIndex >= 0, logicalPageIndex < totalPages else { return nil }
        return logicalPageIndex
    }
}
