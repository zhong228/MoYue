import UIKit

/// Pure math for the paged reader's pull-down-to-bookmark gesture: a bookmark
/// pill drops in from the top edge and grows while the finger travels down;
/// releasing past the commit point adds this page's bookmark — or removes it,
/// when the page already has one. Scroll mode never installs this gesture,
/// because there a downward drag is the scroll itself.
///
/// Stateless like `ReaderSwipeUpExitMotion`, its mirror image, so the thresholds
/// are unit-testable without a view.
enum ReaderPullDownBookmarkMotion {
    /// Downward finger travel (pt) that maps to 100% progress.
    static let fullProgressTranslation: CGFloat = 180
    /// Progress at or above which releasing the finger toggles the bookmark.
    static let commitProgress: CGFloat = 0.55
    /// Downward fling velocity (pt/s, positive = down) that commits before the
    /// distance threshold is reached.
    static let commitVelocityY: CGFloat = 1100
    /// A fling still needs this much progress so a stray flick can't bookmark.
    static let flingMinimumProgress: CGFloat = 0.18

    static let pillHeight: CGFloat = 44
    static let pillHorizontalPadding: CGFloat = 16
    static let pillIconTextSpacing: CGFloat = 8
    static let pillIconPointSize: CGFloat = 17
    /// How far the pill center travels down from rest at 100% progress.
    static let pillDrop: CGFloat = 120
    /// Pill center's rest offset below the top safe-area edge. Rest plus the
    /// travel it has made by the time it is fully opaque (40%) clears the reader's
    /// top bar, so the pill is readable whether or not the chrome is showing —
    /// the pill is parented to the paged view, which sits *under* that bar.
    static let pillRestTopInset: CGFloat = 12
    static let minPillScale: CGFloat = 0.6
    /// Extra scale "pop" once the gesture passes the commit point.
    static let armedScaleBoost: CGFloat = 1.08
    static let cancelSettleDuration: TimeInterval = 0.25
    /// How long the committed result ("已加入書籤") stays on screen before fading.
    static let confirmationHold: TimeInterval = 0.55
    static let confirmationFadeDuration: TimeInterval = 0.22
    /// Icon swap / label change while dragging — short enough to feel attached
    /// to the finger.
    static let stateChangeDuration: TimeInterval = 0.18

    /// The pan may only begin on a clearly downward drag, so horizontal
    /// page-turn pans and upward drags (the exit gesture) keep their behavior.
    static func shouldBegin(velocity: CGPoint) -> Bool {
        velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.4
    }

    static func progress(forTranslationY translationY: CGFloat) -> CGFloat {
        guard translationY > 0 else { return 0 }
        return min(translationY / fullProgressTranslation, 1)
    }

    static func pillScale(forProgress progress: CGFloat) -> CGFloat {
        minPillScale + (1 - minPillScale) * progress
    }

    /// Fades in over the first 40% of the travel so the pill never pops.
    static func pillAlpha(forProgress progress: CGFloat) -> CGFloat {
        min(progress * 2.5, 1)
    }

    static func pillCenterY(
        forProgress progress: CGFloat,
        topSafeInset: CGFloat
    ) -> CGFloat {
        topSafeInset + pillRestTopInset + pillDrop * progress
    }

    static func shouldCommit(progress: CGFloat, velocityY: CGFloat) -> Bool {
        if progress >= commitProgress { return true }
        return velocityY >= commitVelocityY && progress >= flingMinimumProgress
    }

    /// What the pill says and shows at each step. `isBookmarked` is read once when
    /// the gesture begins, so the pill never flips mid-drag because a neighbouring
    /// page settled underneath it.
    enum Phase: Equatable {
        /// Dragging, not yet far enough to commit.
        case pulling
        /// Dragging past the commit point — release now and it happens.
        case armed
        /// Committed; showing the outcome before it fades.
        case done
    }

    static func iconName(isBookmarked: Bool, phase: Phase) -> String {
        switch (isBookmarked, phase) {
        case (false, .pulling): return "bookmark"
        case (false, .armed), (false, .done): return "bookmark.fill"
        case (true, .pulling): return "bookmark.fill"
        case (true, .armed), (true, .done): return "bookmark.slash.fill"
        }
    }

    /// Localization keys, resolved by the caller through `localized(_:)`.
    static func titleKey(isBookmarked: Bool, phase: Phase) -> String {
        switch (isBookmarked, phase) {
        case (false, .pulling): return "下拉加入書籤"
        case (false, .armed): return "放開加入書籤"
        case (false, .done): return "已加入書籤"
        case (true, .pulling): return "下拉移除書籤"
        case (true, .armed): return "放開移除書籤"
        case (true, .done): return "已移除書籤"
        }
    }
}
