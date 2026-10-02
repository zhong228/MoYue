import SwiftUI
import UIKit

extension View {
    /// Reports how far the scroll view this view sits in has scrolled from its top, in
    /// points: once when the view is placed, then each time the reader scrolls. With no
    /// scroll view above it, it reports 0 — the page is at its top.
    ///
    /// Put it on a view inside the scroll view's content — a grid, or a list's first row.
    /// It observes the nearest `UIScrollView` above itself, so it always measures the
    /// scroll view it is in. The navigation controller's `contentScrollView(for: .top)`
    /// would be shorter, but on iOS 17 it names 書架's group filter bar instead of its
    /// list. The same on every iOS version from 17 on.
    ///
    /// A list recycles the row this sits on once it scrolls far out of sight; the last
    /// offset reported stands until the row comes back near the top.
    func reportsScrollOffset(_ action: @escaping (CGFloat) -> Void) -> some View {
        background(ScrollOffsetReader(onChange: action).accessibilityHidden(true))
    }
}

private struct ScrollOffsetReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ReaderView {
        ReaderView(onChange: onChange)
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: (CGFloat) -> Void
        private var observation: NSKeyValueObservation?
        private weak var observedScrollView: UIScrollView?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor, !(view is UIScrollView) {
                ancestor = view.superview
            }
            let scrollView = ancestor as? UIScrollView
            if scrollView !== observedScrollView || observation == nil {
                observedScrollView = scrollView
                // contentOffset changes on the main thread, so the change handler runs there.
                observation = scrollView?.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    MainActor.assumeIsolated {
                        self?.report(scrollView)
                    }
                }
            }
            // The offset as placed goes out on the main actor's next turn: SwiftUI is still
            // adding this view to the window here, and publishing in the middle of that is a
            // change during a view update. Every later change comes from a scroll.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let observedScrollView {
                    report(observedScrollView)
                } else {
                    onChange(0)
                }
            }
        }

        private func report(_ scrollView: UIScrollView) {
            onChange(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }
    }
}
