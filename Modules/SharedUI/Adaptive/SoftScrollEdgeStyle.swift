import SwiftUI

/// iOS 26's soft scroll-edge fade (`.scrollEdgeEffectStyle(.soft, for: .all)`).
/// Earlier systems have no scroll edge effect at all, so this is a no-op there.
///
/// The `#if compiler` guard mirrors `RootTabBarMinimizeStyle`: the iOS 26 API only
/// exists in the Xcode 26 SDK, and the project still has to compile on older toolchains.
struct SoftScrollEdgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Gives vertical scroll views an explicit soft top/bottom edge on iOS 26+.
    func softScrollEdges() -> some View {
        modifier(SoftScrollEdgeStyle())
    }
}
