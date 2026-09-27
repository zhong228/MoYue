import UIKit

/// Reader tap zones must not consume taps on embedded controls (for example Live Text).
/// Check ancestors too, since UIKit reports the label/image inside a button as the hit view.
@MainActor
final class FixedPageReaderControlTapDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        Self.acceptsReaderTap(on: touch.view)
    }

    static func acceptsReaderTap(on view: UIView?) -> Bool {
        var candidate = view
        while let current = candidate {
            if current is UIControl { return false }
            candidate = current.superview
        }
        return true
    }
}
